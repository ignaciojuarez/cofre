# Server Join Sheet: Popup Data Contract

*Exact data models and state contracts for the SwiftUI/UIKit Server Join Sheet in Cofre.*
*Directly maps to `CofreUI/Facade/Models.swift`, `Requirements.swift`, and `Services.swift`.*

---

## 1. Sheet State Machine

The Server Join workflow operates as a state machine rendered within an interactive modal sheet (compact on iPhone, regular modal on iPad):

```
       ┌────────────────────────┐
       │   Resolving Card       │
       └───────────┬────────────┘
                   ▼
       ┌────────────────────────┐       (Warnings present)
       │      Requirements      │ ────────────────────────────┐
       └───────────┬────────────┘                             ▼
                   │                               ┌──────────────────────┐
                   │ (User taps Install / Update)  │       Warnings       │
                   ▼                               └──────────┬───────────┘
       ┌────────────────────────┐                             │ (User confirms)
       │       Installing       │ ◀───────────────────────────┘
       └───────────┬────────────┘
                   │
         ┌─────────┴─────────┐
         ▼                   ▼
┌─────────────────┐ ┌─────────────────┐
│      Ready      │ │      Error      │
└─────────────────┘ └─────────────────┘
```

---

## 2. State Payloads (Swift Data Contracts)

### 2.1 State: `requirements`
*Rendered when a server card is resolved and presented to the user for review.*

```swift
public struct ServerJoinRequirementsState: Equatable, Sendable {
    /// Server identity
    public let serverID: String
    public let serverName: String
    public let serverAddress: String
    public let iconURL: URL?
    public let motd: String?
    public let pingMS: Int?
    
    /// Game & Engine Specifications
    public let gameVersion: String
    public let loader: Loader                  // .fabric, .neoforge, etc.
    public let loaderVersion: String
    public let javaMajorVersion: Int          // e.g. 21
    
    /// Modpack Summary
    public let packName: String
    public let packVersion: String
    public let totalDownloadSizeBytes: Int64
    public let formattedDownloadSize: String   // e.g. "48.2 MB"
    public let estimatedDownloadSeconds: Int?
    public let requiredModCount: Int
    
    /// Optional & Custom Content
    public let optionalMods: [SelectableContentItem]
    public let resourcePacks: [SelectableContentItem]
    public let shaderPacks: [SelectableContentItem]
    
    /// Performance & System Settings
    public let recommendedRAMMB: Int
    public let deviceRAMMB: Int
    public let isNewProfile: Bool              // true = fresh install; false = update
}

public struct SelectableContentItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String?
    public let sizeBytes: Int64
    public var isSelected: Bool
    public let isRequired: Bool
}
```

### 2.2 State: `warnings`
*Presented if security anomalies, hardware constraints, or platform incompatibilities exist.*

```swift
public struct ServerJoinWarningState: Equatable, Sendable {
    public enum WarningSeverity: Sendable {
        case notice      // Informational (e.g. desktop audio mod excluded)
        case performance // Hardware (e.g. RAM exceeds 4GB on 6GB device)
        case security    // High severity (untrusted domain, unpinned key change)
        case blocking    // Must resolve before proceeding (e.g. storage full)
    }
    
    public struct WarningItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let severity: WarningSeverity
        public let title: String
        public let message: String
        public let actionLabel: String?
        public let actionURL: URL?
    }
    
    public let warnings: [WarningItem]
    public let canProceedAnyway: Bool
}
```

*Standard Warning IDs*:
* `warn.security.untrusted_host`: Download host is not in the approved CDN allowlist.
* `warn.security.key_rotation_unverified`: Ed25519 signing key changed without valid previous key signature.
* `warn.hardware.high_ram`: Requested RAM exceeds safe threshold on 6 GB iPhones.
* `warn.hardware.low_storage`: Device storage is near capacity.
* `warn.network.cellular_data`: Download size exceeds 50 MB over WWAN.
* `warn.ios.incompatible_mod_dropped`: Mod with x86_64 desktop natives disabled for mobile stability.
* `warn.curseforge.manual_download_needed`: Mod has third-party distribution disabled by author.

### 2.3 State: `installing`
*Real-time installation progress, adhering to `InstallProgress` in `Models.swift`.*

```swift
public struct ServerJoinInstallingState: Equatable, Sendable {
    public let title: String                   // e.g. "Downloading Mods..."
    public let progressFraction: Double        // 0.0 to 1.0
    public let formattedProgress: String       // e.g. "32.4 MB of 48.2 MB (67%)"
    public let speedFormatted: String?         // e.g. "4.8 MB/s"
    public let timeRemainingSeconds: Int?
    
    /// Multi-stage pipeline steps
    public let stages: [InstallStage]
    public let currentStageIndex: Int
    public let canCancel: Bool
}

public struct InstallStage: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String                   // "Resolving dependencies", "Fetching CAS cache", etc.
    public let state: CheckState               // .checking, .ready, .failed(String)
    public let detail: String?
}
```

*Pipeline Stages*:
1. `Stage 0`: Validate manifest & Ed25519 signature
2. `Stage 1`: Install Loader & Game Engine (Fabric/Forge)
3. `Stage 2`: Download missing assets to CAS cache
4. `Stage 3`: Stage profile & unpack configs
5. `Stage 4`: Verify file hashes (SHA-512)
6. `Stage 5`: Atomic profile commit

### 2.4 State: `update_available`
*Rendered when an existing server profile detects a new version.*

```swift
public struct ServerJoinUpdateState: Equatable, Sendable {
    public let serverID: String
    public let currentVersion: String
    public let newVersion: String
    public let changelogText: String?
    public let changelogURL: URL?
    public let isBreakingChange: Bool          // true if loader or MC version changed
    
    /// Content Differences
    public let addedMods: [String]
    public let removedMods: [String]
    public let updatedMods: [ModUpdateSummary]
    public let downloadSizeBytes: Int64
}

public struct ModUpdateSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let fromVersion: String
    public let toVersion: String
}
```

### 2.5 State: `error`
*Structured failure report with concrete user remediation.*

```swift
public struct ServerJoinErrorState: Equatable, Sendable {
    public enum ErrorCode: String, Sendable {
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
    public let title: String
    public let message: String
    public let recoveryAction: RecoveryAction
}

public enum RecoveryAction: Sendable {
    case retry
    case openSettingsStorage
    case triggerJITWorkflow
    case openCurseForgeWeb(url: URL, expectedHash: String)
    case contactServerAdmin
    case dismiss
}
```

### 2.6 State: `ready`
*Final confirmation before launching into Minecraft.*

```swift
public struct ServerJoinReadyState: Equatable, Sendable {
    public let serverID: String
    public let serverName: String
    public let serverAddress: String
    public let instanceID: String
    public let isJITReady: Bool
    public var autoConnectOnLaunch: Bool       // true = passes --server & --port
    public let primaryButtonTitle: String      // "Launch & Join"
}
```

---

## 3. UI Component Mapping to `CofreUI` Design System

| Screen State | Main Components | Facade Service Binding |
|---|---|---|
| **Requirements** | `PixelScene`, `ColumnHeader`, `Badge×3`, `ListSection(Rows)`, `AdaptiveGrid(Stat)`, `BlockButton(primary L)` | `LibraryService.preferences`, `ProjectCatalog` |
| **Warnings** | `Banner(alert)`, `ListSection(Row+Badge)`, `BlockButton(ghost)`, `BlockButton(primary)` | `SetupService`, Security Audits |
| **Installing** | `ProgressBar(XP)`, `Row(stage)×6`, `Stat(Speed)`, `BlockButton(ghost cancel)` | `InstallProgressSource.importPack` |
| **Update Available** | `Banner(tip)`, `Segmented(Diff)`, `ListSection(Added/Removed)`, `BlockButton(primary L)` | `ContentService.updateAll` |
| **Error** | `Banner(error)`, `PixelIcon(warn)`, `Rows(Details)`, `BlockButton(primary retry)` | Error Handler |
| **Ready** | `Badge(big)`, `Row(server)`, `Switch(auto-connect)`, `BlockButton(primary L: Launch)` | `LaunchControl.launch` |
