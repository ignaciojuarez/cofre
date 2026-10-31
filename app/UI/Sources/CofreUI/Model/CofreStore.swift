#if canImport(UIKit)
    import SwiftUI
    import CofreKit

    /// UI state for every screen. Screens read this; it calls the `CofreBackend` protocols.
    /// Errors surface as a banner (`lastError`) instead of crashing a pane.
    @Observable @MainActor
    public final class CofreStore {
        public let services: CofreServices
        var backend: any CofreBackend { services.backend }
        /// Cofre-owned instance files. The launcher profile remains Air-compatible on disk.
        public let instanceStore: InstanceStore?

        // Setup
        public var setup = SetupState()
        /// `true` once the first `setupState()` returns. Until then the root shows a neutral splash, not the wizard.
        public private(set) var setupLoaded = false
        /// Saved: setup finished once. After that, live failures show as a banner on Play, never the wizard again.
        public var setupCompleted: Bool { didSet { defaults.set(setupCompleted, forKey: PreferenceKey.setupCompleted.rawValue) } }
        /// Saved: the wizard step the user was on (0 welcome … 7 ready), so a cold start resumes there.
        public var setupStep: Int? { didSet { defaults.set(setupStep, forKey: PreferenceKey.setupStep.rawValue) } }
        /// Set when the key came from a picked file (AirDrop fallback), so S04 can say to delete that copy.
        public var pairingFromFile = false
        public var jitSteps: [JITStatusStep] = []
        public var jitTesting = false
        public var signing: SigningInfo?
        public var device: DeviceInfo?

        // Library
        public private(set) var libraryLoaded = false
        public var instances: [InstanceSummary] = [] { didSet { searchModsInstance() } }
        /// Play's instance. When it runs mods, Mods works on it too.
        public var activeInstanceID: String? { didSet { searchModsInstance() } }
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
        /// Why a project's versions didn't load, so M02 shows Try again instead of a spinner.
        public var versionsError: [String: String] = [:]
        /// Project pages (About, Gallery, links) by project ID, with videos found in the body (`CofreStore+Pages`).
        public var pages: [String: ProjectPage] = [:]
        /// The About tab's sanitized HTML for `ProjectBody`; missing when the project has no body.
        public var pageDocuments: [String: PageDocument] = [:]
        /// Why a page didn't load. The summary and Get keep working without it.
        public var pageErrors: [String: String] = [:]
        /// Loaded page IDs, oldest first, so only the newest few stay in memory.
        @ObservationIgnored var pageOrder: [String] = []
        public var dependencies: [String: [ProjectDependency]] = [:]
        public var installed: [ContentKind: [InstalledItem]] = [:]
        /// Gets in flight or waiting to be read, by project ID (planning, confirming, installing, done, failed).
        public var modInstalls: [String: ModInstall] = [:]
        /// The Get sheet: which `modInstalls` entry it shows.
        public var modInstallSheet: String?
        /// Installs run one at a time, so two Gets never write the same dependency twice.
        @ObservationIgnored private var installChain: Task<Void, Never>?
        @ObservationIgnored private var fullVersionTasks: [String: Task<Void, Never>] = [:]
        public var importProgress: InstallProgress?
        /// Saved: the last modded instance picked (in Mods, Play or Instances), so Mods keeps it while Play is on
        /// Vanilla.
        public var modsInstanceID: String? { didSet { defaults.set(modsInstanceID, forKey: PreferenceKey.modsInstance.rawValue) } }
        /// Pre-fills P04 New instance when it opens from Mods.
        public var newInstancePlan: NewInstancePlan?

        // Launch
        public var launch: LaunchProgress?
        public var launchFailure: LaunchFailure?
        /// Retained for callers displaying or setting an unclassified message.
        public var launchError: String? {
            get { launchFailure?.localizedDescription }
            set { launchFailure = newValue.map(LaunchFailure.unknown) }
        }
        public var launchRecovery: LaunchFailure.Recovery? {
            guard let failure = launchFailure else { return nil }
            // A download can be retried only before Java has started.
            return failure.recovery == .retry && (launch?.stage ?? 0) >= 3 ? .log : failure.recovery
        }
        @ObservationIgnored private var launchRejoin: RejoinIntent?
        public var launchLog: [LogLine] = []
        public var logs: [LogKind: [LogLine]] = [:]
        public var pendingModCompatibility: [ModCompatibilityIssue]?

        // System
        public var renderers: [RendererOption] = []
        public var javaRuntimes: [JavaRuntime] = []
        public var storage: StorageUsage?
        public var curseForgeKey: String?
        public var lastError: String?

        // Servers (plan/servers.md). `servers` above is the active instance's servers.dat, read again on every show.
        /// The instance `servers` was loaded for; differs from the active one while it loads.
        public var serversInstanceID: String?
        /// Live ping per address (lowercased). Rows merge it over the saved fields.
        public var serverPings: [String: ServerPingState] = [:]
        /// "Recommended" (Modrinth's list) for `recommendedInstanceID`.
        public var recommended: [ServerSummary] = []
        public var recommendedInstanceID: String?
        public var recommendedError: String?
        public var recommendedLoading = false
        /// The server the running launch joins; the launch screen names it.
        public var joiningServer: ServerSummary?

        // Server join (GAP-14)
        /// Live Join server models by `ServerJoinRequest.id`. An installing one stays after its sheet closes.
        public var serverJoins: [String: any ServerJoinViewModel] = [:]
        /// Set by the sheet's "Launch & Join"; the root starts the launch once the sheet is gone.
        public var pendingJoinIntent: RejoinIntent?
        public var pendingJoinLaunch: String?
        /// A destructive action waiting for the one shared confirmation alert (root view).
        public var pendingConfirmation: Confirmation?
        private var lastTrash: InstanceStore.TrashToken?
        /// Deleted instances that can still be restored (their files sit in the instances' trash).
        public private(set) var recentlyDeleted: [InstanceStore.Deleted] = []
        @ObservationIgnored private let defaults: UserDefaults

        /// `defaults` holds the setup progress; tests and the preview host pass their own suite.
        public init(services: CofreServices, defaults: UserDefaults = .standard) {
            self.services = services
            self.instanceStore = services.instances
            self.defaults = defaults
            setupCompleted = defaults.bool(forKey: PreferenceKey.setupCompleted.rawValue)
            setupStep = defaults.object(forKey: PreferenceKey.setupStep.rawValue) as? Int
            modsInstanceID = defaults.string(forKey: PreferenceKey.modsInstance.rawValue)
        }

        public var capabilities: BackendCapabilities { backend.capabilities }
        public func can(_ c: BackendCapabilities) -> Bool { capabilities.contains(c) }

        public var activeInstance: InstanceSummary? { instances.first { $0.id == activeInstanceID } ?? instances.first }
        public var activeAccount: Account? { accounts.first { $0.isActive } ?? accounts.first }
        public var updateCount: Int { modsInstance?.updatesAvailable ?? 0 }
        public var isJITReady: Bool { setup.jit.isReady }
        /// The wizard shows only for users who never finished it, once their state has loaded. It stays up through
        /// S08 Ready even when every check passes mid-flow; `finishSetup()` (Play) or a complete state at load ends it.
        public var showsSetup: Bool { setupLoaded && !setupCompleted }
        /// Where a cold start opens the wizard: the saved step, unless that step's check has passed since.
        public var resumeStep: Int {
            guard let saved = setupStep else { return 0 }
            guard (1...6).contains(saved) else { return saved == 7 ? (setup.isComplete ? 7 : firstOpenStep) : saved }
            return setup.all[saved - 1].isReady ? firstOpenStep : saved
        }

        /// The first check that isn't ready (1…6), or 7 (Ready) when all pass.
        public var firstOpenStep: Int { (setup.all.firstIndex { !$0.isReady } ?? 6) + 1 }

        public func finishSetup() {
            setupCompleted = true
            setupStep = nil
        }

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
                if let instanceStore = self.instanceStore {
                    self.instances = try instanceStore.list().map(Self.summary)
                    self.recentlyDeleted = instanceStore.recentlyDeleted()
                } else {
                    self.instances = try await self.backend.instances()
                }
                self.accounts = try await self.backend.accounts()
                self.preferences = try await self.backend.preferences(instanceID: nil)
            }
            libraryLoaded = true
            if activeInstanceID == nil { activeInstanceID = instanceStore?.lastPlayedID ?? instances.first?.id }
            await loadActiveInstance()
        }

        public func selectInstance(_ id: String) async {
            activeInstanceID = id
            if let i = instances.first(where: { $0.id == id }), i.loader != .vanilla { modsInstanceID = id }
            await loadActiveInstance()
        }

        func loadActiveInstance() async {
            guard let id = activeInstance?.id else { return }
            let mods = modsInstance?.id
            await run {
                async let s = self.backend.servers(instanceID: id)
                self.servers = try await s
                self.serversInstanceID = id
                self.pingServers()
                if let mods { self.installed[.mods] = try await self.backend.installed(.mods, instanceID: mods) }
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
            do {
                try backend.importPairing(data)
                pairingFromFile = true
                setup.pairing = .ready
            } catch { setup.pairing = .failed(error.localizedDescription) }
        }

        public func startVPN() async {
            setup.vpn = .checking
            do {
                try await backend.startVPN()
                setup.vpn = .ready
            } catch { setup.vpn = .failed(error.localizedDescription) }
        }

        public func testJIT() async {
            jitTesting = true
            jitSteps = JITStatusStep.Kind.allCases.map { JITStatusStep(kind: $0, state: .unknown) }
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
                if let i = jitSteps.firstIndex(where: { $0.state == .checking }) {
                    jitSteps[i].state = .failed(error.localizedDescription)
                }
                setup.jit = .failed(error.localizedDescription)
            }
        }

        /// The step that failed in the last JIT test, for the next-step hint.
        public var failedJITStep: JITStatusStep.Kind? {
            jitSteps.first { $0.state.isFailed }?.kind
        }

        public func signIn() async {
            setup.account = .checking
            do {
                let a = try await backend.signInMicrosoft()
                accounts.removeAll { $0.id == a.id }
                accounts.insert(a, at: 0)
                setup.account = .ready
            } catch { setup.account = .failed(error.localizedDescription) }
        }

        // MARK: Server join (GAP-14)

        /// The live model for `request`, made on first use. `nil` without `.serverJoin` or when the backend has none.
        @discardableResult public func openServerJoin(_ request: ServerJoinRequest) -> (any ServerJoinViewModel)? {
            if let m = serverJoins[request.id] { return m }
            guard can(.serverJoin), let m = backend.serverJoin(request) else { return nil }
            serverJoins[request.id] = m
            return m
        }

        /// The sheet closed. An install keeps its model and keeps going; anything else is dropped, so the next open
        /// reads the card again.
        public func closeServerJoin(_ request: ServerJoinRequest) {
            guard let m = serverJoins[request.id] else { return }
            m.send(.dismiss)
            if case .installing = m.state { return }
            serverJoins[request.id] = nil
        }

        /// Install progress for a server row while its sheet is closed.
        public func serverJoinProgress(address: String) -> Double? {
            guard case .installing(let s) = serverJoins[ServerJoinRequest(server: address).id]?.state else {
                return nil
            }
            return s.progressFraction
        }

        public func removeAccount(_ a: Account) async {
            await run {
                try await self.backend.removeAccount(id: a.id)
                self.accounts.removeAll { $0.id == a.id }
            }
        }

        // MARK: Launch

        /// With `server`, launches straight into it (`joinServer`, plan/servers.md).
        public func play(_ instanceID: String? = nil, server: ServerSummary? = nil, rejoin: RejoinIntent? = nil) {
            CofreBreadcrumb.log("play", details: instanceID.map { "instance=\($0)" } ?? "")

            guard let id = instanceID ?? activeInstance?.id else { return }
            activeInstanceID = id
            if instances.first(where: { $0.id == id })?.restartRequired == true {
                pendingModCompatibility = nil
                startPlay(id, server: server, rejoin: rejoin)
                return
            }
            if rejoin == nil, server == nil, let instance = instances.first(where: { $0.id == id }) {
                let issues = playIssues(instance)
                if !issues.isEmpty {
                    NSLog("[Cofre] compat play check instance=%@ issues=%@", id, issues.map(\.badge).joined(separator: ","))
                    pendingModCompatibility = issues
                    return
                }
            }
            startPlay(id, server: server, rejoin: rejoin)
        }

        public func playAnywayAfterModWarning(turnOff: Bool) {
            guard let id = activeInstance?.id else { pendingModCompatibility = nil; return }
            if turnOff, let issues = pendingModCompatibility { turnOffForPlay(issues, instanceID: id) }
            pendingModCompatibility = nil
            startPlay(id, server: nil, rejoin: nil)
        }

        private func startPlay(_ id: String, server: ServerSummary?, rejoin: RejoinIntent?) {
            joiningServer = server
            launchRejoin = rejoin
            launchFailure = nil
            launchLog = []
            launch = LaunchProgress(stage: 1, of: 7, title: "JIT")
            guard instances.first(where: { $0.id == id })?.restartRequired != true else {
                launchFailure = .restartRequired
                return
            }
            Task {
                for await line in backend.logLines(.launcher) {
                    launchLog.append(line)
                    if launch == nil { break }
                }
            }
            Task {
                do {
                    let stream =
                        rejoin.map {
                            backend.rejoin(instanceID: id, kind: $0.kind, target: $0.target, accountID: activeAccount?.id)
                        } ?? server.map {
                            backend.joinServer(instanceID: id, address: $0.address, accountID: activeAccount?.id)
                        } ?? backend.launch(instanceID: id, accountID: activeAccount?.id)
                    for try await p in stream {
                        launch = p
                        if p.finished { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    }
                } catch is CancellationError {
                    launch = nil
                } catch {
                    launchFailure = (error as? LaunchFailure) ?? .unknown(error.localizedDescription)
                }
            }
        }

        public func retryLaunch() {
            guard launchRecovery == .retry, let id = activeInstance?.id else { return }
            startPlay(id, server: joiningServer, rejoin: launchRejoin)
        }

        public func cancelLaunch() async {
            await backend.cancelLaunch()
            launch = nil
        }

        // MARK: Instances

        /// Returns `nil` and sets `lastError` on failure, so the sheet can stay open.
        public func createInstance(
            name: String, version: String, loader: Loader, loaderVersion: String?,
            ownFolder: Bool = true, fabricAPI: Bool = true
        ) async -> InstanceSummary? {
            guard loader == .vanilla || !(loaderVersion?.isEmpty ?? true) else {
                lastError = "Choose a loader version before creating the instance."
                return nil
            }
            var made: InstanceSummary?
            await run {
                let i: InstanceSummary
                if let instanceStore = self.instanceStore {
                    let made = try instanceStore.create(name: name, version: version, loader: loader, loaderVersion: loaderVersion)
                    do {
                        // The engine's installer writes the loader's real version id into the profile.
                        if let v = loaderVersion, loader != .vanilla {
                            try await self.backend.installLoader(instanceID: made.id, loader: loader, version: v)
                        }
                    } catch {
                        // Do not leave a plain-Minecraft profile behind. It looks modded in Cofre's metadata,
                        // but Air would launch the base version and silently ignore the mods.
                        try? instanceStore.remove(made.id)
                        throw error
                    }
                    i = Self.summary(try instanceStore.list().first { $0.id == made.id } ?? made)
                } else {
                    i = self.can(.createOptions)
                        ? try await self.backend.createInstance(name: name, version: version, loader: loader, ownFolder: ownFolder, fabricAPI: fabricAPI)
                        : try await self.backend.createInstance(name: name, version: version, loader: loader)
                    if let v = loaderVersion, loader != .vanilla { try await self.backend.installLoader(instanceID: i.id, loader: loader, version: v) }
                }
                self.instances.append(i)
                made = i
            }
            // A loader's processor JVM affects every instance, including failed installs.
            if let instanceStore, let refreshed = try? instanceStore.list() {
                instances = refreshed.map(Self.summary)
            }
            return made
        }

        public func duplicate(_ id: String) async {
            await run {
                let copy: InstanceSummary
                if let instanceStore = self.instanceStore { copy = Self.summary(try instanceStore.duplicate(id)) }
                else { copy = try await self.backend.duplicate(instanceID: id) }
                self.instances.append(copy)
            }
        }

        public func delete(_ id: String) async {
            await run {
                if let instanceStore = self.instanceStore {
                    self.lastTrash = try instanceStore.trash(id)
                    self.recentlyDeleted = instanceStore.recentlyDeleted()
                } else { try await self.backend.delete(instanceID: id) }
                self.instances.removeAll { $0.id == id }
            }
            if activeInstanceID == id { activeInstanceID = instances.first?.id }
        }

        public func restore(_ deleted: InstanceStore.Deleted) async {
            guard let instanceStore else { return }
            await run {
                self.instances.append(Self.summary(try instanceStore.restore(deleted)))
                self.recentlyDeleted = instanceStore.recentlyDeleted()
            }
        }

        public func undoDelete() async {
            guard let token = lastTrash, let instanceStore else { return }
            await run {
                self.instances.append(Self.summary(try instanceStore.restore(token)))
                self.lastTrash = nil
                self.recentlyDeleted = instanceStore.recentlyDeleted()
            }
        }

        public func export(_ id: String) async -> URL? {
            var url: URL?
            await run {
                if let instanceStore = self.instanceStore { url = try instanceStore.export(id) }
                else { url = try await self.backend.export(instanceID: id, format: .mrpack) }
            }
            return url
        }

        public func setInstanceMeta(_ id: String, notes: String? = nil, group: String?? = nil, favorite: Bool? = nil) async {
            guard let instanceStore else { return }
            await run {
                let i = try instanceStore.setMetadata(id, notes: notes, group: group, favorite: favorite)
                if let n = self.instances.firstIndex(where: { $0.id == id }) { self.instances[n] = Self.summary(i) }
            }
        }

        public func renameInstance(_ id: String, to name: String) async {
            guard let instanceStore, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await run {
                let i = try instanceStore.rename(id, to: name.trimmingCharacters(in: .whitespacesAndNewlines))
                if let n = self.instances.firstIndex(where: { $0.id == id }) { self.instances[n] = Self.summary(i) }
            }
        }

        private static func summary(_ i: Instance) -> InstanceSummary {
            let loader = i.loader
            // Air's "latest-release" alias resolves to the newest release at launch.
            let game = ["latest-release": "Latest release", "latest-snapshot": "Latest snapshot"][i.gameVersion] ?? i.gameVersion
            var summary = InstanceSummary(id: i.id, name: i.name, loader: loader, gameVersion: game,
                                   loaderVersion: i.loaderVersion, javaVersion: i.javaVersion.map(String.init),
                                   icon: InstanceIcon.resolve(png: nil, picked: i.icon, id: i.id, loader: loader),
                                   favorite: i.favorite, group: i.group, notes: i.notes,
                                   restartRequired: i.restartRequired)
            summary.renderer = i.renderer
            return summary
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

        /// Searches the current query. Only the search for the latest query may change results, the error or
        /// the spinner: an older one that finishes late, or that a keystroke cancelled, leaves them alone.
        public func search() async {
            let q = query
            searching = true
            defer { if q == query { searching = false } }
            do {
                // The target's own list too, so rows show ✓ for what it already has (after a switch, too).
                async let found = backend.search(q)
                if let inst = q.instanceID, q.kind != .modpacks,
                    let have = try? await backend.installed(q.kind, instanceID: inst), q == query
                {
                    installed[q.kind] = have
                }
                let hits = try await found
                guard q == query, !Task.isCancelled else { return }
                results = hits
                searchError = nil
            } catch {
                // Cancelling also surfaces as URLError.cancelled from URLSession; neither is a failure.
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                guard q == query, !Task.isCancelled, !cancelled else { return }
                NSLog("[Cofre] search failed: %@", String(describing: error))
                results = []
                searchError = error.localizedDescription
            }
        }

        public func loadProject(_ id: String) async {
            guard let inst = modsInstance?.id else {
                versionsError[id] = String(localized: "Pick an instance first.")
                return
            }
            fullVersionTasks[id]?.cancel()
            fullVersionTasks[id] = nil
            versionsError[id] = nil
            do {
                let matching = try await backend.versions(projectID: id, instanceID: inst)
                versions[id] = matching
                if results.first(where: { $0.id == id })?.source != .curseforge {
                    fullVersionTasks[id] = Task { [weak self] in
                        guard let self else { return }
                        do {
                            let all = try await self.backend.allVersions(projectID: id, instanceID: inst)
                            guard !Task.isCancelled, self.modsInstance?.id == inst else { return }
                            var seen = Set<String>()
                            let merged = (matching + all).filter { seen.insert($0.id).inserted }
                            self.versions[id] = merged
                            if merged.count > matching.count {
                                NSLog("[Cofre] modrinth versions project=%@ matched=%ld total=%ld", id, matching.count, merged.count)
                            }
                            if matching.preferred == nil, let first = merged.preferred {
                                self.dependencies[first.id] = try? await self.backend.dependencies(versionID: first.id, instanceID: inst)
                            }
                        } catch is CancellationError {} catch {
                            // The fast response is already useful; a slow or offline full catalog is optional.
                        }
                    }
                }
                if let first = matching.preferred {
                    dependencies[first.id] = try await backend.dependencies(versionID: first.id, instanceID: inst)
                }
            } catch is CancellationError {} catch {
                versionsError[id] = error.localizedDescription
            }
        }

        /// Get: works out what installs, asks only when that's more than the project itself, then installs. Blocked
        /// or failed Gets open the sheet with the reason.
        public func get(_ projectID: String, versionID: String? = nil) {
            guard let inst = modsInstance?.id else { return }
            if let busy = modInstalls[projectID], !busy.isFinished {
                if busy.phase != .planning { modInstallSheet = projectID }
                return
            }
            let kind = query.kind
            let title = results.first { $0.id == projectID }?.title ?? projectID
            modInstalls[projectID] = ModInstall(id: projectID, title: title, instanceID: inst)
            Task {
                do {
                    var plan = try await backend.installPlan(
                        projectID: projectID, versionID: versionID, kind: kind, instanceID: inst)
                    if plan.target.name == plan.target.id { plan.target.name = title }
                    modInstalls[projectID]?.plan = plan
                    if let reason = plan.blocked {
                        fail(projectID, reason, retry: false)
                    } else if plan.needsConfirmation
                        || self.compatibilityIssue(id: plan.target.id, name: plan.target.name, kind: kind) != nil
                    {
                        modInstalls[projectID]?.phase = .confirm
                        modInstallSheet = projectID
                    } else {
                        confirmInstall(projectID)
                    }
                } catch is CancellationError {
                    modInstalls[projectID] = nil
                } catch {
                    fail(projectID, Self.installMessage(error), retry: true)
                }
            }
        }

        /// Kept for callers from before plans: same as Get.
        public func install(projectID: String, versionID: String? = nil) { get(projectID, versionID: versionID) }

        /// The sheet's Install. Queues behind any install already running.
        public func confirmInstall(_ projectID: String) {
            guard var job = modInstalls[projectID], let plan = job.plan else { return }
            job.phase = .queued
            job.progress = InstallProgress(
                title: plan.target.name, fraction: 0,
                stages: plan.files(picking: job.picked).map { .init(title: $0.name, state: .unknown) })
            modInstalls[projectID] = job
            let previous = installChain
            installChain = Task {
                await previous?.value
                await runInstall(projectID)
            }
        }

        private func runInstall(_ projectID: String) async {
            guard var job = modInstalls[projectID], let plan = job.plan else { return }
            job.phase = .installing
            modInstalls[projectID] = job
            do {
                for try await p in backend.install(plan, picking: job.picked, instanceID: job.instanceID) {
                    modInstalls[projectID]?.progress = p
                }
                modInstalls[projectID]?.phase = .done
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if plan.makesInstance {
                    instances = (try? await backend.instances()) ?? instances
                } else if job.instanceID == modsInstance?.id {
                    installed[plan.kind] = try? await backend.installed(plan.kind, instanceID: job.instanceID)
                }
                // Nobody's looking: a quiet success needs no sheet.
                if modInstallSheet != projectID { modInstalls[projectID] = nil }
            } catch {
                // Mark the file that was going; the others never landed.
                if var stages = modInstalls[projectID]?.progress?.stages,
                    let i = stages.firstIndex(where: { $0.state == .checking })
                {
                    stages[i].state = .failed(Self.installMessage(error))
                    modInstalls[projectID]?.progress?.stages = stages
                }
                fail(projectID, Self.installMessage(error), retry: true)
            }
        }

        private func fail(_ projectID: String, _ reason: String, retry: Bool) {
            modInstalls[projectID]?.phase = .failed(reason)
            modInstalls[projectID]?.canRetry = retry
            modInstallSheet = projectID
        }

        /// The sheet closed. Finished Gets are forgotten; running ones keep going on the row.
        public func closeModInstall(_ projectID: String) {
            if modInstallSheet == projectID { modInstallSheet = nil }
            if modInstalls[projectID]?.isFinished == true || modInstalls[projectID]?.phase == .confirm {
                modInstalls[projectID] = nil
            }
        }

        /// Try again after a failure: plans again, since the reason may have changed (online again, mod turned off).
        public func retryInstall(_ projectID: String) {
            let version = modInstalls[projectID]?.plan?.target.versionID
            modInstalls[projectID] = nil
            get(projectID, versionID: version?.isEmpty == false ? version : nil)
        }

        /// Offline reads as offline, not as a URL error.
        static func installMessage(_ error: Error) -> String {
            if let u = error as? URLError,
                [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(u.code)
            {
                return String(localized: "You're offline. Connect and try again.")
            }
            return error.localizedDescription
        }

        /// A search row in the Mods target: installed, off, or with an update. Modpacks become instances, so never.
        public func installState(_ p: ProjectSummary) -> ProjectInstallState {
            guard let item = installedItem(for: p) else { return .notInstalled }
            if let to = item.updateTo { return .update(to) }
            return item.enabled ? .installed : .off
        }

        /// The target's file for a search row, if it has one.
        public func installedItem(for p: ProjectSummary) -> InstalledItem? {
            guard query.kind != .modpacks else { return nil }
            let items = installed[query.kind] ?? []
            // An exact project match beats a same-name one.
            return items.first { $0.projectID == p.id } ?? items.first { $0.matches(p.id, title: p.title) }
        }

        /// Update: exactly the build the backend offered, so a beta never replaces a release unasked.
        public func update(_ p: ProjectSummary) {
            get(p.id, versionID: installedItem(for: p)?.updateVersionID)
        }

        /// Instances that can run mods: Mods targets one of these.
        public var moddedInstances: [InstanceSummary] { instances.filter { $0.loader != .vanilla } }

        /// Where Mods searches and installs: Play's instance when it runs mods, else the last one picked, else the
        /// most recently played. `nil` when none runs mods; Mods then only offers to make one.
        public var modsInstance: InstanceSummary? {
            if let a = activeInstance, a.loader != .vanilla { return a }
            let modded = moddedInstances
            return modded.first { $0.id == modsInstanceID }
                ?? modded.max { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
        }

        /// Points the search at the Mods target whenever it may have changed.
        private func searchModsInstance() {
            guard query.instanceID != modsInstance?.id else { return }
            query.instanceID = modsInstance?.id
            for kind in query.filtersByKind.keys { query.filtersByKind[kind]?.followInstance() }
        }

        /// P04 from Mods: Fabric on the active version (empty: the newest release), with a name that isn't taken.
        public func planNewInstance() -> NewInstancePlan {
            let version = activeInstance?.gameVersion ?? ""
            var name = version.isEmpty ? Loader.fabric.displayName : "\(Loader.fabric.displayName) \(version)"
            let taken = Set(instances.map(\.name))
            if taken.contains(name) {
                let base = name
                name = (2...).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) }!
            }
            return NewInstancePlan(name: name, version: version, loader: .fabric)
        }

        public func importPack(_ url: URL, intoInstance: Bool = false) {
            CofreBreadcrumb.log("import", details: url.lastPathComponent)

            importProgress = InstallProgress(title: url.deletingPathExtension().lastPathComponent, fraction: 0)
            Task {
                do {
                    for try await p in backend.importPack(url, instanceID: intoInstance ? activeInstance?.id : nil) {
                        importProgress = p
                    }
                    await refreshLibrary()
                } catch {
                    importProgress = nil
                    lastError = error.localizedDescription
                }
            }
        }

        public func loadInstalled(_ kind: ContentKind) async {
            guard let inst = modsInstance?.id else { return }
            await run { self.installed[kind] = try await self.backend.installed(kind, instanceID: inst) }
        }

        public func setEnabled(_ on: Bool, item: InstalledItem) {
            CofreBreadcrumb.log("toggle", details: "\(item.id)=\(on ? "on" : "off")")

            guard let inst = modsInstance?.id, var list = installed[item.kind], let i = list.firstIndex(of: item)
            else { return }
            list[i].enabled = on
            installed[item.kind] = list
            Task { await run { try await self.backend.setEnabled(on, item: item, instanceID: inst) } }
        }

        public func deleteItem(_ item: InstalledItem) {
            CofreBreadcrumb.log("delete", details: item.id)

            guard let inst = modsInstance?.id else { return }
            installed[item.kind]?.removeAll { $0.id == item.id }
            Task { await run { try await self.backend.delete(item, instanceID: inst) } }
        }

        public func updateAll(kind: ContentKind = .mods) async {
            guard let inst = modsInstance?.id else { return }
            await run {
                let count = self.installed[kind]?.filter { $0.updateTo != nil }.count ?? 0
                try await self.backend.updateAll(kind: kind, instanceID: inst)
                self.installed[kind] = try await self.backend.installed(kind, instanceID: inst)
                if let i = self.instances.firstIndex(where: { $0.id == inst }) {
                    self.instances[i].updatesAvailable = max(0, self.instances[i].updatesAvailable - count)
                }
            }
        }

        // MARK: Logs, system

        public func streamLog(_ kind: LogKind) async {
            logs[kind] = []
            for await line in backend.logLines(kind) { logs[kind, default: []].append(line) }
        }

        public func exportLog(_ kind: LogKind) async -> URL? {
            var url: URL?
            await run { url = try await self.backend.exportLog(kind) }
            return url
        }

        public func exportReport() async -> URL? {
            var url: URL?
            await run { url = try await self.backend.exportReport() }
            return url
        }

        public func reportPreview() async -> ReportPreviewData { await backend.reportPreview() }

        public func clearCache() async {
            await run { try await self.backend.clearCache() }
            storage = await backend.storage()
        }

        public func setCurseForgeKey(_ key: String) {
            do {
                try backend.setCurseForgeKey(key.isEmpty ? nil : key)
                curseForgeKey = key.isEmpty ? nil : key
            } catch { lastError = error.localizedDescription }
        }

        /// Runs the pending confirmation's action.
        public func confirm(_ c: Confirmation) async {
            switch c {
            case .deleteInstance(let i): await delete(i.id)
            case .removeAccount(let a): await removeAccount(a)
            case .removeServer(let s): await removeServer(s)
            }
        }

        func run(_ body: @escaping () async throws -> Void) async {
            do { try await body() } catch { lastError = error.localizedDescription }
        }
    }

    /// One Get, from planning to done. The row shows it while the sheet is closed.
    public struct ModInstall: Identifiable, Equatable {
        public enum Phase: Equatable { case planning, confirm, queued, installing, done, failed(String) }
        public let id: String
        public var title: String, instanceID: String
        public var phase = Phase.planning
        public var plan: ModInstallPlan?
        /// Optional dependencies the user turned on. None by default: offered, never forced.
        public var picked: Set<String> = []
        public var progress: InstallProgress?
        public var canRetry = false
        public var isFinished: Bool {
            switch phase {
            case .done, .failed: true
            default: false
            }
        }
        public var isBusy: Bool { [.planning, .queued, .installing].contains(phase) }
        /// Bytes still to download, for "Install · 3.1 MB".
        public var downloadBytes: Int64? {
            guard let plan else { return nil }
            let files = plan.files(picking: picked).filter { !$0.turnsOn }
            let sizes = files.compactMap(\.sizeBytes)
            return sizes.count == files.count && !files.isEmpty ? sizes.reduce(0, +) : nil
        }
    }

    /// Pre-fills P04 New instance.
    public struct NewInstancePlan: Equatable {
        public var name: String, version: String, loader: Loader
        /// From a server that needs another version: saved in the new instance once it's made.
        public var server: ServerSummary?
    }

    /// Destructive actions confirmed by the root view's alert, whichever menu, swipe or button started them.
    public enum Confirmation: Identifiable, Equatable {
        case deleteInstance(InstanceSummary)
        case removeAccount(Account)
        case removeServer(ServerSummary)
        public var id: String {
            switch self {
            case .deleteInstance(let i): "instance-\(i.id)"
            case .removeAccount(let a): "account-\(a.id)"
            case .removeServer(let s): "server-\(s.id)"
            }
        }
    }

    extension CheckState {
        var isFailed: Bool { if case .failed = self { true } else { self == .blocked } }
    }
#endif
