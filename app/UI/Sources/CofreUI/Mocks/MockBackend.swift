#if canImport(UIKit)
    import UIKit

    /// Sample data from the approved mockups. For previews, tests and the preview host only: no Air logic.
    public final class MockBackend: CofreBackend, @unchecked Sendable {
        public var state: SetupState
        public var instanceList: [InstanceSummary]
        public var prefs = GamePreferences()
        public var mods: [InstalledItem]
        public var accountList = [Account(id: "steve", name: "Steve_42", kind: "Microsoft", isActive: true)]
        /// Seconds between simulated launch/test steps. 0 makes streams finish immediately.
        public var stepDelay: Double
        /// GAP-13. `.serverJoin` (GAP-14) and `.instanceIcon`, so screenshots show what ships plus the Join server sheet.
        /// Tests turn flags on.
        public var capabilities: BackendCapabilities = [.serverJoin, .instanceIcon]
        /// GAP-14. Where the Join server sheet starts; `nil` reads the card (resolving, then first visit, or ready once installed).
        public var serverJoinScenario: MockServerJoin.Scenario?
        private var joinedServers: Set<String> = []
        /// Makes `search` throw, for the offline state.
        public var offline = false
        /// Makes `versions` throw, for M02's Try again state.
        public var failVersions = false
        private var worldList: [String: [WorldSummary]] = [:]
        private var extraServers: [ServerSummary] = []
        private var cfKey: String? = "cf_live_••••3f9a"
        private let (setupStream, setupContinuation) = AsyncStream<SetupState>.makeStream()

        public init(setupComplete: Bool = true, stepDelay: Double = 0.35) {
            self.stepDelay = stepDelay
            state =
                setupComplete
                ? SetupState(devMode: .ready, trust: .ready, pairing: .ready, vpn: .ready, jit: .ready, account: .ready)
                : SetupState(
                    devMode: .ready, trust: .ready, pairing: .unknown, vpn: .unknown, jit: .unknown, account: .unknown)
            let now = Date()
            // No icons: each gets `InstanceIcon.automatic` (its loader's, or a block for vanilla).
            instanceList = [
                InstanceSummary(
                    id: "survival", name: "Survival+", loader: .fabric, gameVersion: "1.21.1", loaderVersion: "0.16.14",
                    modCount: 142,
                    sizeBytes: 4_402_000_000, lastPlayed: now.addingTimeInterval(-7200), updatesAvailable: 3,
                    javaVersion: "21"),
                InstanceSummary(
                    id: "create", name: "Create: Above & Beyond", loader: .forge, gameVersion: "1.20.1",
                    loaderVersion: "47.3.0", modCount: 189,
                    sizeBytes: 6_228_000_000, lastPlayed: now.addingTimeInterval(-86400), javaVersion: "17"),
                InstanceSummary(
                    id: "cobblemon", name: "Cobblemon", loader: .neoforge, gameVersion: "1.21.1",
                    loaderVersion: "21.1.77", modCount: 64,
                    sizeBytes: 2_362_000_000, lastPlayed: now.addingTimeInterval(-3 * 86400), javaVersion: "21"),
                InstanceSummary(
                    id: "skyblock", name: "Skyblock", loader: .quilt, gameVersion: "1.20.4", loaderVersion: "0.26.4",
                    modCount: 23,
                    sizeBytes: 966_000_000, lastPlayed: now.addingTimeInterval(-8 * 86400), javaVersion: "17"),
                InstanceSummary(
                    id: "vanilla", name: "Vanilla", loader: .vanilla, gameVersion: "26.3", sizeBytes: 644_000_000,
                    javaVersion: "21"),
            ]
            mods = [
                InstalledItem(id: "sodium", name: "Sodium", version: "0.6.13", enabled: true),
                InstalledItem(id: "iris", name: "Iris Shaders", version: "1.8.8", enabled: true),
                InstalledItem(id: "create", name: "Create", version: "6.0.4", enabled: true, updateTo: "6.0.6"),
                InstalledItem(id: "xaero", name: "Xaero's Minimap", version: "25.2.0", enabled: false),
                InstalledItem(id: "jei", name: "JEI", version: "19.21.0", enabled: true, updateTo: "19.21.2"),
                InstalledItem(
                    id: "glass", name: "Better Glass", version: "1.4", enabled: true, issue: "Fabric API missing"),
                InstalledItem(id: "lithium", name: "Lithium", version: "0.14.3", enabled: true, updateTo: "0.14.4"),
                InstalledItem(id: "modmenu", name: "Mod Menu", version: "11.0.3", enabled: true),
            ]
            prefs.ramMB = 6144
            prefs.resolution = 0.7
            prefs.renderer = "mobileglues"
            prefs.jvmArgs = "-XX:+UseG1GC -Xss2m"
        }

        private func pause(_ f: Double = 1) async {
            if stepDelay > 0 { try? await Task.sleep(for: .seconds(stepDelay * f)) }
        }

        // MARK: SetupService
        public func setupState() async -> SetupState { state }
        public func setupUpdates() -> AsyncStream<SetupState> { setupStream }
        public func recheckSetup() async { setupContinuation.yield(state) }
        @MainActor public func openDeveloperModeSettings() {}
        public func hasPairing() -> Bool { state.pairing.isReady }
        public func importPairing(_ data: Data) throws { state.pairing = .ready }
        public func deletePairing() throws { state.pairing = .unknown }
        public var isVPNRunning: Bool { state.vpn.isReady }
        public func startVPN() async throws {
            await pause()
            state.vpn = .ready
        }
        public var isJITEnabled: Bool { state.jit.isReady }

        // MARK: LibraryService
        public func instances() async throws -> [InstanceSummary] { instanceList }
        public func createInstance(name: String, version: String, loader: Loader) async throws -> InstanceSummary {
            let i = InstanceSummary(
                id: UUID().uuidString, name: name, loader: loader, gameVersion: version, modCount: 0, sizeBytes: 0)
            instanceList.append(i)
            return i
        }
        public func installLoader(instanceID: String, loader: Loader, version: String) async throws {}
        public func setIcon(_ glyph: PixelGlyph?, instanceID: String) async throws {
            guard let i = instanceList.firstIndex(where: { $0.id == instanceID }) else { return }
            instanceList[i].icon =
                glyph.map { .init(glyph: $0) } ?? .automatic(id: instanceID, loader: instanceList[i].loader)
        }
        public func worlds(instanceID: String) async throws -> [WorldSummary] {
            if let list = worldList[instanceID] { return list }
            let now = Date()
            let t = PixelArtColors.oreTints
            return [
                WorldSummary(
                    id: "w1", name: "Ironwood", mode: "Survival", playTime: "41 h",
                    lastPlayed: now.addingTimeInterval(-7200)),
                WorldSummary(
                    id: "w2", name: "Skyhaven", mode: "Creative", playTime: "6 h",
                    lastPlayed: now.addingTimeInterval(-86400), icon: .init(glyph: .ore, tintHex: t["diamond"])),
                WorldSummary(
                    id: "w3", name: "River Base", mode: "Survival", playTime: "12 h",
                    lastPlayed: now.addingTimeInterval(-4 * 86400)),
                WorldSummary(
                    id: "w4", name: "Hardcore #3", mode: "Hardcore", playTime: "3 h",
                    lastPlayed: now.addingTimeInterval(-14 * 86400), icon: .init(glyph: .ore, tintHex: t["redstone"])),
            ]
        }
        public func servers(instanceID: String) async throws -> [ServerSummary] {
            [
                MockServerJoin.ironwood,
                ServerSummary(
                    id: "s1", name: "friends.cofre.lan", address: "10.0.0.4", detail: "LAN · 3/8 online", pingMS: 24),
                ServerSummary(
                    id: "s2", name: "play.example.net", address: "play.example.net", detail: "1.21.1 · 112/500",
                    pingMS: 140),
            ] + extraServers
        }
        public func preferences(instanceID: String?) async throws -> GamePreferences { prefs }
        public func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws {
            if instanceID == nil { prefs = preferences }
        }

        // MARK: ContentService
        public func installed(_ kind: ContentKind, instanceID: String) async throws -> [InstalledItem] {
            switch kind {
            case .mods: return mods
            case .shaders:
                return [
                    InstalledItem(id: "bsl", name: "BSL Shaders", version: "8.2.09", enabled: true, kind: .shaders),
                    InstalledItem(
                        id: "complementary", name: "Complementary", version: "r5.2", enabled: false, kind: .shaders),
                ]
            case .resourcePacks:
                return [
                    InstalledItem(
                        id: "faithful", name: "Faithful 32x", version: "1.21", enabled: true, kind: .resourcePacks)
                ]
            case .dataPacks, .modpacks: return []
            }
        }
        public func setEnabled(_ enabled: Bool, item: InstalledItem, instanceID: String) async throws {
            if let i = mods.firstIndex(where: { $0.id == item.id }) { mods[i].enabled = enabled }
        }
        public func delete(_ item: InstalledItem, instanceID: String) async throws {
            mods.removeAll { $0.id == item.id }
        }
        public func updateAll(instanceID: String) async throws {
            await pause(2)
            for i in mods.indices {
                if let v = mods[i].updateTo {
                    mods[i].version = v
                    mods[i].updateTo = nil
                }
            }
            if let i = instanceList.firstIndex(where: { $0.id == instanceID }) { instanceList[i].updatesAvailable = 0 }
        }

        // MARK: AccountService
        public func accounts() async throws -> [Account] { accountList }
        public func signInMicrosoft() async throws -> Account {
            await pause(2)
            state.account = .ready
            return accountList[0]
        }
        public func removeAccount(id: String) async throws { accountList.removeAll { $0.id == id } }

        // MARK: GAP-01 LaunchControl
        private var launchTask: Task<Void, Never>?
        public static let launchStages = [
            "JIT", "Game files", "Renderer · MobileGlues", "Java 21", "Starting Minecraft", "Loading", "In game",
        ]
        public func launch(instanceID: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error> {
            AsyncThrowingStream { c in
                launchTask = Task {
                    let stages = Self.launchStages
                    for (i, title) in stages.enumerated() {
                        if Task.isCancelled {
                            c.finish()
                            return
                        }
                        let detail = title == "Game files" ? "assets 2,431/3,904" : nil
                        c.yield(
                            LaunchProgress(
                                stage: i + 1, of: stages.count, title: title,
                                fraction: Double(i) / Double(stages.count), detail: detail))
                        await pause(title == "Game files" ? 4 : 1.2)
                    }
                    c.yield(
                        LaunchProgress(
                            stage: stages.count, of: stages.count, title: "In game", fraction: 1, finished: true))
                    c.finish()
                }
            }
        }
        public func cancelLaunch() async { launchTask?.cancel() }

        // MARK: GAP-02 LogSource
        public static let sampleLog: [LogLine] = [
            LogLine(id: 1, time: "18:02:11", tag: "JIT", text: "region 64 MB ready"),
            LogLine(id: 2, time: "18:02:11", tag: "JIT", text: "detached"),
            LogLine(id: 3, time: "18:02:12", tag: "Java", text: "OpenJDK 21.0.5"),
            LogLine(id: 4, time: "18:02:14", tag: "Assets", text: "2,431/3,904"),
            LogLine(id: 5, time: "18:02:14", tag: "WARN", text: "Shader cache cold", level: .warning),
            LogLine(id: 6, time: "18:02:19", tag: "Fabric", text: "Loading 142 mods", level: .success),
            LogLine(id: 7, time: "18:02:41", tag: "Render", text: "MobileGlues · GL 4.6"),
            LogLine(id: 8, time: "18:03:02", tag: "Client", text: "Joined world", level: .success),
        ]
        public func logLines(_ kind: LogKind) -> AsyncStream<LogLine> {
            AsyncStream { c in
                let lines =
                    kind == .crash
                    ? [LogLine(id: 1, time: "17:40:02", tag: "Crash", text: "No crash reports", level: .success)]
                    : Self.sampleLog
                for l in lines { c.yield(l) }
                c.finish()
            }
        }
        public func exportLog(_ kind: LogKind) async throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cofre-\(kind.rawValue).log")
            try Self.sampleLog.map { "\($0.time) [\($0.tag)] \($0.text)" }.joined(separator: "\n").write(
                to: url, atomically: true, encoding: .utf8)
            return url
        }

        // MARK: GAP-03 InstanceActions
        public func duplicate(instanceID: String) async throws -> InstanceSummary {
            guard var i = instanceList.first(where: { $0.id == instanceID }) else { throw MockError.notFound }
            i = InstanceSummary(
                id: UUID().uuidString, name: i.name + " copy", loader: i.loader, gameVersion: i.gameVersion,
                loaderVersion: i.loaderVersion,
                modCount: i.modCount, sizeBytes: i.sizeBytes, icon: i.icon)
            instanceList.append(i)
            return i
        }
        public func delete(instanceID: String) async throws { instanceList.removeAll { $0.id == instanceID } }
        public func export(instanceID: String, format: ExportFormat) async throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(instanceID).\(format.rawValue)")
            try Data().write(to: url)
            return url
        }

        // MARK: GAP-04 VersionCatalog
        public func gameVersions(_ kind: VersionKind) async throws -> [GameVersion] {
            switch kind {
            case .release:
                ["26.3", "1.21.4", "1.21.1", "1.20.4", "1.20.1", "1.19.2", "1.18.2", "1.16.5", "1.12.2"].map {
                    GameVersion(id: $0)
                }
            case .snapshot: ["26w44a", "26w43b"].map { GameVersion(id: $0, kind: .snapshot) }
            case .old: ["b1.7.3", "a1.2.6"].map { GameVersion(id: $0, kind: .old) }
            }
        }
        public func loaderVersions(loader: Loader, game: String) async throws -> [String] {
            switch loader {
            case .vanilla: []
            case .fabric: ["0.16.14", "0.16.10", "0.15.11"]
            case .quilt: ["0.26.4", "0.26.3"]
            case .forge: ["52.0.31", "47.3.0"]
            case .neoforge: ["21.1.77", "21.1.65"]
            }
        }

        // MARK: GAP-05 ProjectCatalog
        public static let projects: [ProjectSummary] = {
            let t = PixelArtColors.oreTints
            // Real Modrinth icons. Offline (tests, Xcode previews) the tinted ore stands in.
            let cdn = "https://cdn.modrinth.com/data/"
            let icons = [
                "sodium": "AANobbMI/295862f4724dc3f78df3447ad6072b2dcd3ef0c9_96.webp",
                "iris": "YL57xq9U/18d0e7f076d3d6ed5bedd472b853909aac5da202_96.webp",
                "xaero": "1bokaNcj/354080f65407e49f486fcf9c4580e82c45ae63b8_96.webp",
                "lithium": "gvQqBUqZ/bcc8686c13af0143adf4285d741256af824f70b7_96.webp",
                "create": "LNytGWDc/61d716699bcf1ec42ed4926a9e1c7311be6087e2_96.webp",
                "modmenu": "mOgUt4GM/5a20ed1450a0e1e79a1fe04e61bb4e5878bf1d20.png",
                "culling": "NNAgCjsB/7873452d6cede4daed12da3d7d8c193ab88b4fd6_96.webp",
                "fabric-api": "P7dR8mSH/icon.png",
                // Continuity and AppleSkin have none, so the fallback shows too.
            ].compactMapValues { URL(string: cdn + $0) }
            func p(
                _ id: String, _ title: String, _ author: String, _ summary: String, _ tint: String, _ dl: Int,
                installed: Bool = false, fits: Bool = true, loaders: [Loader] = [.fabric, .quilt]
            ) -> ProjectSummary {
                ProjectSummary(
                    id: id, title: title, author: author, summary: summary, iconURL: icons[id],
                    iconTintHex: t[tint], downloads: dl,
                    updated: Date().addingTimeInterval(-3 * 86400), loaders: loaders, clientSide: true,
                    fits: fits, installed: installed)
            }
            return [
                p("sodium", "Sodium", "jellysquid3", "Faster rendering", "diamond", 74_000_000, installed: true),
                p(
                    "iris", "Iris Shaders", "coderbot",
                    "Shaders on modern versions. Works with Sodium and loads OptiFine shader packs.", "amethyst",
                    42_000_000),
                p("xaero", "Xaero's Minimap", "xaero96", "Map in a corner", "emerald", 31_000_000),
                p("lithium", "Lithium", "jellysquid3", "Faster game logic", "gold", 39_000_000, installed: true),
                p("create", "Create", "simibubi", "Gears & machines", "copper", 12_000_000, loaders: [.forge, .neoforge]),
                p("modmenu", "Mod Menu", "Prospector", "Mod list in game", "lapis", 60_000_000, installed: true),
                p("culling", "Entity Culling", "tr7zw", "Skips hidden mobs", "emerald", 28_000_000),
                p("fabric-api", "Fabric API", "modmuss50", "Core library", "gold", 140_000_000, installed: true),
                p("continuity", "Continuity", "PepperCode1", "Connected textures", "diamond", 9_000_000),
                p("appleskin", "AppleSkin", "squeek502", "Food and saturation", "redstone", 33_000_000),
            ]
        }()
        public func search(_ query: ProjectQuery) async throws -> [ProjectSummary] {
            if offline { throw URLError(.notConnectedToInternet) }
            let q = query.text.lowercased()
            let inst = instanceList.first { $0.id == query.instanceID }
            return Self.projects.filter { q.isEmpty || $0.title.lowercased().contains(q) }.compactMap {
                var p = $0
                p.source = query.source
                // Like Modrinth's loader facet: only mods for the instance's loader.
                if let inst, query.kind == .mods {
                    p.fits = p.loaders.contains(inst.loader)
                    if !p.fits { return nil }
                }
                return p
            }
        }
        public func versions(projectID: String, instanceID: String) async throws -> [ProjectVersion] {
            if failVersions { throw URLError(.timedOut) }
            // Fits like the adapter: the instance's loader and exact game version.
            let inst = instanceList.first { $0.id == instanceID }
            let loaders = Self.projects.first { $0.id == projectID }?.loaders ?? []
            func fits(_ game: String) -> Bool {
                guard let inst, inst.loader != .vanilla else { return false }
                return inst.gameVersion == game && (loaders.isEmpty || loaders.contains(inst.loader))
            }
            return [
                ProjectVersion(id: "\(projectID)-188", name: "1.8.8", gameVersions: "1.21.1", fits: fits("1.21.1")),
                ProjectVersion(id: "\(projectID)-187", name: "1.8.7", gameVersions: "1.21.1", fits: fits("1.21.1")),
                ProjectVersion(id: "\(projectID)-181", name: "1.8.1", gameVersions: "1.21", fits: fits("1.21")),
                ProjectVersion(id: "\(projectID)-174", name: "1.7.4", gameVersions: "1.20.4", fits: fits("1.20.4")),
                ProjectVersion(id: "\(projectID)-162", name: "1.6.2", gameVersions: "1.20.1", fits: fits("1.20.1")),
            ]
        }
        public func dependencies(versionID: String, instanceID: String) async throws -> [ProjectDependency] {
            versionID.hasPrefix("iris") ? [ProjectDependency(id: "sodium", name: "Sodium", installed: true)] : []
        }

        // MARK: GAP-06 InstallProgressSource
        public func install(projectID: String, versionID: String, instanceID: String) -> AsyncThrowingStream<
            InstallProgress, Error
        > {
            AsyncThrowingStream { c in
                Task {
                    for f in stride(from: 0.0, through: 1.0, by: 0.25) {
                        c.yield(InstallProgress(title: projectID, fraction: f))
                        await pause(0.5)
                    }
                    if let p = Self.projects.first(where: { $0.id == projectID }) {
                        mods.append(InstalledItem(id: p.id, name: p.title, version: "1.8.8", enabled: true))
                    }
                    c.finish()
                }
            }
        }
        public func importPack(_ url: URL, instanceID: String?) -> AsyncThrowingStream<InstallProgress, Error> {
            AsyncThrowingStream { c in
                Task {
                    let name = url.deletingPathExtension().lastPathComponent
                    for step in 0...4 {
                        let f = Double(step) / 4
                        c.yield(
                            InstallProgress(
                                title: name, fraction: f, detail: "Mods \(Int(f * 128))/128 · 41 MB/s",
                                stages: [
                                    .init(title: "Manifest", state: .ready),
                                    .init(title: "Fabric 0.16.14", state: step > 0 ? .ready : .checking),
                                    .init(
                                        title: "Mods", state: step >= 4 ? .ready : step > 0 ? .checking : .unknown,
                                        detail: "\(Int(f * 100))%"),
                                    .init(title: "Overrides · configs", state: step >= 4 ? .ready : .unknown),
                                ]))
                        await pause(1)
                    }
                    c.finish()
                }
            }
        }

        // MARK: GAP-07 JITTester
        public func testJIT() -> AsyncThrowingStream<JITStep, Error> {
            AsyncThrowingStream { c in
                Task {
                    let details: [JITStep.Kind: String] = [
                        .pairing: "Valid", .vpn: "On", .diskImage: "Mounted", .debugger: "Attached", .region: "64 MB",
                        .detach: "Done",
                    ]
                    for k in JITStep.Kind.allCases {
                        c.yield(JITStep(kind: k, state: .checking))
                        await pause(0.8)
                        c.yield(JITStep(kind: k, state: .ready, detail: details[k]))
                    }
                    state.jit = .ready
                    c.finish()
                }
            }
        }
        public func deviceInfo() async -> DeviceInfo? {
            DeviceInfo(model: "iPhone 17 Pro", os: "iOS 26.1", jitMode: "TXM")
        }

        // MARK: GAP-08 SigningInfoSource
        public func signingInfo() async -> SigningInfo? {
            SigningInfo(
                team: "Ignacio J.",
                expires: Calendar.current.date(from: DateComponents(year: 2027, month: 10, day: 28))!,
                deviceRegistered: true)
        }
        public func appInfo() -> AppInfo {
            AppInfo(
                version: "1.0", airVersion: "5.1", sourceURL: URL(string: "https://github.com/ignaciojuarez/cofre")!)
        }

        // MARK: GAP-09 SystemCatalog
        public func renderers() async -> [RendererOption] {
            [
                RendererOption(id: "auto", name: "Auto", detail: "Picks per version", recommended: true),
                RendererOption(id: "mobileglues", name: "MobileGlues", detail: "OpenGL 4 · modern packs"),
                RendererOption(id: "zink", name: "Zink · MoltenVK", detail: "OpenGL on Vulkan"),
                RendererOption(id: "ltw", name: "LTW", detail: "OpenGL 3 · light"),
                RendererOption(id: "krypton", name: "Krypton", detail: "Fast · older packs"),
                RendererOption(id: "angle", name: "ANGLE", detail: "OpenGL ES on Metal"),
                RendererOption(id: "gl4es", name: "gl4es", detail: "Legacy · 1.16 and older"),
            ]
        }
        public func javaRuntimes() async -> [JavaRuntime] {
            [8, 17, 21, 25].map { JavaRuntime(id: "\($0)", major: $0, installed: true) }
        }
        public func storage() async -> StorageUsage {
            StorageUsage(gameBytes: 4_400_000_000, javaBytes: 900_000_000, cacheBytes: 850_000_000)
        }
        public func clearCache() async throws {}
        public func curseForgeKey() -> String? { cfKey }
        public func setCurseForgeKey(_ key: String?) throws { cfKey = key }

        // MARK: GAP-13 OptionalActions
        public func deleteWorld(instanceID: String, worldID: String) async throws {
            var list = try await worlds(instanceID: instanceID)
            list.removeAll { $0.id == worldID }
            worldList[instanceID] = list
        }
        public func backUpWorld(instanceID: String, worldID: String) async throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(worldID).zip")
            try Data().write(to: url)
            return url
        }
        public func addServer(instanceID: String, name: String, address: String) async throws -> ServerSummary {
            let s = ServerSummary(id: UUID().uuidString, name: name, address: address)
            extraServers.append(s)
            return s
        }
        public func createInstance(name: String, version: String, loader: Loader, ownFolder: Bool, fabricAPI: Bool)
            async throws -> InstanceSummary
        {
            var i = try await createInstance(name: name, version: version, loader: loader)
            i.ownFolder = ownFolder
            if let n = instanceList.firstIndex(where: { $0.id == i.id }) { instanceList[n] = i }
            return i
        }

        // MARK: GAP-14 ServerJoinSource
        @MainActor public func serverJoin(_ request: ServerJoinRequest) -> (any ServerJoinViewModel)? {
            let server =
                request.id == MockServerJoin.ironwood.address
                ? MockServerJoin.ironwood
                : ServerSummary(id: request.id, name: request.server, address: request.server, hasServerCard: true)
            let model = MockServerJoin(
                server: server,
                scenario: serverJoinScenario ?? (joinedServers.contains(request.id) ? .ready : .resolving),
                stepDelay: stepDelay)
            model.onInstalled = { [weak self] in self?.joinedServers.insert(request.id) }
            return model
        }

        // MARK: GAP-11 AirAppearance
        public private(set) var lastAppearance: (String, String, String)?
        public func applyAirAppearance(accentHex: String, cardHex: String, textHex: String) {
            lastAppearance = (accentHex, cardHex, textHex)
        }

        enum MockError: LocalizedError {
            case notFound
            var errorDescription: String? { "Not found" }
        }
    }

    /// Stand-ins for Air's UIKit screens (GAP-10).
    public final class MockAirScreens: AirScreens {
        public init() {}
        @MainActor public func controlsEditor() -> UIViewController {
            Self.placeholder("Controls editor", detail: "Air · CustomControlsViewController")
        }

        @MainActor static func placeholder(_ title: String, detail: String) -> UIViewController {
            let vc = UITableViewController(style: .insetGrouped)
            vc.title = title
            let label = UILabel()
            label.text = detail
            label.font = .cofre(.label)
            label.textAlignment = .center
            vc.tableView.tableHeaderView = label
            label.frame.size.height = 60
            return vc
        }
    }
#endif
