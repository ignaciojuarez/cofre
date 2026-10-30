#if canImport(UIKit)
    import Foundation
    import UIKit
    import NetworkExtension
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
            [.addServer, .serverFiles, .pingServers, .quickPlay, .discoverServers, .envVariables, .rendererTuning, .serverJoin, .instanceIcon]
        }
        let air: any CofreAirBridging
        var instances: InstanceStore?
        var launchingGameDirectory: URL?
        let modCatalog = CofreModCatalog()
        private lazy var accountStore: AccountStore = {
            // Air keeps accounts in $POJAV_HOME/accounts (Documents, or Caches when Documents isn't writable).
            AccountStore(directory: ProcessInfo.processInfo.environment["POJAV_HOME"].map { URL(fileURLWithPath: $0) }
                             ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
                         readSelected: { [weak self] in self?.air.preferenceObject("internal.selected_account", profile: nil) as? String },
                         writeSelected: { [weak self] id in self?.air.setPreferenceObject("internal.selected_account", value: id ?? "", profile: nil) })
        }()
        public init(bridge: any CofreAirBridging) {
            self.air = bridge
            super.init()
            CofreGameInput.shared.bridge = bridge
            if let packs = Self.modpackDirectory { ModpackImport.cleanupAbandonedImport(in: packs) }
            loadPersistedSetup()
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
            if UserDefaults.standard.bool(forKey: "cofre.setup.jit") { setup.jit = .ready }
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
            setup.pairing = hasPairing() ? .ready : (setup.pairing.isReady ? .unknown : setup.pairing)
            if await CofreVPN.isAllowed() { setup.vpn = .ready } else if setup.vpn.isReady { setup.vpn = .unknown }
            if isJITEnabled {
                setup.jit = .ready
            } else if !hasPairing(), setup.jit.isReady {
                // A remembered JIT test means nothing once the pairing key is gone: launches would fail.
                UserDefaults.standard.removeObject(forKey: "cofre.setup.jit"); setup.jit = .unknown
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
            guard let data = try? Data(contentsOf: pairingURL) else { return false }
            return (try? PairingFileValidator.validate(data)) != nil
        }
        public func importPairing(_ data: Data) throws {
            _ = try PairingFileValidator.validate(data)
            try PairingFileStore.write(data, to: pairingURL)
            setup.pairing = .ready
            publishSetup()
        }
        public func deletePairing() throws { if hasPairing() { try FileManager.default.removeItem(at: pairingURL) } }
        public private(set) var isVPNRunning = false
        public func startVPN() async throws {
            try await CofreVPN.connect()
            isVPNRunning = true
            setup.vpn = .ready
            publishSetup()
        }
        /// True once a debugger has attached to Cofre (CS_DEBUGGED), which is what turning on JIT does.
        public var isJITEnabled: Bool {
            var flags: UInt32 = 0
            return csops(getpid(), 0, &flags, MemoryLayout<UInt32>.size) == 0 && flags & 0x1000_0000 != 0
        }

        public func instances() async throws -> [InstanceSummary] {
            var list: [InstanceSummary] = air.instances().compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                let loader = Loader(rawValue: (d["loader"] as? String ?? "vanilla").lowercased()) ?? .vanilla
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
            return list
        }
        public func setIcon(_ glyph: PixelGlyph?, instanceID: String) async throws {
            air.setCofreIcon(glyph?.rawValue, forProfile: instanceID)
            NSLog("[Cofre] instance icon instance=%@ icon=%@", instanceID, glyph?.rawValue ?? "auto")
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
            return preferenceStore.load(instanceID: instanceID)
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

        public func launch(instanceID: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error> {
            return launch(instanceID: instanceID, accountID: accountID, gameArguments: [])
        }
        func launch(instanceID: String, accountID: String?, gameArguments: [String]) -> AsyncThrowingStream<LaunchProgress, Error> {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "cofre.launch.started.\(instanceID)")
            if let dir = air.gameDirectory(forProfile: instanceID), let options = try? String(contentsOf: dir.appendingPathComponent("options.txt"), encoding: .utf8) {
                UserDefaults.standard.set(options, forKey: "cofre.options.before.\(instanceID)")
            }
            CofreBreadcrumb.log("play", details: "instance=\(instanceID)")
            return AsyncThrowingStream { continuation in
                guard self.launchingGameDirectory == nil else {
                    continuation.finish(throwing: CofreServersStore.Failure.gameRunning); return
                }
                self.launchingGameDirectory = self.air.gameDirectory(forProfile: instanceID)
                launchTask?.cancel()
                let task = Task { @MainActor in
                    var finished = false
                    var awaitingFirstFrame = false
                    var watchdog: Task<Void, Never>?
                    func finish(_ reason: String, error: Error? = nil) {
                        guard !finished else { return }
                        finished = true
                        if reason != "inGame" { Task { @MainActor in self.launchingGameDirectory = nil } }
                        watchdog?.cancel()
                        NSLog("[Cofre] launch state=%@", reason)
                        Task { @MainActor in self.air.hideCofreLaunchOverlay() }
                        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
                    }
                    do {
                        try Task.checkCancellation()
                        if !self.isJITEnabled {
                            continuation.yield(LaunchProgress(stage: 1, of: 7, title: "JIT", detail: "Enabling JIT"))
                            try await self.ensureJIT()
                        }
                        try Task.checkCancellation()
                        if let instance = try? self.storedInstance(instanceID), instance.loader == .forge || instance.loader == .neoforge {
                            do { try FMLConfig.disableEarlyWindow(in: instance.gameDirectory) } catch {
                                NSLog("[Cofre] fml.toml not updated: %@", error.localizedDescription)
                            }
                        }
                        NSLog("[Cofre] launch JIT ready; starting Air")
                        self.air.launchProfile(instanceID, accountID: accountID, gameArguments: gameArguments) { event, fraction, message in
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
                                    finish("failed reason=launchTimeout", error: CofreBackendError.unavailable("Minecraft took too long to show its first frame"))
                                }
                            case .firstFrame:
                                guard awaitingFirstFrame else { return }
                                awaitingFirstFrame = false
                                continuation.yield(LaunchProgress(stage: 7, of: 7, title: "In game", finished: true))
                                finish("inGame")
                            case .failed, .cancelled, .exited:
                                self.launchingGameDirectory = nil
                                finish(event == .cancelled ? "cancelled" : "failed", error: NSError(domain: "CofreAir", code: 1, userInfo: [NSLocalizedDescriptionKey: message ?? "Minecraft couldn't start. Check the launcher log."]))
                            @unknown default: break
                            }
                        }

                    } catch {
                        finish("failed", error: error)
                    }
                }
                launchTask = task
                continuation.onTermination = { _ in task.cancel() }
            }
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
            return try ReportBundle(store: logStore(), context: .init()).make(at: url)
        }
        public func reportPreview() async -> ReportPreviewData {
            let p = ReportBundle(store: logStore(), context: .init()).preview()
            return ReportPreviewData(fields: p.fields.map { "\($0.name): \($0.value)" }, files: p.files)
        }
        public func importPack(_ url: URL, instanceID: String?) -> AsyncThrowingStream<InstallProgress, Error> {
            unavailableStream("pack import")
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
                throw CofreBackendError.jit(step.map { "JIT failed at \($0): \(message)" } ?? message)
            case .unavailable, .enabling: throw CofreBackendError.jit("JIT didn't turn on")
            }
            guard isJITEnabled else { throw CofreBackendError.jit("JIT didn't turn on") }
        }

        public func testJIT() -> AsyncThrowingStream<JITStep, Error> {
            AsyncThrowingStream { continuation in
                Task { @MainActor in
                    let result = await CofreJIT.enable(pid: Int32(getpid()), pairingURL: { self.pairingURL })
                    NSLog("[Cofre] JIT status=%@", String(describing: result))
                    let (kind, message): (JITStep.Kind, String) =
                        switch result {
                        case .enabled: (.debugger, "")
                        case .needsPairing: (.pairing, "This device isn't paired yet")
                        case .needsVPN: (.vpn, "The VPN isn't on")
                        case .failed(let m, let step): (step.flatMap(JITStep.Kind.init) ?? .debugger, m)
                        case .unavailable, .enabling: (.debugger, "JIT didn't turn on")
                        }
                    guard result.isEnabled else {
                        // Steps before the one that failed passed.
                        for passed in JITStep.Kind.allCases.prefix(while: { $0 != kind }) {
                            continuation.yield(JITStep(kind: passed, state: .ready))
                        }
                        continuation.yield(JITStep(kind: kind, state: .failed(message)))
                        continuation.finish(throwing: CofreBackendError.jit(message))
                        return
                    }
                    for kind in JITStep.Kind.allCases { continuation.yield(JITStep(kind: kind, state: .ready)) }
                    UserDefaults.standard.set(true, forKey: "cofre.setup.jit")
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
            let manifestURL = Bundle.main.url(forResource: "RendererManifest", withExtension: "json")
            let metalDetail = (manifestURL.flatMap { try? RendererManifest.load(from: $0) }).map { "Manifest: \($0.gameVersions.sorted().joined(separator: ", "))" } ?? "Ship-derived renderer manifest"
            let candidates: [(String, String, String, String?)] = [
                ("auto", "Auto", "Picks per version", nil),
                ("libmetallum.dylib", "Metal", metalDetail, "libmetallum.dylib"),
                ("libmobileglues.dylib", "MobileGlues", "OpenGL 4 · modern packs", "libmobileglues.dylib"),
                ("libtinygl4angle.dylib", "ANGLE", "OpenGL ES on Metal", "libtinygl4angle.dylib"),
                ("libOSMesa.8.dylib", "Zink", "OpenGL on Vulkan", "libOSMesa.8.dylib"),
                ("libltw.dylib", "LTW", "OpenGL 3 · light", "libltw.dylib"),
                ("libMoltenVK.dylib", "Vulkan", "MoltenVK", "libMoltenVK.dylib"),
                ("libMobileGL.dylib", "MobileGL", "Direct Vulkan", "libMobileGL.dylib"),
                ("libMobileGL-gles.dylib", "MobileGL GLES", "Direct GLES", "libMobileGL-gles.dylib"),
                ("libgl4es_114.dylib", "GL4ES", "Legacy · 1.16 and older", "libgl4es_114.dylib"),
                ("libgl4eszl2.dylib", "Krypton", "OpenGL 3 · light", "libgl4eszl2.dylib"),
                ("libSimpleFPEWrapper.dylib", "SimpleFPEWrapper", "Fixed-function compatibility", "libSimpleFPEWrapper.dylib"),
                ("libvgpu.dylib", "VGPU", "Legacy OpenGL", "libvgpu.dylib"),
                ("libOSMesaVirgl.dylib", "VirGL", "Mesa compatibility", "libOSMesaVirgl.dylib"),
                ("libnggl4es.dylib", "NG-GL4ES", "Shader translation", "libnggl4es.dylib"),
            ]
            let current = preferenceStore.stringValue(.renderer, profile: nil)
            return candidates.compactMap { id, name, detail, file in
                let path = file.map { Bundle.main.bundleURL.appendingPathComponent("Frameworks").appendingPathComponent($0).path }
                guard file == nil || (path.map { FileManager.default.fileExists(atPath: $0) } ?? false) || id == current else { return nil }
                return RendererOption(id: id, name: name, detail: detail, recommended: id == "auto")
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
        private func unavailableStream<T>(_ name: String) -> AsyncThrowingStream<T, Error> {
            AsyncThrowingStream { continuation in continuation.finish(throwing: unavailable(name)) }
        }
        private func callback(_ body: (@escaping ([Any]) -> Void) -> Void) async throws -> [Any] {
            await withCheckedContinuation { c in body { c.resume(returning: $0) } }
        }
    }
#endif

#if canImport(UIKit)
import CofreUI

extension CofreBackendAdapter: GameEngine {
    public var input: any GameInputService { CofreGameInput.shared }
}
#endif
