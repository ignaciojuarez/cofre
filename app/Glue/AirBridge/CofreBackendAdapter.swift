#if canImport(UIKit)
    import Foundation
    import UIKit
    import NetworkExtension
    import CofreUI

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
            [.deleteWorld, .addServer, .envVariables, .rendererTuning, .serverJoin]
        }
        let air: any CofreAirBridging
        public init(bridge: any CofreAirBridging) {
            self.air = bridge
            super.init()
            loadPersistedSetup()
        }
        private var launchTask: Task<Void, Never>?
        private var setup = SetupState()
        private var setupContinuations: [UUID: AsyncStream<SetupState>.Continuation] = [:]
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
            if isJITEnabled { setup.jit = .ready }
            let accountReady = (try? await accounts().isEmpty == false) ?? false
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
            air.instances().compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                let loader = Loader(rawValue: (d["loader"] as? String ?? "vanilla").lowercased()) ?? .vanilla
                return InstanceSummary(
                    id: id, name: d["name"] as? String ?? id, loader: loader, gameVersion: d["version"] as? String ?? ""
                )
            }
        }
        public func createInstance(name: String, version: String, loader: Loader) async throws -> InstanceSummary {
            throw unavailable("instance creation")
        }
        public func installLoader(instanceID: String, loader: Loader, version: String) async throws {
            throw unavailable("loader installation")
        }
        public func worlds(instanceID: String) async throws -> [WorldSummary] {
            try await callback { done in self.air.worlds(forProfile: instanceID) { done($0 as? [Any] ?? []) } }.map { d in
                let x = d as? [String: Any] ?? [:]
                let n = x["name"] as? String ?? "World"
                return WorldSummary(
                    id: x["id"] as? String ?? n, name: n, mode: x["mode"] as? String ?? "", playTime: nil,
                    lastPlayed: nil)
            }
        }
        public func servers(instanceID: String) async throws -> [ServerSummary] {
            try await callback { done in self.air.searchServers(["query": "", "limit": "50"], source: 1) { rows, error in done(error == nil ? (rows as [Any]) : []) } }
                .compactMap { d in
                    let x = d as? [String: Any] ?? [:]
                    guard let id = x["id"] as? String, !id.isEmpty else { return nil }
                    let address = x["address"] as? String ?? ""
                    let hasCard = UserDefaults.standard.bool(
                        forKey: "cofre.server-card.\(address.split(separator: ":").first.map(String.init) ?? address)")
                    return ServerSummary(
                        id: id, name: x["title"] as? String ?? id, address: address,
                        detail: x["description"] as? String, hasServerCard: hasCard)
                }
        }
        public func deleteWorld(instanceID: String, worldID: String) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                air.deleteWorld(worldID, forProfile: instanceID) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
        public func backUpWorld(instanceID: String, worldID: String) async throws -> URL {
            throw unavailable("world backup")
        }
        public func addServer(instanceID: String, name: String, address: String) async throws -> ServerSummary {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                air.addServer(address, name: name, forProfile: instanceID) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            return ServerSummary(id: address, name: name, address: address)
        }
        public func createInstance(name: String, version: String, loader: Loader, ownFolder: Bool, fabricAPI: Bool)
            async throws -> InstanceSummary
        { try await createInstance(name: name, version: version, loader: loader) }
        public func preferences(instanceID: String?) async throws -> GamePreferences {
            var p = GamePreferences()
            p.autoRAM = air.preferenceObject("java.auto_ram") as? Bool ?? true
            p.ramMB = Int(
                air.preferences(forProfile: instanceID ?? air.selectedProfileName())["ramMB"] as? Int ?? 4096)
            p.deviceRAMMB = p.ramMB
            p.envVariables = parseEnv(air.preferenceObject("java.env_variables") as? String ?? "")
            p.shaderCacheMB = air.preferenceObject("mobileglues.max_glsl_cache_size") as? Int ?? 512
            p.multidraw = "\(air.preferenceObject("mobileglues.multidraw_mode") as? Int ?? 0)"
            p.computeShaders = air.preferenceObject("mobileglues.enable_ext_compute_shader") as? Bool ?? true
            return p
        }
        public func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws {
            air.setPreferenceObject(
                "java.env_variables",
                value: preferences.envVariables.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            air.setPreferenceObject("mobileglues.max_glsl_cache_size", value: preferences.shaderCacheMB)
            air.setPreferenceObject(
                "mobileglues.multidraw_mode",
                value: preferences.multidraw == "Auto" ? 0 : (Int(preferences.multidraw) ?? 0))
            air.setPreferenceObject("mobileglues.enable_ext_compute_shader", value: preferences.computeShaders)
        }

        public func installed(_ kind: ContentKind, instanceID: String) async throws -> [InstalledItem] {
            try await callback { done in self.air.mods(forProfile: instanceID) { done($0) } }.compactMap { d in
                let x = d as? [String: Any] ?? [:]
                guard let id = x["id"] as? String ?? x["name"] as? String else { return nil }
                return InstalledItem(
                    id: id, name: x["name"] as? String ?? id, version: x["version"] as? String ?? "",
                    enabled: x["enabled"] as? Bool ?? true, kind: kind)
            }
        }
        public func setEnabled(_ enabled: Bool, item: InstalledItem, instanceID: String) async throws {
            throw unavailable("mod changes")
        }
        public func delete(_ item: InstalledItem, instanceID: String) async throws {
            throw unavailable("content deletion")
        }
        public func updateAll(instanceID: String) async throws { throw unavailable("content updates") }

        public func accounts() async throws -> [Account] {
            air.accounts().compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                return Account(id: id, name: d["name"] as? String ?? id, isActive: d["active"] as? Bool ?? false)
            }
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
        public func removeAccount(id: String) async throws { throw unavailable("account removal") }

        public func launch(instanceID: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error> {
            AsyncThrowingStream { continuation in
                self.air.launchProfile(instanceID, accountID: accountID) { stage in
                    continuation.yield(
                        LaunchProgress(stage: 1, of: 1, title: stage, finished: stage == "running" || stage == "failed")
                    )
                }
                continuation.finish()
            }
        }
        public func cancelLaunch() async {
            launchTask?.cancel()
            launchTask = nil
        }
        public func logLines(_ kind: LogKind) -> AsyncStream<LogLine> {
            AsyncStream { continuation in
                let url = logURL(kind)
                if let text = try? String(contentsOf: url) {
                    for (i, line) in text.split(separator: "\n").enumerated() {
                        continuation.yield(LogLine(id: i, time: "", tag: "Air", text: String(line)))
                    }
                }
                continuation.finish()
            }
        }
        public func exportLog(_ kind: LogKind) async throws -> URL {
            let u = logURL(kind)
            guard FileManager.default.fileExists(atPath: u.path) else { throw unavailable("log export") }
            return u
        }
        public func duplicate(instanceID: String) async throws -> InstanceSummary {
            throw unavailable("instance duplication")
        }
        public func delete(instanceID: String) async throws { throw unavailable("instance deletion") }
        public func export(instanceID: String, format: ExportFormat) async throws -> URL {
            throw unavailable("instance export")
        }
        public func gameVersions(_ kind: VersionKind) async throws -> [GameVersion] {
            throw unavailable("version catalog")
        }
        public func loaderVersions(loader: Loader, game: String) async throws -> [String] {
            throw unavailable("loader catalog")
        }
        public func search(_ query: ProjectQuery) async throws -> [ProjectSummary] {
            let source = query.source == .curseforge ? 2 : 1
            let rows = try await callback { done in
                self.air.searchProjects(["query": query.text, "limit": "50"], source: source) { rows, error in done(error == nil ? (rows as [Any]) : []) }
            }
            return rows.compactMap { d in
                let x = d as? [String: Any] ?? [:]
                guard let id = x["id"] as? String, !id.isEmpty else { return nil }
                return ProjectSummary(
                    id: id, title: x["title"] as? String ?? id, author: x["author"] as? String ?? "",
                    summary: x["description"] as? String ?? "", iconURL: URL(string: x["iconURL"] as? String ?? ""),
                    downloads: (x["downloads"] as? NSNumber)?.intValue ?? 0, loaders: [], fits: true,
                    source: query.source, pageURL: URL(string: x["url"] as? String ?? ""))
            }
        }
        public func versions(projectID: String, instanceID: String) async throws -> [ProjectVersion] {
            throw unavailable("project versions")
        }
        public func dependencies(versionID: String, instanceID: String) async throws -> [ProjectDependency] {
            throw unavailable("project dependencies")
        }
        public func install(projectID: String, versionID: String, instanceID: String) -> AsyncThrowingStream<
            InstallProgress, Error
        > { unavailableStream("content installation") }
        public func importPack(_ url: URL, instanceID: String?) -> AsyncThrowingStream<InstallProgress, Error> {
            unavailableStream("pack import")
        }
        public func testJIT() -> AsyncThrowingStream<JITStep, Error> {
            AsyncThrowingStream { continuation in
                Task { @MainActor in
                    let result = await CofreJIT.enable(pid: Int32(getpid()), pairingURL: { self.pairingURL })
                    NSLog("[Cofre] JIT status=%@", String(describing: result))
                    let (kind, message): (JITStep.Kind, String) =
                        switch result {
                        case .enabled: (.debugger, "")
                        case .needsPairing: (.pairing, "No pairing key yet")
                        case .needsVPN: (.vpn, "The VPN isn't on")
                        case .failed(let m): (.debugger, m)
                        case .unavailable, .enabling: (.debugger, "JIT didn't turn on")
                        }
                    guard result.isEnabled else {
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
            AppInfo(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                airVersion: "Air", sourceURL: URL(string: "https://github.com/ignaciojb/cofre")!)
        }
        public func renderers() async -> [RendererOption] { [] }
        public func javaRuntimes() async -> [JavaRuntime] { [] }
        public func storage() async -> StorageUsage { StorageUsage(gameBytes: 0, javaBytes: 0, cacheBytes: 0) }
        public func clearCache() async throws { throw unavailable("cache management") }
        public func curseForgeKey() -> String? { nil }
        public func setCurseForgeKey(_ key: String?) throws { throw unavailable("CurseForge key storage") }
        public func applyAirAppearance(accentHex: String, cardHex: String, textHex: String) {}

        private var pairingURL: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(
                CofreConstants.pairingRelativePath)
        }
        private func logURL(_ kind: LogKind) -> URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(
                kind == .latest ? "latestlog.txt" : "latestlog.txt")
        }
        private func publishSetup() {
            setupContinuations.values.forEach { $0.yield(setup) }
        }
        private func parseEnv(_ value: String) -> [String: String] {
            Dictionary(
                uniqueKeysWithValues: value.split(separator: " ").compactMap { p in
                    let a = p.split(separator: "=", maxSplits: 1)
                    return a.count == 2 ? (String(a[0]), String(a[1])) : nil
                })
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
