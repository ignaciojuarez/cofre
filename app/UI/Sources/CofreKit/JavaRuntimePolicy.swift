import Foundation

/// Chooses a launch runtime for renderers that inject Java-side code.
public enum JavaRuntimePolicy {
    /// Metallum uses `SymbolLookup.findOrThrow`, which is only available in Java 22+.
    public static let metalMinimumMajor = 22

    public enum Decision: Equatable, Sendable {
        case keep
        case use(major: Int)
        case unsupportedSelection
        case unavailable
    }

    /// Metal's agent needs Java 22 even when Minecraft's manifest only asks for Java 21.
    /// Explicit choices below 22 fail clearly; Auto uses the lowest bundled runtime
    /// that can load the agent. Newer explicit choices remain unchanged.
    public static func decision(
        requiredJava: Int, selectedJava: Int?, renderer: RendererID,
        bundledMajors: [Int]
    ) -> Decision {
        guard RendererPolicy.isMetal(renderer), requiredJava < metalMinimumMajor else { return .keep }
        if let selectedJava {
            return selectedJava < metalMinimumMajor ? .unsupportedSelection : .use(major: selectedJava)
        }
        guard let bundled = bundledMajors.filter({ $0 >= metalMinimumMajor }).min() else { return .unavailable }
        return .use(major: bundled)
    }
}
