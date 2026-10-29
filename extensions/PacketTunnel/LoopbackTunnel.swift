import Foundation
import NetworkExtension

/// Loopback flow: app sends to 10.7.0.1, the tunnel reflects it to 10.7.0.2,
/// where the device lockdownd listener receives it. Open spike S1: verify
/// traffic originating in this appex traverses its own tunnel.
final class LoopbackTunnel {
    private let settings: NEPacketTunnelNetworkSettings
    init() {
        settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.7.0.1")
        settings.ipv4Settings = NEIPv4Settings(addresses: ["10.7.0.2"], subnetMasks: ["255.255.255.0"])
        settings.ipv4Settings?.includedRoutes = [
            NEIPv4Route(destinationAddress: "10.7.0.1", subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings?.excludedRoutes = [NEIPv4Route.default()]
    }
    func apply(to provider: NEPacketTunnelProvider) async throws {
        try await provider.setTunnelNetworkSettings(settings)
        read(provider)
    }
    private func read(_ provider: NEPacketTunnelProvider) {
        provider.packetFlow.readPackets { [weak self, weak provider] packets, _ in
            guard let self, let provider else { return }
            var out = packets
            for i in out.indices { out[i] = self.swapIPv4(out[i]) }
            provider.packetFlow.writePackets(out, withProtocols: packets.map { _ in NSNumber(value: AF_INET) })
            self.read(provider)
        }
    }
    private func swapIPv4(_ packet: Data) -> Data {
        guard packet.count >= 20, packet[0] >> 4 == 4 else { return packet }
        var p = packet
        for i in 0..<4 { p.swapAt(12 + i, 16 + i) }
        return p
    }
}
