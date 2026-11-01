import Foundation
import NetworkExtension
import CofreKit

public enum CofreJITStatus: Equatable {
    case unavailable, needsPairing, needsVPN, enabling
    case enabled(String)
    case failed(String, step: JITStep.Kind? = nil)
}
extension CofreJITStatus {
    public var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }
}
public final class CofreJIT: @unchecked Sendable {
    public private(set) var status: CofreJITStatus = .unavailable
    private let tunnel: () -> NETunnelProviderSession?
    private let pairingURL: () -> URL
    public init(tunnel: @escaping () -> NETunnelProviderSession?, pairingURL: @escaping () -> URL) {
        self.tunnel = tunnel
        self.pairingURL = pairingURL
    }
    static let noReply = "The VPN extension didn't enable JIT."

    /// A tunnel iOS killed (memory limit, reinstall, a debugger terminating the app) can still read as connected and
    /// drops the message without a reply. Restart it once and ask again.
    public static func enable(pid: Int32, pairingURL: @escaping () -> URL) async -> CofreJITStatus {
        guard ProvisioningProfile.current?.supportsBuiltInJIT == true else {
            return .failed(ProvisioningProfile.builtInJITUnavailableMessage)
        }
        var session: NETunnelProviderSession
        do { session = try await CofreVPN.connect() } catch { return .failed(error.localizedDescription) }
        let first = await CofreJIT(tunnel: { session }, pairingURL: pairingURL).enable(pid: pid)
        guard first == .failed(noReply) else { return first }
        NSLog("[Cofre] JIT got no reply; restarting the VPN")
        session.stopVPNTunnel()
        let deadline = Date().addingTimeInterval(5)
        while session.status != .disconnected, session.status != .invalid, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        do { session = try await CofreVPN.connect() } catch { return .failed(error.localizedDescription) }
        return await CofreJIT(tunnel: { session }, pairingURL: pairingURL).enable(pid: pid)
    }
    public func enable(pid: Int32) async -> CofreJITStatus {
        guard FileManager.default.fileExists(atPath: pairingURL().path) else {
            status = .needsPairing
            return status
        }
        guard let session = tunnel() else {
            status = .needsVPN
            return status
        }
        status = .enabling
        do {
            let pairing = try Data(contentsOf: pairingURL())
            let body = try JSONEncoder().encode(JITMessage.enableJIT(pid: pid, pairing: pairing))
            let reply = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data?, Error>) in
                do { try session.sendProviderMessage(body) { c.resume(returning: $0) } } catch {
                    c.resume(throwing: error)
                }
            }
            let message = reply.flatMap { try? JSONDecoder().decode(JITMessage.self, from: $0) }
            if message?.state == .enabled, let mode = message?.mode, !mode.isEmpty {
                status = .enabled(mode)
                return status
            }
            status = .failed(message?.reason ?? Self.noReply, step: message?.step)
            return status
        } catch {
            status = .failed(error.localizedDescription)
            return status
        }
    }
}
