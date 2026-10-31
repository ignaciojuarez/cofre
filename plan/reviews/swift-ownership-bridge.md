# Swift ownership of the engine bridge: review

Scope: Air ↔ Cofre bridge only (`app/Glue/AirBridge/*`, `CofreStartup.m`, the CofreCore build/load path, patches 0001–0005).
UI/facade/model and input/JIT/VPN are covered by other reviewers. Read-only audit of the working tree on 2026-10-30
(it had uncommitted edits, so line numbers can drift). Confidence: **H** = read in code and checked, **M** = inferred from code, not run.

## Answer in one line

The layering is **about 2.5× bigger than it needs to be, but the ObjC shim itself is a real constraint**. Keep a thin
ObjC shim of about 450 lines inside Air's binary. Move everything that only uses Apple APIs or file I/O to Swift, delete the dead
and fallback-only paths, and don't import Air headers into Swift.

## Real constraints (checked)

| Constraint | Evidence | Real? |
|---|---|---|
| Air builds with gmake + CMake. Its only Swift is one file compiled by a custom `swiftc` rule, with no bridging header | `.work/air/Makefile:120-128`, `Natives/CMakeLists.txt:286-340` (AmeTabBar) | **Real (H).** Cofre's Swift packages need xcodebuild, so the Swift ships separately |
| CofreCore is built by a separate xcodegen project *after* Air, then `dlopen`ed | `scripts/run.sh:84-96`, `project.yml:25-61`, `CofreStartup.m:118-133` | **Real (H).** It also enables the ObjC fallback root when Swift fails to load (`CofreStartup.m:194-213`), which can't be written in Swift |
| The patches call C functions that must resolve when **Air** links | 13 hooks: `CofreMakeRootViewController`, `CofreEngineAlert`, `CofreReturnToLauncher` (0002); `CofreOwnsJIT`, `CofreLaunchFailed` (0003); `CofreHandleGameExit`, `CofreLaunchGameExited`, `CofreOwnsLaunchUI`, `CofreLaunchSurfaceAttached`, `CofreLaunchFirstFramePresented` (0004); `CofreShouldShowTextInput`, `CofreSDLTextInputStateChanged`, `CofreTextInputAreaDidChange` (0005) | **Real (H).** They must stay C in the Air binary, because CofreCore isn't loaded at link time |
| C11 atomics in Air headers | `JavaLauncher.h:50,61` (`atomic_int g_ame_headlessJvmFinished`, used at `AirBridgeAdapter.m:710`) | **Real (H).** Swift can't import `_Atomic` |
| ObjC runtime tricks | Metal `nextDrawable` swizzle (`AirBridgeAdapter.m:67-79`), SceneDelegate swizzle (`CofreStartup.m:49-74`) | **Real (H)** but small. Swift could do it with `@convention(c)` IMPs, which gains nothing |
| Air types not importable or ugly in Swift | `utils.h` is 628 lines and pulls in `jni.h` and `environ.h`. `PLProfiles.h`, `LauncherPreferences.h` and `BaseAuthenticator.h` have no `NS_ASSUME_NONNULL` | **Real friction (H).** Every Air type would import as an implicitly unwrapped optional (IUO) |
| Air symbols are exported (direct linking would be possible) | `nm -m` on `artifacts/Payload/Cofre.app`: `_OBJC_CLASS_$_PLProfiles`, `_getPrefObject`, `_amePCLVersionGameDirAbsolute` and others are `external`. `slim-app.sh` uses only `strip -S` | Possible, via `-undefined dynamic_lookup` or MH_BUNDLE + `-bundle_loader`. Not recommended (see "Don't") |
| GPL boundary | Root `LICENSE` is GPL-3.0, so Cofre and Air are one combined GPL work | **Not a constraint (H).** The dlopen split is about the build, not the license |
| Patch budget | 5/5 used (`patches/air/README.md`) | Real. The plan below adds **no** patches and keeps the 0001 file list unchanged |

So the protocol (`CofreAirBridging`) is needed: it is the runtime ABI between a binary that can't build Swift
packages and a framework that can't link to Air. What isn't needed is ~700 lines of Foundation, URLSession, Keychain and
file I/O logic, plus fallback paths that happen to sit on the ObjC side of that ABI.

## Piece-by-piece

`AirBridgeAdapter.m` (1,166 lines) grouped by feature, plus the other bridge files.

| Piece | Lines | What it does | Why ObjC today | Verdict | Effort | Risk |
|---|---|---|---|---|---|---|
| **Engine hooks** `AirBridgeAdapter.m:43-133` | 91 | C entry points the patches call; launch-phase atomics; engine-alert capture | **Real:** patches link to C symbols; atomics | **Keep** | — | — |
| **Surface/overlay + first frame** `:134-180`, `:67-79` | 60 | Builds `SurfaceViewController`, overlay window, Metal swizzle | **Real:** Air VC + IMP swizzle | **Keep** | — | — |
| **Version list bootstrap** `:182-214` | 33 | Fills Air's global `remoteVersionList` from Mojang/BMCLAPI | History. Air's download task reads the global (`MinecraftResourceDownloadTask.m:349,381`) | **Move to Swift:** fetch with `VersionManifest`; ObjC keeps a 3-line `setRemoteVersions:` | S | L |
| **init, selected, reload, jvmUsed** `:216-249` | 34 | `PLProfiles` handle, hides Air download popups | Real (Air objects) | **Keep** | — | — |
| **Instance summary/list** `:253-267`, `:324-331` | 23 | `launcher_profiles.json` → dicts | History. `InstanceStore.list()` reads the same file | **Delete:** callers use `InstanceStore` (`CofreBackendAdapter.swift:136,480`, `+Modpacks.swift:69,86`, `+Instances.swift:168`) | S | L |
| `gameDirectoryForProfile:` `:333-337` | 5 | `amePCLVersionGameDirAbsolute` | Real (Air resolver) | **Keep**, then **own** later (own-air #4) | M | M |
| **`CofreDownloadInstaller`** `:269-322` | 54 | Synchronous installer download | **Dead:** no callers (grep) | **Delete** | S | none |
| **Catalog URLs** `:339-361` | 23 | Mirror candidates, Fabric/Quilt profile URL, NeoForge versions | History. Downloads are forced to `official` at every start (`CofreStartup.m:190`) | **Own in Swift:** URL builders; NeoForge via `maven-metadata.xml` like Forge already does (`+Instances.swift:73-90`) | S | L |
| **create/duplicate/delete/export profile** `:385-434`, `:504-622` | 167 | Air-side instance operations | History. In production `CofreStore` uses `InstanceStore` whenever it exists (`CofreStore.swift:392,425,433,462`). These only run in the fallback and in `CofreScenarioRunner` | **Delete** (with Swift `+Instances.swift:94-123,199-227`) | S | L |
| **`saveLoaderProfile` + `persistInstanceProfiles`** `:363-383`, `:436-479` | 65 | Writes `versions/<id>/<id>.json` and the profile fields | History: plain file I/O | **Move to Swift:** an `InstanceStore.setLoader(...)` method. This makes CofreKit the single writer of `launcher_profiles.json` | M | M |
| **`installInstanceMod`** (Fabric API) `:481-501` | 21 | Air `ModService` download | History. Cofre already downloads mods itself | **Delete:** use `DownloadQueue` + `ContentStore` | S | L |
| **`installForgeLoader`** `:624-767` | 144 | Builds the Maven URL, downloads the installer, runs Air's processors, updates the profile | Partly real: `ForgeDirectInstaller`/`NeoForgeDirectInstaller` and the atomic reset | **Split:** Swift builds the URL and version ID (untested today, `:650-674`), downloads and writes the profile. ObjC keeps `runForgeInstaller:jar:versionID:gameDir:neo:` (~35 lines) | M | M |
| **Accounts** `:772-851` | 80 | `SecItemDelete`, `ASWebAuthenticationSession`, `MicrosoftAuthenticator` | Partly real: only `MicrosoftAuthenticator` and `BaseAuthenticator.current` are Air | **Move** the OAuth session, Keychain delete and anchor to Swift. ObjC keeps `completeMicrosoftSignInWithCode:` (~25 lines) | S | M (sign-in) |
| **Preferences** `:852-899` | 48 | Raw get/set, a profile-field map, the memory-default sentinel | Partly real (`getPrefObject`, `PLProfiles resolveKey`) | **Keep** raw get/set. **Delete** `CofreProfileFieldForPreference` (duplicate of `CofrePreferences.swift:36-45`; pass the field from Swift) and `ensureAutomaticMemoryDefault` (move to Swift; it's also called twice: `CofreStartup.m:183` and `CofreCoreEntry.swift:29`) | S | L |
| **`launchProfile`** `:901-975` | 75 | Account select, Air download task, 0.25 s `NSTimer` poll, JVM argument injection, surface | Real core (Air download task, surface) | **Keep the core**, split into `prepareVersion` and `startGame` (step 6) | M | M |
| **Renderer, resolution, language** `:976-1054` | 79 | Calls back into Swift through `objc_msgSend` for the renderer, writes prefs, edits `options.txt` | History. All of it is Swift policy or file edits, and none of it is tested | **Move to Swift** (RendererPolicy is already Swift; language → CofreKit `GameOptions`, Mac-tested) | M | M |
| `hideCofreLaunchOverlay` `:1055-1058` | 4 | Overlay dismissal | Real | **Keep** | — | — |
| **CurseForge search/versions** `:1059-1123` | 65 | Air `CurseForgeAPI` | History. **Unreachable:** `curseForgeKey()` returns nil and `setCurseForgeKey` throws (`CofreBackendAdapter.swift:497-498`), and no compiled key is set in `run.sh` | **Delete**, or own a Swift client with a Keychain key 🤔 | S | L |
| **`importPack`** `:1125-1146` | 22 | Air `ModpackImportService` (2,854 lines) | Real (Air importer, roadmap 7) | **Keep for now**, but fix the bugs below | S | M |
| **Input forwarding** `:1147-1164` | 18 | Protocol → `CofreInput*` C functions → static functions (3 hops) | History | Input reviewer's call. Collapse one hop | S | L |
| `AirBridgeAdapter.h` | 92 | Re-declares the whole protocol, with stale comments (`:52`, `:83-85`, `:90`) | Nothing | **Delete** down to `@interface … <CofreAirBridging> @end` (≈5 lines) | S | none |
| `CofreAirBridging.h` | 99 | Swift ↔ ObjC ABI (31 methods) | **Real** | **Keep**, shrinking to ~19 methods (13 plus 6 input). Fix the misplaced doc comments (`:46-47`, `:84`) | — | — |
| `CofreStartup.m` | 250 | Constructor, dlopen, fallback root, Scene swizzle, JIT prefs, exit hook | **Real** (fallback UI and C hooks can't be Swift) | **Keep.** Type the reverse calls (step 2). Optional: fold the URL hooks into patch 0002, which already edits `SceneDelegate.m`, and drop the swizzle (−26 lines) | S | L |
| `CofreCoreEntry.swift` | 49 | Swift entry class used by ObjC | Real (dlopen entry) | **Keep.** Delete `renderer(forProfile:)` after step 6 | S | L |
| `CofreGameExit.swift` | 79 | Crash and recovery screen | Already Swift | **Keep.** Use `InstanceStore` instead of `bridge.selectedProfileName/gameDirectory` | S | L |
| `CofrePreferences.swift` | 173 | Typed preference store | Already Swift | **Keep.** Delete the unused `subscript(safe:)` (`:171-173`) | S | none |
| `CofreScenarioRunner.swift` | 93 | Device test scenarios | Swift | **Fix:** create and delete through `InstanceStore` (`:36,39`). Today it tests Air's path, not the user's path | S | L |
| `CofreTunnelService.m`, `CofrePairingImport.m` | 79 | VPN start, pairing URL | History (`CofreVPN.swift` duplicates the manager lookup) | VPN reviewer's call. Both could be Swift in `CofreCoreEntry.start` | S | L |
| Patches 0001–0005 | 820 | Compile the glue; root, JIT, exit and text-input hooks | Real | **Keep all.** Keep the glue file names stable so 0001 doesn't churn | — | — |

## Bugs found on the way

| # | Finding | Evidence | Conf. |
|---|---|---|---|
| B1 | Settings › Download source never sticks: every app start writes `general.download_source=official` | `CofreStartup.m:190` vs `SettingsScreen.swift:282`, `CofrePreferences.swift:86,115` | H |
| B2 | `importPack:profile:` ignores `profile`. ServerJoin passes the server host as the instance ID, then reports `instanceID: request.id`, which doesn't exist. It also skips the rollback and loader check that `importWithAir` does | `AirBridgeAdapter.m:1125-1146`, `ServerJoinAdapter.swift:177-197`, `+Modpacks.swift:64-104`, `ServerJoin.swift:60` | H (param), M (user impact) |
| B3 | Device scenarios exercise Air's create and delete, not `InstanceStore`. Air's delete keeps folders, so `fresh` scenarios leak `cofre-instances/<uuid>` | `CofreScenarioRunner.swift:36,39`, `AirBridgeAdapter.m:579-580` | H |
| B4 | Two writers of `launcher_profiles.json` (Air `PLProfiles` through the bridge, and CofreKit). `InstanceStore.rename/update/remove/setMetadata` write from the cache without `loadProfiles()`, so they can revert Air's writes (renderer pick `:1009-1012`, loader `:750-760`, selected profile `:912`) | `Instances.swift:176-177,285-291,318-326` | M (CofreKit reviewer) |
| B5 | The exit code travels as the `double fraction` progress argument | `AirBridgeAdapter.m:80`, `CofreBackendAdapter.swift:322` | H (smell) |

## 1. Target architecture

```
 Air binary (CMake/gmake, GPL)                         CofreCore.framework (Swift 6, dlopen'd)
┌─────────────────────────────────────┐   ABI:        ┌──────────────────────────────────────────┐
│ Air: JVM · surface · renderers ·    │ CofreAir-     │ Engine (one final class, async/await,    │
│ SDL · Forge processors · MS auth ·  │ Bridging.h    │  typed enums) ← the only Air caller      │
│ download task · modpack importer    │ ≈19 methods   │        │                                 │
│        ▲                            │ ─────────────▶│ CofreKit: InstanceStore (single writer   │
│ CofreGlue/*.m  ≈450 lines           │               │  of launcher_profiles.json), Accounts,   │
│  • 13 C hooks the patches call      │ ◀──────────── │  Content, Modrinth, Downloads, Options   │
│  • surface/overlay/first frame      │ CofreCore-    │        │                                 │
│  • thin calls on Air objects only   │ EntryPoints   │ CofreUI feature models → screens         │
│    (no URLSession/Keychain/files)   │ (typed, no    └──────────────────────────────────────────┘
└─────────────────────────────────────┘  objc_msgSend)
```

Layers: **Air → ObjC shim → Engine → CofreKit/feature models**. That's one fewer than today (`CofreBackendAdapter` and the facade
protocols go away in roadmap 9), and the shim holds only code that has to be ObjC.

## 2. Migration steps (each step ships on its own)

| Step | What | Deletes | Test / device marker | Depends on |
|---|---|---|---|---|
| **0** | Dead-code sweep | `CofreDownloadInstaller` (54), duplicate declarations in `AirBridgeAdapter.h` (−87), stale comments, `subscript(safe:)`, the second `ensureAutomaticMemoryDefault` call | `scripts/test.sh` + device build; `[Cofre] AirBridge connected profiles=` | — |
| **1** | Preferences: fix B1 (one-time sentinel like the memory default). Move the memory, vsync and source defaults into `CofrePreferenceStore.applyDefaults()`. Swift passes the profile field | `CofreProfileFieldForPreference`, `ensureAutomaticMemoryDefault` (≈20 ObjC) | `CofrePreferencesTests`; set Source=Mirror, relaunch, check it persists; `[Cofre] memory auto default enabled` on a fresh install | — |
| **2** | Typed reverse calls: `@protocol CofreCoreEntryPoints` (class methods) in `CofreAirBridging.h`, adopted by `CofreCoreEntry`. Shared constants for `CofreOpenURL`/`CofreRootReady` | 5 `objc_msgSend`/`NSSelectorFromString` sites (`CofreStartup.m:181,204,229`, `AirBridgeAdapter.m:979-986`, `CofreGameInput.m:188-191`) | `[Cofre] UI root installed`, `[Cofre] game exit screen reason=` | — |
| **3** 🤔 | CurseForge: delete it, or own a Swift client with a user key | `searchProjects`/`projectVersions` (−65 ObjC), the `source == 2` branches in `+Mods.swift` (~40) | Mods search on device | UI reviewer (ModsScreen copy) |
| **4** | Instances: `InstanceStore` only. Scenario runner on `InstanceStore` (B3). Drop the `else backend.*` fallbacks in `CofreStore` | create/duplicate/delete/export (−167 ObjC, ~−55 Swift) and their facade methods | `InstancesTests`; `[Cofre] scenario … step=instance result=ok` | **Roadmap 9** (LibraryService slice); own-air #4 |
| **5** | Loaders in Swift: Fabric/Quilt JSON and NeoForge versions, mirror candidates, Fabric API through `DownloadQueue`, Forge URL, version ID, download and profile update. ObjC keeps `runForgeInstaller` | `saveLoaderProfile`, `persistInstanceProfiles`, `installInstanceMod`, catalog methods, most of `installForgeLoader` (≈−218 ObjC) | New Mac tests for the Forge/NeoForge URL and version-ID rules (`:650-674`); `[Cofre] loader installed … ok=1` | Step 4 (single writer); fixes B4 |
| **6** | Split launch into `prepareVersion` → Swift picks renderer, resolution and language (CofreKit `GameOptions`) and injects arguments → `startGame`. Swift fetches the manifest | `CofreLoadVersionList`, `pickRenderer`, `applyResolution`, `setGameLanguage`, `CofreCoreEntry.renderer` (≈−110 ObjC, −12 Swift). Typed exit event (B5) | Mac tests for the language rule and renderer; `[Cofre] renderer resolved`, `[Cofre] game lang:`, `[Cofre] first-frame source=` | Launch state machine (done `ff659d2`); step 5 |
| **7** | Accounts: `ASWebAuthenticationSession` + `SecItemDelete` in Swift; ObjC keeps `completeMicrosoftSignInWithCode:` | ≈−55 ObjC | `[Cofre] signed in demo=0`; remove account | Roadmap #2 accounts (done) |
| **8** | Modpacks: fix B2. ServerJoin goes through `importWithAir` (rollback, returns the real ID); pass `profile` or drop it | Duplicate import path in `ServerJoinAdapter.swift` | `[Cofre] pack import done instance=` from a server card | Roadmap 7 (owning the importer later) |
| **9** | Wrap the ~19-method ABI in one Swift `Engine`; dissolve `CofreBackendAdapter` | Adapter and facade (roadmap 9's count) | Roadmap 9 markers | **This is roadmap 9.** Doing steps 0–8 first means it dissolves a much smaller adapter |

Order: 0, 1, 2 can run in parallel. 4 → 5 → 6. 7 and 8 are independent. Keep `AirBridgeAdapter.m` and the other glue file names, so patch 0001 never changes.

## 3. Stringly-typed spots → enums or constants

| What | Where | Make it |
|---|---|---|
| Loader strings in ObjC | `AirBridgeAdapter.m:261` (`@"vanilla"`), `:350` (`@"quilt"`), `:643` (`@"neoforge"`); `loader:(NSString*)` in `CofreAirBridging.h:21,29,38` | Gone after steps 4–5 (Swift `Loader`). Until then, `NS_ENUM` |
| `cofreRequestedLoader` key twice | `AirBridgeAdapter.m:46` vs `Instances.swift:23` | Only `Instance.Loader.requestedProfileKey` (after step 5) |
| Instance summary dict keys parsed twice | `AirBridgeAdapter.m:259-266`; `CofreBackendAdapter.swift:136-147` and `+Instances.swift:114-123` (same `Loader(rawValue: … ?? "vanilla")`) | Delete (step 4); `InstanceStore.list()` |
| API source `1`/`2` | `AirBridgeAdapter.m:1062-1083`; `+Mods.swift:9,34,103-106,127,144-156` | Existing `ProjectSource` (`ProjectFilters.swift:11`) |
| Mirror resource `0`/`3` | `+Instances.swift:40,61` (Air's `PLMirrorResourceType`, `PLMirrorCenter.h:6-15`) | Gone after step 5 |
| Launch finish reasons `"inGame"`, `"failed"`, `"failed reason=launchTimeout"` | `CofreBackendAdapter.swift:248-333` | An enum (or reuse the launch state machine's) |
| Exit code passed as `fraction` | `AirBridgeAdapter.m:80`, `CofreBackendAdapter.swift:322` | Its own `code` parameter or event payload |
| Export format `"zip"`/`"mrpack"` | `AirBridgeAdapter.m:595,611` | Gone after step 4 (Swift `ExportFormat`) |
| Air pref keys outside `CofrePreferenceStore.Key` | `AirBridgeAdapter.m:139,191,209,666,855-857,985,1027-1029`; `CofreStartup.m:144-145,188,190`; `CofreGameInput.m:172` (`video.performance_hud` = `Key.fpsOverlay`) | Add them to `Key` (e.g. `selectedAccount`, `fsr1`, `disableGameVSync`) and set them from Swift |
| Download source values `"bmclapi"`/`"official"` | `AirBridgeAdapter.m:191,666`; `CofreStartup.m:190`; `CofrePreferences.swift:86,115` | `DownloadSource` raw values in one place |
| Cofre `UserDefaults` keys spread over files | `cofre.render.scale` (`AirBridgeAdapter.m:1026`, `CofrePreferences.swift:49`); `cofre.options.before.<id>` (`CofreBackendAdapter.swift:235`, `CofreGameExit.swift:28`); `cofre.launch.started.<id>` (`CofreBackendAdapter.swift:233`, `CofreGameExit.swift:58`); `cofre.setup.jit` (`CofreBackendAdapter.swift:68,96,427`, `CofrePreferences.swift:131`); `cofre.server-card.<host>` (`+Servers.swift:22`, `ServerJoinAdapter.swift:193`); `cofre.mods.identities` (`+Mods.swift:71,390`) | One `enum CofreDefaultsKey` |
| Notification names | `CofreOpenURL` (`CofreStartup.m:23`, `CofreRootViewController.swift:49`); `CofreRootReady` (`CofreStartup.m:239`, `CofreRootViewController.swift:53`) | `FOUNDATION_EXPORT NSNotificationName const` in `CofreAirBridging.h` |
| Selectors as strings | `CofreStartup.m:181,204,229`; `AirBridgeAdapter.m:979-980`; `CofreGameInput.m:188-189` | `CofreCoreEntryPoints` protocol (step 2) |
| Default renderer dylib twice | `AirBridgeAdapter.m:991` vs `CofreBackendAdapter.swift:455` | `RendererPolicy` returns a concrete dylib (step 6) |

## 4. What I would NOT do

| Don't | Why |
|---|---|
| Import Air headers into Swift (bridging header or module map) and delete the shim | It needs `-undefined dynamic_lookup` or an MH_BUNDLE + `-bundle_loader` link against `.work/air` output. Every Air type imports as an IUO (no nullability), `utils.h` drags in JNI, atomics don't import, and CofreCore and its tests would stop compiling without a built Air. The ~450 lines left after this plan would be about as long in Swift with IUOs. Revisit only if Air ships nullability and module maps |
| Compile Cofre Swift into Air's binary through Air's `swiftc` rule | That rule compiles one file with no ObjC import (AmeTabBar). Extending it grows patch 0001's CMake, and you'd *still* need a protocol to reach CofreCore. No layer removed |
| Reach Air from Swift with `NSClassFromString` + `perform(_:)` or `dlsym` on Air symbols | Stringly typed and unchecked; Air header drift would fail silently at runtime on device |
| Remove the dlopen split | It's what makes the ObjC fallback screen possible, and Air can't build SwiftPM |
| Rewrite hooks, surface, swizzle or atomics in Swift | Patches resolve C symbols when Air links. That code is engine boundary (`own-air.md` "Hard boundary") |
| Own Microsoft auth, `MinecraftResourceDownloadTask`, Forge processors or `ModpackImportService` now | L/high risk per `own-air.md` #7, #8 and "below top eight". Only their thin wrappers move |
| Add ObjC value classes to type the protocol | Boilerplate. Move the logic to Swift so only primitives cross |
| Merge `CofreConstants.h`/`.swift` | 3 values each, used by two targets with different bridging headers |
| Add a patch | 5/5. Step 2's optional `SceneDelegate` URL hook goes into existing 0002 |

## Report: top 5 recommendations

1. **Delete about 290 lines of dead or fallback-only ObjC** (steps 0, 3, 4): `CofreDownloadInstaller`, Air create/duplicate/delete/export, unreachable CurseForge, and the duplicate `AirBridgeAdapter.h`. Point the scenario runner at `InstanceStore`, so device tests cover the user's path (B3).
2. **Make CofreKit the single writer of `launcher_profiles.json`** and move loader install to Swift (step 5). ObjC keeps only `runForgeInstaller`. This removes the dual-writer risk (B4) and puts the Forge URL and version-ID rules under Mac tests.
3. **Split launch into prepare and start** (step 6), so the renderer, resolution and language decisions are Swift and Mac-tested. This deletes the `objc_msgSend` callback into Swift.
4. **Fix the two bridge bugs now:** the download source gets overwritten at every start (B1), and `importPack` ignores `profile` while ServerJoin skips the rollback (B2).
5. **Keep a thin ObjC shim; don't import Air headers into Swift.** Type both directions (`CofreCoreEntryPoints`, constant notification names, typed exit code). Then roadmap 9 wraps the ~19-method ABI in one Swift `Engine`.

**Estimated lines removed (bridge scope, excluding roadmap 9's adapter and facade):** about **−775 ObjC**
(`AirBridgeAdapter.{h,m}` 1,258 → ~480; `CofreAirBridging.h` 31 → ~19 methods) and about −130 Swift, with about +300 Swift
moved over and tested. **Net about −600 lines**, with every remaining ObjC line one that only ObjC/C can do.
