#if canImport(UIKit)
import Foundation
import UIKit
import NetworkExtension
import CofreUI

public enum CofreBackendError: LocalizedError {
    case unavailable(String)
    public var errorDescription: String? { switch self { case .unavailable(let name): "\(name) is unavailable in this Air build" } }
}

/// Production bridge. Air owns the data and launch lifecycle; unsupported Air APIs are surfaced as unavailable.
@MainActor
public final class CofreBackendAdapter: NSObject, CofreBackend {
    public var capabilities: BackendCapabilities { [.deleteWorld, .addServer, .envVariables, .rendererTuning] }
    private let air = CofreAirBridgeAdapter()
    private var launchTask: Task<Void, Never>?
    private var setup = SetupState()
    private var setupContinuations: [AsyncStream<SetupState>.Continuation] = []
    private func loadPersistedSetup() {
        let d = UserDefaults.standard
        if d.object(forKey: "cofre.setup.pairing") != nil { setup.pairing = d.bool(forKey: "cofre.setup.pairing") ? .ready : .blocked }
        if d.object(forKey: "cofre.setup.vpn") != nil { setup.vpn = d.bool(forKey: "cofre.setup.vpn") ? .ready : .blocked }
        if d.object(forKey: "cofre.setup.trust") != nil { setup.trust = d.bool(forKey: "cofre.setup.trust") ? .ready : .blocked }
        if d.object(forKey: "cofre.setup.account") != nil { setup.account = d.bool(forKey: "cofre.setup.account") ? .ready : .blocked }
        if d.object(forKey: "cofre.setup.devMode") != nil { setup.devMode = d.bool(forKey: "cofre.setup.devMode") ? .ready : .blocked }
        if d.object(forKey: "cofre.setup.jit") != nil { setup.jit = d.bool(forKey: "cofre.setup.jit") ? .ready : .blocked }
    }
    public override init() { super.init(); loadPersistedSetup() }

    public func setupState() async -> SetupState { setup }
    public func setupUpdates() -> AsyncStream<SetupState> {
        AsyncStream { continuation in
            setupContinuations.append(continuation)
            continuation.yield(setup)
            continuation.onTermination = { _ in }
        }
    }
    public func recheckSetup() async {
        let key = hasPairing()
        let accountReady = (try? await accounts().isEmpty == false) ?? false
        let vpnReady = await vpnManagerEnabled()
        setup.pairing = key ? .ready : .failed("Import a valid pairing file")
        setup.trust = key ? .ready : .failed("Trust this iPhone, then import its key")
        setup.account = accountReady ? .ready : .failed("Sign in with Microsoft")
        setup.vpn = vpnReady ? .ready : .failed("Allow Cofre's VPN")
        setup.jit = isJITEnabled ? .ready : .failed("Run Test JIT after pairing")
        setup.devMode = isJITEnabled ? .ready : .failed("Enable Developer Mode")
        persistSetup()
        setupContinuations.forEach { $0.yield(setup) }
    }
    public func openDeveloperModeSettings() { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
    public func hasPairing() -> Bool { FileManager.default.fileExists(atPath: pairingURL.path) }
    public func importPairing(_ data: Data) throws { try data.write(to: pairingURL, options: [.atomic, .completeFileProtection]) }
    public func deletePairing() throws { if hasPairing() { try FileManager.default.removeItem(at: pairingURL) } }
    public var isVPNRunning: Bool { false }
    public func startVPN() async throws { throw CofreBackendError.unavailable("VPN control") }
    public var isJITEnabled: Bool { false }

    public func instances() async throws -> [InstanceSummary] { air.instances().compactMap { d in
        guard let id = d["id"] as? String else { return nil }; let loader = Loader(rawValue: (d["loader"] as? String ?? "vanilla").lowercased()) ?? .vanilla
        return InstanceSummary(id: id, name: d["name"] as? String ?? id, loader: loader, gameVersion: d["version"] as? String ?? "")
    } }
    public func createInstance(name: String, version: String, loader: Loader) async throws -> InstanceSummary { throw unavailable("instance creation") }
    public func installLoader(instanceID: String, loader: Loader, version: String) async throws { throw unavailable("loader installation") }
    public func worlds(instanceID: String) async throws -> [WorldSummary] { try await callback { done in self.air.worldsForProfile(instanceID) { done($0) } }.map { d in let x=d as? [String:Any] ?? [:]; let n=x["name"] as? String ?? "World"; return WorldSummary(id: x["id"] as? String ?? n, name:n, mode:x["mode"] as? String ?? "", playTime:nil, lastPlayed:nil) } }
    public func servers(instanceID: String) async throws -> [ServerSummary] { throw unavailable("server list") }
    public func deleteWorld(instanceID: String, worldID: String) async throws { var e: NSError?; guard air.deleteWorld(worldID, forProfile: instanceID, error: &e) else { throw e ?? unavailable("world deletion") } }
    public func backUpWorld(instanceID: String, worldID: String) async throws -> URL { throw unavailable("world backup") }
    public func addServer(instanceID: String, name: String, address: String) async throws -> ServerSummary { var e: NSError?; guard air.addServer(address, name: name, forProfile: instanceID, error: &e) else { throw e ?? unavailable("server addition") }; return ServerSummary(id: address, name: name, address: address) }
    public func createInstance(name: String, version: String, loader: Loader, ownFolder: Bool, fabricAPI: Bool) async throws -> InstanceSummary { try await createInstance(name: name, version: version, loader: loader) }
    public func preferences(instanceID: String?) async throws -> GamePreferences {
        var p = GamePreferences(); p.autoRAM = air.preferenceObject("java.auto_ram") as? Bool ?? true
        p.ramMB = Int(air.preferencesForProfile(instanceID ?? air.profiles.selectedProfileName)["ramMB"] as? Int ?? 4096)
        p.deviceRAMMB = p.ramMB
        p.envVariables = parseEnv(air.preferenceObject("java.env_variables") as? String ?? "")
        p.shaderCacheMB = air.preferenceObject("mobileglues.max_glsl_cache_size") as? Int ?? 512
        p.multidraw = "\(air.preferenceObject("mobileglues.multidraw_mode") as? Int ?? 0)"
        p.computeShaders = air.preferenceObject("mobileglues.enable_ext_compute_shader") as? Bool ?? true
        return p
    }
    public func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws {
        air.setPreferenceObject("java.env_variables", value: preferences.envVariables.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        air.setPreferenceObject("mobileglues.max_glsl_cache_size", value: preferences.shaderCacheMB)
        air.setPreferenceObject("mobileglues.multidraw_mode", value: preferences.multidraw == "Auto" ? 0 : (Int(preferences.multidraw) ?? 0))
        air.setPreferenceObject("mobileglues.enable_ext_compute_shader", value: preferences.computeShaders)
    }

    public func installed(_ kind: ContentKind, instanceID: String) async throws -> [InstalledItem] { try await callback { done in self.air.modsForProfile(instanceID) { done($0) } }.compactMap { d in let x=d as? [String:Any] ?? [:]; guard let id=x["id"] as? String ?? x["name"] as? String else { return nil }; return InstalledItem(id:id,name:x["name"] as? String ?? id,version:x["version"] as? String ?? "",enabled:x["enabled"] as? Bool ?? true,kind:kind) } }
    public func setEnabled(_ enabled: Bool, item: InstalledItem, instanceID: String) async throws { throw unavailable("mod changes") }
    public func delete(_ item: InstalledItem, instanceID: String) async throws { throw unavailable("content deletion") }
    public func updateAll(instanceID: String) async throws { throw unavailable("content updates") }

    public func accounts() async throws -> [Account] { air.accounts().compactMap { d in guard let id=d["id"] as? String else { return nil }; return Account(id:id,name:d["name"] as? String ?? id,isActive:false) } }
    public func signInMicrosoft() async throws -> Account { throw unavailable("Microsoft sign-in") }
    public func removeAccount(id: String) async throws { throw unavailable("account removal") }

    public func launch(instanceID: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error> { AsyncThrowingStream { continuation in self.air.launchProfile(instanceID, accountID: accountID) { stage in continuation.yield(LaunchProgress(stage: 1, of: 1, title: stage, finished: stage == "running" || stage == "failed")) }; continuation.finish() } }
    public func cancelLaunch() async { launchTask?.cancel(); launchTask=nil }
    public func logLines(_ kind: LogKind) -> AsyncStream<LogLine> { AsyncStream { continuation in let url=logURL(kind); if let text=try? String(contentsOf:url) { for (i,line) in text.split(separator:"\n").enumerated() { continuation.yield(LogLine(id:i,time:"",tag:"Air",text:String(line))) } }; continuation.finish() } }
    public func exportLog(_ kind: LogKind) async throws -> URL { let u=logURL(kind); guard FileManager.default.fileExists(atPath:u.path) else { throw unavailable("log export") }; return u }
    public func duplicate(instanceID: String) async throws -> InstanceSummary { throw unavailable("instance duplication") }
    public func delete(instanceID: String) async throws { throw unavailable("instance deletion") }
    public func export(instanceID: String, format: ExportFormat) async throws -> URL { throw unavailable("instance export") }
    public func gameVersions(_ kind: VersionKind) async throws -> [GameVersion] { throw unavailable("version catalog") }
    public func loaderVersions(loader: Loader, game: String) async throws -> [String] { throw unavailable("loader catalog") }
    public func search(_ query: ProjectQuery) async throws -> [ProjectSummary] { throw unavailable(query.source.displayName + " catalog") }
    public func versions(projectID: String, instanceID: String) async throws -> [ProjectVersion] { throw unavailable("project versions") }
    public func dependencies(versionID: String, instanceID: String) async throws -> [ProjectDependency] { throw unavailable("project dependencies") }
    public func install(projectID: String, versionID: String, instanceID: String) -> AsyncThrowingStream<InstallProgress, Error> { unavailableStream("content installation") }
    public func importPack(_ url: URL, instanceID: String?) -> AsyncThrowingStream<InstallProgress, Error> { unavailableStream("pack import") }
    public func testJIT() -> AsyncThrowingStream<JITStep, Error> {
        AsyncThrowingStream { continuation in
            Task { let pid = Int32(getpid()); let service = CofreJIT(tunnel: { nil }, pairingURL: { self.pairingURL }); let result = await service.enable(pid: pid); NSLog("[Cofre] JIT status=%@", String(describing: result)); continuation.yield(JITStep(kind: .debugger, state: result.isEnabled ? .ready : .failed, detail: String(describing: result))); continuation.finish() }
        }
    }
    public func deviceInfo() async -> DeviceInfo? { nil }
    public func signingInfo() async -> SigningInfo? { nil }
    public func appInfo() -> AppInfo { AppInfo(version: Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "", airVersion:"Air", sourceURL: URL(string:"https://github.com/ignaciojb/cofre")!) }
    public func renderers() async -> [RendererOption] { [] }
    public func javaRuntimes() async -> [JavaRuntime] { [] }
    public func storage() async -> StorageUsage { StorageUsage(gameBytes:0,javaBytes:0,cacheBytes:0) }
    public func clearCache() async throws { throw unavailable("cache management") }
    public func curseForgeKey() -> String? { nil }
    public func setCurseForgeKey(_ key: String?) throws { throw unavailable("CurseForge key storage") }
    public func applyAirAppearance(accentHex: String, cardHex: String, textHex: String) { }

    private var pairingURL: URL { FileManager.default.urls(for:.documentDirectory,inDomains:.userDomainMask)[0].appendingPathComponent("StikJIT/pairingFile.plist") }
    private func logURL(_ kind: LogKind) -> URL { FileManager.default.urls(for:.documentDirectory,inDomains:.userDomainMask)[0].appendingPathComponent(kind == .latest ? "latestlog.txt" : "latestlog.txt") }
    private func vpnManagerEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                continuation.resume(returning: managers?.contains { $0.isEnabled && $0.protocolConfiguration is NETunnelProviderProtocol && (($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == "com.ignaciojuarez.cofre.tunnel") } ?? false)
            }
        }
    }
    private func persistSetup() {
        let d = UserDefaults.standard
        d.set(setup.pairing.isReady, forKey: "cofre.setup.pairing")
        d.set(setup.trust.isReady, forKey: "cofre.setup.trust")
        d.set(setup.account.isReady, forKey: "cofre.setup.account")
        d.set(setup.devMode.isReady, forKey: "cofre.setup.devMode")
        d.set(setup.vpn.isReady, forKey: "cofre.setup.vpn")
        d.set(setup.jit.isReady, forKey: "cofre.setup.jit")
    }
    private func parseEnv(_ value: String) -> [String: String] { Dictionary(uniqueKeysWithValues: value.split(separator: " ").compactMap { p in let a = p.split(separator: "=", maxSplits: 1); return a.count == 2 ? (String(a[0]), String(a[1])) : nil }) }
    private func unavailable(_ name: String) -> CofreBackendError { .unavailable(name) }
    private func unavailableStream<T>(_ name: String) -> AsyncThrowingStream<T, Error> { AsyncThrowingStream { continuation in continuation.finish(throwing: unavailable(name)) } }
    private func callback(_ body: (@escaping (NSArray) -> Void) -> Void) async throws -> NSArray { await withCheckedContinuation { c in body { c.resume(returning:$0) } } }
}
#endif
