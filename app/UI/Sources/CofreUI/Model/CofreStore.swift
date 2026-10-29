#if canImport(UIKit)
import SwiftUI

/// UI state for every screen. Screens read this; it calls the `CofreBackend` protocols.
/// Errors surface as a banner (`lastError`) instead of crashing a pane.
@Observable @MainActor
public final class CofreStore {
    public let services: CofreServices
    var backend: any CofreBackend { services.backend }

    // Setup
    public var setup = SetupState()
    /// `true` once the first `setupState()` returns. Until then the root shows a neutral splash, not the wizard.
    public private(set) var setupLoaded = false
    /// Saved: setup finished once. After that, live failures show as a banner on Play, never the wizard again.
    public var setupCompleted: Bool { didSet { defaults.set(setupCompleted, forKey: Keys.completed) } }
    /// Saved: the wizard step the user was on (0 welcome … 7 ready), so a cold start resumes there.
    public var setupStep: Int? { didSet { defaults.set(setupStep, forKey: Keys.step) } }
    /// Set when the key came from a picked file (AirDrop fallback), so S04 can say to delete that copy.
    public var pairingFromFile = false
    public var jitSteps: [JITStep] = []
    public var jitTesting = false
    public var signing: SigningInfo?
    public var device: DeviceInfo?

    // Library
    public private(set) var libraryLoaded = false
    public var instances: [InstanceSummary] = []
    public var activeInstanceID: String?
    public var worlds: [WorldSummary] = []
    public var servers: [ServerSummary] = []
    public var accounts: [Account] = []
    public var preferences = GamePreferences()
    public var instancePreferences: [String: GamePreferences] = [:]

    // Mods
    public var query = ProjectQuery()
    public var results: [ProjectSummary] = []
    public var searching = false
    public var searchError: String?
    public var versions: [String: [ProjectVersion]] = [:]
    public var dependencies: [String: [ProjectDependency]] = [:]
    public var installed: [ContentKind: [InstalledItem]] = [:]
    public var installing: Set<String> = []
    public var importProgress: InstallProgress?

    // Launch
    public var launch: LaunchProgress?
    public var launchError: String?
    public var launchLog: [LogLine] = []
    public var logs: [LogKind: [LogLine]] = [:]

    // System
    public var renderers: [RendererOption] = []
    public var javaRuntimes: [JavaRuntime] = []
    public var storage: StorageUsage?
    public var curseForgeKey: String?
    public var theme = CofreTheme.current
    public var lastError: String?
    /// A destructive action waiting for the one shared confirmation alert (root view).
    public var pendingConfirmation: Confirmation?
    /// Set by the hosting controller so window-level UIKit state follows X07.
    @ObservationIgnored public var onThemeChange: ((CofreTheme) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let completed = "cofre.setup.completed"
        static let step = "cofre.setup.step"
    }

    /// `defaults` holds the setup progress; tests and the preview host pass their own suite.
    public init(services: CofreServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        setupCompleted = defaults.bool(forKey: Keys.completed)
        setupStep = defaults.object(forKey: Keys.step) as? Int
    }

    public var capabilities: BackendCapabilities { backend.capabilities }
    public func can(_ c: BackendCapabilities) -> Bool { capabilities.contains(c) }

    public var activeInstance: InstanceSummary? { instances.first { $0.id == activeInstanceID } ?? instances.first }
    public var activeAccount: Account? { accounts.first { $0.isActive } ?? accounts.first }
    public var updateCount: Int { activeInstance?.updatesAvailable ?? 0 }
    public var isJITReady: Bool { setup.jit.isReady }
    /// The wizard shows only for users who never finished it, once their state has loaded. It stays up through
    /// S08 Ready even when every check passes mid-flow; `finishSetup()` (Play) or a complete state at load ends it.
    public var showsSetup: Bool { setupLoaded && !setupCompleted }
    @available(*, deprecated, renamed: "setupCompleted")
    public var setupDismissed: Bool { get { setupCompleted } set { setupCompleted = newValue } }

    /// Where a cold start opens the wizard: the saved step, unless that step's check has passed since.
    public var resumeStep: Int {
        guard let saved = setupStep else { return 0 }
        guard (1...6).contains(saved) else { return saved == 7 ? (setup.isComplete ? 7 : firstOpenStep) : saved }
        return setup.all[saved - 1].isReady ? firstOpenStep : saved
    }

    /// The first check that isn't ready (1…6), or 7 (Ready) when all pass.
    public var firstOpenStep: Int { (setup.all.firstIndex { !$0.isReady } ?? 6) + 1 }

    public func finishSetup() { setupCompleted = true; setupStep = nil }

    // MARK: Loading

    public func start() async {
        setup = await backend.setupState()
        if setup.isComplete { setupCompleted = true }
        setupLoaded = true
        signing = await backend.signingInfo()
        device = await backend.deviceInfo()
        await refreshLibrary()
        Task { for await s in backend.setupUpdates() { self.setup = s } }
        Task { await loadSystemLists() }
        Task { await search() }
    }

    public func refreshLibrary() async {
        await run {
            self.instances = try await self.backend.instances()
            self.accounts = try await self.backend.accounts()
            self.preferences = try await self.backend.preferences(instanceID: nil)
        }
        libraryLoaded = true
        if activeInstanceID == nil { activeInstanceID = instances.first?.id }
        await loadActiveInstance()
    }

    public func selectInstance(_ id: String) async {
        activeInstanceID = id
        await loadActiveInstance()
    }

    func loadActiveInstance() async {
        guard let id = activeInstance?.id else { return }
        query.instanceID = id
        await run {
            async let w = self.backend.worlds(instanceID: id)
            async let s = self.backend.servers(instanceID: id)
            async let m = self.backend.installed(.mods, instanceID: id)
            self.worlds = try await w; self.servers = try await s; self.installed[.mods] = try await m
        }
    }

    func loadSystemLists() async {
        renderers = await backend.renderers()
        javaRuntimes = await backend.javaRuntimes()
        storage = await backend.storage()
        curseForgeKey = backend.curseForgeKey()
    }

    // MARK: Setup

    public func importPairing(_ data: Data) {
        do { try backend.importPairing(data); pairingFromFile = true; setup.pairing = .ready } catch { setup.pairing = .failed(error.localizedDescription) }
    }

    public func startVPN() async {
        setup.vpn = .checking
        do { try await backend.startVPN(); setup.vpn = .ready } catch { setup.vpn = .failed(error.localizedDescription) }
    }

    public func testJIT() async {
        jitTesting = true; jitSteps = JITStep.Kind.allCases.map { JITStep(kind: $0, state: .unknown) }
        setup.jit = .checking
        defer { jitTesting = false }
        do {
            for try await step in backend.testJIT() {
                if let i = jitSteps.firstIndex(where: { $0.kind == step.kind }) { jitSteps[i] = step }
            }
            try Task.checkCancellation()
            setup.jit = .ready
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            if let i = jitSteps.firstIndex(where: { $0.state == .checking }) { jitSteps[i].state = .failed(error.localizedDescription) }
            setup.jit = .failed(error.localizedDescription)
        }
    }

    /// The step that failed in the last JIT test, for the next-step hint.
    public var failedJITStep: JITStep.Kind? {
        jitSteps.first { $0.state.isFailed }?.kind
    }

    public func signIn() async {
        setup.account = .checking
        do {
            let a = try await backend.signInMicrosoft()
            accounts.removeAll { $0.id == a.id }; accounts.insert(a, at: 0)
            setup.account = .ready
        } catch { setup.account = .failed(error.localizedDescription) }
    }

    // MARK: Worlds and servers (GAP-13)

    public func deleteWorld(_ w: WorldSummary) async {
        guard let inst = activeInstance?.id else { return }
        await run { try await self.backend.deleteWorld(instanceID: inst, worldID: w.id); self.worlds.removeAll { $0.id == w.id } }
    }

    public func backUpWorld(_ w: WorldSummary) async -> URL? {
        guard let inst = activeInstance?.id else { return nil }
        var url: URL?
        await run { url = try await self.backend.backUpWorld(instanceID: inst, worldID: w.id) }
        return url
    }

    public func addServer(name: String, address: String) async {
        guard let inst = activeInstance?.id, !address.isEmpty else { return }
        await run {
            let s = try await self.backend.addServer(instanceID: inst, name: name.isEmpty ? address : name, address: address)
            self.servers.append(s)
        }
    }

    public func removeAccount(_ a: Account) async {
        await run { try await self.backend.removeAccount(id: a.id); self.accounts.removeAll { $0.id == a.id } }
    }

    // MARK: Launch

    public func play(_ instanceID: String? = nil) {
        guard let id = instanceID ?? activeInstance?.id else { return }
        activeInstanceID = id
        launchError = nil; launchLog = []
        launch = LaunchProgress(stage: 1, of: 8, title: "JIT")
        Task {
            for await line in backend.logLines(.launcher) { launchLog.append(line); if launch == nil { break } }
        }
        Task {
            do {
                for try await p in backend.launch(instanceID: id, accountID: activeAccount?.id) {
                    launch = p
                    if p.finished { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            } catch {
                launchError = error.localizedDescription
            }
        }
    }

    public func cancelLaunch() async {
        await backend.cancelLaunch()
        launch = nil
    }

    // MARK: Instances

    /// Returns `nil` and sets `lastError` on failure, so the sheet can stay open.
    public func createInstance(name: String, version: String, loader: Loader, loaderVersion: String?,
                               ownFolder: Bool = true, fabricAPI: Bool = true) async -> InstanceSummary? {
        var made: InstanceSummary?
        await run {
            let i = self.can(.createOptions)
                ? try await self.backend.createInstance(name: name, version: version, loader: loader, ownFolder: ownFolder, fabricAPI: fabricAPI)
                : try await self.backend.createInstance(name: name, version: version, loader: loader)
            if let v = loaderVersion, loader != .vanilla, !loader.usesAirInstaller {
                try await self.backend.installLoader(instanceID: i.id, loader: loader, version: v)
            }
            self.instances.append(i); made = i
        }
        return made
    }

    public func duplicate(_ id: String) async {
        await run { let copy = try await self.backend.duplicate(instanceID: id); self.instances.append(copy) }
    }

    public func delete(_ id: String) async {
        await run { try await self.backend.delete(instanceID: id); self.instances.removeAll { $0.id == id } }
        if activeInstanceID == id { activeInstanceID = instances.first?.id }
    }

    public func export(_ id: String) async -> URL? {
        var url: URL?
        await run { url = try await self.backend.export(instanceID: id, format: .mrpack) }
        return url
    }

    public func preferences(for id: String) -> GamePreferences { instancePreferences[id] ?? preferences }

    public func loadPreferences(for id: String) async {
        await run { self.instancePreferences[id] = try await self.backend.preferences(instanceID: id) }
    }

    public func save(_ p: GamePreferences, instanceID: String? = nil) {
        if let instanceID { instancePreferences[instanceID] = p } else { preferences = p }
        Task { await run { try await self.backend.setPreferences(p, instanceID: instanceID) } }
    }

    // MARK: Mods

    public func search() async {
        searching = true; defer { searching = false }
        do { results = try await backend.search(query); searchError = nil }
        catch is CancellationError {}
        catch { results = []; searchError = error.localizedDescription }
    }

    public func loadProject(_ id: String) async {
        guard let inst = activeInstance?.id else { return }
        await run {
            let v = try await self.backend.versions(projectID: id, instanceID: inst)
            self.versions[id] = v
            if let first = v.first(where: \.fits) { self.dependencies[first.id] = try await self.backend.dependencies(versionID: first.id, instanceID: inst) }
        }
    }

    public func install(projectID: String, versionID: String? = nil) {
        guard let inst = activeInstance?.id else { return }
        let version = versionID ?? versions[projectID]?.first(where: \.fits)?.id ?? "latest"
        installing.insert(projectID)
        Task {
            defer { installing.remove(projectID) }
            do {
                for try await _ in backend.install(projectID: projectID, versionID: version, instanceID: inst) {}
                if let i = results.firstIndex(where: { $0.id == projectID }) { results[i].installed = true }
                installed[.mods] = try await backend.installed(.mods, instanceID: inst)
            } catch { lastError = error.localizedDescription }
        }
    }

    public func importPack(_ url: URL, intoInstance: Bool = false) {
        importProgress = InstallProgress(title: url.deletingPathExtension().lastPathComponent, fraction: 0)
        Task {
            do {
                for try await p in backend.importPack(url, instanceID: intoInstance ? activeInstance?.id : nil) { importProgress = p }
                instances = try await backend.instances()
            } catch { lastError = error.localizedDescription }
        }
    }

    public func loadInstalled(_ kind: ContentKind) async {
        guard let inst = activeInstance?.id else { return }
        await run { self.installed[kind] = try await self.backend.installed(kind, instanceID: inst) }
    }

    public func setEnabled(_ on: Bool, item: InstalledItem) {
        guard let inst = activeInstance?.id, var list = installed[item.kind], let i = list.firstIndex(of: item) else { return }
        list[i].enabled = on; installed[item.kind] = list
        Task { await run { try await self.backend.setEnabled(on, item: item, instanceID: inst) } }
    }

    public func deleteItem(_ item: InstalledItem) {
        guard let inst = activeInstance?.id else { return }
        installed[item.kind]?.removeAll { $0.id == item.id }
        Task { await run { try await self.backend.delete(item, instanceID: inst) } }
    }

    public func updateAll() async {
        guard let inst = activeInstance?.id else { return }
        await run {
            try await self.backend.updateAll(instanceID: inst)
            self.installed[.mods] = try await self.backend.installed(.mods, instanceID: inst)
            if let i = self.instances.firstIndex(where: { $0.id == inst }) { self.instances[i].updatesAvailable = 0 }
        }
    }

    // MARK: Logs, system, look

    public func streamLog(_ kind: LogKind) async {
        logs[kind] = []
        for await line in backend.logLines(kind) { logs[kind, default: []].append(line) }
    }

    public func exportLog(_ kind: LogKind) async -> URL? {
        var url: URL?
        await run { url = try await self.backend.exportLog(kind) }
        return url
    }

    public func clearCache() async {
        await run { try await self.backend.clearCache() }
        storage = await backend.storage()
    }

    public func setCurseForgeKey(_ key: String) {
        do { try backend.setCurseForgeKey(key.isEmpty ? nil : key); curseForgeKey = key.isEmpty ? nil : key }
        catch { lastError = error.localizedDescription }
    }

    /// X07: swaps the accent family and appearance for both stacks and pushes the colors to Air (GAP-11).
    public func applyTheme(accent: AccentFamily? = nil, appearance: Appearance? = nil) {
        var t = CofreTheme.current
        if let accent { t.accent = accent }
        if let appearance { t.appearance = appearance }
        CofreTheme.current = t
        theme = t
        CofreUIKitTheme.apply(t)
        onThemeChange?(t)
        backend.applyAirAppearance(accentHex: UIColor.cofre.face.hexString(), cardHex: UIColor.cofre.panel.hexString(),
                                   textHex: UIColor.cofre.ink.hexString())
    }

    /// Runs the pending confirmation's action.
    public func confirm(_ c: Confirmation) async {
        switch c {
        case .deleteInstance(let i): await delete(i.id)
        case .deleteWorld(let w): await deleteWorld(w)
        case .removeAccount(let a): await removeAccount(a)
        }
    }

    private func run(_ body: @escaping () async throws -> Void) async {
        do { try await body() } catch { lastError = error.localizedDescription }
    }
}

/// Destructive actions confirmed by the root view's alert, whichever menu, swipe or button started them.
public enum Confirmation: Identifiable, Equatable {
    case deleteInstance(InstanceSummary), deleteWorld(WorldSummary), removeAccount(Account)
    public var id: String {
        switch self {
        case .deleteInstance(let i): "instance-\(i.id)"
        case .deleteWorld(let w): "world-\(w.id)"
        case .removeAccount(let a): "account-\(a.id)"
        }
    }
}

extension CheckState {
    var isFailed: Bool { if case .failed = self { true } else { self == .blocked } }
}
#endif
