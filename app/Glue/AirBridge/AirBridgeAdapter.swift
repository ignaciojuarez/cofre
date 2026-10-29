import Foundation

/// Thin seam for Air's public services. The app target supplies the concrete calls;
/// this adapter keeps the shell independent of Air view controllers.
public final class AirBridgeAdapter: AirBridge {
    public let launchStages: AsyncStream<LaunchStage>; private let continuation: AsyncStream<LaunchStage>.Continuation
    public init() { (launchStages, continuation) = AsyncStream.makeStream(of: LaunchStage.self) }
    private func unavailable<T>() throws -> T { throw NSError(domain: "Cofre.AirBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Air service is unavailable"]) }
    public func instances() async throws -> [CofreInstance] { try unavailable() }
    public func createInstance(name: String, version: String, loader: String) async throws -> CofreInstance { try unavailable() }
    public func installLoader(instanceID: String, loader: String, version: String) async throws { try unavailable() }
    public func worlds(instanceID: String) async throws -> [CofreWorld] { try unavailable() }
    public func servers(instanceID: String) async throws -> [CofreServer] { try unavailable() }
    public func mods(instanceID: String) async throws -> [CofreMod] { try unavailable() }
    public func shaders(instanceID: String) async throws -> [CofrePack] { try unavailable() }
    public func resourcePacks(instanceID: String) async throws -> [CofrePack] { try unavailable() }
    public func toggleMod(instanceID: String, id: String, enabled: Bool) async throws { try unavailable() }
    public func deleteMod(instanceID: String, id: String) async throws { try unavailable() }
    public func updateMods(instanceID: String) async throws { try unavailable() }
    public func searchModrinth(query: String) async throws -> [CofrePack] { try unavailable() }
    public func searchCurseForge(query: String) async throws -> [CofrePack] { try unavailable() }
    public func install(pack: CofrePack, instanceID: String) async throws { try unavailable() }
    public func importPack(_ data: Data, instanceID: String) async throws { try unavailable() }
    public func accounts() async throws -> [CofreAccount] { try unavailable() }
    public func signInMicrosoft() async throws -> CofreAccount { try unavailable() }
    public func removeAccount(id: String) async throws { try unavailable() }
    public func preferences(instanceID: String) async throws -> CofrePreferences { try unavailable() }
    public func setPreferences(_ preferences: CofrePreferences, instanceID: String) async throws { try unavailable() }
    public func launch(instanceID: String) async throws { continuation.yield(.preparing); try unavailable() }
}
