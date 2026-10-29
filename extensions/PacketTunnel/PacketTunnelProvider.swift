import NetworkExtension
import Foundation

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let loopback = LoopbackTunnel()
    private var jitTask: Task<Void, Never>?
    private var pairingURL: URL?
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Task { do { try await loopback.apply(to: self); NSLog("[Cofre] tunnel up 10.7.0.1"); completionHandler(nil) } catch { completionHandler(error) } }
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) { completionHandler() }
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        let started = mach_task_basic_info_data_t(); var info = started; var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let peak = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: task_info_t.self, capacity: 1) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) == KERN_SUCCESS ? Double(info.resident_size_max) / 1048576 : 0 }
        }
        guard let object = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any], object["cmd"] as? String == "enableJIT", let pid = object["pid"] as? Int, pid > 0, let encoded = object["pairing"] as? String, let pairing = Data(base64Encoded: encoded), pairing.count < 262144 else { completionHandler?(Data("{\"state\":\"failed\",\"reason\":\"invalid message\"}".utf8)); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cofre-pairing-\(UUID().uuidString).plist")
        do { try pairing.write(to: url, options: .completeFileProtection); pairingURL = url } catch { completionHandler?(Data("{\"state\":\"failed\",\"reason\":\"pairing write failed\"}".utf8)); return }
        let scriptURL = Bundle.main.url(forResource: "CofreTXM", withExtension: "js")!
        jitTask?.cancel()
        jitTask = Task.detached { [weak self] in
            do {
                try StikJIT.enableJIT(targetPID: Int32(pid), pairingFile: url, configuration: .init(deviceAddress: "10.7.0.1", rsdPort: 49152), script: .custom(scriptURL), forceScript: true, progress: { NSLog("[Cofre] JIT %@", $0) })
                NSLog("[Cofre] JIT enabled pid=%d mode=txm peakMB=%.1f", pid, peak)
            } catch { NSLog("[Cofre] JIT failed pid=%d %@", pid, error.localizedDescription) }
            try? FileManager.default.removeItem(at: url); self?.pairingURL = nil
        }
        completionHandler?(Data("{\"state\":\"enabling\",\"mode\":\"txm\",\"peakMB\":\(peak)}".utf8))
    }
}
