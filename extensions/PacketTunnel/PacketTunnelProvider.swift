import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let loopback = LoopbackTunnel()
    private var jitTask: Task<Void, Never>?
    private var pairingURL: URL?
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                let temporaryDirectory = FileManager.default.temporaryDirectory
                for url in (try? FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
                    where url.lastPathComponent.hasPrefix("cofre-pairing-") && url.pathExtension == "plist" {
                    try? FileManager.default.removeItem(at: url)
                }
                try await loopback.apply(to: self)
                NSLog("[Cofre] tunnel up 10.7.0.1")
                completionHandler(nil)
            } catch { completionHandler(error) }
        }
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        let task = jitTask
        let pairing = pairingURL
        jitTask = nil
        pairingURL = nil
        Task {
            task?.cancel()
            _ = await task?.value
            if let pairing { try? FileManager.default.removeItem(at: pairing) }
            completionHandler()
        }
    }
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        let started = mach_task_basic_info_data_t()
        var info = started
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let ok = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) == KERN_SUCCESS
            }
        }
        let peak = ok ? Double(info.resident_size_max) / 1_048_576 : 0
        func reply(_ state: String, _ reason: String? = nil, mode: String? = nil) -> Data {
            var object: [String: Any] = ["state": state]
            if let reason { object["reason"] = reason }
            if let mode { object["mode"] = mode }
            return (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{\"state\":\"failed\",\"reason\":\"response encoding failed\"}".utf8)
        }
        guard let object = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
            object["cmd"] as? String == "enableJIT", let pid = object["pid"] as? Int, pid > 0,
            let encoded = object["pairing"] as? String, let pairing = Data(base64Encoded: encoded),
            pairing.count < 262144
        else {
            completionHandler?(reply("failed", "invalid message"))
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cofre-pairing-\(UUID().uuidString).plist")
        do {
            try pairing.write(to: url, options: .completeFileProtection)
            pairingURL = url
        } catch {
            completionHandler?(reply("failed", "pairing write failed: \(error.localizedDescription)"))
            return
        }
        guard let scriptURL = Bundle.main.url(forResource: "CofreTXM", withExtension: "js") else {
            try? FileManager.default.removeItem(at: url)
            pairingURL = nil
            completionHandler?(reply("failed", "TXM script missing"))
            return
        }
        jitTask?.cancel()
        let task = Task.detached { [weak self] in
            do {
                try StikJIT.enableJIT(
                    targetPID: Int32(pid), pairingFile: url,
                    configuration: .init(deviceAddress: CofreConstants.tunnelAddress, rsdPort: 49152), script: .custom(scriptURL),
                    forceScript: true, progress: { NSLog("[Cofre] JIT %@", $0) })
                NSLog("[Cofre] JIT enabled pid=%d mode=txm peakMB=%.1f", pid, peak)
                completionHandler?(reply("enabled", mode: "txm"))
            } catch {
                NSLog("[Cofre] JIT failed pid=%d %@", pid, error.localizedDescription)
                completionHandler?(reply("failed", error.localizedDescription))
            }
            try? FileManager.default.removeItem(at: url)
            self?.pairingURL = nil
        }
        jitTask = task
    }
}
