import Foundation

/// A launch stop and the action that can recover it. Engine errors cross into the UI as this value.
public enum LaunchFailure: Error, Equatable, Sendable, LocalizedError {
    case loaderMissing, modsNeedLoader, unknownLoader, profileMissing, restartRequired, rendererUnsupported,
        jitUnavailable
    case downloadFailed(String)
    case jvmExit(Int)
    case unknown(String)

    public enum Recovery: String, Sendable {
        case repairInstance, reopen, renderer, jit, retry, log

        public var title: String {
            switch self {
            case .repairInstance: "Review instance"
            case .reopen: "Close Cofre"
            case .renderer: "Renderer settings"
            case .jit: "Test JIT"
            case .retry: "Try again"
            case .log: "View log"
            }
        }
    }

    public var errorDescription: String? {
        switch self {
        case .loaderMissing: "This modded instance has no installed loader. Reinstall the loader before launching."
        case .modsNeedLoader:
            "This instance has mods, but no mod loader is installed. Choose Fabric, Forge or NeoForge, then reinstall the instance."
        case .unknownLoader:
            "This instance names an unrecognized mod loader. Choose a supported loader before launching."
        case .profileMissing: "This instance profile is unavailable. Reinstall or repair the instance before launching."
        case .restartRequired: "Java has already run in this session. Close Cofre and open it again to play."
        case .rendererUnsupported: "This instance needs a renderer that is not available in this build."
        case .jitUnavailable: "JIT could not be enabled on this device."
        case .downloadFailed(let message): "Game files could not be downloaded: \(message)"
        case .jvmExit(let code): "Minecraft exited before it reached the game (code \(code))."
        case .unknown(let message): message.isEmpty ? "Minecraft couldn't start. Check the launcher log." : message
        }
    }

    public var recovery: Recovery {
        switch self {
        case .loaderMissing, .modsNeedLoader, .unknownLoader, .profileMissing: .repairInstance
        case .restartRequired: .reopen
        case .rendererUnsupported: .renderer
        case .jitUnavailable: .jit
        case .downloadFailed: .retry
        case .jvmExit, .unknown: .log
        }
    }
}
