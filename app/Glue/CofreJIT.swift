import Foundation
import NetworkExtension

public enum CofreJITStatus: Equatable {
    case unavailable, needsPairing, needsVPN, enabling
    case enabled(String)
    /// `step`: the `JITStep.Kind` raw value that failed (vpn, diskImage, debugger), when the tunnel knows it.
    case failed(String, step: String? = nil)
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
    public static func enable(pid: Int32, pairingURL: @escaping () -> URL) async -> CofreJITStatus {
        let session: NETunnelProviderSession
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
            let body = try JSONSerialization.data(withJSONObject: [
                "cmd": "enableJIT", "pid": pid, "pairing": pairing.base64EncodedString(),
            ])
            let reply = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data?, Error>) in
                do { try session.sendProviderMessage(body) { c.resume(returning: $0) } } catch {
                    c.resume(throwing: error)
                }
            }
            let dict = (reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
            if dict["state"] as? String == "enabled", let mode = dict["mode"] as? String, !mode.isEmpty {
                status = .enabled(mode)
                return status
            }
            status = .failed(
                dict["reason"] as? String ?? "The VPN extension didn't enable JIT.", step: dict["step"] as? String)
            return status
        } catch {
            status = .failed(error.localizedDescription)
            return status
        }
    }
}
