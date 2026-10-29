# CofreUI

Cofre's whole UI as one SwiftUI package (iOS 17+). iPhone and iPad render the **same panes**; only the container
changes. Spec: `cofre-design/system/DESIGN_SYSTEM.md`. No Air, CofreBackendAdapter or ObjC imports.

**macOS 14 too, for the Mac pairing helper** (`tools/llave`). There, tokens resolve to `NSColor` (`PlatformColor`), fonts
skip Dynamic Type, and only tokens, fonts and components build. Screens, layout, store, facades, mocks, `NavChrome`,
`LogView` and the UIKit theme are wrapped in `#if canImport(UIKit)`. `PixelArt` draws larger art in the PixelIcon recipe.

| Part | Where | Count |
|---|---|---|
| Tokens (only hex values) · theme · fonts · UIKit theme | `Sources/CofreUI/Tokens/` | — |
| Components (§2, one file each) | `Sources/CofreUI/Components/` | 27 |
| Layout containers (§3.2) | `Sources/CofreUI/Layout/` | 7 |
| Screens: Setup S01–S08 · Play P01 · Launch P02 · Instances P03/I02/P04 · Mods M01–M04 · Settings X00–X07 + About | `Sources/CofreUI/Screens/` | 26 screen IDs |
| Join server sheet (GAP-14): join, needs you, key changed, installing, update, error, ready | `Sources/CofreUI/Screens/ServerJoin/` | 1 sheet, 7 states |
| Nav model + observable store | `Sources/CofreUI/Model/` | — |
| Service protocols · facade gaps · UI value types | `Sources/CofreUI/Facade/` | — |
| Mock backend (previews, tests, preview host) | `Sources/CofreUI/Mocks/` | — |
| Fonts (Pixelify Sans, Geist, Geist Mono, SIL OFL 1.1) + `OFL.txt` | `Sources/CofreUI/Resources/Fonts/` | 8 TTFs, 0.97 MB |

## Navigation

```
NAV = [Play, Instances, Mods, Settings]
compact (size class)            → bottom tab bar, NavigationStack push
regular, shell width < 1100 pt  → 76 pt rail, list + detail columns
regular, shell width ≥ 1100 pt  → 248 pt sidebar (+ pinned, JIT, account)
```

Layout reads `horizontalSizeClass` plus measured width (`WidthClass.resolve`), never the device. All selection lives
in `NavModel`, so resizing a Stage Manager window keeps it. ⌃⌘S toggles sidebar ↔ rail, ⌘1–⌘4 switch sections.
The size classes themselves come from the window size (`SizeClasses`: regular from 700 pt wide), not UIKit, because
Air forces every UIKit trait collection to regular. Sheets and covers reuse the root's values.

## Shell entry point (for the adapter)

`CofreRootViewController` (Air's SceneDelegate hook, patch 0002) embeds one hosting controller:

```swift
import CofreUI

public final class CofreRootViewController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        let services = CofreServices(backend: CofreBackendAdapter(/* AirBridge, TunnelService, JITService, PairingStore, SetupStatusStore */),
                                     airScreens: AirScreensAdapter())   // Glue; optional
        let ui = CofreUI.makeRootViewController(services: services)   // also registers fonts + UIKit theme
        addChild(ui)
        ui.view.frame = view.bounds
        ui.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(ui.view)
        ui.didMove(toParent: self)
    }
}
```

- Link the `CofreUI` product from this local package (`app/UI`) into Air's app target. SwiftPM embeds `CofreUI_CofreUI.bundle` (fonts, icon).
- Fonts register at runtime with `CTFontManagerRegisterFontsForURL(.process)`; Air's Info.plist is untouched.
- `CofreUI.bootstrap()` (called by `makeRootViewController`) applies `CofreUIKitTheme` once. Present every Air view controller inside `CofreAirHostController` so the scoped UIAppearance applies (CofreUI already does this for `AirScreens`).
- State restoration: save `nav.userActivity()` in `stateRestorationActivity`, restore with `nav.restore(from:)` and pass the `NavModel` to `makeRootViewController(services:nav:)`.

## What the adapter implements

One adapter conforming to `CofreBackend` (typealias in `Facade/Services.swift`), plus optional `AirScreens` in Glue.

| Protocol | File | Covers | Maps to |
|---|---|---|---|
| `SetupService` | Services.swift | S01–S08, X04 | `SetupStatusStore`, `PairingStore`, `TunnelService`, `JITService` |
| `LibraryService` | Services.swift | P01, P03, P04, I02, X01 | `AirBridge.instances/createInstance/installLoader/worlds/servers/preferences/setPreferences` |
| `ContentService` | Services.swift | M04, I02 | `AirBridge.mods/shaders/resourcePacks/toggleMod/deleteMod/updateMods` |
| `AccountService` | Services.swift | S07, X05 | `AirBridge.accounts/signInMicrosoft/removeAccount` |
| `LaunchControl` | Requirements.swift GAP-01 | P02 | new: progress stream + `cancelLaunch()` |
| `LogSource` | GAP-02 | P02, X06 | new |
| `InstanceActions` (+ `InstanceSummary` metadata) | GAP-03 | P03, I02 | new |
| `VersionCatalog` | GAP-04 | P04 | new |
| `ProjectCatalog` | GAP-05 | M01, M02 | replaces `searchModrinth/searchCurseForge` |
| `InstallProgressSource` | GAP-06 | M02, M03 | replaces `install(pack:)`, `importPack(_:)` |
| `JITTester` | GAP-07 | S06, X04 | new |
| `SigningInfoSource` | GAP-08 | S03, X06 | new |
| `SystemCatalog` | GAP-09 | X02, X04, X05 | new (CF key in Keychain) |
| `AirScreens` | GAP-10 | X03, P04 Forge/NeoForge | Glue, UIKit |
| `AirAppearance` | GAP-11 | all Air VCs | Air prefs + `AMEGlassStyleChanged` |
| `GamePreferences` extra keys | GAP-12 (addition) | X01–X07 | Air pref keys |
| `ServerJoinSource` + `ServerJoinViewModel` | GAP-14 (addition) | Join server sheet | `CofreServerJoin` view-models (see below) |

`MockBackend` implements all of it with the mockups' sample data and is the reference for expected values.

## Facade changes for the backend

All additive (2026-10-29). Every new member has a default, so `CofreBackendAdapter` compiles unchanged.

| Change | Where | Default | What the backend can do |
|---|---|---|---|
| `OptionalActions` added to `CofreBackend` (GAP-13) | Requirements.swift | Nothing supported; actions throw `UnsupportedAction` | Implement what works, then report it in `capabilities` |
| `capabilities: BackendCapabilities` | Requirements.swift | `[]`, which hides every control below | Turn on a flag only once its action works |
| `deleteWorld(instanceID:worldID:)` | Requirements.swift | throws | `.deleteWorld`: world context menu → Delete (always confirmed) |
| `backUpWorld(instanceID:worldID:) -> URL` | Requirements.swift | throws | `.backUpWorld`: zip URL for the share sheet |
| `addServer(instanceID:name:address:) -> ServerSummary` | Requirements.swift | throws | `.addServer`: "+ Add server" (native alert with two fields) |
| `createInstance(name:version:loader:ownFolder:fabricAPI:)` | Requirements.swift | Calls the 3-argument `createInstance` | `.createOptions`: shows the "Own folder" and "Add Fabric API" switches in P04 |
| `.envVariables`, `.rendererTuning` | Requirements.swift | hidden | Map `GamePreferences.envVariables`, `shaderCacheMB`, `multidraw`, `computeShaders` to Air prefs |
| `.controllerNavigation` | Requirements.swift | hidden | Turn on once `ControllerFocusBridge` drives the launcher; shows the A/B/Y hint strip |
| `.appIcon`, `.language`, `.lanRoom` | Requirements.swift | hidden | X07 rows; no handlers yet |
| `GamePreferences.autoRAM` now defaults to `true` | Models.swift | — | Pick a safe amount when it's on. The UI says "Cofre picks a safe amount automatically" |
| `GamePreferences.envVariables`, `shaderCacheMB`, `multidraw`, `computeShaders` | Models.swift | `[:]`, 512, "Auto", `true` | GAP-12 pref keys |
| `ProjectSummary.pageURL: URL?` | Models.swift | `nil` → `fallbackPageURL` (Modrinth project, CurseForge search) | The project's web page, used by M02 Share |
| `CofreStore(services:defaults:)` | CofreStore.swift | `.standard` | UI-only. Saves setup progress under `cofre.setup.completed` and `cofre.setup.step` |
| `ServerJoinSource` added to `CofreBackend` (GAP-14) | Requirements.swift | `serverJoin(_:)` returns `nil` | Return one live `ServerJoinViewModel` per server (types in `Facade/ServerJoin.swift`) |
| `.serverJoin` capability | Requirements.swift | off (on in `MockBackend`) | Turn on once `serverJoin(_:)` works. Shows "Modded" badges, Join buttons and `cofre://join` links |
| `ServerSummary.hasServerCard` | Models.swift | `false` | The server publishes a card: its row gets "Modded" and Join |
| `NavModel.serverJoin`, `NavModel.open(_ url:) -> Bool` | NavModel.swift | — | Shell: forward `scene(_:openURLContexts:)` to `nav.open(url)`; register the `cofre` URL scheme in Info.plist |

### Join server sheet (GAP-14)

`Facade/ServerJoin.swift` mirrors `launcher-plan/server-join/POPUP_CONTRACT.md` §2 field for field (same type and
field names, `Loader` and `CheckState` from Models.swift), so the adapter around `CofreServerJoin` is a mapping. In the
adapter file, use the facade types directly.

```swift
@MainActor protocol ServerJoinViewModel: AnyObject, Observable {
    var server: ServerSummary { get }   // header: name, address, detail "12/40 online", pingMS
    var state: ServerJoinState { get }  // .resolving · .requirements · .warnings(_, requirements:) · .installing · .updateAvailable · .error · .ready
    func send(_ action: ServerJoinAction)
}
```

| Action | Sent when | Backend does |
|---|---|---|
| `.setSelected(id:isSelected:)` | An optional mod, resource pack or shader switch | Update `isSelected`, recompute `totalDownloadSizeBytes` and `formattedDownloadSize` |
| `.install` / `.update` | "Install & Join" / "Update & Join" | Go to `.installing`. The UI never sends `.install` while blocked |
| `.resolveWarning(id:)` | "Get" on a CurseForge item (UI also opens `actionURL`), or "Trust new key" after the native alert | Set `isResolved` when the file arrives or the key is pinned |
| `.cancelInstall` | Cancel in `.installing` | Stop and keep the old profile |
| `.setAutoUpdate(_)` / `.setAutoConnect(_)` | The two switches | Update the state |
| `.retry` | `RecoveryAction.retry` | Resolve again |
| `.launch` | "Launch & Join" | Pass `--server`/`--port` on the next launch of `instanceID` if `autoConnectOnLaunch`. The UI starts the launch |
| `.dismiss` | The sheet closed | Nothing. Keep installing |

Additions to the contract (all defaulted): `requiredMods` and `trust: ServerJoinTrust?` (origin, key fingerprint,
pinned fingerprint, first use) on requirements; `isResolved` on `WarningItem`; `autoUpdate` on the update state;
`ServerJoinState`, `ServerJoinAction` and `ServerJoinRequest` (deep-link fields `server`, `card`, `pin`). `RecoveryAction`
is `Hashable`, because the contract's `Equatable` error state needs it.

Semantics the UI relies on:

- **Warnings.** Group by ID prefix: `warn.ios.incompatible_mod_dropped` → "Won't work on iPhone",
  `warn.curseforge.manual_download_needed` → "Download N mods yourself", the rest → "Before you join". Several items
  of one kind use `prefix:item` IDs. `blocking` and `security` items keep the one primary disabled ("1 left") until
  `isResolved`. `canProceedAnyway` waives `blocking` only, never `security`. An open item with no action shows "Blocked".
- **Key changed.** Send `warn.security.key_rotation_unverified` (no action: blocked, the UI tells the user to ask the
  owner) with `trust.pinnedKeyFingerprint` set. A signed rotation is another `security` item with
  `actionLabel: "Trust new key"`; the UI confirms in a native alert, then sends `.resolveWarning`.
- **First visit.** `trust.isFirstUse` shows the trust line: origin and the first 8 characters of the key.
- **Errors.** The sheet shows its own words for each `ErrorCode`. `title`, `message` and `.failed(String)` are never
  shown, so raw errors can't leak. Use them for logs.
- **Installing.** Stage titles are shown as is: use the player's words ("Fabric 1.21.1", "Mods", "Java 21"), with
  `detail` as the trailing meta ("17 / 24", "Already have").
- **Lifetime.** `serverJoin(_:)` is called when the sheet opens. The store keeps an installing model after the sheet
  closes (the server row shows its percent) and drops any other, so the next open reads the card again.

Layout: a system bottom sheet on compact, with a detent that hugs the content. On regular width it's a centered
560 pt card overlay instead of a system sheet, because iPad sheets size themselves once and can't follow content
that changes between states. The card is modal for VoiceOver, and Esc, the scrub gesture and a tap outside close it.

Semantics the UI now relies on:

- **Setup.** The first frame waits for `setupState()` only for users who never finished setup. Everyone else goes straight to the shell. After `finishSetup()`, the wizard never returns: a missing key (`pairing` `.failed`/`.blocked`) shows as a banner on Play. A `SetupState` where every check is ready at load skips the wizard.
- **Auto-advance.** When the current step's check turns `.ready` (through `setupUpdates()`, `importPairing`, `startVPN` or `testJIT`), the wizard moves to the next check that isn't ready. S06 starts `testJIT()` by itself. Report `devMode` and `trust` as soon as you can; `.unknown` shows "Checking".
- **JIT failures.** Throw from `testJIT()` while the failing `JITStep` is `.checking`, or yield it as `.failed`. The UI maps the step to a next step (pairing → run the Mac step, vpn → other VPNs, diskImage → Wi-Fi, debugger → Developer Mode).
- **Search errors.** Throw from `search(_:)` when offline; M01 shows "Can't reach Modrinth · Try again".
- **Links.** `CofreLinks.pairing` is `https://ignaciojuarez.github.io/cofre/pair/` (GitHub Pages from `docs/`). A test keeps every link on `CofreLinks.allowedHosts`.

## Build, test, preview

```sh
cd app/UI
xcodebuild -scheme CofreUI -destination 'generic/platform=iOS Simulator' build
xcodebuild test -scheme CofreUI -destination 'platform=iOS Simulator,id=<shared UDID>'   # 28 tests
# TEST_RUNNER_COFRE_SNAPSHOT_DIR=/tmp/join … keeps the Join sheet render-test PNGs (every state × compact, card, AX)
swift test                     # macOS: the 2 AppKit token and font tests

cd PreviewHost                 # regenerate with `xcodegen` after editing project.yml
xcodebuild -project CofrePreviewHost.xcodeproj -scheme CofrePreviewHost -destination 'generic/platform=iOS Simulator' build
xcrun simctl install <UDID> <DerivedData>/Build/Products/Debug-iphonesimulator/CofrePreviewHost.app
xcrun simctl launch <UDID> app.cofre.ui.previewhost -screen mods          # play|instances|mods|modpage|settings|jit|setup|launch
xcrun simctl launch <UDID> app.cofre.ui.previewhost -screen setup -setupStep 3 -type xl
xcrun simctl launch <UDID> app.cofre.ui.previewhost -screen play -canvas 1376x1032 -snapshot ipad13   # PNG in app Documents
xcrun simctl launch <UDID> app.cofre.ui.previewhost -screen join -joinState needsAttention   # firstVisit|keyChanged|installing|update|error|ready|resolving|live
xcrun simctl launch <UDID> app.cofre.ui.previewhost -screen join -joinURL 'cofre://join?server=mc.example.com'   # deep-link route
```

Use the shared simulators from `<local-volume>/Developer/kiwios/docs/simulators.md`. Never install on devices.
Screenshots: `cofre-design/system/screens/`; Join server sheet: `cofre-design/server-join/screens/`.

## Known gaps

- Menu-bar commands (`buildMenu` forward) and `ControllerFocusBridge` aren't built. Shortcuts are SwiftUI `keyboardShortcut`s.
- Controls with no working backend are hidden behind `BackendCapabilities` (see above). Worlds have no "+ New": worlds are made in game.
- Switch thumb animates linearly over 120 ms, not in 3 steps.
- Light theme passes contrast tests but has no screenshots yet.
