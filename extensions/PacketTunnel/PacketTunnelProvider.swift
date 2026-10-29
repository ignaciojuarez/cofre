import Foundation
import Network
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
                // Our own sockets skip this tunnel unless bound to it (TunnelRoute.c).
                var index: UInt32 = 0
                if #available(iOS 18, *), let tunnel = virtualInterface { index = UInt32(tunnel.index) }
                CofreRouteThroughTunnel(CofreConstants.tunnelAddress, index)
                NSLog("[Cofre] tunnel up 10.7.0.1 interface=%u", index)
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
        func reply(_ state: String, _ reason: String? = nil, mode: String? = nil, step: String? = nil) -> Data {
            var object: [String: Any] = ["state": state]
            if let reason { object["reason"] = reason }
            if let mode { object["mode"] = mode }
            if let step { object["step"] = step }
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
        let once = ReplyOnce(completionHandler)
        let task = Task.detached { [weak self] in
            // The step that failed, for the app's checklist: reaching the phone, then the disk image, then the debugger.
            var step = "vpn"
            do {
                guard #available(iOS 17.4, *) else { throw TunnelError("JIT needs iOS 17.4 or later.") }
                let configuration = StikJIT.Configuration(deviceAddress: CofreConstants.tunnelAddress, rsdPort: 49152)
                if try !StikJIT.isDDIMounted(pairingFile: url, configuration: configuration) {
                    step = "diskImage"
                    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    let paths = DDIPaths.default(in: caches)
                    try await StikJIT.downloadDDIIfNeeded(to: paths)
                    try StikJIT.mountDDI(pairingFile: url, configuration: configuration, paths: paths)
                    NSLog("[Cofre] JIT disk image mounted")
                }
                step = "debugger"
                // Blocks until CofreTXM.js detaches (right after the game's code region) or the game exits. Reply once
                // it has attached.
                try StikJIT.enableJIT(
                    targetPID: Int32(pid), pairingFile: url, configuration: configuration, script: .custom(scriptURL),
                    forceScript: true,
                    progress: { message in
                        NSLog("[Cofre] JIT %@", message)
                        guard message == "COFRE_ATTACHED" else { return }
                        NSLog("[Cofre] JIT enabled pid=%ld mode=txm peakMB=%.1f", pid, peakMegabytes())
                        once.send(reply("enabled", mode: "txm"))
                    })
                once.send(reply("enabled", mode: "txm"))
            } catch {
                NSLog("[Cofre] JIT failed pid=%ld step=%@ %@", pid, step, error.localizedDescription)
                once.send(reply("failed", error.localizedDescription, step: step))
            }
            try? FileManager.default.removeItem(at: url)
            self?.pairingURL = nil
        }
        jitTask = task
    }
}

/// The app waits for exactly one reply per message.
private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((Data?) -> Void)?
    init(_ handler: ((Data?) -> Void)?) { self.handler = handler }
    func send(_ data: Data) {
        lock.lock()
        let h = handler
        handler = nil
        lock.unlock()
        h?(data)
    }
}

private struct TunnelError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private func peakMegabytes() -> Double {
    var info = mach_task_basic_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<natural_t>.stride)
    let ok = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) == KERN_SUCCESS
        }
    }
    return ok ? Double(info.resident_size_max) / 1_048_576 : 0
}
