#if canImport(UIKit)
import UIKit

// ┌────────────────────────────────────────────────────────────────────────────────────────────┐
// │ FACADE REQUIREMENTS FOR THE LOGIC AGENT                                                    │
// │ DESIGN_SYSTEM §4.2 lists 11 gaps between CofreKit's facade and the screens. Each is a       │
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
}

// MARK: GAP-06 · Install and import progress (M02, M03)
/// Streams instead of `async throws`, so M03 can show stages and keep going in the background.
public protocol InstallProgressSource: AnyObject {
    func install(projectID: String, versionID: String, instanceID: String) -> AsyncThrowingStream<InstallProgress, Error>
    /// `instanceID == nil` imports the pack as a new instance.
    func importPack(_ url: URL, instanceID: String?) -> AsyncThrowingStream<InstallProgress, Error>
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
    /// The user's own CurseForge key, stored in the Keychain by CofreKit. Never bundled.
    func curseForgeKey() -> String?
    func setCurseForgeKey(_ key: String?) throws
}

// MARK: GAP-10 · Air screens (X03, P04 Forge/NeoForge)
/// Goes in Glue (not CofreKit) so CofreKit stays UI-agnostic. CofreUI presents the returned
/// controllers inside `CofreAirHostController`, where `CofreUIKitTheme` applies.
public protocol AirScreens: AnyObject {
    @MainActor func controlsEditor() -> UIViewController
    @MainActor func forgeInstaller(instanceID: String) -> UIViewController
}

// MARK: GAP-11 · Air appearance (all Air VCs)
/// Writes `general.accent_color`, `general.card_color`, `general.text_color`, sets
/// `background_glass_style = "native"`, `background_glass_handdrawn = NO`, then posts `AMEGlassStyleChanged`.
public protocol AirAppearance: AnyObject {
    func applyAirAppearance(accentHex: String, cardHex: String, textHex: String)
}

// MARK: GAP-12 · Extended preferences (addition, not in §4.2)
// `GamePreferences` has more fields than `CofrePreferences` (autoRAM, fsrMode, fpsOverlay, vsync, fpsCap,
// mute, mic, gyro, virtual mouse, hotbar swipe, TouchController, button scale, layouts, download source,
// verify files, AirPlay, capes, updates). Map each to its Air pref key in `LibraryService.preferences`.
#endif
