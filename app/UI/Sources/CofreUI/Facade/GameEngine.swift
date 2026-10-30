import Foundation

#if canImport(UIKit)
/// The only UI-facing boundary for work that still belongs to Air.
/// File-backed launcher data stays in CofreKit; this protocol is intentionally small.
public protocol GameEngine: AnyObject {
    var input: any GameInputService { get }
    func launch(instanceID: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error>
    func signInMicrosoft() async throws -> Account
    func refreshAccount(id: String) async throws -> Account
    func testJIT() -> AsyncThrowingStream<JITStep, Error>
    func installLoader(instanceID: String, loader: Loader, version: String) async throws
    func preferences(instanceID: String?) async throws -> GamePreferences
    func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws
    func renderers() async -> [RendererOption]
    func curseForgeKey() -> String?
    func setCurseForgeKey(_ key: String?) throws
}

public extension GameEngine {
    func refreshAccount(id: String) async throws -> Account {
        throw UnsupportedAction(name: "Refreshing accounts")
    }
}
#endif
