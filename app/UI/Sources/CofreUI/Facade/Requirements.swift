#if canImport(UIKit)
    import UIKit

    // ┌────────────────────────────────────────────────────────────────────────────────────────────┐
    // │ FACADE REQUIREMENTS FOR THE LOGIC AGENT                                                    │
    // │ DESIGN_SYSTEM §4.2 lists 11 gaps between CofreBackendAdapter's facade and the screens. Each is a       │
    // │ protocol below. `CofreBackend` (Services.swift) composes them, so one adapter conforms to   │
    // │ all. CofreUI only declares them; it implements none (MockBackend is sample data only).      │
    // └────────────────────────────────────────────────────────────────────────────────────────────┘

    // MARK: GAP-01 · Launch progress and cancel (P02)
    /// Replaces the bare `AsyncStream<LaunchStage>`: one value per stage change or progress tick.
    /// Finish with `finished == true`; throw to fail (the message is shown with the failing stage).
    public protocol LaunchControl: AnyObject {
        func launch(instanceID: String, accountID: String?) -> AsyncThrowingStream<LaunchProgress, Error>
        func cancelLaunch() async
    }

    // MARK: GAP-02 · Logs (P02, X06)
    public protocol LogSource: AnyObject {
        /// Emits the existing lines first, then live lines.
        func logLines(_ kind: LogKind) -> AsyncStream<LogLine>
        /// A file URL suitable for the share sheet.
        func exportLog(_ kind: LogKind) async throws -> URL
    }

    // MARK: GAP-03 · Instance metadata and actions (P03, I02)
    /// Metadata: fill `InstanceSummary.loaderVersion`, `modCount`, `sizeBytes`, `lastPlayed`, `updatesAvailable`,
    /// `javaVersion` and `icon.png` from `LibraryService.instances()`. Actions:
    public protocol InstanceActions: AnyObject {
        func duplicate(instanceID: String) async throws -> InstanceSummary
        func delete(instanceID: String) async throws
        func export(instanceID: String, format: ExportFormat) async throws -> URL
    }

    // MARK: GAP-04 · Version catalog (P04)
    public protocol VersionCatalog: AnyObject {
        func gameVersions(_ kind: VersionKind) async throws -> [GameVersion]
        func loaderVersions(loader: Loader, game: String) async throws -> [String]
    }

    // MARK: GAP-05 · Project metadata (M01, M02)
    /// Replaces `searchModrinth/searchCurseForge -> [CofrePack]` with rich results, versions and dependencies.
    public protocol ProjectCatalog: AnyObject {
        func search(_ query: ProjectQuery) async throws -> [ProjectSummary]
        func versions(projectID: String, instanceID: String) async throws -> [ProjectVersion]
        func dependencies(versionID: String, instanceID: String) async throws -> [ProjectDependency]
        /// What Get installs for `projectID` of `kind`: required dependencies, optional ones, or why it can't
        /// (`ModResolver` does the work). `versionID == nil` picks the newest fitting version.
        func installPlan(projectID: String, versionID: String?, kind: ContentKind, instanceID: String) async throws
            -> ModInstallPlan
    }

    extension ProjectCatalog {
        /// Default for backends without a resolver: the picked version alone, with the dependencies it reports.
        public func installPlan(projectID: String, versionID: String?, kind: ContentKind, instanceID: String)
            async throws -> ModInstallPlan
        {
            let all = try await versions(projectID: projectID, instanceID: instanceID)
            guard let v = all.first(where: { $0.id == versionID }) ?? all.first(where: \.fits) else {
                return ModInstallPlan(
                    target: PlannedMod(id: projectID, name: projectID, versionID: ""), kind: kind,
                    blocked: String(localized: "No version fits this instance."))
            }
            let deps = kind == .mods ? try await dependencies(versionID: v.id, instanceID: instanceID) : []
            return ModInstallPlan(
                target: PlannedMod(id: projectID, name: projectID, versionID: v.id, version: v.name), kind: kind,
                required: deps.filter { $0.required && !$0.installed }.map {
                    PlannedMod(id: $0.id, name: $0.name, versionID: "")
                },
                optional: deps.filter { !$0.required && !$0.installed }.map {
                    PlannedMod(id: $0.id, name: $0.name, versionID: "")
                },
                present: deps.filter(\.installed).map(\.name))
        }
    }

    // MARK: GAP-06 · Install and import progress (M02, M03)
    /// Streams instead of `async throws`, so M03 can show stages and keep going in the background.
    public protocol InstallProgressSource: AnyObject {
        func install(projectID: String, versionID: String, instanceID: String) -> AsyncThrowingStream<
            InstallProgress, Error
        >
        /// `instanceID == nil` imports the pack as a new instance.
        func importPack(_ url: URL, instanceID: String?) -> AsyncThrowingStream<InstallProgress, Error>
        /// Installs every file of `plan.files(picking:)` or none: downloads all, then moves them in together. One
        /// `stages` entry per file. A modpack becomes a new instance.
        func install(_ plan: ModInstallPlan, picking optionalIDs: Set<String>, instanceID: String)
            -> AsyncThrowingStream<InstallProgress, Error>
    }

    extension InstallProgressSource {
        /// Default: the target alone, which resolves its own dependencies.
        public func install(_ plan: ModInstallPlan, picking optionalIDs: Set<String>, instanceID: String)
            -> AsyncThrowingStream<InstallProgress, Error>
        {
            install(projectID: plan.target.id, versionID: plan.target.versionID, instanceID: instanceID)
        }
    }

    // MARK: GAP-07 · JIT test steps (S06, X04)
    public protocol JITTester: AnyObject {
        /// pairing → VPN → disk image → debugger → region → detach. Throw with the failing step's message.
        func testJIT() -> AsyncThrowingStream<JITStep, Error>
        /// "TXM · iPhone 17 Pro · iOS 26.1" for the S06 banner and X04.
        func deviceInfo() async -> DeviceInfo?
    }

    // MARK: GAP-08 · Signing info (S03, X06)
    public protocol SigningInfoSource: AnyObject {
        func signingInfo() async -> SigningInfo?
        func appInfo() -> AppInfo
    }

    // MARK: GAP-09 · Lists (X02, X04, X05)
    public protocol SystemCatalog: AnyObject {
        func renderers() async -> [RendererOption]
        func javaRuntimes() async -> [JavaRuntime]
        func storage() async -> StorageUsage
        func clearCache() async throws
        /// The user's own CurseForge key, stored in the Keychain by CofreBackendAdapter. Never bundled.
        func curseForgeKey() -> String?
        func setCurseForgeKey(_ key: String?) throws
    }

    // MARK: GAP-10 · Air screens (X03)
    /// Goes in Glue (not CofreBackendAdapter) so CofreBackendAdapter stays UI-agnostic. CofreUI presents the controls
    /// editor directly, as Air does: inside a navigation controller its exit menu acts on the wrong controller.
    /// Forge and NeoForge install without a screen (`installLoader`).
    public protocol AirScreens: AnyObject {
        @MainActor func controlsEditor() -> UIViewController
    }

    // MARK: GAP-11 · Air appearance (all Air VCs)
    /// Writes `general.accent_color`, `general.card_color`, `general.text_color`, sets
    /// `background_glass_style = "native"`, `background_glass_handdrawn = NO`, then posts `AMEGlassStyleChanged`.
    public protocol AirAppearance: AnyObject {
        func applyAirAppearance(accentHex: String, cardHex: String, textHex: String)
    }

    // MARK: GAP-13 · Capabilities and optional actions (addition, not in §4.2)
    /// Controls the backend can't do yet stay hidden. The backend reports what it supports; every member has a
    /// default (nothing supported, actions throw), so adapters written before this compile unchanged.
    public struct BackendCapabilities: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// World context menu: Delete (with confirmation) → `deleteWorld`.
        public static let deleteWorld = BackendCapabilities(rawValue: 1 << 0)
        /// World context menu: Back up → `backUpWorld`, then the share sheet.
        public static let backUpWorld = BackendCapabilities(rawValue: 1 << 1)
        /// Worlds pane "+ Add server" → `addServer`.
        public static let addServer = BackendCapabilities(rawValue: 1 << 2)
        /// X04 "Env variables" row, from `GamePreferences.envVariables`.
        public static let envVariables = BackendCapabilities(rawValue: 1 << 3)
        /// P04 "Own folder" and "Add Fabric API" → `createInstance(name:version:loader:ownFolder:fabricAPI:)`.
        public static let createOptions = BackendCapabilities(rawValue: 1 << 4)
        /// X02 MobileGlues shader cache, multidraw and compute shaders (`GamePreferences.shaderCacheMB` and friends).
        public static let rendererTuning = BackendCapabilities(rawValue: 1 << 5)
        /// Controller navigation in the launcher (`ControllerFocusBridge`). Shows the A/B/Y hint strip.
        public static let controllerNavigation = BackendCapabilities(rawValue: 1 << 6)
        /// X07 rows: app icon, language, LAN room. No handlers exist yet.
        public static let appIcon = BackendCapabilities(rawValue: 1 << 7)
        public static let language = BackendCapabilities(rawValue: 1 << 8)
        public static let lanRoom = BackendCapabilities(rawValue: 1 << 9)
        /// GAP-14 Join server sheet: "Modded" badges and Join buttons on server rows, and `cofre://join` links.
        public static let serverJoin = BackendCapabilities(rawValue: 1 << 10)
        /// I02 Options icon grid → `setIcon(_:instanceID:)`.
        public static let instanceIcon = BackendCapabilities(rawValue: 1 << 11)
    }

    public protocol OptionalActions: AnyObject {
        var capabilities: BackendCapabilities { get }
        func deleteWorld(instanceID: String, worldID: String) async throws
        /// A file URL (zip) for the share sheet.
        func backUpWorld(instanceID: String, worldID: String) async throws -> URL
        func addServer(instanceID: String, name: String, address: String) async throws -> ServerSummary
        func createInstance(name: String, version: String, loader: Loader, ownFolder: Bool, fabricAPI: Bool)
            async throws -> InstanceSummary
        /// The user's icon pick; `nil` goes back to `InstanceIcon.automatic`.
        func setIcon(_ glyph: PixelGlyph?, instanceID: String) async throws
    }

    public struct UnsupportedAction: LocalizedError {
        public let name: String
        public var errorDescription: String? { "\(name) isn't available in this build." }
    }

    extension OptionalActions {
        public var capabilities: BackendCapabilities { [] }
        public func deleteWorld(instanceID: String, worldID: String) async throws {
            throw UnsupportedAction(name: "Deleting worlds")
        }
        public func backUpWorld(instanceID: String, worldID: String) async throws -> URL {
            throw UnsupportedAction(name: "World backups")
        }
        public func addServer(instanceID: String, name: String, address: String) async throws -> ServerSummary {
            throw UnsupportedAction(name: "Adding servers")
        }
        public func createInstance(name: String, version: String, loader: Loader, ownFolder: Bool, fabricAPI: Bool)
            async throws -> InstanceSummary
        {
            throw UnsupportedAction(name: "Creating instances")
        }
        public func setIcon(_ glyph: PixelGlyph?, instanceID: String) async throws {
            throw UnsupportedAction(name: "Instance icons")
        }
    }

    extension OptionalActions where Self: LibraryService {
        /// Default for full backends: ignores both options and calls the base `createInstance`.
        public func createInstance(name: String, version: String, loader: Loader, ownFolder: Bool, fabricAPI: Bool)
            async throws -> InstanceSummary
        {
            try await createInstance(name: name, version: version, loader: loader)
        }
    }

    // MARK: GAP-14 · Join server sheet (addition, not in §4.2)
    /// Hands out one `ServerJoinViewModel` per server (types in ServerJoin.swift). The default returns `nil`, and the
    /// sheet stays hidden until `capabilities` contains `.serverJoin`, so adapters written before this compile unchanged.
    public protocol ServerJoinSource: AnyObject {
        /// Start resolving the server's card and return its live model. Called again only after the previous model
        /// was dropped (sheet closed while nothing was installing).
        @MainActor func serverJoin(_ request: ServerJoinRequest) -> (any ServerJoinViewModel)?
    }

    extension ServerJoinSource {
        @MainActor public func serverJoin(_ request: ServerJoinRequest) -> (any ServerJoinViewModel)? { nil }
    }

// MARK: GAP-12 · Extended preferences (addition, not in §4.2)
// `GamePreferences` has more fields than `CofrePreferences` (autoRAM, fsrMode, fpsOverlay, vsync, fpsCap,
// mute, mic, gyro, virtual mouse, hotbar swipe, TouchController, button scale, layouts, download source,
// verify files, AirPlay, capes, updates). Map each to its Air pref key in `LibraryService.preferences`.
#endif
