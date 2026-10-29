#if canImport(UIKit)
import Foundation

// Value types the screens render. Plain Swift, no Air or ObjC. The logic agent maps CofreKit/AirBridge types onto these.

public enum CheckState: Equatable, Sendable {
    case unknown, checking, ready, blocked, failed(String)
    public var isReady: Bool { self == .ready }
}

/// The six wizard checks (§4: one-to-one with `CofreKit.SetupStatus`).
public struct SetupState: Equatable, Sendable {
    public var devMode, trust, pairing, vpn, jit, account: CheckState
    public init(devMode: CheckState = .unknown, trust: CheckState = .unknown, pairing: CheckState = .unknown,
                vpn: CheckState = .unknown, jit: CheckState = .unknown, account: CheckState = .unknown) {
        self.devMode = devMode; self.trust = trust; self.pairing = pairing; self.vpn = vpn; self.jit = jit; self.account = account
    }
    public var all: [CheckState] { [devMode, trust, pairing, vpn, jit, account] }
    public var isComplete: Bool { all.allSatisfy(\.isReady) }
    public var readyCount: Int { all.filter(\.isReady).count }
}

public enum Loader: String, CaseIterable, Codable, Sendable, Identifiable {
    case vanilla, fabric, quilt, forge, neoforge
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .vanilla: "Vanilla"; case .fabric: "Fabric"; case .quilt: "Quilt"; case .forge: "Forge"; case .neoforge: "NeoForge" }
    }
    public var tone: Tone {
        switch self { case .vanilla: .neutral; case .fabric: .fabric; case .quilt: .quilt; case .forge: .forge; case .neoforge: .neoforge }
    }
    /// Forge and NeoForge install through Air's UIKit installer (`AirScreens.forgeInstaller`).
    public var usesAirInstaller: Bool { self == .forge || self == .neoforge }
}

/// Instance icon: a pixel glyph plus an optional ore tint (hex), or a PNG from the pack.
public struct InstanceIcon: Hashable, Sendable {
    public var glyph: PixelGlyph
    public var tintHex: UInt32?
    public var png: Data?
    public init(glyph: PixelGlyph = .grass, tintHex: UInt32? = nil, png: Data? = nil) { self.glyph = glyph; self.tintHex = tintHex; self.png = png }
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

    public init(id: String, name: String, loader: Loader, gameVersion: String, loaderVersion: String? = nil, modCount: Int? = nil,
                sizeBytes: Int64? = nil, lastPlayed: Date? = nil, updatesAvailable: Int = 0, javaVersion: String? = nil,
                ownFolder: Bool = true, icon: InstanceIcon = .init()) {
        self.id = id; self.name = name; self.loader = loader; self.gameVersion = gameVersion; self.loaderVersion = loaderVersion
        self.modCount = modCount; self.sizeBytes = sizeBytes; self.lastPlayed = lastPlayed; self.updatesAvailable = updatesAvailable
        self.javaVersion = javaVersion; self.ownFolder = ownFolder; self.icon = icon
    }

    public var loaderLabel: String { loader == .vanilla ? "Vanilla \(gameVersion)" : "\(loader.displayName) \(gameVersion)" }
}

public struct WorldSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String, mode: String
    public var playTime: String?, lastPlayed: Date?
    public var icon: InstanceIcon
    public init(id: String, name: String, mode: String, playTime: String? = nil, lastPlayed: Date? = nil, icon: InstanceIcon = .init()) {
        self.id = id; self.name = name; self.mode = mode; self.playTime = playTime; self.lastPlayed = lastPlayed; self.icon = icon
    }
}

public struct ServerSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String, address: String
    public var detail: String?, pingMS: Int?
    /// The server publishes a server card (GAP-14): its row gets a "Modded" badge and a Join button.
    public var hasServerCard: Bool
    public init(id: String, name: String, address: String, detail: String? = nil, pingMS: Int? = nil, hasServerCard: Bool = false) {
        self.id = id; self.name = name; self.address = address; self.detail = detail; self.pingMS = pingMS; self.hasServerCard = hasServerCard
    }
}

public enum ContentKind: String, CaseIterable, Codable, Sendable { case mods, shaders, resourcePacks, dataPacks, modpacks }

public struct InstalledItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String, version: String, enabled: Bool
    public var kind: ContentKind
    public var updateTo: String?
    /// e.g. "Fabric API missing".
    public var issue: String?
    public init(id: String, name: String, version: String, enabled: Bool, kind: ContentKind = .mods, updateTo: String? = nil, issue: String? = nil) {
        self.id = id; self.name = name; self.version = version; self.enabled = enabled; self.kind = kind; self.updateTo = updateTo; self.issue = issue
    }
}

public struct Account: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var kind: String
    public var isActive: Bool
    public init(id: String, name: String, kind: String = "Microsoft", isActive: Bool = false) { self.id = id; self.name = name; self.kind = kind; self.isActive = isActive }
}

/// Everything X01–X07 edit. Existing CofreKit fields first; the rest map to Air prefs (see Requirements GAP-12).
public struct GamePreferences: Equatable, Sendable {
    /// `autoRAM` is on by default: Cofre (the backend) picks a safe amount. `ramMB` applies only when it's off.
    public var ramMB = 4096, autoRAM = true, deviceRAMMB = 8192
    public var renderer = "auto", resolution = 1.0, fsr = true, fsrMode = FSRMode.ultra
    public var java = "auto", jvmArgs = ""
    public var fpsOverlay = true, vsync = false, fpsCap = 60, muteWithSwitch = true, microphone = false
    public var gyroAim = true, virtualMouse = false, hotbarSwipe = true, touchControllerMod = true, buttonScale = 1.0
    public var controllerLayout = "Default", touchLayout = "Default"
    public var downloadSource = DownloadSource.official, verifyFiles = true
    public var airPlayFullscreen = true, capes = false, checkUpdates = true
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
    public init(stage: Int, of: Int, title: String, fraction: Double? = nil, detail: String? = nil, finished: Bool = false) {
        self.stage = stage; self.of = of; self.title = title; self.fraction = fraction; self.detail = detail; self.finished = finished
    }
}

public enum LogKind: String, CaseIterable, Sendable { case latest, crash, launcher }

public struct LogLine: Identifiable, Hashable, Sendable {
    public enum Level: Sendable { case info, success, warning, error }
    public let id: Int
    public var time: String, tag: String, text: String, level: Level
    public init(id: Int, time: String, tag: String, text: String, level: Level = .info) {
        self.id = id; self.time = time; self.tag = tag; self.text = text; self.level = level
    }
}

public enum ExportFormat: String, Sendable { case mrpack, zip }
public enum VersionKind: String, CaseIterable, Sendable { case release, snapshot, old }

public struct GameVersion: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: VersionKind
    public init(id: String, kind: VersionKind = .release) { self.id = id; self.kind = kind }
}

public enum ProjectSource: String, CaseIterable, Sendable { case modrinth, curseforge
    public var displayName: String { self == .modrinth ? "Modrinth" : "CurseForge" }
}

public struct ProjectQuery: Hashable, Sendable {
    public var text: String, source: ProjectSource, kind: ContentKind, instanceID: String?, onlyFitting: Bool
    public init(text: String = "", source: ProjectSource = .modrinth, kind: ContentKind = .mods, instanceID: String? = nil, onlyFitting: Bool = true) {
        self.text = text; self.source = source; self.kind = kind; self.instanceID = instanceID; self.onlyFitting = onlyFitting
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
    public init(id: String, title: String, author: String, summary: String, iconURL: URL? = nil, iconTintHex: UInt32? = nil, downloads: Int,
                updated: Date? = nil, loaders: [Loader], clientSide: Bool = false, fits: Bool, installed: Bool = false, source: ProjectSource = .modrinth,
                pageURL: URL? = nil) {
        self.id = id; self.title = title; self.author = author; self.summary = summary; self.iconURL = iconURL; self.iconTintHex = iconTintHex
        self.downloads = downloads; self.updated = updated; self.loaders = loaders; self.clientSide = clientSide; self.fits = fits
        self.installed = installed; self.source = source; self.pageURL = pageURL
    }

    /// Modrinth resolves project IDs and slugs. CurseForge has no ID URL, so it gets a search for the title.
    public var fallbackPageURL: URL? {
        switch source {
        case .modrinth: URL(string: "https://modrinth.com/project/\(id)")
        case .curseforge:
            URL(string: "https://www.curseforge.com/minecraft/search?search=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)")
        }
    }
}

public struct ProjectVersion: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String, gameVersions: String, channel: String, fits: Bool
    public init(id: String, name: String, gameVersions: String, channel: String = "Release", fits: Bool) {
        self.id = id; self.name = name; self.gameVersions = gameVersions; self.channel = channel; self.fits = fits
    }
}

public struct ProjectDependency: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String, required: Bool, installed: Bool
    public init(id: String, name: String, required: Bool = true, installed: Bool) { self.id = id; self.name = name; self.required = required; self.installed = installed }
}

public struct InstallProgress: Equatable, Sendable {
    public struct Stage: Equatable, Sendable { public var title: String, state: CheckState, detail: String?
        public init(title: String, state: CheckState, detail: String? = nil) { self.title = title; self.state = state; self.detail = detail } }
    public var title: String, fraction: Double, detail: String?
    public var stages: [Stage]
    public init(title: String, fraction: Double, detail: String? = nil, stages: [Stage] = []) {
        self.title = title; self.fraction = fraction; self.detail = detail; self.stages = stages
    }
}

/// S06 / X04 step stream: pairing, VPN, DDI, debugger, region, detach.
public struct JITStep: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case pairing, vpn, diskImage, debugger, region, detach }
    public var kind: Kind, state: CheckState, detail: String?
    public init(kind: Kind, state: CheckState, detail: String? = nil) { self.kind = kind; self.state = state; self.detail = detail }
}

public struct SigningInfo: Equatable, Sendable {
    public var team: String, expires: Date, deviceRegistered: Bool, installed: Bool
    public init(team: String, expires: Date, deviceRegistered: Bool, installed: Bool = true) {
        self.team = team; self.expires = expires; self.deviceRegistered = deviceRegistered; self.installed = installed
    }
}

public struct RendererOption: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String, detail: String, recommended: Bool
    public init(id: String, name: String, detail: String, recommended: Bool = false) { self.id = id; self.name = name; self.detail = detail; self.recommended = recommended }
}

public struct JavaRuntime: Identifiable, Hashable, Sendable {
    public let id: String
    public var major: Int, installed: Bool
    public init(id: String, major: Int, installed: Bool) { self.id = id; self.major = major; self.installed = installed }
}

public struct StorageUsage: Equatable, Sendable {
    public var gameBytes: Int64, javaBytes: Int64, cacheBytes: Int64
    public var total: Int64 { gameBytes + javaBytes + cacheBytes }
    public init(gameBytes: Int64, javaBytes: Int64, cacheBytes: Int64) { self.gameBytes = gameBytes; self.javaBytes = javaBytes; self.cacheBytes = cacheBytes }
}

public struct DeviceInfo: Equatable, Sendable {
    public var model: String, os: String, jitMode: String
    public init(model: String, os: String, jitMode: String) { self.model = model; self.os = os; self.jitMode = jitMode }
}

public struct AppInfo: Equatable, Sendable {
    public var version: String, airVersion: String, sourceURL: URL
    public init(version: String, airVersion: String, sourceURL: URL) { self.version = version; self.airVersion = airVersion; self.sourceURL = sourceURL }
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
