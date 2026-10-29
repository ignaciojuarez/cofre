import Foundation
import NetworkExtension
import UIKit

public enum CofreJITStatus: Equatable { case unavailable, needsPairing, needsVPN, enabling, enabled(String), failed(String) }
extension CofreJITStatus { public var isEnabled: Bool { if case .enabled = self { return true }; return false } }
public final class CofreJIT: @unchecked Sendable {
    public private(set) var status: CofreJITStatus = .unavailable
    private let tunnel: () -> NETunnelProviderSession?
    private let pairingURL: () -> URL
    public init(tunnel: @escaping () -> NETunnelProviderSession?, pairingURL: @escaping () -> URL) { self.tunnel=tunnel; self.pairingURL=pairingURL }
    public func enable(pid: Int32) async -> CofreJITStatus {
        guard FileManager.default.fileExists(atPath: pairingURL().path) else { status = .needsPairing; return status }
        guard let session = tunnel() else { status = .needsVPN; return status }
        status = .enabling
        do {
            let pairing = try Data(contentsOf: pairingURL())
            let body = try JSONSerialization.data(withJSONObject: ["cmd":"enableJIT", "pid":pid, "pairing": pairing.base64EncodedString()])
            let reply = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data?, Error>) in
                do { try session.sendProviderMessage(body) { c.resume(returning: $0) } }
                catch { c.resume(throwing: error) }
            }
            let dict = (reply.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String:Any] }) ?? [:]
            if let mode = dict["mode"] as? String { status = .enabled(mode); return status }
            throw NSError(domain:"CofreJIT", code: 1, userInfo:[NSLocalizedDescriptionKey: dict["reason"] as? String ?? "PacketTunnel did not enable JIT"])
        } catch {
            status = .failed(error.localizedDescription)
            if UIApplication.shared.canOpenURL(URL(string:"stikjit://")!) {
                let url = URL(string:"stikjit://enable-jit?bundle-id=com.ignaciojuarez.cofre&pid=\(pid)")!
                await UIApplication.shared.open(url)
            }
            return status
        }
    }
}
