#if canImport(UIKit)
    import Foundation
    import UIKit
    import NetworkExtension
    import os
    import CofreUI
    import CofreKit

    public enum CofreBackendError: LocalizedError {
        case unavailable(String)
        case notOwned
        case jit(String)
        public var errorDescription: String? {
            switch self {
            case .unavailable(let name): "\(name) is unavailable in this Air build"
            case .notOwned: "This account doesn't own Minecraft: Java Edition."
            case .jit(let message): message
            }
        }
    }

    @_silgen_name("csops")
    private func csops(_ pid: pid_t, _ ops: UInt32, _ useraddr: UnsafeMutableRawPointer?, _ usersize: Int) -> Int32

    /// Production bridge. Air owns the data and launch lifecycle; unsupported Air APIs are surfaced as unavailable.
    @MainActor
    public final class CofreBackendAdapter: NSObject, CofreBackend {
        public var capabilities: BackendCapabilities {
            [.addServer, .serverFiles, .pingServers, .quickPlay, .discoverServers, .envVariables, .rendererTuning, .serverJoin]
        }
        let air: any CofreAirBridging
        var instances: InstanceStore?
        var launchingGameDirectory: URL?
        var loaderInstallInProgress = false
        let modCatalog = CofreModCatalog()
        /// The one Modrinth client (and its 30 s cache), shared with CofreUI's project pages.
        public var modrinth: Modrinth { modCatalog.modrinth }
        private lazy var accountStore: AccountStore = {
            // Air keeps accounts in $POJAV_HOME/accounts (Documents, or Caches when Documents isn't writable).
            AccountStore(directory: ProcessInfo.processInfo.environment["POJAV_HOME"].map { URL(fileURLWithPath: $0) }
                             ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
                         readSelected: { [weak self] in self?.air.preferenceObject(CofrePreferenceStore.Key.selectedAccount.rawValue, profile: nil) as? String },
                         writeSelected: { [weak self] id in self?.air.setPreferenceObject(CofrePreferenceStore.Key.selectedAccount.rawValue, value: id ?? "", profile: nil) })
        }()
        public init(bridge: any CofreAirBridging) {
            self.air = bridge
            super.init()
            CofreGameInput.shared.bridge = bridge
            if let packs = Self.modpackDirectory { ModpackImport.cleanupAbandonedImport(in: packs) }
            ModpackImport.cleanupAbandonedStaging(in: FileManager.default.temporaryDirectory)
            vpnStatusObserver = NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.refreshVPNStatus() }
            }
            Task { @MainActor in await self.refreshVPNStatus() }
            loadPersistedSetup()
        }
        deinit {
            if let vpnStatusObserver { NotificationCenter.default.removeObserver(vpnStatusObserver) }
        }
        private var launchTask: Task<Void, Never>?
        /// Where Air's importer builds each modpack instance (`<POJAV_GAME_DIR>/custom_gamedir/<id>`), so an interrupted
        /// import is rolled back there and nowhere else.
        static var modpackDirectory: URL? {
            ProcessInfo.processInfo.environment["POJAV_GAME_DIR"].map {
                URL(fileURLWithPath: $0).appendingPathComponent("custom_gamedir", isDirectory: true)
            }
        }
        private var setup = SetupState()
        private var setupContinuations: [UUID: AsyncStream<SetupState>.Continuation] = [:]
        private var preferenceStore: CofrePreferenceStore {
            CofrePreferenceStore(
                read: { [air] key, profile in air.preferenceObject(key, profile: profile) },
                write: { [air] key, value, profile in air.setPreferenceObject(key, value: value, profile: profile) })
        }
        private func loadPersistedSetup() {
            // Only the JIT test result is remembered; every other check is recomputed by `recheckSetup()`.
            if UserDefaults.standard.bool(forKey: PreferenceKey.setupJIT.rawValue) { setup.jit = .ready }
        }

        public func setupState() async -> SetupState {
            await recheckSetup()
            return setup
        }
        public func setupUpdates() -> AsyncStream<SetupState> {
            AsyncStream { continuation in
                let id = UUID()
                setupContinuations[id] = continuation
                continuation.yield(setup)
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in self?.setupContinuations.removeValue(forKey: id) }
                }
            }
        }
        /// Checks not done yet stay `.unknown` (no error shown); `.failed` is only for an attempt that failed.
        public func recheckSetup() async {
            // iOS opens a development build only with Developer Mode on and its signer trusted.
            setup.devMode = ProvisioningProfile.current?.isDevelopment == true ? .ready : .blocked
            setup.trust = .ready
            let pairingReady = hasPairing()
            setup.pairing = pairingReady ? .ready : (setup.pairing.isReady ? .unknown : setup.pairing)
            await refreshVPNStatus()
            if await CofreVPN.isAllowed() { setup.vpn = .ready } else if setup.vpn.isReady { setup.vpn = .unknown }
            // The debugger attaches only at launch, so a passed JIT test stays ready until the pairing goes away.
            if pairingReady && isJITEnabled {
                setup.jit = .ready
            } else if !pairingReady && setup.jit.isReady {
                // A remembered JIT test means nothing without a complete pairing key: launches would fail.
                UserDefaults.standard.removeObject(forKey: PreferenceKey.setupJIT.rawValue); setup.jit = .unknown
            }
            let accountReady = accountStore.list().contains { $0.state == .ready }
            if accountReady { setup.account = .ready } else if setup.account.isReady { setup.account = .unknown }
            publishSetup()
        }
        /// Settings › Privacy & Security › Developer Mode, else the Settings app.
        public func openDeveloperModeSettings() {
            let links = ["App-prefs:Privacy&path=DEVELOPER_MODE", "App-prefs:Privacy", "App-prefs:"]
            func open(_ i: Int) {
                guard i < links.count, let url = URL(string: links[i]) else { return }
                UIApplication.shared.open(url) { ok in if !ok { open(i + 1) } }
            }
            open(0)
        }
        public func hasPairing() -> Bool {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: pairingURL.path),
                  let size = attributes[.size] as? NSNumber,
                  size.uint64Value <= UInt64(PairingFileValidator.maxFileSize),
                  let data = try? Data(contentsOf: pairingURL) else { return false }
            return (try? PairingFileValidator.validate(data)) != nil
        }
        public func importPairing(_ data: Data) throws {
            _ = try PairingFileValidator.validate(data)
            try PairingFileStore.write(data, to: pairingURL)
            setup.pairing = .ready
            publishSetup()
        }
        public func deletePairing() throws { if hasPairing() { try FileManager.default.removeItem(at: pairingURL) } }
        private var vpnStatus: NEVPNStatus = .disconnected
        private var vpnStatusObserver: NSObjectProtocol?
        public var isVPNRunning: Bool { vpnStatus == .connected }
        public func startVPN() async throws {
            try await CofreVPN.connect()
            await refreshVPNStatus()
            setup.vpn = .ready
            publishSetup()
        }
        private func refreshVPNStatus() async {
            vpnStatus = (try? await CofreVPN.manager())?.connection.status ?? .disconnected
        }
        /// True once a debugger has attached to Cofre (CS_DEBUGGED), which is what turning on JIT does.
        public var isJITEnabled: Bool {
            var flags: UInt32 = 0
            return csops(getpid(), 0, &flags, MemoryLayout<UInt32>.size) == 0 && flags & 0x1000_0000 != 0
        }

        public func instances() async throws -> [InstanceSummary] {
            var list: [InstanceSummary] = air.instances().compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                let loader = Loader(rawValue: (d["loader"] as? String ?? "vanilla").lowercased()) ?? .unknown
                return InstanceSummary(
                    id: id, name: d["name"] as? String ?? id, loader: loader,
                    gameVersion: d["version"] as? String ?? "",
                    loaderVersion: (d["loaderVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    ownFolder: d["ownFolder"] as? Bool ?? true,
                    icon: .resolve(
                        png: packIcon(d["icon"] as? String), picked: d["cofreIcon"] as? String, id: id, loader: loader)
                )
            }
            for i in list.indices where list[i].loader != .vanilla {
                list[i].modCount = try? await scan(.mods, instanceID: list[i].id, online: false, identify: false).count
            }
            for i in list.indices { list[i].restartRequired = air.jvmUsedInProcess() }
            return list
        }
        /// Persist only when Air confirms a JVM actually started. Its runtime flag is the launch guard.
        func recordJVMUse() {
            guard air.jvmUsedInProcess() else { return }
            do { try instances?.markJVMUsed() }
            catch { NSLog("[Cofre] JVM session marker write failed: %@", error.localizedDescription) }
            NSLog("[Cofre] restartRequired scope=process")
        }
        /// A pack's own icon: Air stores a data URL or a file URL in the profile. Web URLs fall back to our icons.
        private func packIcon(_ s: String?) -> Data? {
            guard let s, !s.isEmpty else { return nil }
            if s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") {
                return Data(base64Encoded: String(s[s.index(after: comma)...]))
            }
            if let url = URL(string: s), url.isFileURL { return try? Data(contentsOf: url) }
            return nil
        }
        public func preferences(instanceID: String?) async throws -> GamePreferences {
            var p = preferenceStore.load(instanceID: instanceID)
            if p.autoRAM { p.ramMB = javaHeap(instanceID: instanceID, prefs: p).heap }
            return p
        }

        /// -Xmx for the next launch, sized with the headroom iOS gives this process right now.
        func javaHeap(instanceID: String?, prefs: GamePreferences) -> (heap: Int, requested: Int, available: Int) {
            let instance = instanceID.flatMap { try? storedInstance($0) }
            let physical = Int(ProcessInfo.processInfo.physicalMemory >> 20)
            let mods = instance.flatMap { try? ContentStore(gameDirectory: $0.gameDirectory).list(.mods).count } ?? 0
            let requested = prefs.autoRAM
                ? JavaHeap.autoMB(loader: instance?.loader ?? .vanilla, modCount: mods, physicalMB: physical) : prefs.ramMB
            let available = Int(os_proc_available_memory() >> 20)
            return (JavaHeap.clamp(requested, availableMB: available), requested, available)
        }

        /// Writes playable view distances before Air fills in its own 2-chunk default. The first time Cofre sees an
        /// instance it also replaces Air's defaults already saved there; after that the game owns the values.
        private func seedViewDistances(_ instance: Instance, instanceID: String) {
            let key = PreferenceKey.distancesSeeded(instanceID).rawValue
            let firstTime = !UserDefaults.standard.bool(forKey: key)
            do {
                let changed = try GameOptions.seedDistances(in: instance.gameDirectory,
                    physicalMB: Int(ProcessInfo.processInfo.physicalMemory >> 20),
                    displayHz: UIScreen.main.maximumFramesPerSecond, replacingEngineDefaults: firstTime)
                UserDefaults.standard.set(true, forKey: key)
                if changed { NSLog("[Cofre] view distances seeded instance=%@", instanceID) }
            } catch {
                NSLog("[Cofre] options.txt not updated: %@", error.localizedDescription)
            }
        }

        /// Air reads AMETHYST_MEM_MB for -Xmx; NO_CLAMP skips its own clamp, which caches a stale reading.
        private func applyJavaHeap(instanceID: String) {
            let size = javaHeap(instanceID: instanceID, prefs: preferenceStore.load(instanceID: instanceID))
            setenv("AMETHYST_MEM_MB", String(size.heap), 1)
            setenv("AMETHYST_MEM_NO_CLAMP", "1", 1)
            NSLog("[Cofre] memory heap=%ldMB requested=%ldMB available=%ldMB", size.heap, size.requested, size.available)
        }
        public func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws {
            preferenceStore.save(preferences, instanceID: instanceID)
            NSLog("[Cofre] preferences saved instance=%@ keys=%@", instanceID ?? "global", "renderer,javaArgs,graphicsApi,video,controls,java,mobileglues")
        }

        // Installed content (list, on/off, delete, updates) lives in CofreBackendAdapter+Mods.swift.

        public func accounts() async throws -> [Account] {
            accountStore.list().map { a in Account(id: a.id, name: a.name, kind: a.kind, isActive: a.isActive, state: AccountState(rawValue: a.state.rawValue) ?? .ready, expiry: a.expiry) }
        }
        public func signInMicrosoft() async throws -> Account {
            let d: [AnyHashable: Any] = try await withCheckedThrowingContinuation { c in
                air.signInMicrosoft(progress: { NSLog("[Cofre] sign-in %@", $0) }) { account, error in
                    if let account {
                        c.resume(returning: account)
                    } else {
                        c.resume(throwing: error ?? CofreBackendError.unavailable("Microsoft sign-in"))
                    }
                }
            }
            guard d["demo"] as? Bool != true else {
                throw CofreBackendError.notOwned
            }
            let account = Account(
                id: d["id"] as? String ?? "", name: d["name"] as? String ?? "", isActive: true)
            setup.account = .ready
            publishSetup()
            return account
        }
        public func removeAccount(id: String) async throws { _ = try accountStore.remove(id: id); air.removeAccountToken(id) }

        func repairLibraries() {
            for file in instances?.repairLibraries() ?? [] { NSLog("[Cofre] libraries repaired: removed empty %@", file.path) }
        }

        public func launch(instanceID: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error> {
            return launch(instanceID: instanceID, accountID: accountID, gameArguments: [])
        }
        func launch(instanceID: String, accountID: String?, gameArguments: [String]) -> AsyncThrowingStream<LaunchProgress, Error> {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: PreferenceKey.launchStarted(instanceID).rawValue)
            if let dir = air.gameDirectory(forProfile: instanceID), let options = try? String(contentsOf: dir.appendingPathComponent("options.txt"), encoding: .utf8) {
                UserDefaults.standard.set(options, forKey: PreferenceKey.optionsBefore(instanceID).rawValue)
            }
            CofreBreadcrumb.log("play", details: "instance=\(instanceID)")
            return AsyncThrowingStream { continuation in
                guard self.launchingGameDirectory == nil, !self.loaderInstallInProgress else {
                    continuation.finish(throwing: CofreServersStore.Failure.gameRunning); return
                }
                self.launchingGameDirectory = self.air.gameDirectory(forProfile: instanceID)
                launchTask?.cancel()
                let task = Task { @MainActor in
                    var finished = false
                    var awaitingFirstFrame = false
                    var watchdog: Task<Void, Never>?
                    var loaderWatch: Task<Void, Never>?
                    func finish(_ reason: String, error: Error? = nil) {
                        guard !finished else { return }
                        finished = true
                        if reason != "inGame" { Task { @MainActor in self.launchingGameDirectory = nil } }
                        watchdog?.cancel()
                        loaderWatch?.cancel()
                        NSLog("[Cofre] launch state=%@", reason)
                        if reason == "inGame" { Task { @MainActor in self.air.hideCofreLaunchOverlay() } }
                        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
                    }
                    do {
                        try Task.checkCancellation()
                        guard !self.air.jvmUsedInProcess() else { throw LaunchFailure.restartRequired }
                        guard let store = self.instances else { throw LaunchFailure.profileMissing }
                        let instance: Instance
                        do { instance = try self.storedInstance(instanceID) }
                        catch { throw LaunchFailure.profileMissing }
                        guard !instance.restartRequired else { throw LaunchFailure.restartRequired }
                        guard instance.loader != .unknown else { throw LaunchFailure.unknownLoader }
                        if instance.loader == .vanilla,
                           let mods = try? ContentStore(gameDirectory: instance.gameDirectory).list(.mods),
                           !mods.isEmpty {
                            NSLog("[Cofre] refusing vanilla launch with %ld installed mods", mods.count)
                            throw LaunchFailure.modsNeedLoader
                        }
                        guard instance.loader.isInstalled(in: instance.versionID, root: store.root,
                            minecraftVersion: instance.gameVersion) else { throw LaunchFailure.loaderMissing }
                        try await self.checkDiskBeforeLaunch(instance, root: store.root)
                        if !self.isJITEnabled {
                            continuation.yield(LaunchProgress(stage: 1, of: 7, title: "JIT", detail: "Enabling JIT"))
                            do { try await self.ensureJIT() }
                            catch is CancellationError { throw CancellationError() }
                            catch {
                                NSLog("[Cofre] launch JIT failed: %@", error.localizedDescription)
                                throw LaunchFailure.jitUnavailable
                            }
                        }
                        try Task.checkCancellation()
                        if instance.loader == .forge || instance.loader == .neoforge {
                            do { try FMLConfig.disableEarlyWindow(in: instance.gameDirectory) } catch {
                                NSLog("[Cofre] fml.toml not updated: %@", error.localizedDescription)
                            }
                        }
                        self.repairLibraries()
                        self.seedViewDistances(instance, instanceID: instanceID)
                        self.applyJavaHeap(instanceID: instanceID)
                        NSLog("[Cofre] launch JIT ready; starting Air")
                        if instance.loader == .forge || instance.loader == .neoforge {
                            let loader = instance.loader == .forge ? "Forge" : "NeoForge"
                            loaderWatch = self.watchModLoaderFailure {
                                finish("failed reason=modLoader",
                                       error: LaunchFailure.unknown("\(loader) couldn't load the mods."))
                            }
                        }
                        self.air.launchProfile(instanceID, accountID: accountID, gameArguments: gameArguments) { event, fraction, message in
                            Task { @MainActor in
                            switch event {
                            case .downloading:
                                continuation.yield(LaunchProgress(stage: 2, of: 7, title: "Game files", fraction: min(max(fraction, 0), 0.999)))
                            case .preparing:
                                continuation.yield(LaunchProgress(stage: 5, of: 7, title: message ?? "Starting Minecraft"))
                            case .surfaceShown:
                                awaitingFirstFrame = true
                                NSLog("[Cofre] launch state=surfaceShown")
                                watchdog = Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(60))
                                    guard !Task.isCancelled, awaitingFirstFrame else { return }
                                    self.recordJVMUse()
                                    finish("failed reason=launchTimeout", error: LaunchFailure.unknown("Minecraft took too long to show its first frame"))
                                }
                            case .firstFrame:
                                guard awaitingFirstFrame else { return }
                                self.recordJVMUse()
                                awaitingFirstFrame = false
                                continuation.yield(LaunchProgress(stage: 7, of: 7, title: "In game", finished: true))
                                finish("inGame")
                            case .rendererUnsupported:
                                finish("failed", error: LaunchFailure.rendererUnsupported)
                            case .downloadFailed:
                                finish("failed", error: LaunchFailure.downloadFailed(message ?? "Check your connection and the launcher log."))
                            case .exited:
                                self.recordJVMUse()
                                self.launchingGameDirectory = nil
                                finish("failed", error: LaunchFailure.jvmExit(Int(fraction)))
                            case .failed:
                                self.recordJVMUse()
                                finish("failed", error: LaunchFailure.unknown(message ?? "Minecraft couldn't start. Check the launcher log."))
                            @unknown default: break
                            }
                            }
                        }

                    } catch {
                        self.recordJVMUse()
                        finish("failed", error: error)
                    }
                }
                launchTask = task
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        /// FML's own error screen can't draw on Metal and the JVM doesn't exit, so a mod-loading failure would sit on a
        /// black screen: on "Failed to start FML" before the first frame, `failed` ends the launch and Cofre's exit
        /// screen (with its "Get TerraBlender") shows. Cancel it once the first frame is up.
        func watchModLoaderFailure(_ failed: @escaping @MainActor () -> Void) -> Task<Void, Never> {
            let log = LogStore().latestLog
            return Task { @MainActor in
                let watch = Task.detached(priority: .utility) { await Self.modLoaderFailure(in: log) }
                let text = await withTaskCancellationHandler { await watch.value } onCancel: { watch.cancel() }
                guard let text, !Task.isCancelled else { return }
                NSLog("[Cofre] launch mod loader failed before first frame; showing exit screen")
                self.recordJVMUse()
                failed()
                CofreGameExit.handle(code: 1, root: nil, bridge: self.air, launcherLog: text)
            }
        }

        /// Waits for `LaunchFailure.modLoaderFailed` in what the launch appends to `url`, then returns that text once
        /// the rest of the error is written. Nil when cancelled (the first frame came, or the launch ended).
        nonisolated static func modLoaderFailure(in url: URL) async -> String? {
            var offset = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
            var seen = ""
            func readNew() -> String {
                guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
                defer { try? handle.close() }
                guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return "" }
                offset += UInt64(data.count)
                return String(decoding: data, as: UTF8.self)
            }
            while !Task.isCancelled {
                seen += readNew()
                if LaunchFailure.modLoaderFailed(seen) {
                    try? await Task.sleep(for: .seconds(2))
                    return Task.isCancelled ? nil : String((seen + readNew()).suffix(100_000))
                }
                if seen.count > 400_000 { seen = String(seen.suffix(2_000)) }
                try? await Task.sleep(for: .seconds(1))
            }
            return nil
        }

        public func rejoin(instanceID: String, kind: RejoinIntent.Kind, target: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error> {
            if kind == .server { return joinServer(instanceID: instanceID, address: target, accountID: accountID) }
            let version = (try? storedInstance(instanceID).gameVersion) ?? ""
            return launch(instanceID: instanceID, accountID: accountID,
                          gameArguments: MinecraftLaunchArguments.singleplayer(folder: target, gameVersion: version))
        }
        public func cancelLaunch() async {
            launchTask?.cancel()
            launchTask = nil
            air.hideCofreLaunchOverlay()
        }
        private func logStore() -> LogStore {
            let id = air.selectedProfileName()
            return LogStore(instance: id.isEmpty ? nil : air.gameDirectory(forProfile: id))
        }
        private func kitSource(_ kind: LogKind) -> CofreKit.LogFile {
            switch kind { case .latest: .game; case .launcher: .launcher; case .crash: .crash }
        }
        public func logLines(_ kind: LogKind) -> AsyncStream<LogLine> {
            let store = logStore(), source = kitSource(kind)
            return AsyncStream { continuation in
                let task = Task.detached {
                    var seen = Set<String>(), nextID = 0
                    while !Task.isCancelled {
                        for entry in store.read(source) {
                            let key = entry.text + "\u{0}" + String(entry.id)
                            guard seen.insert(key).inserted else { continue }
                            let level: LogLine.Level = switch entry.level { case .error: .error; case .warning: .warning; case .success: .success; case .info: .info }
                            continuation.yield(LogLine(id: nextID, time: "", tag: entry.source.rawValue.capitalized, text: entry.text, level: level)); nextID += 1
                        }
                        if kind == .crash { break }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        public func exportLog(_ kind: LogKind) async throws -> URL { try logStore().export(kitSource(kind)) }
        public func exportReport() async throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString).zip")
            return try ReportBundle(store: logStore(), context: .current()).make(at: url)
        }
        public func reportPreview() async -> ReportPreviewData {
            let p = ReportBundle(store: logStore(), context: .current()).preview()
            return ReportPreviewData(fields: p.fields.map { "\($0.name): \($0.value)" }, files: p.files)
        }
        /// Turns on JIT through the built-in VPN, as the game and the Forge/NeoForge installers need it.
        func ensureJIT() async throws {
            guard !isJITEnabled else { return }
            let result = await CofreJIT.enable(pid: getpid(), pairingURL: { self.pairingURL })
            NSLog("[Cofre] JIT status=%@", String(describing: result))
            try Task.checkCancellation()
            switch result {
            case .enabled: break
            case .needsPairing: throw CofreBackendError.jit("This device isn't paired yet. Pair it in Settings.")
            case .needsVPN: throw CofreBackendError.jit("The VPN isn't on")
            case .failed(let message, let step):
                throw CofreBackendError.jit(step.map { "JIT failed at \($0.rawValue): \(message)" } ?? message)
            case .unavailable, .enabling: throw CofreBackendError.jit("JIT didn't turn on")
            }
            guard isJITEnabled else { throw CofreBackendError.jit("JIT didn't turn on") }
            UserDefaults.standard.set(true, forKey: PreferenceKey.setupJIT.rawValue)
            setup.jit = .ready
            publishSetup()
        }

        public func testJIT() -> AsyncThrowingStream<JITStatusStep, Error> {
            AsyncThrowingStream { continuation in
                Task { @MainActor in
                    let result = await CofreJIT.enable(pid: Int32(getpid()), pairingURL: { self.pairingURL })
                    NSLog("[Cofre] JIT status=%@", String(describing: result))
                    let (kind, message): (JITStep.Kind, String) =
                        switch result {
                        case .enabled: (.debugger, "")
                        case .needsPairing: (.pairing, "This device isn't paired yet")
                        case .needsVPN: (.vpn, "The VPN isn't on")
                        case .failed(let m, let step): (step ?? .debugger, m)
                        case .unavailable, .enabling: (.debugger, "JIT didn't turn on")
                        }
                    guard result.isEnabled else {
                        // Steps before the one that failed passed.
                        for passed in JITStep.Kind.allCases.prefix(while: { $0 != kind }) {
                            continuation.yield(JITStatusStep(kind: passed, state: .ready))
                        }
                        continuation.yield(JITStatusStep(kind: kind, state: .failed(message)))
                        continuation.finish(throwing: CofreBackendError.jit(message))
                        return
                    }
                    for kind in JITStatusStep.Kind.allCases { continuation.yield(JITStatusStep(kind: kind, state: .ready)) }
                    UserDefaults.standard.set(true, forKey: PreferenceKey.setupJIT.rawValue)
                    self.setup.jit = .ready
                    self.publishSetup()
                    continuation.finish()
                }
            }
        }
        public func deviceInfo() async -> DeviceInfo? { nil }
        public func signingInfo() async -> SigningInfo? {
            ProvisioningProfile.current.map {
                // Running at all means this device is in the profile.
                SigningInfo(team: $0.team, expires: $0.expires, deviceRegistered: true)
            }
        }
        public func appInfo() -> AppInfo {
            let info = Bundle.main.infoDictionary ?? [:]
            let version = info["CofreVersion"] as? String ?? "", build = info["CofreBuild"] as? String ?? ""
            return AppInfo(
                version: build.isEmpty ? version : "\(version) (\(build))",
                airVersion: info["CFBundleShortVersionString"] as? String ?? "", sourceURL: CofreLinks.source)
        }
        public func renderers() async -> [RendererOption] {
            let candidates: [(RendererID, String?)] = [
                (.auto, nil),
                (.metallum, "libmetallum.dylib"),
                (.mobileglues, "libmobileglues.dylib"),
                (.zink, "libOSMesa.8.dylib"),
                (.gl4es, "libgl4es_114.dylib"),
                (.simpleFPEWrapper, "libSimpleFPEWrapper.dylib"),
                (.angle, "libtinygl4angle.dylib"),
                (.ltw, "libltw.dylib"),
                (RendererID(rawValue: "mobilegl"), "libMobileGL.dylib"),
                (RendererID(rawValue: "mobilegles"), "libMobileGL-gles.dylib"),
                (.krypton, "libgl4eszl2.dylib"),
                (RendererID(rawValue: "vulkan"), "libMoltenVK.dylib"),
                (RendererID(rawValue: "vgpu"), "libvgpu.dylib"),
                (RendererID(rawValue: "virgl"), "libOSMesaVirgl.dylib"),
                (RendererID(rawValue: "nggl4es"), "libnggl4es.dylib"),
            ]
            let current = preferenceStore.stringValue(.renderer, profile: nil).map(RendererID.init(rawValue:))
            let allowed = RendererPolicy.pickerRenderers(current: current)
            return candidates.compactMap { id, file in
                guard allowed.contains(where: { RendererPolicy.sameRenderer($0, id) }) else { return nil }
                let path = file.map { Bundle.main.bundleURL.appendingPathComponent("Frameworks").appendingPathComponent($0).path }
                guard file == nil || (path.map { FileManager.default.fileExists(atPath: $0) } ?? false)
                    || current.map({ RendererPolicy.sameRenderer($0, id) }) == true else { return nil }
                return RendererOption(id: id, name: RendererPolicy.displayName(id), detail: RendererPolicy.detail(id))
            }
        }
        public func javaRuntimes() async -> [JavaRuntime] { [] }
        private var storageCleanup: StorageCleanup {
            let env = ProcessInfo.processInfo.environment
            let home = env["POJAV_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var directories = air.instances().compactMap { ($0["id"] as? String).flatMap { air.gameDirectory(forProfile: $0) } }
            if let game = env["POJAV_GAME_DIR"] { directories.append(URL(fileURLWithPath: game)) }
            return StorageCleanup(home: home, gameDirectories: directories)
        }
        public func storage() async -> StorageUsage {
            let cleanup = storageCleanup
            return await Task.detached {
                let total = StorageCleanup.bytes(cleanup.home)
                let cache = cleanup.reclaimableBytes
                let java = StorageCleanup.bytes(Bundle.main.bundleURL.appendingPathComponent("java_runtimes"))
                return StorageUsage(gameBytes: max(0, total - cache), javaBytes: java, cacheBytes: cache)
            }.value
        }
        public func clearCache() async throws {
            let cleanup = storageCleanup
            try await Task.detached { _ = try cleanup.clear() }.value
        }
        public func curseForgeKey() -> String? { nil }
        public func setCurseForgeKey(_ key: String?) throws { throw unavailable("CurseForge key storage") }

        private var pairingURL: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(
                CofreConstants.pairingRelativePath)
        }
        private func publishSetup() {
            setupContinuations.values.forEach { $0.yield(setup) }
        }
        private func unavailable(_ name: String) -> CofreBackendError { .unavailable(name) }
    }

    extension CofreBackendAdapter {
        public func seedPresetOptions(
            instanceID: String, options: CofrePreset.FirstCreateOptions, physicalMB: Int
        ) async throws {
            guard let directory = air.gameDirectory(forProfile: instanceID) else {
                throw CofreBackendError.unavailable("instance options")
            }
            try GameOptions.seedPreset(options, in: directory, physicalMB: physicalMB)
        }
    }
#endif
