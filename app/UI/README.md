# CofreUI

Cofre's whole UI as one SwiftUI package (iOS 17+). iPhone and iPad render the **same panes**; only the container
changes. Spec: `cofre-design/system/DESIGN_SYSTEM.md`. No Air, CofreKit or ObjC imports.

| Part | Where | Count |
|---|---|---|
| Tokens (only hex values) · theme · fonts · UIKit theme | `Sources/CofreUI/Tokens/` | — |
| Components (§2, one file each) | `Sources/CofreUI/Components/` | 27 |
| Layout containers (§3.2) | `Sources/CofreUI/Layout/` | 7 |
| Screens: Setup S01–S08 · Play P01 · Launch P02 · Instances P03/I02/P04 · Mods M01–M04 · Settings X00–X07 + About | `Sources/CofreUI/Screens/` | 26 screen IDs |
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

## Shell entry point (for the logic agent)

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

## What the logic agent implements

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

`MockBackend` implements all of it with the mockups' sample data and is the reference for expected values.

## Build, test, preview

```sh
cd app/UI
xcodebuild -scheme CofreUI -destination 'generic/platform=iOS Simulator' build
xcodebuild test -scheme CofreUI -destination 'platform=iOS Simulator,id=<shared UDID>'   # 10 tests

cd PreviewHost                 # regenerate with `xcodegen` after editing project.yml
xcodebuild -project CofrePreviewHost.xcodeproj -scheme CofrePreviewHost -destination 'generic/platform=iOS Simulator' build
xcrun simctl install <UDID> <DerivedData>/Build/Products/Debug-iphonesimulator/CofrePreviewHost.app
xcrun simctl launch <UDID> app.cofre.ui.previewhost -screen mods          # play|instances|mods|modpage|settings|setup|launch
xcrun simctl launch <UDID> app.cofre.ui.previewhost -screen setup -setupStep 3 -type xl
xcrun simctl launch <UDID> app.cofre.ui.previewhost -screen play -canvas 1376x1032 -snapshot ipad13   # PNG in app Documents
```

Use the shared simulators from `<local-volume>/Developer/kiwios/docs/simulators.md`. Never install on devices.
Screenshots: `cofre-design/system/screens/`.

## Known gaps

- Menu-bar commands (`buildMenu` forward) and `ControllerFocusBridge` aren't built. Shortcuts are SwiftUI `keyboardShortcut`s.
- Some rows have no facade yet and are display-only: world back up / open folder, new world, add server, env variables,
  language, app icon, LAN room, MobileGlues shader cache / multidraw.
- Switch thumb animates linearly over 120 ms, not in 3 steps.
- Light theme passes contrast tests but has no screenshots yet.
