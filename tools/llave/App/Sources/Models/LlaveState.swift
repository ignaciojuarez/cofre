import Foundation

public enum LlaveState: Equatable, Sendable {
    case noDevice
    case multipleDevices([Device])
    case locked(Device)
    case waitingForTrust(Device)
    case pairing(Device)
    case placing(Device)
    case ready(fileURL: URL)
    case done(Device)
    case cofreMissing(Device)
    case placementFailed(Device, String)
    case error(LlaveError)
}
