#if canImport(UIKit)
import Foundation

// The boundary between CofreUI and the logic layer. Screens never see these directly: they read the
// @Observable `CofreStore`, which calls these protocols. No Air, CofreKit or ObjC types appear here.
//
// This file covers what CofreKit's facade already offers (AirBridge, TunnelService, JITService,
// PairingStore, SetupStatusStore). New capabilities are in Requirements.swift.

/// S01–S08, X04. Maps to `SetupStatusStore`, `PairingStore`, `TunnelService`, `JITService`.
public protocol SetupService: AnyObject {
    /// `SetupStatusStore.value`
    func setupState() async -> SetupState
    /// `SetupStatusStore.updates`
    func setupUpdates() -> AsyncStream<SetupState>
    /// Re-runs every check and publishes through `setupUpdates()`.
    func recheckSetup() async
    /// S02 "Open Settings app". Public API can only open the Settings app, not Privacy & Security.
    @MainActor func openDeveloperModeSettings()
    /// `PairingStore.hasPairing()` / `.importPairing(_:)` / `.deletePairing()`
    func hasPairing() -> Bool
    func importPairing(_ data: Data) throws
    func deletePairing() throws
    /// `TunnelService.isRunning` / `.start()`. The iOS VPN prompt is native.
    var isVPNRunning: Bool { get }
    func startVPN() async throws
    /// `JITService.isEnabled`
    var isJITEnabled: Bool { get }
}

/// P01, P03, P04, I02, X01. Maps to `AirBridge.instances/createInstance/installLoader/worlds/servers/preferences/setPreferences`.
public protocol LibraryService: AnyObject {
    func instances() async throws -> [InstanceSummary]
    func createInstance(name: String, version: String, loader: Loader) async throws -> InstanceSummary
    func installLoader(instanceID: String, loader: Loader, version: String) async throws
    func worlds(instanceID: String) async throws -> [WorldSummary]
    func servers(instanceID: String) async throws -> [ServerSummary]
    /// `nil` means the global defaults (Settings), an ID means per-instance overrides.
    func preferences(instanceID: String?) async throws -> GamePreferences
    func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws
}

/// M04. Maps to `AirBridge.mods/shaders/resourcePacks/toggleMod/deleteMod/updateMods`.
public protocol ContentService: AnyObject {
    func installed(_ kind: ContentKind, instanceID: String) async throws -> [InstalledItem]
    func setEnabled(_ enabled: Bool, item: InstalledItem, instanceID: String) async throws
    func delete(_ item: InstalledItem, instanceID: String) async throws
    func updateAll(instanceID: String) async throws
}

/// S07, X05. Maps to `AirBridge.accounts/signInMicrosoft/removeAccount`.
public protocol AccountService: AnyObject {
    func accounts() async throws -> [Account]
    func signInMicrosoft() async throws -> Account
    func removeAccount(id: String) async throws
}

/// Everything the UI needs from one object. The logic agent writes one adapter around CofreKit that conforms.
public typealias CofreBackend = SetupService & LibraryService & ContentService & AccountService
    & LaunchControl & LogSource & InstanceActions & VersionCatalog & ProjectCatalog & InstallProgressSource
    & JITTester & SigningInfoSource & SystemCatalog & AirAppearance & OptionalActions

/// What the shell hands to `CofreUI.makeRootViewController(services:)`.
public struct CofreServices {
    public var backend: any CofreBackend
    /// Air's leftover UIKit screens (GAP-10). Lives in Glue; `nil` hides the entry points.
    public var airScreens: (any AirScreens)?

    public init(backend: any CofreBackend, airScreens: (any AirScreens)? = nil) {
        self.backend = backend; self.airScreens = airScreens
    }

    /// Sample data from the mockups, for previews, tests and the preview host.
    public static func mock(setupComplete: Bool = true) -> CofreServices {
        CofreServices(backend: MockBackend(setupComplete: setupComplete), airScreens: MockAirScreens())
    }
}
#endif
