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
            [.deleteWorld, .addServer, .envVariables, .rendererTuning, .serverJoin, .instanceIcon]
        }
        let air: any CofreAirBridging
        let modCatalog = CofreModCatalog()
        public init(bridge: any CofreAirBridging) {
            self.air = bridge
            super.init()
            CofreGameInput.shared.bridge = bridge
            loadPersistedSetup()
        }
        private var launchTask: Task<Void, Never>?
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
        public func preferences(instanceID: String?) async throws -> GamePreferences {
            return preferenceStore.load(instanceID: instanceID)
        }
        public func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws {
            preferenceStore.save(preferences, instanceID: instanceID)
            NSLog("[Cofre] preferences saved instance=%@ keys=%@", instanceID ?? "global", "renderer,javaArgs,graphicsApi,video,controls,java,mobileglues")
        }

        // Installed content (list, on/off, delete, updates) lives in CofreBackendAdapter+Mods.swift.

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
                launchTask?.cancel()
                let task = Task { @MainActor in
                    do {
                        try Task.checkCancellation()
                        if !self.isJITEnabled {
                            continuation.yield(LaunchProgress(stage: 1, of: 7, title: "JIT", detail: "Enabling JIT"))
                            let result = await CofreJIT.enable(pid: getpid(), pairingURL: { self.pairingURL })
                            NSLog("[Cofre] launch JIT status=%@", String(describing: result))
                            try Task.checkCancellation()
                            switch result {
                            case .enabled: break
                            case .needsPairing: throw CofreBackendError.jit("No pairing key yet")
                            case .needsVPN: throw CofreBackendError.jit("The VPN isn't on")
                            case .failed(let message, let step):
                                throw CofreBackendError.jit(step.map { "JIT failed at \($0): \(message)" } ?? message)
                            case .unavailable, .enabling: throw CofreBackendError.jit("JIT didn't turn on")
                            }
                            guard self.isJITEnabled else { throw CofreBackendError.jit("JIT didn't turn on") }
                        }
                        try Task.checkCancellation()
                        NSLog("[Cofre] launch JIT ready; starting Air")
                        // Air downloads first, then publishes its real launch stages. Completion is emitted only after
                        // AmeLaunchStageCompleted (the first rendered frame).
                        self.air.launchProfile(instanceID, accountID: accountID) { event in
                            let parts = event.split(separator: ":", maxSplits: 3).map(String.init)
                            let kind = parts.first ?? ""
                            switch kind {
                            case "downloading":
                                let f = min(max(Double(parts.dropFirst().first ?? "0") ?? 0, 0), 0.999)
                                continuation.yield(
                                    LaunchProgress(
                                        stage: 2, of: 7, title: "Game files", fraction: f))
                            case "air":
                                let airStage = Int(parts.count > 1 ? parts[1] : "0") ?? 0
                                let fraction = Double(parts.count > 2 ? parts[2] : "0") ?? 0
                                let mapped: (Int, String) = switch airStage {
                                case 2: (3, "Renderer")
                                case 3: (4, "Java")
                                case 4, 5: (5, "Starting Minecraft")
                                case 6: (6, "Loading")
                                case 7: (7, "In game")
                                // Air's first stages run once its game view is up, so they count as past Game files.
                                default: (3, "Renderer")
                                }
                                NSLog("[Cofre] launch Air stage=%d title=%@ fraction=%.3f", airStage, mapped.1, fraction)
                                continuation.yield(LaunchProgress(stage: mapped.0, of: 7, title: mapped.1, fraction: fraction))
                            case "completed":
                                continuation.yield(LaunchProgress(stage: 7, of: 7, title: "In game", finished: true))
                                continuation.finish()
                            case "failed":
                                let value = parts.dropFirst().joined(separator: ":")
                                continuation.finish(
                                    throwing: NSError(
                                        domain: "CofreAir", code: 1,
                                        userInfo: [
                                                NSLocalizedDescriptionKey: value.isEmpty
                                                ? "Minecraft couldn't start. Check the launcher log." : value
                                        ]))
                            default: break
                            }
                        }
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                launchTask = task
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        public func cancelLaunch() async {
            launchTask?.cancel()
            launchTask = nil
            air.hideCofreLaunchOverlay()
        }
        public func logLines(_ kind: LogKind) -> AsyncStream<LogLine> { CofreLogStore().lines(kind) }
        public func exportLog(_ kind: LogKind) async throws -> URL { try CofreLogStore().export(kind) }
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
            AppInfo(
                version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                airVersion: "Air", sourceURL: URL(string: "https://github.com/ignaciojuarez/cofre")!)
        }
        public func renderers() async -> [RendererOption] {
            let candidates: [(String, String, String, String?)] = [
                ("auto", "Auto", "Picks per version", nil),
                ("libmetallum.dylib", "Metal", "Best for Minecraft 26+", "libmetallum.dylib"),
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
        public func storage() async -> StorageUsage { StorageUsage(gameBytes: 0, javaBytes: 0, cacheBytes: 0) }
        public func clearCache() async throws { throw unavailable("cache management") }
        public func curseForgeKey() -> String? { nil }
        public func setCurseForgeKey(_ key: String?) throws { throw unavailable("CurseForge key storage") }
        public func applyAirAppearance(accentHex: String, cardHex: String, textHex: String) {}

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
