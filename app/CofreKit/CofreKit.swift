import Foundation

public enum CofreState: Equatable {
    case unknown, checking, ready, blocked
    case failed(String)
}
public struct SetupStatus: Equatable {
    public var devMode, trust, pairing, vpn, jit, account: CofreState
    public init(
        devMode: CofreState = .unknown, trust: CofreState = .unknown, pairing: CofreState = .unknown,
        vpn: CofreState = .unknown, jit: CofreState = .unknown, account: CofreState = .unknown
    ) {
        self.devMode = devMode
        self.trust = trust
        self.pairing = pairing
        self.vpn = vpn
        self.jit = jit
        self.account = account
    }
}
public protocol TunnelService {
    var isRunning: Bool { get }
    func start() async throws
    func stop() async throws
}
public protocol JITService {
    func enable(pid: Int32) async throws
    func disable() async
    var isEnabled: Bool { get }
}
public protocol PairingStore {
    func hasPairing() -> Bool
    func importPairing(_ data: Data) throws
    func deletePairing() throws
}
public final class SetupStatusStore {
    public private(set) var value = SetupStatus()
    public let updates = AsyncStream<SetupStatus>.makeStream()
    public init() {}
    public func set(_ status: SetupStatus) {
        value = status
        updates.continuation.yield(status)
    }
}

public struct CofreInstance: Identifiable, Sendable {
    public let id: String
    public var name, loader, version: String
    public init(id: String, name: String, loader: String, version: String) {
        self.id = id
        self.name = name
        self.loader = loader
        self.version = version
    }
}
public struct CofreWorld: Identifiable, Sendable {
    public let id: String
    public var name, instanceID: String
}
public struct CofreServer: Identifiable, Sendable {
    public let id: String
    public var name, address: String
}
public struct CofreMod: Identifiable, Sendable {
    public let id: String
    public var name, version: String, enabled: Bool
}
public struct CofrePack: Identifiable, Sendable {
    public let id: String
    public var name, kind: String, version: String
}
public struct CofreAccount: Identifiable, Sendable {
    public let id: String
    public var name: String
}
public struct CofrePreferences: Sendable {
    public var ramMB = 4096, renderer = "Auto", resolution = 1.0, fsr = true, java = "auto", jvmArgs = ""
}
public enum LaunchStage: Sendable {
    case preparing, downloading, starting, running, finished
    case failed(String)
}

public protocol AirBridge {
    var launchStages: AsyncStream<LaunchStage> { get }
    func instances() async throws -> [CofreInstance]
    func createInstance(name: String, version: String, loader: String) async throws -> CofreInstance
    func installLoader(instanceID: String, loader: String, version: String) async throws
    func worlds(instanceID: String) async throws -> [CofreWorld]
    func servers(instanceID: String) async throws -> [CofreServer]
    func mods(instanceID: String) async throws -> [CofreMod]
    func shaders(instanceID: String) async throws -> [CofrePack]
    func resourcePacks(instanceID: String) async throws -> [CofrePack]
    func toggleMod(instanceID: String, id: String, enabled: Bool) async throws
    func deleteMod(instanceID: String, id: String) async throws
    func updateMods(instanceID: String) async throws
    func searchModrinth(query: String) async throws -> [CofrePack]
    func searchCurseForge(query: String) async throws -> [CofrePack]
    func install(pack: CofrePack, instanceID: String) async throws
    func importPack(_ data: Data, instanceID: String) async throws
    func accounts() async throws -> [CofreAccount]
    func signInMicrosoft() async throws -> CofreAccount
    func removeAccount(id: String) async throws
    func preferences(instanceID: String) async throws -> CofrePreferences
    func setPreferences(_ preferences: CofrePreferences, instanceID: String) async throws
    func launch(instanceID: String) async throws
}
