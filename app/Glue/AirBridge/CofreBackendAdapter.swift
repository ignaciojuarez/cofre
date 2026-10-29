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
    private let air = CofreAirBridgeAdapter()
    private var launchTask: Task<Void, Never>?
    private var setup = SetupState()

    public func setupState() async -> SetupState { setup }
    public func setupUpdates() -> AsyncStream<SetupState> { AsyncStream { _ in } }
    public func recheckSetup() async { setup.pairing = hasPairing() ? .ready : .blocked; setup.vpn = isVPNRunning ? .ready : .unknown; setup.jit = isJITEnabled ? .ready : .blocked }
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
    public func preferences(instanceID: String?) async throws -> GamePreferences { throw unavailable("preferences") }
    public func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws { throw unavailable("preferences") }

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
    public func testJIT() -> AsyncThrowingStream<JITStep, Error> { unavailableStream("JIT test") }
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
    private func unavailable(_ name: String) -> CofreBackendError { .unavailable(name) }
    private func unavailableStream<T>(_ name: String) -> AsyncThrowingStream<T, Error> { AsyncThrowingStream { continuation in continuation.finish(throwing: unavailable(name)) } }
    private func callback(_ body: (@escaping (NSArray) -> Void) -> Void) async throws -> NSArray { await withCheckedContinuation { c in body { c.resume(returning:$0) } } }
}
#endif
