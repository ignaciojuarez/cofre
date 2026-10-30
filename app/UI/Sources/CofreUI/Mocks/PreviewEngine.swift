#if canImport(UIKit)
import Foundation

/// Air-free engine used by previews and UI tests. It emits honest empty progress and
/// never invents launcher data; fixture-backed CofreKit objects provide that data.
public final class PreviewEngine: GameEngine, @unchecked Sendable {
    public let input: any GameInputService
    public init(input: (any GameInputService)? = nil) { self.input = input ?? PreviewInput() }
    public func launch(instanceID: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(LaunchProgress(stage: 0, of: 1, title: "Preview", finished: true))
            continuation.finish()
        }
    }
    public func signInMicrosoft() async throws -> Account { throw UnsupportedAction(name: "Microsoft sign-in in preview") }
    public func testJIT() -> AsyncThrowingStream<JITStep, Error> {
        AsyncThrowingStream { continuation in
            for kind in JITStep.Kind.allCases { continuation.yield(JITStep(kind: kind, state: .ready)) }
            continuation.finish()
        }
    }
    public func installLoader(instanceID: String, loader: Loader, version: String) async throws {}
    public func preferences(instanceID: String?) async throws -> GamePreferences { GamePreferences() }
    public func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws {}
    public func renderers() async -> [RendererOption] { [] }
    public func curseForgeKey() -> String? { nil }
    public func setCurseForgeKey(_ key: String?) throws {}
}

private final class PreviewInput: NSObject, GameInputService {}
#endif
