#if canImport(UIKit)
    import Foundation

    // Value types the screens render. Plain Swift, no Air or ObjC. The adapter maps CofreBackendAdapter/AirBridge types onto these.

    public enum CheckState: Equatable, Sendable {
        case unknown, checking, ready, blocked
        case failed(String)
        public var isReady: Bool { self == .ready }
    }

    /// The six wizard checks (§4: one-to-one with `CofreBackendAdapter.SetupStatus`).
    public struct SetupState: Equatable, Sendable {
        public var devMode, trust, pairing, vpn, jit, account: CheckState
        public init(
            devMode: CheckState = .unknown, trust: CheckState = .unknown, pairing: CheckState = .unknown,
            vpn: CheckState = .unknown, jit: CheckState = .unknown, account: CheckState = .unknown
        ) {
            self.devMode = devMode
            self.trust = trust
            self.pairing = pairing
            self.vpn = vpn
            self.jit = jit
            self.account = account
        }
        public var all: [CheckState] { [devMode, trust, pairing, vpn, jit, account] }
        public var isComplete: Bool { all.allSatisfy(\.isReady) }
        public var readyCount: Int { all.filter(\.isReady).count }
    }

    public enum Loader: String, CaseIterable, Codable, Sendable, Identifiable {
        case vanilla, fabric, quilt, forge, neoforge
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .vanilla: "Vanilla"
            case .fabric: "Fabric"
            case .quilt: "Quilt"
            case .forge: "Forge"
            case .neoforge: "NeoForge"
            }
        }
        public var tone: Tone {
            switch self {
            case .vanilla: .neutral
            case .fabric: .fabric
            case .quilt: .quilt
            case .forge: .forge
            case .neoforge: .neoforge
            }
        }
        /// Its icon: grass for vanilla, else the loader's mark.
        public var glyph: PixelGlyph {
            switch self {
            case .vanilla: .grass
            case .fabric: .fabric
            case .quilt: .quilt
            case .forge: .forge
            case .neoforge: .neoforge
            }
        }
    }

    /// Instance icon: a pixel glyph plus an optional ore tint (hex), or a PNG from the pack. Instances without one get
    /// `automatic`.
    public struct InstanceIcon: Hashable, Sendable {
        public var glyph: PixelGlyph
        public var tintHex: UInt32?
        public var png: Data?
        public init(glyph: PixelGlyph = .grass, tintHex: UInt32? = nil, png: Data? = nil) {
            self.glyph = glyph
            self.tintHex = tintHex
            self.png = png
        }

        /// Vanilla instances get one of these, picked from the ID so it never changes between launches.
        public static let blocks: [PixelGlyph] = [.dirt, .cobble, .planks, .stone, .sand, .gravel, .log, .bricks]
        /// The Options grid: grass, the blocks, then the loaders.
        public static let choices: [PixelGlyph] = [.grass] + blocks + [.fabric, .quilt, .forge, .neoforge]

        /// Without a pack PNG or a pick: the loader's icon, or a block for vanilla.
        public static func automatic(id: String, loader: Loader) -> InstanceIcon {
            .init(glyph: loader == .vanilla ? blocks[Int(stableHash(id) % UInt32(blocks.count))] : loader.glyph)
        }

        /// The pack's PNG wins, then the user's pick (a `PixelGlyph` raw value), then `automatic`.
        public static func resolve(png: Data?, picked: String?, id: String, loader: Loader) -> InstanceIcon {
            if let png { return .init(png: png) }
            if let glyph = picked.flatMap(PixelGlyph.init(rawValue:)) { return .init(glyph: glyph) }
            return automatic(id: id, loader: loader)
        }

        /// Same value on every launch (`hashValue` is seeded per process).
        static func stableHash(_ s: String) -> UInt32 { s.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value } }
    }

    public struct InstanceSummary: Identifiable, Hashable, Sendable {
        public let id: String
        public var name: String
        public var loader: Loader
        public var gameVersion: String
        // GAP-03 metadata (optional until the facade provides it).
        public var loaderVersion: String?
        public var modCount: Int?
        public var sizeBytes: Int64?
        public var lastPlayed: Date?
        public var updatesAvailable: Int
        public var javaVersion: String?
        public var ownFolder: Bool
        public var icon: InstanceIcon
        public var favorite: Bool
        public var group: String?
        public var notes: String

        public init(
            id: String, name: String, loader: Loader, gameVersion: String, loaderVersion: String? = nil,
            modCount: Int? = nil,
            sizeBytes: Int64? = nil, lastPlayed: Date? = nil, updatesAvailable: Int = 0, javaVersion: String? = nil,
            ownFolder: Bool = true, icon: InstanceIcon? = nil, favorite: Bool = false, group: String? = nil, notes: String = ""
        ) {
            self.id = id
            self.name = name
            self.loader = loader
            self.gameVersion = gameVersion
            self.loaderVersion = loaderVersion
            self.modCount = modCount
            self.sizeBytes = sizeBytes
            self.lastPlayed = lastPlayed
            self.updatesAvailable = updatesAvailable
            self.javaVersion = javaVersion
            self.ownFolder = ownFolder
            self.icon = icon ?? .automatic(id: id, loader: loader)
            self.favorite = favorite; self.group = group; self.notes = notes
        }

        public var loaderLabel: String {
            loader == .vanilla ? "Vanilla \(gameVersion)" : "\(loader.displayName) \(gameVersion)"
        }
    }

    public struct WorldSummary: Identifiable, Hashable, Sendable {
        public let id: String
        public var name: String, mode: String
        public var playTime: String?, lastPlayed: Date?
        public var icon: InstanceIcon
        public init(
            id: String, name: String, mode: String, playTime: String? = nil, lastPlayed: Date? = nil,
            icon: InstanceIcon = .init()
        ) {
            self.id = id
            self.name = name
            self.mode = mode
            self.playTime = playTime
            self.lastPlayed = lastPlayed
            self.icon = icon
        }
    }

    /// One entry of an instance's servers.dat, the only copy. Cofre never keeps its own list: renaming, reordering and
    /// the resource-pack policy happen in game, and Cofre reads the file again when it shows the list.
    public struct ServerSummary: Identifiable, Hashable, Sendable {
        /// Unique within one `servers(instanceID:)` result. The UI reloads after every write.
        public let id: String
        /// `address` is servers.dat's `ip`: host, host:port, or a name with an SRV record.
        public var name: String, address: String
        public var detail: String?, pingMS: Int?
        /// The server publishes a server card (GAP-14): its row gets a "Modded" badge and Join opens the card sheet.
        public var hasServerCard: Bool
        /// The instance whose servers.dat holds it.
        public var instanceID: String?
        /// servers.dat `icon`, or the last ping's favicon (64×64 PNG).
        public var iconPNG: Data?
        /// Plain text. The UI strips `§` codes that slip through.
        public var motd: String?
        public var playersOnline: Int?, playersMax: Int?
        /// Versions it accepts, newest first (the ping's protocol mapped to versions). Empty = unknown.
        public var gameVersions: [String]
        public var protocolVersion: Int?

        public init(
            id: String, name: String, address: String, detail: String? = nil, pingMS: Int? = nil,
            hasServerCard: Bool = false, instanceID: String? = nil, iconPNG: Data? = nil, motd: String? = nil,
            playersOnline: Int? = nil, playersMax: Int? = nil, gameVersions: [String] = [], protocolVersion: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.address = address
            self.detail = detail
            self.pingMS = pingMS
            self.hasServerCard = hasServerCard
            self.instanceID = instanceID
            self.iconPNG = iconPNG
            self.motd = motd
            self.playersOnline = playersOnline
            self.playersMax = playersMax
            self.gameVersions = gameVersions
            self.protocolVersion = protocolVersion
        }

        /// Whether `instance` can join: it runs one of `gameVersions`. Unknown when the server doesn't say.
        public func fit(_ instance: InstanceSummary?) -> ServerFit {
            guard let instance, let newest = gameVersions.first else { return .unknown }
            return gameVersions.contains(instance.gameVersion) ? .fits : .needs(newest)
        }

        /// Fills the live fields from a ping.
        public func updated(with ping: ServerPing) -> ServerSummary {
            var s = self
            s.motd = ping.motd
            s.playersOnline = ping.online
            s.playersMax = ping.max
            s.pingMS = ping.latencyMS
            s.protocolVersion = ping.protocolVersion ?? s.protocolVersion
            if !ping.gameVersions.isEmpty { s.gameVersions = ping.gameVersions }
            s.iconPNG = ping.iconPNG ?? s.iconPNG
            return s
        }
    }

    public enum ServerFit: Hashable, Sendable {
        case unknown, fits
        /// Play it on this version (the newest it accepts).
        case needs(String)
    }

    /// Server List Ping (1.7+ status). `gameVersions` is `protocolVersion` mapped through the backend's table,
    /// because `versionName` can be "Paper 1.21.1" or "Velocity 3.4".
    public struct ServerPing: Hashable, Sendable {
        public var motd: String
        public var online: Int?, max: Int?
        public var versionName: String?, protocolVersion: Int?
        public var gameVersions: [String]
        public var iconPNG: Data?
        public var latencyMS: Int
        public init(
            motd: String, online: Int? = nil, max: Int? = nil, versionName: String? = nil, protocolVersion: Int? = nil,
            gameVersions: [String] = [], iconPNG: Data? = nil, latencyMS: Int
        ) {
            self.motd = motd
            self.online = online
            self.max = max
            self.versionName = versionName
            self.protocolVersion = protocolVersion
            self.gameVersions = gameVersions
            self.iconPNG = iconPNG
            self.latencyMS = latencyMS
        }
    }

    public enum ContentKind: String, CaseIterable, Codable, Sendable {
        case mods, shaders, resourcePacks, dataPacks, modpacks
    }

    public struct InstalledItem: Identifiable, Hashable, Sendable {
        public let id: String
        public var name: String, version: String, enabled: Bool
        public var kind: ContentKind
        public var inUse: Bool
        public var world: String?
        public var updateTo: String?
        /// e.g. "Fabric API missing".
        public var issue: String?
        /// The Modrinth or CurseForge project this file came from, when known. Search rows match on it.
        public var projectID: String?
        /// The exact version installed, when known, so M02 can mark it and offer to switch.
        public var versionID: String?
        /// The build `updateTo` names. Never less stable than the installed one (`VersionChannel.allowsUpdate`).
        public var updateVersionID: String?
        public init(
            id: String, name: String, version: String, enabled: Bool, kind: ContentKind = .mods,
            updateTo: String? = nil, issue: String? = nil, projectID: String? = nil, versionID: String? = nil,
            updateVersionID: String? = nil
        ) {
            self.id = id
            self.name = name
            self.version = version
            self.enabled = enabled
            self.kind = kind
            self.inUse = false
            self.world = nil
            self.updateTo = updateTo
            self.issue = issue
            self.projectID = projectID
            self.versionID = versionID
            self.updateVersionID = updateVersionID
        }

        /// The same project as a search row: its project ID, else the same name (files Cofre couldn't identify, or
        /// installed from the other site).
        public func matches(_ projectID: String, title: String? = nil) -> Bool {
            self.projectID == projectID || id == projectID || title.map { Self.key(name) == Self.key($0) } == true
        }
        static func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
    }

    public enum AccountState: String, Sendable { case ready, expired, demo }
    public struct Account: Identifiable, Hashable, Sendable {
        public let id: String
        public var name: String
        public var kind: String
        public var isActive: Bool
        public var state: AccountState
        public var expiry: Date?
        public init(id: String, name: String, kind: String = "Microsoft", isActive: Bool = false,
                    state: AccountState = .ready, expiry: Date? = nil) {
            self.id = id; self.name = name; self.kind = kind; self.isActive = isActive
            self.state = state; self.expiry = expiry
        }
    }

    /// Everything X01–X07 edit. Existing CofreBackendAdapter fields first; the rest map to Air prefs (see Requirements GAP-12).
    public struct GamePreferences: Equatable, Sendable {
        /// `autoRAM` is on by default: Cofre (the backend) picks a safe amount. `ramMB` applies only when it's off.
        public var ramMB = 4096, autoRAM = true, deviceRAMMB = 8192
        public var renderer = "auto", resolution = 1.0, fsr = true, fsrMode = FSRMode.ultra, graphicsApi = "auto"
        public var java = "auto", jvmArgs = ""
        /// Zero means Auto: follow the display's maximum refresh rate.
        public var fpsOverlay = true, muteWithSwitch = true, microphone = false
        public var gyroAim = true, virtualMouse = false, hotbarSwipe = true, touchControllerMod = true,
            buttonScale = 1.0
        public var controllerLayout = "Default", touchLayout = "Default"
        public var downloadSource = DownloadSource.official, verifyFiles = true
        /// Shown only with `BackendCapabilities.envVariables` / `.rendererTuning` (GAP-13).
        public var envVariables: [String: String] = [:]
        public var shaderCacheMB = 512, multidraw = "Auto", computeShaders = true
        public init() {}

        public enum FSRMode: String, CaseIterable, Sendable { case off, ultra, quality, performance }
        public enum DownloadSource: String, CaseIterable, Sendable { case official, mirror }
    }

    // MARK: GAP payloads (see Requirements.swift)

    public struct LaunchProgress: Equatable, Sendable {
        public var stage: Int, of: Int
        public var title: String
        public var fraction: Double?
        public var detail: String?
        public var finished: Bool
        public init(
            stage: Int, of: Int, title: String, fraction: Double? = nil, detail: String? = nil, finished: Bool = false
        ) {
            self.stage = stage
            self.of = of
            self.title = title
            self.fraction = fraction
            self.detail = detail
            self.finished = finished
        }
    }

    public enum LogKind: String, CaseIterable, Sendable { case latest, crash, launcher }

    public struct ReportPreviewData: Sendable { public let fields: [String]; public let files: [String]; public init(fields: [String], files: [String]) { self.fields = fields; self.files = files } }

    public struct LogLine: Identifiable, Hashable, Sendable {
        public enum Level: Sendable { case info, success, warning, error }
        public let id: Int
        public var time: String, tag: String, text: String, level: Level
        public init(id: Int, time: String, tag: String, text: String, level: Level = .info) {
            self.id = id
            self.time = time
            self.tag = tag
            self.text = text
            self.level = level
        }
    }

    public enum ExportFormat: String, Sendable { case mrpack, zip }
    public enum VersionKind: String, CaseIterable, Sendable { case release, snapshot, old }

    public struct GameVersion: Identifiable, Hashable, Sendable {
        public var id: String
        public var kind: VersionKind
        public init(id: String, kind: VersionKind = .release) {
            self.id = id
            self.kind = kind
        }
    }

    public enum ProjectSource: String, CaseIterable, Sendable {
        case modrinth, curseforge
        public var displayName: String { self == .modrinth ? "Modrinth" : "CurseForge" }
    }

    public struct ProjectQuery: Hashable, Sendable {
        /// Results fit `instanceID` (its game version, and its loader for mods). `nil` browses everything.
        public var text: String, source: ProjectSource, kind: ContentKind, instanceID: String?
        public init(
            text: String = "", source: ProjectSource = .modrinth, kind: ContentKind = .mods, instanceID: String? = nil
        ) {
            self.text = text
            self.source = source
            self.kind = kind
            self.instanceID = instanceID
        }
    }

    public struct ProjectSummary: Identifiable, Hashable, Sendable {
        public let id: String
        public var title: String, author: String, summary: String
        public var iconURL: URL?, iconTintHex: UInt32?
        public var downloads: Int, updated: Date?
        public var loaders: [Loader], clientSide: Bool
        public var fits: Bool, installed: Bool
        public var source: ProjectSource
        /// The project's web page, for Share. `nil` falls back to `fallbackPageURL`.
        public var pageURL: URL?
        public init(
            id: String, title: String, author: String, summary: String, iconURL: URL? = nil, iconTintHex: UInt32? = nil,
            downloads: Int,
            updated: Date? = nil, loaders: [Loader], clientSide: Bool = false, fits: Bool, installed: Bool = false,
            source: ProjectSource = .modrinth,
            pageURL: URL? = nil
        ) {
            self.id = id
            self.title = title
            self.author = author
            self.summary = summary
            self.iconURL = iconURL
            self.iconTintHex = iconTintHex
            self.downloads = downloads
            self.updated = updated
            self.loaders = loaders
            self.clientSide = clientSide
            self.fits = fits
            self.installed = installed
            self.source = source
            self.pageURL = pageURL
        }

        /// Modrinth resolves project IDs and slugs. CurseForge has no ID URL, so it gets a search for the title.
        public var fallbackPageURL: URL? {
            switch source {
            case .modrinth: URL(string: "https://modrinth.com/project/\(id)")
            case .curseforge:
                URL(
                    string:
                        "https://www.curseforge.com/minecraft/search?search=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)"
                )
            }
        }
    }

    public struct ProjectVersion: Identifiable, Hashable, Sendable {
        public let id: String
        /// `name` is the readable label ("0.9.3 beta 1"); `number` the raw one, for Details.
        public var name: String, gameVersions: String, channel: String, fits: Bool
        public var number: String
        public var games: [String], loaders: [Loader]
        public init(
            id: String, name: String, gameVersions: String, channel: String = "Release", fits: Bool,
            number: String? = nil, games: [String]? = nil, loaders: [Loader] = []
        ) {
            self.id = id
            self.name = name
            self.gameVersions = gameVersions
            self.channel = channel
            self.fits = fits
            self.number = number ?? name
            self.games = games ?? gameVersions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            self.loaders = loaders
        }
        public var versionChannel: VersionChannel { VersionChannel(channel) }
    }

    public struct ProjectDependency: Identifiable, Hashable, Sendable {
        public let id: String
        public var name: String, required: Bool, installed: Bool
        public init(id: String, name: String, required: Bool = true, installed: Bool) {
            self.id = id
            self.name = name
            self.required = required
            self.installed = installed
        }
    }

    /// One file an install adds, or turns back on (GAP-05).
    public struct PlannedMod: Identifiable, Hashable, Sendable {
        /// The project ID.
        public let id: String
        public var name: String, versionID: String, version: String
        public var sizeBytes: Int64?
        /// Already in the instance but off: the install turns it back on instead of downloading it.
        public var turnsOn: Bool
        /// Not a release: the sheet says so.
        public var channel: VersionChannel
        public init(
            id: String, name: String, versionID: String, version: String = "", sizeBytes: Int64? = nil,
            turnsOn: Bool = false, channel: VersionChannel = .release
        ) {
            self.id = id
            self.name = name
            self.versionID = versionID
            self.version = version
            self.sizeBytes = sizeBytes
            self.turnsOn = turnsOn
            self.channel = channel
        }
    }

    /// What Get will do, worked out before anything downloads. Required dependencies come along; optional ones are
    /// offered; ones already on are left out. `blocked` explains why nothing can install.
    public struct ModInstallPlan: Hashable, Sendable {
        public var target: PlannedMod
        public var kind: ContentKind
        public var required: [PlannedMod]
        public var optional: [PlannedMod]
        /// Dependencies already on, by name ("Already have Sodium").
        public var present: [String]
        public var blocked: String?
        public init(
            target: PlannedMod, kind: ContentKind = .mods, required: [PlannedMod] = [], optional: [PlannedMod] = [],
            present: [String] = [], blocked: String? = nil
        ) {
            self.target = target
            self.kind = kind
            self.required = required
            self.optional = optional
            self.present = present
            self.blocked = blocked
        }
        /// A modpack becomes its own instance instead of going into the target.
        public var makesInstance: Bool { kind == .modpacks }
        /// Asks first only when Get would do more than install the one thing the user tapped.
        /// A beta or alpha pick asks too, so it's never a surprise.
        public var needsConfirmation: Bool {
            !required.isEmpty || !optional.isEmpty || makesInstance || target.channel != .release
                || required.contains { $0.channel != .release && !$0.turnsOn }
        }
        /// Everything that installs, with the optional ones picked.
        public func files(picking optionalIDs: Set<String> = []) -> [PlannedMod] {
            [target] + required + optional.filter { optionalIDs.contains($0.id) }
        }
    }

    /// A search row's state in the Mods target.
    public enum ProjectInstallState: Equatable, Sendable {
        case notInstalled, installed, off
        case update(String)
    }

    public struct InstallProgress: Equatable, Sendable {
        public struct Stage: Equatable, Sendable {
            public var title: String, state: CheckState, detail: String?
            public init(title: String, state: CheckState, detail: String? = nil) {
                self.title = title
                self.state = state
                self.detail = detail
            }
        }
        public var title: String, fraction: Double, detail: String?
        public var stages: [Stage]
        public init(title: String, fraction: Double, detail: String? = nil, stages: [Stage] = []) {
            self.title = title
            self.fraction = fraction
            self.detail = detail
            self.stages = stages
        }
    }

    /// S06 / X04 step stream: pairing, VPN, DDI, debugger, region, detach.
    public struct JITStep: Equatable, Sendable {
        public enum Kind: String, CaseIterable, Sendable { case pairing, vpn, diskImage, debugger, region, detach }
        public var kind: Kind, state: CheckState, detail: String?
        public init(kind: Kind, state: CheckState, detail: String? = nil) {
            self.kind = kind
            self.state = state
            self.detail = detail
        }
    }

    public struct SigningInfo: Equatable, Sendable {
        public var team: String, expires: Date, deviceRegistered: Bool, installed: Bool
        public init(team: String, expires: Date, deviceRegistered: Bool, installed: Bool = true) {
            self.team = team
            self.expires = expires
            self.deviceRegistered = deviceRegistered
            self.installed = installed
        }
    }

    public struct RendererOption: Identifiable, Hashable, Sendable {
        public let id: String
        public var name: String, detail: String, recommended: Bool
        public init(id: String, name: String, detail: String, recommended: Bool = false) {
            self.id = id
            self.name = name
            self.detail = detail
            self.recommended = recommended
        }
    }

    public struct JavaRuntime: Identifiable, Hashable, Sendable {
        public let id: String
        public var major: Int, installed: Bool
        public init(id: String, major: Int, installed: Bool) {
            self.id = id
            self.major = major
            self.installed = installed
        }
    }

    public struct StorageUsage: Equatable, Sendable {
        public var gameBytes: Int64, javaBytes: Int64, cacheBytes: Int64
        public var total: Int64 { gameBytes + javaBytes + cacheBytes }
        public init(gameBytes: Int64, javaBytes: Int64, cacheBytes: Int64) {
            self.gameBytes = gameBytes
            self.javaBytes = javaBytes
            self.cacheBytes = cacheBytes
        }
    }

    public struct DeviceInfo: Equatable, Sendable {
        public var model: String, os: String, jitMode: String
        public init(model: String, os: String, jitMode: String) {
            self.model = model
            self.os = os
            self.jitMode = jitMode
        }
    }

    public struct AppInfo: Equatable, Sendable {
        public var version: String, airVersion: String, sourceURL: URL
        public init(version: String, airVersion: String, sourceURL: URL) {
            self.version = version
            self.airVersion = airVersion
            self.sourceURL = sourceURL
        }
    }

    // MARK: Formatting

    enum Fmt {
        static func bytes(_ b: Int64?) -> String? {
            guard let b else { return nil }
            let gb = Double(b) / 1_073_741_824
            return gb >= 1 ? String(format: "%.1f GB", gb) : "\(Int((Double(b) / 1_048_576).rounded())) MB"
        }
        static func count(_ n: Int) -> String {
            n >= 1_000_000 ? "\(n / 1_000_000)M" : n >= 1000 ? "\(n / 1000)K" : "\(n)"
        }
        static func ago(_ d: Date?, now: Date = .now) -> String? {
            guard let d else { return nil }
            let s = now.timeIntervalSince(d)
            switch s {
            case ..<3600: return "\(max(1, Int(s / 60))) min"
            case ..<86400: return "\(Int(s / 3600)) h"
            case ..<(86400 * 7): return "\(Int(s / 86400)) d"
            default: return "\(Int(s / (86400 * 7))) w"
            }
        }
        static func agoLong(_ d: Date?, now: Date = .now) -> String? {
            guard let d else { return nil }
            let days = Int(now.timeIntervalSince(d) / 86400)
            switch days {
            case 0: return "today"
            case 1: return "yesterday"
            case ..<7: return "\(days) days ago"
            case ..<14: return "last week"
            case ..<31: return "\(days / 7) weeks ago"
            case ..<365: return days < 61 ? "last month" : "\(days / 30) months ago"
            default: return "over a year ago"
            }
        }
        static func mb(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) + " MB" }
    }
#endif
