import Foundation

/// Debug hook for screenshots: `LLAVE_PREVIEW_STATE=waitingForTrust` pins the window to one state with a sample iPhone.
/// Names follow `LlaveState`; errors take an optional code, e.g. `error:USER_DENIED`. A preview run is simulated (see LlaveApp).
enum PreviewState {
    static let current: LlaveState? = ProcessInfo.processInfo.environment["LLAVE_PREVIEW_STATE"].flatMap(state(named:))
    /// `LLAVE_PREVIEW_NOTE=airDrop|saved` shows the line that follows that button.
    static let note: String? = switch ProcessInfo.processInfo.environment["LLAVE_PREVIEW_NOTE"] {
    case "airDrop": StateScreen.airDropSent
    case "saved": StateScreen.saved
    default: nil
    }

    static func state(named name: String) -> LlaveState? {
        let phone = Device(udid: "00008150-PREVIEW", name: "Ana's iPhone", version: "26.1")
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts.first {
        case "noDevice": return .noDevice
        case "multipleDevices": return .multipleDevices([phone, Device(udid: "00008140-PREVIEW", name: "Work iPhone", version: "18.6")])
        case "locked": return .locked(phone)
        case "waitingForTrust": return .waitingForTrust(phone)
        case "pairing": return .pairing(phone)
        case "placing": return .placing(phone)
        case "ready": return .ready(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("Ana's iPhone.mobiledevicepairing"))
        case "done": return .done(phone)
        case "cofreMissing": return .cofreMissing(phone)
        case "placementFailed": return .placementFailed(phone, "")
        case "error": return .error(LlaveError(code: parts.count > 1 ? parts[1] : "PAIRING_FAILED", message: ""))
        default: return nil
        }
    }
}
