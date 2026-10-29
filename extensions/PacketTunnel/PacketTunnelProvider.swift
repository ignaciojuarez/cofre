import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let loopback = LoopbackTunnel()
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Task { do { try await loopback.apply(to: self); completionHandler(nil) } catch { completionHandler(error) } }
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) { completionHandler() }
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) { completionHandler?(messageData) }
}
