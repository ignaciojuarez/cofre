#if canImport(UIKit)
import Foundation

// GAP-14 · Join server sheet. Mirrors `launcher-plan/server-join/POPUP_CONTRACT.md` §2 field for field, so the
// adapter around `CofreServerJoin` is a thin mapping. Fields marked "Addition" aren't in the contract yet; each
// has a default. The sheet binds to `ServerJoinViewModel`; the backend hands one out through `ServerJoinSource`.

/// One server's join flow. The sheet reads `server` and `state` and sends every tap as a `ServerJoinAction`.
/// CofreUI keeps the model while an install runs, so closing the sheet never stops it.
@MainActor public protocol ServerJoinViewModel: AnyObject, Observable {
    /// Header in every state. `detail` is the player line ("12/40 online"), `pingMS` the latency.
    var server: ServerSummary { get }
    var state: ServerJoinState { get }
    func send(_ action: ServerJoinAction)
}

/// §1 state machine. `warnings` keeps the requirements so the primary button can show the download size.
public enum ServerJoinState: Equatable, Sendable {
    case resolving
    case requirements(ServerJoinRequirementsState)
    case warnings(ServerJoinWarningState, requirements: ServerJoinRequirementsState)
    case installing(ServerJoinInstallingState)
    case updateAvailable(ServerJoinUpdateState)
    case error(ServerJoinErrorState)
    case ready(ServerJoinReadyState)
}

public enum ServerJoinAction: Equatable, Sendable {
    /// An optional mod, resource pack or shader switched on or off. Recompute `totalDownloadSizeBytes` and
    /// `formattedDownloadSize` for the new selection.
    case setSelected(id: String, isSelected: Bool)
    /// "Install & Join" in `requirements` or `warnings`.
    case install
    /// "Get" on a CurseForge item (the UI also opens `actionURL`), or "Trust new key" after the native confirmation.
    /// Set `isResolved` once the file arrives or the key is pinned.
    case resolveWarning(id: String)
    case cancelInstall
    /// "Update & Join" in `updateAvailable`.
    case update
    case setAutoUpdate(Bool)
    case setAutoConnect(Bool)
    /// `RecoveryAction.retry`.
    case retry
    /// "Launch & Join" in `ready`. The UI then starts the launch takeover for `instanceID`; pass `--server`/`--port`
    /// on that launch when `autoConnectOnLaunch` is on.
    case launch
    /// The sheet closed. Installs keep going.
    case dismiss
}

/// What opens the sheet: a server row's Join button, or `cofre://join?server=…&card=…&pin=…` (SPEC §2, priority 1).
public struct ServerJoinRequest: Identifiable, Hashable, Sendable {
    /// Host and optional port, "play.example.com:25565".
    public var server: String
    /// Direct HTTPS URL of `server-card.json`.
    public var card: URL?
    /// Expected Ed25519 key fingerprint (hex or base64url) for pre-pinned trust.
    public var pin: String?
    public var id: String { server.lowercased() }

    public init(server: String, card: URL? = nil, pin: String? = nil) { self.server = server; self.card = card; self.pin = pin }

    /// Parses a deep link. `nil` unless it's `cofre://join` with a plain `server` and, if present, an HTTPS `card`.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "cofre", url.host()?.lowercased() == "join",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        }
        guard let server = value("server"), server.count <= 255,
              server.allSatisfy({ $0.isLetter || $0.isNumber || ".-:[]".contains($0) }) else { return nil }
        var card: URL?
        if let raw = value("card") {
            guard let u = URL(string: raw), u.scheme?.lowercased() == "https", u.host() != nil else { return nil }
            card = u
        }
        self.init(server: server, card: card, pin: value("pin"))
    }
}

// MARK: §2.1 requirements

public struct ServerJoinRequirementsState: Equatable, Sendable {
    public let serverID: String
    public let serverName: String
    public let serverAddress: String
    public let iconURL: URL?
    public let motd: String?
    public let pingMS: Int?

    public let gameVersion: String
    public let loader: Loader
    public let loaderVersion: String
    public let javaMajorVersion: Int

    public let packName: String
    public let packVersion: String
    public let totalDownloadSizeBytes: Int64
    public let formattedDownloadSize: String
    public let estimatedDownloadSeconds: Int?
    public let requiredModCount: Int

    public let optionalMods: [SelectableContentItem]
    public let resourcePacks: [SelectableContentItem]
    public let shaderPacks: [SelectableContentItem]

    public let recommendedRAMMB: Int
    public let deviceRAMMB: Int
    public let isNewProfile: Bool

    /// Addition: every required mod, for the row that expands. Sizes add up to that row's total.
    public let requiredMods: [SelectableContentItem]
    /// Addition: who signed the card. Drives the first-visit trust line and the key-changed warning.
    public let trust: ServerJoinTrust?

    public init(serverID: String, serverName: String, serverAddress: String, iconURL: URL? = nil, motd: String? = nil, pingMS: Int? = nil,
                gameVersion: String, loader: Loader, loaderVersion: String, javaMajorVersion: Int,
                packName: String, packVersion: String, totalDownloadSizeBytes: Int64, formattedDownloadSize: String,
                estimatedDownloadSeconds: Int? = nil, requiredModCount: Int,
                optionalMods: [SelectableContentItem] = [], resourcePacks: [SelectableContentItem] = [], shaderPacks: [SelectableContentItem] = [],
                recommendedRAMMB: Int, deviceRAMMB: Int, isNewProfile: Bool,
                requiredMods: [SelectableContentItem] = [], trust: ServerJoinTrust? = nil) {
        self.serverID = serverID; self.serverName = serverName; self.serverAddress = serverAddress; self.iconURL = iconURL
        self.motd = motd; self.pingMS = pingMS; self.gameVersion = gameVersion; self.loader = loader; self.loaderVersion = loaderVersion
        self.javaMajorVersion = javaMajorVersion; self.packName = packName; self.packVersion = packVersion
        self.totalDownloadSizeBytes = totalDownloadSizeBytes; self.formattedDownloadSize = formattedDownloadSize
        self.estimatedDownloadSeconds = estimatedDownloadSeconds; self.requiredModCount = requiredModCount
        self.optionalMods = optionalMods; self.resourcePacks = resourcePacks; self.shaderPacks = shaderPacks
        self.recommendedRAMMB = recommendedRAMMB; self.deviceRAMMB = deviceRAMMB; self.isNewProfile = isNewProfile
        self.requiredMods = requiredMods; self.trust = trust
    }
}

public struct SelectableContentItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String?
    public let sizeBytes: Int64
    public var isSelected: Bool
    public let isRequired: Bool

    public init(id: String, name: String, detail: String? = nil, sizeBytes: Int64, isSelected: Bool, isRequired: Bool = false) {
        self.id = id; self.name = name; self.detail = detail; self.sizeBytes = sizeBytes; self.isSelected = isSelected; self.isRequired = isRequired
    }
}

/// Addition (SPEC §5.1 TOFU): the HTTPS origin and signing key, shown short on the first visit and when the key changes.
public struct ServerJoinTrust: Equatable, Sendable {
    /// Host of the card's HTTPS origin, "ironwood.gg".
    public let origin: String
    /// The card's Ed25519 key fingerprint, any length. The UI shows the first 8 characters.
    public let keyFingerprint: String
    /// The fingerprint pinned before, when the card's key differs from it. `nil` when nothing changed.
    public let pinnedKeyFingerprint: String?
    /// Nothing is pinned for this origin yet. Shows the trust line.
    public let isFirstUse: Bool

    public init(origin: String, keyFingerprint: String, pinnedKeyFingerprint: String? = nil, isFirstUse: Bool) {
        self.origin = origin; self.keyFingerprint = keyFingerprint; self.pinnedKeyFingerprint = pinnedKeyFingerprint; self.isFirstUse = isFirstUse
    }

    /// "7f3a 9c21": the first 8 letters and digits in two groups.
    public static func short(_ fingerprint: String) -> String {
        let s = String(fingerprint.filter { $0.isLetter || $0.isNumber }.prefix(8))
        return s.count > 4 ? "\(s.prefix(4)) \(s.dropFirst(4))" : s
    }
}

// MARK: §2.2 warnings

public struct ServerJoinWarningState: Equatable, Sendable {
    public enum WarningSeverity: Sendable {
        case notice, performance, security, blocking
    }

    /// Use a standard ID as the prefix and add the item after a colon when there are several,
    /// e.g. `warn.curseforge.manual_download_needed:farmers-delight`. The sheet groups by prefix.
    public struct WarningItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let severity: WarningSeverity
        public let title: String
        public let message: String
        public let actionLabel: String?
        public let actionURL: URL?
        /// Addition: the file arrived or the user confirmed. Blocking and security items stop blocking.
        public var isResolved: Bool

        public init(id: String, severity: WarningSeverity, title: String, message: String, actionLabel: String? = nil,
                    actionURL: URL? = nil, isResolved: Bool = false) {
            self.id = id; self.severity = severity; self.title = title; self.message = message
            self.actionLabel = actionLabel; self.actionURL = actionURL; self.isResolved = isResolved
        }
    }

    public let warnings: [WarningItem]
    /// Lets the user install with unresolved `blocking` items. Never overrides `security` items.
    public let canProceedAnyway: Bool

    public init(warnings: [WarningItem], canProceedAnyway: Bool) { self.warnings = warnings; self.canProceedAnyway = canProceedAnyway }

    public enum StandardID {
        public static let untrustedHost = "warn.security.untrusted_host"
        public static let keyRotationUnverified = "warn.security.key_rotation_unverified"
        public static let highRAM = "warn.hardware.high_ram"
        public static let lowStorage = "warn.hardware.low_storage"
        public static let cellularData = "warn.network.cellular_data"
        public static let iosIncompatible = "warn.ios.incompatible_mod_dropped"
        public static let curseForgeManual = "warn.curseforge.manual_download_needed"
    }
}

// MARK: §2.3 installing

public struct ServerJoinInstallingState: Equatable, Sendable {
    public let title: String
    public let progressFraction: Double
    public let formattedProgress: String
    public let speedFormatted: String?
    public let timeRemainingSeconds: Int?
    /// Titles are shown as is, so make them the player's words ("Fabric 1.21.1", "Mods"), not pipeline stages.
    public let stages: [InstallStage]
    public let currentStageIndex: Int
    public let canCancel: Bool

    public init(title: String, progressFraction: Double, formattedProgress: String, speedFormatted: String? = nil,
                timeRemainingSeconds: Int? = nil, stages: [InstallStage], currentStageIndex: Int, canCancel: Bool) {
        self.title = title; self.progressFraction = progressFraction; self.formattedProgress = formattedProgress
        self.speedFormatted = speedFormatted; self.timeRemainingSeconds = timeRemainingSeconds; self.stages = stages
        self.currentStageIndex = currentStageIndex; self.canCancel = canCancel
    }
}

public struct InstallStage: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    /// `.failed`'s text is never shown; the row says "Failed".
    public let state: CheckState
    /// Trailing meta: "17 / 24", "Already have".
    public let detail: String?

    public init(id: Int, title: String, state: CheckState, detail: String? = nil) {
        self.id = id; self.title = title; self.state = state; self.detail = detail
    }
}

// MARK: §2.4 update_available

public struct ServerJoinUpdateState: Equatable, Sendable {
    public let serverID: String
    public let currentVersion: String
    public let newVersion: String
    public let changelogText: String?
    public let changelogURL: URL?
    public let isBreakingChange: Bool

    public let addedMods: [String]
    public let removedMods: [String]
    public let updatedMods: [ModUpdateSummary]
    public let downloadSizeBytes: Int64
    /// Addition: "Update this server automatically". Changed with `.setAutoUpdate`.
    public var autoUpdate: Bool

    public init(serverID: String, currentVersion: String, newVersion: String, changelogText: String? = nil, changelogURL: URL? = nil,
                isBreakingChange: Bool = false, addedMods: [String] = [], removedMods: [String] = [], updatedMods: [ModUpdateSummary] = [],
                downloadSizeBytes: Int64, autoUpdate: Bool = false) {
        self.serverID = serverID; self.currentVersion = currentVersion; self.newVersion = newVersion
        self.changelogText = changelogText; self.changelogURL = changelogURL; self.isBreakingChange = isBreakingChange
        self.addedMods = addedMods; self.removedMods = removedMods; self.updatedMods = updatedMods
        self.downloadSizeBytes = downloadSizeBytes; self.autoUpdate = autoUpdate
    }
}

public struct ModUpdateSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let fromVersion: String
    public let toVersion: String

    public init(id: String, name: String, fromVersion: String, toVersion: String) {
        self.id = id; self.name = name; self.fromVersion = fromVersion; self.toVersion = toVersion
    }
}

// MARK: §2.5 error

public struct ServerJoinErrorState: Equatable, Sendable {
    public enum ErrorCode: String, CaseIterable, Sendable {
        case networkTimeout = "ERR_NET_TIMEOUT"
        case hostNotFound = "ERR_HOST_NOT_FOUND"
        case checksumMismatch = "ERR_CHECKSUM_MISMATCH"
        case storageFull = "ERR_STORAGE_FULL"
        case jitMissing = "ERR_JIT_UNMOUNTED"
        case signatureRejected = "ERR_SIGNATURE_REJECTED"
        case pathTraversalDetected = "ERR_SECURITY_PATH_TRAVERSAL"
        case curseForgeRestricted = "ERR_CURSEFORGE_RESTRICTED"
    }

    public let code: ErrorCode
    /// For logs only. The sheet shows its own words for `code`, so a raw error never reaches the screen.
    public let title: String
    public let message: String
    public let recoveryAction: RecoveryAction

    public init(code: ErrorCode, title: String = "", message: String = "", recoveryAction: RecoveryAction) {
        self.code = code; self.title = title; self.message = message; self.recoveryAction = recoveryAction
    }
}

public enum RecoveryAction: Hashable, Sendable {
    case retry
    case openSettingsStorage
    case triggerJITWorkflow
    case openCurseForgeWeb(url: URL, expectedHash: String)
    case contactServerAdmin
    case dismiss
}

// MARK: §2.6 ready

public struct ServerJoinReadyState: Equatable, Sendable {
    public let serverID: String
    public let serverName: String
    public let serverAddress: String
    public let instanceID: String
    public let isJITReady: Bool
    public var autoConnectOnLaunch: Bool
    public let primaryButtonTitle: String

    public init(serverID: String, serverName: String, serverAddress: String, instanceID: String, isJITReady: Bool,
                autoConnectOnLaunch: Bool = true, primaryButtonTitle: String = "Launch & Join") {
        self.serverID = serverID; self.serverName = serverName; self.serverAddress = serverAddress; self.instanceID = instanceID
        self.isJITReady = isJITReady; self.autoConnectOnLaunch = autoConnectOnLaunch; self.primaryButtonTitle = primaryButtonTitle
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
