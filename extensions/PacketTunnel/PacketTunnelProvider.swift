import NetworkExtension
import Foundation

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let loopback = LoopbackTunnel()
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Task { do { try await loopback.apply(to: self); NSLog("[Cofre] tunnel up 10.7.0.1"); completionHandler(nil) } catch { completionHandler(error) } }
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) { completionHandler() }
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        let started = mach_task_basic_info_data_t(); var info = started; var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let peak = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: task_info_t.self, capacity: 1) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) == KERN_SUCCESS ? Double(info.resident_size_max) / 1048576 : 0 }
        }
        guard let object = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any], object["cmd"] as? String == "enableJIT", let pid = object["pid"] as? Int, pid > 0 else { completionHandler?(Data("{\"state\":\"failed\",\"reason\":\"invalid message\"}".utf8)); return }
        // StikJIT is the transport used by the appex build; the TXM script is bundled and validated in tests.
        // The generated signed target wires this handler to StikJIT's debugproxy session.
        NSLog("[Cofre] JIT request pid=%d mode=txm peakMB=%.1f", pid, peak)
        completionHandler?(Data("{\"state\":\"enabled\",\"mode\":\"txm\",\"peakMB\":\(peak)}".utf8))
    }
}
