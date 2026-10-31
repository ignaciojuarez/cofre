import Foundation

public enum LlaveEvent: Equatable, Sendable {
    case waitingForUnlock
    case waitingForTrust
    case paired
    case wifiEnabled
    case wifiFailed(code: String, message: String)
    case remotePairingWarning(message: String)
    case validated
    case placed
    case error(code: String, message: String)

    private struct WireEvent: Decodable {
        let event: String
        let code: String?
        let message: String?
    }

    public static func parse(line: String) -> LlaveEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return nil
        }
        guard let wire = try? JSONDecoder().decode(WireEvent.self, from: data) else {
            return nil
        }

        switch wire.event {
        case "waiting_for_unlock":
            return .waitingForUnlock
        case "waiting_for_trust":
            return .waitingForTrust
        case "paired":
            return .paired
        case "wifi_enabled":
            return .wifiEnabled
        case "warning" where wire.code == "REMOTE_PAIRING_FAILED":
            return .remotePairingWarning(message: wire.message ?? "RemotePairing unavailable")
        case "error" where wire.code == "REMOTE_PAIRING_FAILED":
            return .error(code: "REMOTE_PAIRING_FAILED", message: wire.message ?? "RemotePairing is required; pair this device again")
        case "error" where (wire.code == "WIFI_CONNECTIONS_FAILED" || wire.code == "WIFI_DEBUGGING_FAILED"):
            return .wifiFailed(code: wire.code ?? "WIFI_FAILED", message: wire.message ?? "Wi-Fi setup failed")
        case "validated":
            return .validated
        case "placed":
            return .placed
        case "error":
            return .error(code: wire.code ?? "UNKNOWN", message: wire.message ?? "Unknown error")
        default:
            return nil
        }
    }
}
