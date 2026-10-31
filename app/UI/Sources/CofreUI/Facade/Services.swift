#if canImport(UIKit)
    import CofreKit
    import Foundation

    // The boundary between CofreUI and the logic layer. Screens never see these directly: they read the
    // @Observable `CofreStore`, which calls these protocols. No Air, CofreBackendAdapter or ObjC types appear here.
    //
    // This file covers what CofreBackendAdapter's facade already offers (AirBridge, TunnelService, JITService,
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
        func servers(instanceID: String) async throws -> [ServerSummary]
        /// `nil` means the global defaults (Settings), an ID means per-instance overrides.
        func preferences(instanceID: String?) async throws -> GamePreferences
        func setPreferences(_ preferences: GamePreferences, instanceID: String?) async throws
    }

    /// M04. Maps to `AirBridge.mods/shaders/resourcePacks/setEnabled/deleteMod/updateMods`.
    public protocol ContentService: AnyObject {
        func installed(_ kind: ContentKind, instanceID: String) async throws -> [InstalledItem]
        func setEnabled(_ enabled: Bool, item: InstalledItem, instanceID: String) async throws
        func delete(_ item: InstalledItem, instanceID: String) async throws
        func updateAll(kind: ContentKind, instanceID: String) async throws
    }

    /// S07, X05. Maps to `AirBridge.accounts/signInMicrosoft/removeAccount`.
    public protocol AccountService: AnyObject {
        func accounts() async throws -> [Account]
        func signInMicrosoft() async throws -> Account
        func removeAccount(id: String) async throws
    }

    /// Servers (plan/servers.md). The instance's servers.dat is the only saved list: `servers(instanceID:)` reads it,
    /// `addServer` (OptionalActions) appends Recommended picks, links and pasted addresses, these copy and delete.
    /// Renaming, reordering and resource packs stay in game. Cofre's job is jumping straight in. Every member has a
    /// default; controls stay hidden until `capabilities` has `.pingServers`, `.quickPlay`, `.serverFiles` or
    /// `.discoverServers`.
    public protocol ServerService: AnyObject {
        /// "Recommended": popular servers on Modrinth's server list that fit the instance's version (and loader, when
        /// the listing names one), most popular first. Never written anywhere. Throw when offline.
        func discoverServers(instanceID: String) async throws -> [ServerSummary]
        /// Server List Ping. Throw when it can't be reached; the row says so.
        func pingServer(address: String) async throws -> ServerPing
        /// Launches `instanceID` straight into `address`: Quick Play (`--quickPlayMultiplayer`) on 1.20+,
        /// `--server`/`--port` before. Same stream as `launch`.
        func joinServer(instanceID: String, address: String, accountID: String?)
            -> AsyncThrowingStream<LaunchProgress, Error>
        /// Appends a copy of the whole record (icon, `acceptTextures`, unknown tags) to `instanceID`'s servers.dat.
        func copyServer(_ server: ServerSummary, to instanceID: String) async throws -> ServerSummary
        /// Deletes it from `server.instanceID`'s servers.dat.
        func removeServer(_ server: ServerSummary) async throws
    }

    extension ServerService {
        public func discoverServers(instanceID: String) async throws -> [ServerSummary] {
            throw UnsupportedAction(name: "Recommended servers")
        }
        public func pingServer(address: String) async throws -> ServerPing {
            throw UnsupportedAction(name: "Server ping")
        }
        public func copyServer(_ server: ServerSummary, to instanceID: String) async throws -> ServerSummary {
            throw UnsupportedAction(name: "Copying servers")
        }
        public func removeServer(_ server: ServerSummary) async throws {
            throw UnsupportedAction(name: "Removing servers")
        }
    }

    extension ServerService where Self: LaunchControl {
        /// Default without Quick Play: a plain launch. The UI only offers it with `.quickPlay`.
        public func joinServer(instanceID: String, address: String, accountID: String?)
            -> AsyncThrowingStream<LaunchProgress, Error>
        {
            launch(instanceID: instanceID, accountID: accountID)
        }
    }

    /// Everything the UI needs from one object. The adapter writes one adapter around CofreBackendAdapter that conforms.
    public typealias CofreBackend = SetupService & LibraryService & ContentService & AccountService
        & LaunchControl & LogSource & InstanceActions & VersionCatalog & ProjectCatalog & InstallProgressSource
        & JITTester & SigningInfoSource & SystemCatalog & OptionalActions & ServerJoinSource
        & GameInputService & ServerService

    /// What the shell hands to `CofreUI.makeRootViewController(services:)`.
    public struct CofreServices {
        public var backend: any CofreBackend
        /// The directory containing Air's launcher_profiles.json. Production derives this from Air's profiles;
        /// previews and tests may provide a fixture folder.
        public var instances: InstanceStore?

        public init(backend: any CofreBackend, instances: InstanceStore? = nil) {
            self.backend = backend
            self.instances = instances
        }

        /// Sample data from the mockups, for previews, tests and the preview host.
        public static func mock(setupComplete: Bool = true) -> CofreServices {
            CofreServices(backend: MockBackend(setupComplete: setupComplete))
        }
    }
#endif
