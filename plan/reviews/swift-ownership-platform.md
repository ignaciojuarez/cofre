# Swift ownership / platform audit

**Scope:** game input, touch overlay, JIT/VPN, pairing, constants, shell, Llave, server-card, and build/signing. Air bridge/UI facade are out of scope. **Confidence:** H = direct code/test evidence; M = design inference. Audited the working tree on 2026-10-30.

## Verdict

The mix is justified at the Air binary boundary. Air is built by CMake/gmake, while Swift ships in a separately signed `dlopen`'d `CofreCore.framework`; patch 0001 must link C/ObjC symbols into Air. The platform code is still over-layered around that seam. A safe first pass removes about **150 lines** and makes JIT/pairing contracts typed. A larger Swift rewrite of Air callbacks would increase risk without removing a boundary.

## Piece-by-piece

| Piece | Lines | Why not Swift today (real constraint vs history) | Verdict | Effort | Risk | Lines removed |
|---|---:|---|---|:---:|---|---:|
| `CofreGameInput.m/.h` | 233 | **Real:** patch/Air calls C callbacks; uses Air `SurfaceViewController`, `glfw_keycodes.h`, JNI-adjacent preferences. Swift cannot link those headers through `CofreCore`. | **keep** as a thin Air seam; harden failure path | S | M | 0 |
| `CofreGameInput.swift` | 195 | No platform blocker; it already owns input policy and async state. | **own/keep**; add `@MainActor` isolation and typed preference | S | M | 0 |
| Touch overlay (`Screens/Game/*`) | ~1,953 | Pure SwiftUI/UIKit policy with 27 focused tests. No reason to port or split it. | **own/keep** | — | Low | 0 |
| Patch 0005 text-input policy | 97 | **Real today:** Air calls C policy hooks at link time. It can disappear only when Air exposes a supported text-focus callback. | **keep** until upstream hook exists | M | H | 0 (−97 later) |
| `CofreJIT.swift` + `PacketTunnelProvider.swift` + `LoopbackTunnel.swift` | 237 | Separate app/appex process is real; hand-built JSON and string step values are history. | **own/streamline** with one `Codable` message and enum | M | M | 15–20 |
| `CofreTXM.js` | 121 | **Real:** StikJIT debugger/TXM protocol is JavaScript; Swift cannot replace the injected script without changing the protocol. | **keep** | — | H | 0 |
| Patch 0003 JIT hooks | 87 | **Real:** Air must resolve `CofreOwnsJIT`/launch-failure C hooks. | **keep** until Air provider hook | M | H | 0 |
| `CofreVPN.swift` + `CofreTunnelService.m/.h` | 100 | VPN manager lookup/start is Foundation/NetworkExtension and already duplicated in Swift. ObjC is legacy glue, not Air data. | **move to Swift**; delete ObjC service after Core startup owns it | M | M | 47 |
| `CofrePairingImport.m` | 41 | URL handoff was put in the constructor before Swift is loaded; that is history once startup queues a typed URL. | **move to Swift**; keep a typed pending-URL handoff in startup | M | M | 41 |
| `PairingFileValidator.swift` + `ProvisioningProfile.swift` | 96 | Already Swift and the validator is the single useful ownership point. | **own**; add bounded schema and required RP keys | S | M | 5–10 |
| `CofreConstants.h` + `.swift` | 13 | Header is consumed by Air/ObjC; Swift copy is consumed by Core/appex. Different target boundaries are real. | **keep**; generate/check drift instead of merging blindly | S | Low | 0 |
| `CofreRootViewController.swift` | 57 | UIKit host is the root installed by patch 0002 and must exist even when Core fails to load. | **keep** | — | Low | 0 |
| Llave Rust core (`core/src`) | ~756 | **Real:** idevice/lockdown/usbmuxd/house_arrest/AFC has no comparable native Swift API. | **keep split**; type wire events and cancellation | M | M | 0 |
| Llave Swift app/tests | ~1,372 | SwiftUI/state machine is the right owner; a little event/error string plumbing is redundant. | **own/streamline** | S | Low | ~10 |
| `tools/server-card` | 92 | Swift + CryptoKit is already the smallest native implementation. | **keep**; reuse `CardEnvelope`/base64 helper | S | Low | ~20 |
| `scripts/*` + signing `project.yml` | ~449 | Shell/Python/XcodeGen are reasonable build tools; duplicate xcodebuild and split config are history. | **streamline** | S | M | 8–10 |

**Net safe deletion estimate:** ~150 lines, excluding code moved to Swift and the deferred 0005 deletion. Larger future reductions depend on the separate Air-bridge/UI ownership plans.

## Target structure

```text
Air executable (CMake/gmake)
  Air JVM/render/input/surface + only CofreGlue C/ObjC hooks
             │ small typed ABI (patch hooks + entry points)
             ▼
CofreCore.framework (Swift)
  Engine: launch/input/JIT/VPN/pairing URL ownership
  CofreKit: bounded pairing store, typed JIT contract, file state
  CofreUI: TouchOverlay + feature models
             │ Codable JITMessage over the tunnel boundary
             ▼
PacketTunnel.appex (Swift loopback + StikJIT + CofreTXM.js)

Llave.app: SwiftUI state/UI ── typed event wire ── Rust idevice transport
server-card: Swift/CryptoKit CLI
```

The ObjC/C layer should contain only symbols that Air calls before/without Core: patch hooks, Air callbacks, surface/overlay fallback, and scene/root startup. It should not own URLSession, file validation, VPN manager policy, or pairing URL parsing.

## Ordered shippable migration

| Step | Change | Verification / device marker |
|---:|---|---|
| 1 | Add shared `Codable` JIT request/reply and `JITStep.Kind`; replace JSON/string switches. Fix the missing `checkDiskBeforeLaunch` test harness helper. | `node tests/jit/*.test.js` (currently launch test fails to compile); `swift test` UI; TXM/detach tests remain green. |
| 2 | Make RemotePairing mandatory on iOS ≥17.4; bound input plist and every blob; return structured validation errors. | Rust simulation + validator fixtures; device log `[Cofre] pairing imported`; JIT test must report an explicit success/failure step. |
| 3 | Move VPN start/manager selection from `CofreTunnelService.m` into `CofreVPN.swift`; delete the ObjC service/header. | Device marker `[Cofre] tunnel up 10.7.0.1 interface=…`; verify stop/reset updates state. |
| 4 | Queue open URLs in startup and let Swift import pairing; delete `CofrePairingImport.m`. | Cold-launch Files URL test; device marker `[Cofre] pairing imported`. |
| 5 | Keep C key-name/GLFW mapping, but add a mapping test and install Swift touch overlay before hiding Air controls; restore Air controls if installation fails. | Mapping/UI tests; device markers `[Cofre] touch overlay installed` and `[Cofre] touch overlay ready style=…`. |
| 6 | Collapse signing build to one XcodeGen/project generation and one `xcodebuild`; pass validated bundle IDs from `run.config`; retain the build lock. | `scripts/test.sh`, `scripts/smoke.sh`, no-install build; device markers `[Cofre] UI root installed`, `[Cofre] tunnel up …`. |
| 7 | Add typed Llave event/error codes and terminate/wait the Rust child on Swift task cancellation. | `cargo test --offline`; Llave Swift tests; pairing flow reaches placement without secrets in logs. |
| 8 | Reuse the server-card envelope/base64 helper and add a constants/identifier drift check for header, Swift, shell, and appex targets. | `swift build` server-card; `scripts/smoke.sh`. |

## Stringly-typed spots to replace

| Location | Current value | Replacement |
|---|---|---|
| `app/Glue/AirBridge/CofreGameInput.swift:22-25` | UserDefaults key and raw `"auto"` | `InputModePreference` + `CofreDefaultsKey.inputMode` |
| `app/Glue/AirBridge/CofreGameInput.m:22-55` | key names `"W"`, `"SPACE"`, `"F1"`, etc. | keep the C callback, but define one `CofreInputKey`/mapping table and test every supported name |
| `app/UI/Sources/CofreUI/Screens/Game/QuickTray.swift:22-62`; `TouchOverlay.swift:179,191,195,200-203` | action IDs `"keyboard"`, `"edit"`, `"pause"`, `"hud"`, `"empty-*"` | `QuickTrayActionID` with a custom empty-slot case |
| `app/Glue/AirBridge/CofreGameInput.m:127-136` | dictionary keys `inWorld`, `guiScale`, `pixelsPerPoint` | one C struct/typed boundary |
| `app/Glue/CofreJIT.swift:7-8,41-55`; `extensions/PacketTunnel/PacketTunnelProvider.swift:40-87` | JSON keys, `state`, and `step` strings | shared `Codable JITMessage`, `JITStep.Kind` |
| `app/Glue/PairingFileValidator.swift:13-35` | plist key strings | `PairingKey` schema enum and size policy |
| `tools/llave/App/Sources/Models/LlaveEvent.swift:14-47`; `LlaveModel.swift:128-133`; `tools/llave/core/src/pair.rs:125-342` | event/error code strings | shared documented wire enum/constants |
| `tools/server-card/Sources/server-card/main.swift:47,68` | CLI/format/key-ID strings | command enum and `ServerCardFormat` |
| `scripts/run.sh:45-54`; `scripts/run.config:2-6`; `scripts/sign-development.py:19-22` | bundle IDs/options from multiple sources | one validated build configuration |
| `app/Shell/CofreRootViewController.swift:9` | `"com.cofre.downloads"` | shared notification/identifier constant |
| `app/Glue/AirBridge/CofreGameInput.m:171-187` | Air preference literals | typed `CofrePreferences.Key` constants |

## Bugs found

| ID | Finding | Evidence | Confidence |
|---|---|---|:---:|
| B1 | **RemotePairing failure is downgraded to a warning.** Llave continues with legacy keys, while the phone validator defaults `requireRemotePairing` to false; the UI can say ready and StikJIT fails later. | `tools/llave/core/src/pair.rs:211-269`; `app/Glue/PairingFileValidator.swift:18,31`; `CofreBackendAdapter.swift:113-117` | H |
| B2 | **Touch fallback can hide Air controls without a Swift overlay.** It hides `ctrlView`/`gameMenuOverlay` before `touchOverlay` lookup; a failed lookup returns after logging that Air touch remains active. | `app/Glue/AirBridge/CofreGameInput.m:169-194` | H |
| B3 | **JIT launch test does not compile.** `launch.test.js` calls `Harness.checkDiskBeforeLaunch`, but the generated harness has no such member. | `tests/jit/launch.test.js:20-26,105-117`; current `node tests/jit/launch.test.js` | H |
| B4 | **Pairing import reads an unbounded file.** `CofrePairingImport.m` loads the whole URL before validation; top-level plist size and optional remote blobs are not bounded in all paths. | `app/Glue/AirBridge/CofrePairingImport.m:11`; `PairingFileValidator.swift:18-37` | H |
| B5 | **Llave cancellation leaves the child process running.** `Task.detached` waits on `Process`, but outer model reset/disconnect cancellation does not terminate and reap it. | `tools/llave/App/Sources/Services/PairingService.swift:14-75` | H |
| B6 | **VPN state can become stale.** `isVPNRunning` is set true after start and is not reset when the tunnel stops or is externally removed. | `app/Glue/AirBridge/CofreBackendAdapter.swift:122-127` | M |
| B7 | **Signing configuration is partly ignored and the build is duplicated.** `project.yml` includes the same targets that `run.sh` builds again; `run.sh` does not export `BUNDLE_ID`/`TUNNEL_BUNDLE_ID`, so local overrides in `run.config` can be ignored by `sign-development.py`. | `.build-tools/signing/project.yml:105-111`; `scripts/run.sh:91-108`; `scripts/run.config:2-6`; `scripts/sign-development.py:19-22` | H |

## What I would not change

- Do not import Air headers into Swift or compile CofreUI into Air. JNI/atomics, missing nullability, separate CMake/xcodebuild products, and the fallback root make that boundary real.
- Do not rewrite GLFW/key mapping, surface/overlay host, C11 atomics, startup fallback, or patch 0005 until Air supplies equivalent hooks.
- Do not port idevice/lockdown/house_arrest/AFC from Rust to Swift; keep Rust transport and type the wire boundary.
- Do not rewrite `CofreTXM.js` in Swift; it is the StikJIT debugger protocol implementation.
- Do not remove `CofreRootViewController`; it is the UIKit fallback/root host.
- Do not add a sixth Air patch; the budget is 5/5.
- Do not hand-merge `CofreConstants.h` and `.swift`; they serve different targets. Generate or test them against one source of truth.
- Do not replace tested touch overlay rules with a new protocol or service layer; the current Swift model is already the simplest owned implementation.

## REPORT

- **Top 5 recommendations:**
  1. Make JIT messages/steps and pairing keys typed and bounded; fix the failing launch harness.
  2. Make RemotePairing mandatory on supported iOS and fail pairing early.
  3. Move VPN start and pairing URL import into Swift; delete the two legacy ObjC files.
  4. Fix touch-overlay installation ordering and add key-name→GLFW mapping tests.
  5. Collapse duplicate signing builds/config and add identifier drift checks.
- **Bugs found:** 7 (B1–B7), 5 high-confidence.
- **Estimated lines removed:** **~150 safe now**; another **~97** when Air gains a text-input hook and patch 0005 can be dropped.
