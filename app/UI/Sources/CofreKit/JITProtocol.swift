import Foundation

/// Checklist step names shared by the app and PacketTunnel wire protocol.
public enum JITStep {
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case pairing, vpn, diskImage, debugger, region, detach
    }
}

/// The complete app↔PacketTunnel message. Coding keys intentionally match the
/// existing JSON so an updated app can talk to an older appex and vice versa.
public struct JITMessage: Codable, Equatable, Sendable {
    public enum Command: String, Codable, Sendable { case enableJIT }
    public enum State: String, Codable, Sendable { case enabled, failed }
    public var command: Command?
    public var pid: Int32?
    public var pairing: String?
    public var state: State?
    public var reason: String?
    public var mode: String?
    public var step: JITStep.Kind?

    public init(
        command: Command? = nil, pid: Int32? = nil, pairing: String? = nil, state: State? = nil,
        reason: String? = nil, mode: String? = nil, step: JITStep.Kind? = nil
    ) {
        self.command = command
        self.pid = pid
        self.pairing = pairing
        self.state = state
        self.reason = reason
        self.mode = mode
        self.step = step
    }
    public static func enableJIT(pid: Int32, pairing: Data) -> Self {
        Self(command: .enableJIT, pid: pid, pairing: pairing.base64EncodedString())
    }
    public static func enabled(mode: String) -> Self { Self(state: .enabled, mode: mode) }
    public static func failed(_ reason: String, step: JITStep.Kind? = nil) -> Self {
        Self(state: .failed, reason: reason, step: step)
    }

    private enum CodingKeys: String, CodingKey {
        case command = "cmd"
        case pid, pairing, state, reason, mode, step
    }
}
