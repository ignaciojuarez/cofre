import Foundation

public enum LlaveEvent: Equatable, Sendable {
    case waitingForUnlock
    case waitingForTrust
    case paired
    case wifiEnabled
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
