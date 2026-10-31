import Foundation
import NetworkExtension

/// Cofre's loopback VPN (the PacketTunnel extension). `connect()` creates the configuration the first time, which is
/// when iOS asks to allow it. Launch only starts one the user already allowed.
enum CofreVPN {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func manager() async throws -> NETunnelProviderManager? {
        try await NETunnelProviderManager.loadAllFromPreferences().first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == CofreConstants.tunnelBundleID
        }
    }

    static func isAllowed() async -> Bool { (try? await manager())?.isEnabled == true }

    /// Starts an existing, user-approved configuration without prompting.
    static func startIfInstalled() async {
        do {
            guard let m = try await manager(), m.isEnabled,
                  let session = m.connection as? NETunnelProviderSession else {
                NSLog("[Cofre] tunnel not allowed yet")
                return
            }
            guard session.status != .connected, session.status != .connecting else { return }
            try session.startVPNTunnel()
            NSLog("[Cofre] tunnel starting")
        } catch {
            NSLog("[Cofre] tunnel start failed %@", error.localizedDescription)
        }
    }

    /// Creates or re-enables the configuration, then waits up to 15 s for the tunnel to connect.
    @discardableResult
    static func connect() async throws -> NETunnelProviderSession {
        let m = try await manager() ?? NETunnelProviderManager()
        if !m.isEnabled || m.protocolConfiguration == nil {
            let p = NETunnelProviderProtocol()
            p.providerBundleIdentifier = CofreConstants.tunnelBundleID
            p.serverAddress = CofreConstants.tunnelAddress
            m.protocolConfiguration = p
            m.localizedDescription = "Cofre loopback"
            m.isEnabled = true
            do {
                try await m.saveToPreferences()
                try await m.loadFromPreferences()
            } catch {
                NSLog("[Cofre] VPN not allowed: %@", error.localizedDescription)
                throw Failure(errorDescription: "iOS didn't allow the VPN. Tap Allow VPN, then Allow.")
            }
        }
        guard let session = m.connection as? NETunnelProviderSession else {
            throw Failure(errorDescription: "Cofre's VPN is missing. Reinstall Cofre.")
        }
        if session.status != .connected {
            if session.status != .connecting { try session.startVPNTunnel() }
            let deadline = Date().addingTimeInterval(15)
            while session.status != .connected, Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
            guard session.status == .connected else {
                throw Failure(errorDescription: "The VPN didn't connect. Turn off other VPNs, then try again.")
            }
        }
        return session
    }
}
