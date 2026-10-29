import Foundation

public struct LlaveError: Error, Equatable, Sendable, LocalizedError {
    public let code: String
    public let message: String
    public let friendlyCopy: String

    public init(code: String, message: String, friendlyCopy: String? = nil) {
        self.code = code
        self.message = message
        if let friendly = friendlyCopy {
            self.friendlyCopy = friendly
        } else {
            switch code {
            case "DEVICE_RESTRICTED":
                self.friendlyCopy = "This device cannot be paired with Llave."
            case "USER_DENIED":
                self.friendlyCopy = "Trust request was cancelled on your device. Please unlock and tap Trust."
            case "PASSWORD_PROTECTED":
                self.friendlyCopy = "iPhone is locked with a passcode. Please unlock your device."
            case "NO_DEVICE":
                self.friendlyCopy = "No iPhone detected. Connect your iPhone via USB cable."
            case "VALIDATION_FAILED":
                self.friendlyCopy = "Pairing file validation failed. Please try pairing again."
            case "COFRE_MISSING":
                self.friendlyCopy = "Install Cofre first, then try again."
            case "PLACEMENT_FAILED":
                self.friendlyCopy = "Llave could not place the key inside Cofre."
            case "CLI_NOT_FOUND":
                self.friendlyCopy = "llave-pair helper binary could not be found."
            default:
                self.friendlyCopy = message.isEmpty ? "An unexpected pairing error occurred." : message
            }
        }
    }

    public var errorDescription: String? {
        friendlyCopy
    }
}
