# Cofre readability and AI-maintainability review

Read-only audit, 2026-10-29, at `a6854ca`. Line numbers refer to that commit. Goal: a fresh agent can understand, change, build, test and update Cofre safely.
Overlaps with `logic-review.md` are noted, not repeated.

## Checks run

| Check | Result |
|---|---|
| `swift test` in `app/CofreKit/ServerJoin` | ✅ 27 tests, 0 failures |
| CofreUI `xcodebuild test` on shared sim `0A1B03AF…` (reused, not erased) | ✅ 28 of 28 passed |
| `cargo test --offline` in `tools/llave/core` | ✅ 1 test |
| `node tests/jit/txm.test.js` | ✅ |
| `python3 plan/server-join/validate_examples.py` | ✅ valid pass, malicious fail |
| `scripts/smoke.sh` | ✅ (but it checks for the dead `CofreKit.swift`, see H4) |
| `scripts/test-pairing-validation.swift` (concatenated with the validator, built in `/tmp`) | ❌ **fails**: the "valid" fixture lacks `RootPrivateKey` |
| `xcrun swift-format lint -r app/UI/Sources` | 8,301 findings (CofreUI was skipped by the format commit) |
| Built Air tree `.work/air/Natives/build` | Only the 5 Cofre `.m` files have `.o` files. No Cofre Swift is compiled (H2) |

---

## High impact

### H1. 56 MB of Xcode DerivedData is committed and grows with every build
- **Where:** `.build-tools/signing/build/` (1,379 tracked files: `Index.noindex`, `Build/Intermediates`, `ModuleCache.noindex`, `.o`, `.swiftmodule`). Commit `b3ead5a` re-committed about 60 build products. Pack size is 77 MiB.
- **Problem:** every `scripts/run.sh --build` dirties the tree. Diffs and reviews fill with binaries, and agents may "fix" or stage them.
- **Change:**
  - `git rm -r --cached .build-tools/signing/build`
  - Add `.build-tools/signing/build/` and `*.xcodeproj/xcuserdata/` to `.gitignore`.
  - Delete the empty leftover dirs `.build-tools/signing/CofreSigning.bad3`…`bad8` on disk.
  - Rename `.build-tools/signing/` → `signing/` (visible) and add a 3-line README: *stub app plus PacketTunnel appex. It exists only to get provisioning profiles and build `PacketTunnel.appex`. `run.sh:70-77` uses it.* Today the only build definition of the VPN extension is hidden in a dot-folder.

### H2. None of the Swift layer reaches the app, and nothing says so
- **Where:**
  - `scripts/run.sh:22-31` copies `CofreBackendAdapter.swift`, `ServerJoinAdapter.swift`, `CofreRootViewController.swift` and `CofreServerJoin/*.swift` into `.work/air/Natives/CofreGlue/`.
  - `run.sh:37` adds only the 5 `.m` files to CMake.
  - Air's `CMakeLists.txt` compiles exactly one Swift file (`AmeTabBar.swift`, line 304).
  - CofreUI is never linked.
  - `app/CofreKit/CofreJIT.swift`, which `CofreBackendAdapter.swift:278` calls, isn't even copied.
- **Problem:** `CofreRootFactory.m:3-5` gets `nil` from `NSClassFromString`, and patch 0002 silently keeps Air's UI. Commit titles like "Wire server join through the production backend" make a fresh agent believe the adapter ships and is tested.
- **Change:**
  - Add one swiftc rule for `CofreGlue/**/*.swift` plus CofreUI, modelled on Air's AME_TABBAR rule. Put it in patch 0001, which is malformed anyway (M4).
  - Until that lands, put a **Status** line in `AGENTS.md`: "Swift glue is not compiled yet".
  - Make `CofreRootFactory.m` log `[Cofre] CofreRootViewController missing, falling back to Air UI` when `cls == nil`.

### H3. Three pairing validators and four pairing writers
| What | Where | State |
|---|---|---|
| Validator 1 | `app/CofreKit/PairingFileValidator.swift:12-39` | Not compiled into the app. Its test file `PairingFileValidatorTests.swift` belongs to no package, so it never runs. `scripts/test-pairing-validation.swift` fails |
| Validator 2 | `app/Glue/AirBridge/CofrePairingImport.m:5-12` | The only one that ships |
| Validator 3 | `CofreBackendAdapter.swift:76-85` (`hasPairing`) | Weaker re-implementation: no size or UDID checks |
| Writer A | `CofrePairingImport.m:13-23` (URL open) | Validated, temp file, then `replaceItemAtURL` |
| Writer B | `CofreBackendAdapter.swift:86-94` (UI drop zone) | **No validation**. Overwrites a good key with any bytes |
| Writer C | `app/CofreKit/Services.swift:3-15` `FilePairingStore` → `pairing.bin` | Dead: different file name and folder |
| Writer D | `tools/llave/core/src/pair.rs:252-280` (AFC) | Separate machine, OK |
- **Change:**
  - Keep **one** validator plus one writer: `PairingFileValidator.swift` and a Swift port of writer A, once H2 compiles Swift. Until then, keep the ObjC one.
  - Route `importPairing(_:)` through it.
  - Delete `FilePairingStore`, the `hasPairing` body (call the validator), and `scripts/test-pairing-validation.swift`.
  - Move `PairingFileValidatorTests.swift` into a real test target (see H4) and fix its fixture.

### H4. `app/CofreKit` is mostly dead, and every facade comment points at it
- **Where:**
  - `app/CofreKit/CofreKit.swift` (107 lines: `AirBridge` protocol, `CofreInstance`/`CofreWorld`/…, `SetupStatusStore`, `TunnelService`/`JITService`/`PairingStore`) has **zero** code references.
  - `Services.swift` is unused.
  - Comments that still "map to" it:
    - `app/UI/Sources/CofreUI/Facade/Services.swift`: lines 7-8, 10-27, 31, 43, 51, 58
    - `Requirements.swift`: lines 5-8, 12, 43, 171
    - `Models.swift:4`
    - `design/DESIGN_SYSTEM.md:4`
  - `scripts/smoke.sh:6` requires `CofreKit.swift` to exist.
- **Problem:** a fresh agent will extend the wrong layer. The real implementer is `app/Glue/AirBridge/CofreBackendAdapter.swift`.
- **Change:**
  - Delete `CofreKit.swift` and `Services.swift`.
  - Move `CofreJIT.swift` to `app/Glue/` (it imports UIKit and NetworkExtension, so it isn't "UI-agnostic").
  - Move `app/CofreKit/ServerJoin/` → `app/ServerJoin/`, so the folder matches its only module.
  - Point `smoke.sh:6` at `CofreBackendAdapter.swift`.
  - Rewrite those comments as "Implemented by `CofreBackendAdapter`". Drop the "logic agent" and "GAP-xx vs CofreKit" framing (`app/UI/README.md:34,61`).

### H5. Duplicate server-join model types cause the documented naming clash
- **Where:** `app/CofreKit/ServerJoin/Sources/CofreServerJoin/ViewModels.swift:1-123` redefines 11 CofreUI facade types: `SelectableContentItem`, `CheckState`, `ServerJoinRequirementsState`, `ServerJoinWarningState`, `InstallStage`, `ServerJoinInstallingState`, `ModUpdateSummary`, `ServerJoinUpdateState`, `RecoveryAction`, `ServerJoinErrorState`, `ServerJoinReadyState`.
  - `Card.swift:24` adds a 12th clash: `Loader`.
  - Their only users are 3 "names compile" tests (`ServerJoinTests.swift:116-129`).
  - The adapter (`ServerJoinAdapter.swift`) uses the `CofreUI.` versions exclusively. That's why `app/UI/README.md:115` tells agents to qualify names.
- **Change:**
  - Delete `ViewModels.swift` and the 3 tests.
  - Rename `CofreServerJoin.Loader` → `CardLoader`.
  - Remove every `CofreUI.` qualifier in `ServerJoinAdapter.swift`.
  - Delete the "qualify the clashing names" sentence in `app/UI/README.md`.
  - Rule: domain types (card, envelope, plan, trust) live in CofreServerJoin, UI state lives in CofreUI, and the adapter maps between them.

### H6. `UPDATING.md` documents a pipeline the script doesn't have (and the script breaks on macOS)
- **Where:**
  - `UPDATING.md:19-55` promises exit codes 3/4/5, `--export-patches`, `.work/CONFLICT.md`, `.work/build.log`, `.work/smoke.log`, `.work/WATCH-<name>.txt`, a LICENSE check, branch `upstream/YYYYMMDD` and `scripts/add-friend.sh` (line 82).
  - `scripts/update-upstream.sh` is 20 lines and does none of that. It never builds, never runs `smoke.sh`, never reads `scripts/watch/*.txt`.
  - Line 17 uses `strftime`, which macOS awk lacks (`awk: calling undefined function strftime`), so every real, non-dry update dies after fetching.
  - Line 14's trap removes `.work/<name>`, while `run.sh` builds from `.work/air` and re-applies patch 0002 by hand (`run.sh:20`).
  - This is logic-review #10, still open, plus the new awk bug.
- **Change:**
  - Fix line 17: `-v d="$(date +%F)" … $8=d`.
  - Either cut `UPDATING.md` to what the script does, or grow the script. Choose one and say which in `AGENTS.md`.
  - Split lines 5-17 into named functions: `parse_args`, `pin_for`, `make_worktree`, `apply_patches`, `bump_lock`.
  - Drop the trap, so `run.sh --build` uses the patched worktree instead of re-patching.

### H7. Llave: the real pairing path diverges from the simulated one, and errors are string-sniffed
- **Where:**
  - `tools/llave/core/src/pair.rs:283-291` requires `--out`'s parent to equal `$COFRE_PAIRING_DIR` (default: relative `pairings`).
  - `App/Sources/Services/PairingService.swift:25` passes an absolute temp path, and nothing sets `COFRE_PAIRING_DIR`.
  - So after `placed` is printed (`pair.rs:280`), the run returns `Err` and exits 1, and `LlaveModel.swift:104-107` replaces `.done` with a generic error.
  - Placement failures are bare `String`s (`pair.rs:256-279`) printed to stderr. `LlaveModel.swift:128-131` looks for `"not installed"`/`"placement"` in event messages, so `.cofreMissing` and `.placementFailed` (the AirDrop fallback in README Step 3) are unreachable.
  - `simulate.rs:34` skips the check, so `test-pair.sh` and the tests pass.
  - Confirmed by reading the code, not run on a device.
- **Change:**
  - Add `PairEvent::Placed` and emit it (replace the hand-written JSON at `pair.rs:280`).
  - Emit `PairEvent::Error { code: "COFRE_MISSING" | "PLACEMENT_FAILED" }`.
  - Match on `code` in Swift and delete the message sniffing.
  - Write one `write_output(path)` used by both the real and simulated paths.
  - Either pass `COFRE_PAIRING_DIR` from `PairingService` or drop the parent check.

### H8. No agent entry point; rules are scattered and one is missing
- **Where:**
  - There is no root `AGENTS.md`/`CLAUDE.md`.
  - "Never edit upstream/" is only in `UPDATING.md:4`.
  - "≤5 patches" is in `UPDATING.md:47`, `patches/air/README.md:1` and `PLAN.md:127`.
  - The **build lock** rule is written nowhere.
  - `upstream/air/AGENTS.md` exists, and agents that open `upstream/air` will load upstream's rules, not ours.
  - Test commands are spread over `app/UI/README.md`, `PAIRING-ENGINE.md` ("run Rust and Swift tests", with no commands) and nowhere else (ServerJoin, Llave, JS, validator).
  - No CI (`.github/` has only issue templates).
- **Change:**
  - Add `AGENTS.md` (Appendix A) and a one-line `CLAUDE.md` containing `@AGENTS.md`.
  - Add `scripts/test.sh` that runs every device-free suite above.
  - Have `lint.sh` also run swift-format (M12).

---

## Medium impact

### M1. ObjC is written as one-line methods
- **Where:**
  - `AirBridgeAdapter.m`: lines 19-21, 36-38 and 50-56 (up to about 450 characters each).
  - `CofreTunnelService.m:3-4`: line 4 is about 900 characters with 3 nested callbacks.
  - `CofrePairingImport.m:6-21`.
  - `AirBridgeAdapter.m:14,16` both `#import "LauncherPreferences.h"`.
- **Change:**
  - Add `.clang-format` (`BasedOnStyle: LLVM`, `IndentWidth: 4`, `ColumnLimit: 120`, `ObjCBlockIndentWidth: 4`) and run it once on `app/Glue/**/*.{h,m}`.
  - Delete the duplicate import.
  - Add `clang-format --dry-run -Werror` to `lint.sh`.

### M2. Shell and Python one-liners
- **Where:**
  - `update-upstream.sh:5,9,11-17`
  - `smoke.sh:4-9`
  - `run.sh:9,45-46,68`
  - `sign-development.py`:
    - lines 3-13 have `;`-chained statements.
    - lines 8-9 use `(_ for _ in ()).throw(SystemExit(...))`.
    - line 7 has `import os` mid-file.
    - the appex existence check appears twice (lines 24 and 32).
    - line 36's `root/'Tunnel.entitlements'` branch is dead: no such file.
    - two identical Mach-O signing loops (lines 34-35 and 37-39).
- **Change:**
  - One statement per line.
  - `identity = os.environ.get('SIGNING_IDENTITY') or sys.exit('SIGNING_IDENTITY is required')`.
  - Write `def sign_macho(tree, skip=None)`.
  - Delete the second appex check and the dead entitlements branch.

### M3. 19 PlistBuddy lines, each with `|| true`
- **Where:** `run.sh:49-67`.
- **Problem:** failures are silent, and adding a key means editing 3-4 lines.
- **Change:** check in `app/Resources/Info.cofre.plist` (URL scheme, document type, imported UTI). Merge it with `plistlib` inside the `Info.plist` edit `sign-development.py:23-29` already does. Delete run.sh lines 48-68.

### M4. Two ways to inject glue into Air; one is broken
- **Where:**
  - `run.sh:22-31`: 10 hand-listed `cp` lines.
  - `run.sh:37`: a second hand list of 5 names (CofreJIT.swift fell through the gap).
  - `patches/air/0001-cofre-build-appex.patch` isn't used by the build. Its paths are `${COFRE_SOURCE_DIR}/app/Glue/...` while run.sh copies into `CofreGlue/`.
  - The patch is also malformed: hunks have no context lines, the subject is `[TYPE] …` and the author is `cofre@example.invalid`, so `git am` would fail.
  - `run.sh:20` applies 0002 by hand.
- **Change:**
  - One mechanism: a real 0001 that adds `file(GLOB COFRE_GLUE CofreGlue/*.m)` plus the Swift rule from H2.
  - Copy with `cp app/Glue/AirBridge/* app/Shell/*.swift "$AIR/Natives/CofreGlue/"`.
  - Delete the Python CMake editor (`run.sh:32-41`).

### M5. Config that nothing reads
- **Where:**
  - `run.config:10` passes `COFRE=1`, but Air's Makefile has 0 `COFRE` references.
  - `run.config:2,4` set `BUNDLE_ID` and `TUNNEL_BUNDLE_ID`, which `run.sh:8` doesn't export, so `sign-development.py:10` always uses its own defaults.
  - `sign-development.py:19` hard-codes `bundle+'.tunnel'` instead of `tunnel_bundle`.
  - `scripts/watch/*.txt` are read by nothing.
  - `.gitignore:8` lists `scripts/__pycache__/`, but scripts has no Python modules.
- **Change:**
  - Delete `COFRE=1`.
  - Export the two IDs, or delete them from `run.config`.
  - Use `tunnel_bundle` at line 19.
  - Either wire the watch lists into the updater or delete them.

### M6. The same identifiers are hard-coded in many places
- **Where:**
  - `com.ignaciojuarez.cofre.tunnel`: `CofreJIT.swift:30`, `CofreBackendAdapter.swift:318`, `CofreTunnelService.m:3,4`, `run.config:4`, `sign-development.py:10`, `.build-tools/signing/project.yml`.
  - `10.7.0.1`: `CofreTunnelService.m:4`, `LoopbackTunnel.swift:10,13`, `PacketTunnelProvider.swift:12,54`.
  - `StikJIT/pairingFile.plist`: `CofreBackendAdapter.swift:305`, `CofrePairingImport.m:16-18`, `pair.rs:269`.
- **Change:** add one `app/Glue/CofreIDs.swift`:

  ```swift
  enum CofreIDs {
      static let tunnelBundleID
      static let tunnelAddress
      static let pairingRelativePath
  }
  ```

  Plus `CofreIDs.h` with the same `#define`s for ObjC. Reference both from the scripts' comments.

### M7. Three VPN code paths, while the facade says VPN is "unavailable"
- **Where:**
  - `CofreTunnelService.m:4` installs and starts at launch.
  - `CofreJIT.swift:25-35` finds and starts the tunnel.
  - `CofreBackendAdapter.swift:311-322` looks it up.
  - Meanwhile `startVPN()` throws "unavailable" and `isVPNRunning` is hard-coded `false` (`:96-97`).
- **Change:** one `CofreVPN` type (`manager()`, `install()`, `start()`, `status`) used by all three. Implement `startVPN`/`isVPNRunning` with it, and delete `CofreTunnelService.{h,m}` once Swift compiles.

### M8. `CofreBackendAdapter.swift`: copy-paste, dead state, misleading names
| Lines | Problem | Change |
|---|---|---|
| 26-46, 323-331 | 6 copy-pasted `UserDefaults` stanzas each way | Loop over `[("pairing", \.pairing), …] as [(String, WritableKeyPath<SetupState, CheckState>)]` |
| 309 | `kind == .latest ? "latestlog.txt" : "latestlog.txt"` | Map each `LogKind` to a real file, or drop the parameter |
| 23, 215-218 | `launchTask` is never assigned, so `cancelLaunch()` does nothing | Delete it, or assign it in `launch` |
| 57 | `onTermination = { _ in }` does nothing, and continuations leak | Remove the continuation on termination |
| 69 | `devMode` is derived from `isJITEnabled`, which is hard-coded `false` | Comment the coupling or check the real state |
| 124-136 | `servers(instanceID:)` ignores `instanceID` and returns **Modrinth server search** results | Rename (`featuredServers`) or read the instance's `servers.dat`. Add a doc comment |
| 153-155 | Duplicates the protocol default at `Requirements.swift:150-155` | Delete |
| 293 | Source URL `github.com/ignaciojb/cofre` (wrong owner, outside `CofreLinks`) | Add `CofreLinks.source` and use it |
| 7-14, 339 | `CofreBackendError` duplicates CofreUI's `UnsupportedAction` (`Requirements.swift:135`) | Use `UnsupportedAction(name:)`; delete the enum and the wrapper |
| 130-131 vs `ServerJoinAdapter.swift:74-75` | The `cofre.server-card.<host>` key is built twice, with different host parsing | One `static func serverCardKey(_ address:)` |

### M9. `ServerJoinAdapter.swift`: silent no-ops and wrong error codes
- **Where and change:**
  - Lines 57-60: `joinCacheURL` is unused → delete.
  - Lines 30-31: `.cancelInstall`, `.setSelected`, `.resolveWarning`, `.setAutoUpdate` and `.setAutoConnect` are silently ignored. The contract says `resolveWarning` sets `isResolved`. Add a `// TODO(GAP-14): not implemented` per case, or implement them.
  - Line 76: `MrpackIndex(dependencies: [:], files: [])` means every plan shows 0 bytes and 0 mods → comment it, or fetch `modrinth.index.json`.
  - Lines 56 and 96: the trust store lives in memory and `TrustVerifier.confirm` is never called, so every visit is a first visit and `pinnedKeyFingerprint` is always `nil` → persist the store, or document it.
  - Lines 44 and 131: every failure becomes `.signatureRejected` or `.networkTimeout` → write one `func errorCode(for: Error) -> ErrorCode` that maps `ServerJoinError`.
  - Line 107: the card is fetched again at install → reuse the resolution stored on the model.
  - Rename `AirServerJoinModel` → `LiveServerJoinModel`.

### M10. CofreServerJoin internals: copies and unused abstractions
- **Where and change:**
  - `Data(base64URL:)` is written 3 times: `Decoder.swift:83-89`, `Trust.swift:58-64` and `tools/server-card/Sources/server-card/main.swift:16-20`. Keep one `Base64URL.swift` (internal).
  - `server-card` redefines the envelope (`main.swift:4-11`). Add `.package(path: "../../app/ServerJoin")` and reuse `CardEnvelope`.
  - `Discovery.fetchEnvelope` (`Discovery.swift:24-29`) is unused; the adapter inlines the same 2 lines → use it, or delete it.
  - `JoinDownloader` (`InstallEngine.swift:13`) has no implementation → delete.
  - `InstallEngine`/`JoinFileSystem` aren't used outside tests → delete, or keep with a "planned" comment.
  - Magic limits `512 * 1024` (`Decoder.swift:25,37`) and `2_147_483_648` (`Decoder.swift:63`, `InstallEngine.swift:36`) → `enum CardLimits { static let cardBytes, packBytes }`.
  - The allowed-key set includes `min_launcher_version` and `signing` (`Decoder.swift:41`), which `ServerCard` ignores → add a comment saying why.

### M11. Package tests read fixtures from `plan/`
- **Where:**
  - `ServerJoinTests.swift:6-8` walks up 6 directories to `plan/server-join/examples`. Moving either folder breaks the tests.
  - `testCachePathAPI` (line 149) asserts nothing.
- **Change:**
  - Move the fixtures to `Tests/CofreServerJoinTests/Fixtures/`, add `resources: [.copy("Fixtures")]` and load them with `Bundle.module`.
  - Point `plan/server-join/README` and `validate_examples.py` at the new path.
  - Delete `testCachePathAPI`.

### M12. Swift formatting is half done and not enforced
- **Where:**
  - `4465053` formatted CofreKit, Glue, Shell and extensions only.
  - `app/UI` (79 files) still has 8,301 lint findings, for example `Facade/Services.swift:70` and `Facade/ServerJoin.swift:331-332` (`;`-joined assignments).
  - Most of `tools/llave` is also unformatted (`LlaveApp.swift:8,23`, `StateScreen.swift:81,96`).
  - `lint.sh` runs only ShellCheck.
- **Change:**
  - Run `xcrun swift-format format -i -r --configuration .swift-format app/UI tools/llave/App tools/llave/tests` in one `[CLEAN]` commit.
  - Add `xcrun swift-format lint --strict -r app extensions tools` to `lint.sh`.

### M13. Docs that point to paths or facts that don't exist
| Where | Says | Change to |
|---|---|---|
| `app/UI/README.md:4`, `:190`; `AppIcon.swift:4`; `JoinServerSheet.swift:4`; `MockServerJoin.swift:5`; `docs/styles.css:1`; `app/Resources/AppIcon/README.md:3`; `design/DESIGN_SYSTEM.md:168` | `cofre-design/…` | `design/…` |
| `app/UI/README.md:113`; `Facade/ServerJoin.swift:4`; `design/DESIGN_SYSTEM.md:3` | `launcher-plan/…` | `plan/…` (or delete) |
| `app/UI/README.md:40-55` | Sample root VC with `CofreBackendAdapter(/* AirBridge, … */)` | The actual 10 lines of `app/Shell/CofreRootViewController.swift` |
| `design/DESIGN_SYSTEM.md:3-4` | "Status: spec only, nothing built"; facade = `CofreKit.swift` | "Built in `app/UI`; backend = `CofreBackendAdapter`" |
| `UPDATING.md:28,49`; `plan/PLAN.md:128` | `app/Glue/AirBridge.*`, `AirBridge.{h,m}` | `app/Glue/AirBridge/` |
| `plan/PLAN.md:125` | `scripts/build.sh`, `add-friend.sh` | Mark the section historical: "Layout as planned; see AGENTS.md for actual" |
| `patches/air/README.md:1` | "Planned patches" | List 0001/0002 with one line each, plus the budget |
| `tools/llave/PAIRING-ENGINE.md:5` | `curl … <RAW_URL>/pair.sh` | The real URL from `docs/app.js` `LINKS.pairScript` |
| `LoopbackTunnel.swift:5-6` | "Open spike S1: verify …" | State the result, or link the open issue |

### M14. Llave app: duplicated tables and dev fallbacks in release code
- **Where and change:**
  - `DeviceWatcher.swift:40-46`: a signed release app falls back to executing `/tmp/bin/llave-pair` (a world-writable path) and paths relative to the current directory → wrap them in `#if DEBUG`.
  - The same error codes have two copy tables: `LlaveError.swift:14-33` (`friendlyCopy`) and `StateScreen.swift:100-111` (`problem`). Keep `StateScreen`'s and delete the `friendlyCopy` switch.
  - "Cofre missing" exists twice: the `.cofreMissing` state and `.error(code: "COFRE_MISSING")` (`StateScreen.swift:77-81`). Keep the state and map the code to it once, in `LlaveModel`.
  - `LlaveState.ready(fileURL:)` is only produced by `PreviewState.swift:24` → delete it, or document it as the AirDrop-only path.
  - `--simulate` is declared 3 times: `cli.rs:6-7` (global) plus `:14-15` and `:24-25`, merged at `main.rs:14,18,40`. Keep only the global flag.
  - `tools/llave/SHA256SUMS` contains an absolute path into another checkout (a local absolute path). Fix `release.sh:6` to `(cd "$ROOT/build" && shasum -a 256 Llave.app.zip) > "$ROOT/SHA256SUMS"`.

### M15. The app↔appex JIT message has no shared definition
- **Where:**
  - `CofreJIT.swift:50-65` builds `{"cmd","pid","pairing"}` and treats **any** `mode` key as success.
  - `PacketTunnelProvider.swift:36,45,61` writes JSON strings by hand and replies `{"state":"enabling","mode":"txm"}` *before* JIT runs, so the host reports JIT enabled early.
  - `PacketTunnelProvider.swift:7` `pairingURL` is written and never read.
- **Change:**
  - Add `extensions/PacketTunnel/JITMessage.swift` (`Codable` `JITRequest` and `JITReply { state: enabling|enabled|failed, mode, reason }`), compiled into both targets.
  - Decide success on `state`, not on whether `mode` exists.
  - Delete `pairingURL`.

---

## Low impact

| # | Where | Problem | Change |
|---|---|---|---|
| L1 | `app/Shell/CofreRootViewController.swift:14`, `:11,23` | `CofreUIKitTheme.apply()` duplicates `bootstrap()` (`CofreUI.swift:16`); `child` is never read | Delete both |
| L2 | `CofreRootViewController.swift:4-6`, `AirBridgeAdapter.m:61-62` | `@_silgen_name` C shims, though Swift already sees `CofreAirBridgeAdapter` (`CofreBackendAdapter.swift:22`) | Call `CofreAirBridgeAdapter().controlsEditor()` and delete the shims |
| L3 | `CofreRootFactory.m:3-4` | Two class lookups; `@objc(CofreRootViewController)` makes the first one dead | Keep one `NSClassFromString(@"CofreRootViewController")`. Log when nil (H2) |
| L4 | `CofreStartup.m:9-11` | Enumerates instances and worlds only to log them | Delete; keep the memory default and VPN start |
| L5 | `AirBridgeAdapter.m:33-35`, `:58`; `.h:12` | `addServer:name:` drops `name` and calls `joinServer`; `forgeInstaller:` ignores the ID; the header says `id` but the implementation takes `ModItem *` | Pass `name` or rename to `joinServer:`; document the ignored ID; forward-declare `@class ModItem` |
| L6 | `tools/llave/App/Resources/Llave.icns` = `design/icons/llave/Llave.icns`; `design/icons/01-vanilla.png` = `AppIcon-Light/1024x1024.png` (same md5) | Binary copies with no stated source of truth | Say in `design/icons/README` which file is the source and which script writes each copy |
| L7 | `site/` vs `docs/` | Two top-level folders for one website | Add `site/README.md`: "tools and fact-checks for `docs/`; not published" |
| L8 | `tools/llave/App/Llave.xcodeproj`, `app/UI/PreviewHost/*.xcodeproj`, `signing/CofreSigning.xcodeproj` | Generated projects committed next to the `project.yml` that `build.sh:10` and `run.sh:71` regenerate | Ignore the generated `.xcodeproj` files and keep `project.yml` as the source |
| L9 | `update-upstream.sh:19` | Prepends the entry *above* `# Changelog` | Insert after line 2 |
| L10 | `.work/air/artifacts` → `../air/artifacts` (outside the repo); `run.sh:14-18,45` | The build quietly depends on a sibling checkout; the CMake-cache scrub exists because of it (`build-air.log` tail) | Remove the symlink, or document it in `AGENTS.md` |
| L11 | `plan/server-join/examples/signed/test-keypair/private.key`; `server-card/main.swift:43` | Private key with no label; `key_id: "test-key"` is hard-coded for every signature | Add a README "test key, never trusted"; add a `--key-id` argument |
| L12 | `Facade/ServerJoin.swift:336-338` | A general `String.nilIfEmpty` hidden at the end of a facade file | Move to `Screens/Shared.swift` |
| L13 | `CofreKit.swift`, `CofreUI/Models.swift` | `CofreState` vs `CheckState`, `SetupStatus` vs `SetupState` (another naming clash) | Goes away with H4 |
| L14 | `CofreBackendAdapter.swift`, `ServerJoinAdapter.swift` | Wrapped in `#if canImport(UIKit)` though they're iOS-only app code (never built for macOS) | Drop the wrapper |

---

## Structure: would a fresh agent know where to change things?

| Area | Obvious? | Fix |
|---|---|---|
| `app/UI` (CofreUI) | ✅ Excellent README, tests and preview host | Fix stale paths (M13) and the format (M12) |
| `app/CofreKit` | ❌ Name implies "the backend"; it's mostly dead plus a nested package | H4: delete, and move ServerJoin to `app/ServerJoin` |
| `app/Glue/AirBridge` | ⚠️ The real backend, but no README; mixed ObjC and Swift | Add `app/Glue/README.md`: what each file does, what compiles today (H2) |
| `app/Shell` | ✅ One file | — |
| `extensions/PacketTunnel` | ⚠️ Build definition hidden in `.build-tools/` | H1: `signing/` with a README |
| `tools/llave` | ✅ Good doc; tests exist | Add the test commands; fix H7 |
| `tools/server-card` | ⚠️ No README | 3 lines: keygen/sign/verify; "test keys only" |
| `docs/` + `site/` | ⚠️ Split | L7 |
| `plan/`, `design/` | ⚠️ History mixed with live spec; still holds test fixtures | M11; mark `PLAN.md` historical |
| `patches/`, `upstream/`, `UPDATING.md` | ❌ Runbook ≠ script; patch 0001 malformed and unused | H6, M4 |

---

## Top 10 changes

1. **Untrack DerivedData**: `git rm -r --cached .build-tools/signing/build`, ignore it, delete the `.bad*` dirs, and rename to `signing/` with a README (H1).
2. **Add root `AGENTS.md` plus `CLAUDE.md` (`@AGENTS.md`) and `scripts/test.sh`** (H8, Appendix A).
3. **Compile the Swift glue, or say loudly that it isn't compiled**: a swiftc rule in a real patch 0001; `CofreRootFactory.m` logs on fallback (H2, M4).
4. **One pairing validator and one atomic writer**: route the UI's `importPairing` through it; delete `FilePairingStore`, the `hasPairing` copy and the failing test script (H3).
5. **Delete dead CofreKit** (`CofreKit.swift`, `Services.swift`), move `CofreJIT.swift` to Glue and ServerJoin to `app/ServerJoin`, and rewrite the facade comments to name `CofreBackendAdapter` (H4).
6. **Delete `CofreServerJoin/ViewModels.swift`** and rename `Loader` → `CardLoader`, which removes all 12 name clashes and every `CofreUI.` qualifier (H5).
7. **Make `UPDATING.md` match `update-upstream.sh`**: fix the macOS `strftime` crash and split the one-liners into functions (H6).
8. **Llave: typed `Placed`/`COFRE_MISSING`/`PLACEMENT_FAILED` events, one output writer, and no string sniffing**. This fixes the real-device `--out` failure that simulation hides (H7).
9. **Format everything and enforce it**: swift-format on `app/UI` and `tools/llave`, clang-format on the ObjC, both in `lint.sh` (M1, M12).
10. **Centralize identifiers and contracts**: `CofreIDs` (tunnel bundle ID, `10.7.0.1`, pairing path), a shared `JITMessage` Codable, one `CofreVPN` (M6, M7, M15).

---

## Appendix A: proposed root `AGENTS.md`

Paths assume H1 (`signing/`) and H4 (`app/ServerJoin/`). Until those land, read them as `.build-tools/signing/` and `app/CofreKit/ServerJoin/`. The repo defines no build lock today, so rule 5 is a proposed wording: confirm the mechanism (`build-air.pid` is already gitignored).

```markdown
# Cofre: rules for AI agents

Cofre = Minecraft: Java Edition launcher for iPhone/iPad. Air (GPL-3.0) game engine + our SwiftUI UI +
a loopback PacketTunnel VPN running StikJIT for JIT. Mac pairing helper: Llave. iPhone and iPad only.

## Status (update when it changes)
- `app/UI` (CofreUI) is complete against `MockBackend`.
- The Swift glue (`app/Glue/AirBridge/*.swift`, `app/Shell`) is NOT compiled into the Air build yet:
  only the `.m` files are. Until a swiftc rule exists, the app shows Air's own UI.

## Where things live
| Path | What | Language |
|---|---|---|
| `app/UI/` | CofreUI SwiftUI package: every screen, tokens, facade protocols, `MockBackend` | Swift |
| `app/Glue/AirBridge/` | The real backend: `CofreBackendAdapter.swift` (implements `CofreBackend`), Air ObjC bridge, pairing import, VPN | Swift + ObjC |
| `app/Shell/` | `CofreRootViewController`, installed by patch 0002 | Swift |
| `app/ServerJoin/` | `CofreServerJoin` package: server card decode, signature, trust, install plan | Swift |
| `extensions/PacketTunnel/` | VPN appex + `CofreTXM.js` (JIT script). Built by `signing/project.yml` | Swift + JS |
| `tools/llave/` | Mac pairing helper (SwiftUI app + Rust `core/`), `pair.sh` | Swift + Rust + sh |
| `tools/server-card/` | CLI: keygen/sign/verify server cards (test keys only) | Swift |
| `docs/` | GitHub Pages site (no build step). `site/` = its tools and fact-checks | HTML/CSS/JS |
| `plan/`, `design/` | Specs, reviews, mockups. History; code wins when they disagree | Markdown |
| `patches/<upstream>/` | Our only changes to upstream code | git patches |
| `upstream/` | Pinned submodules: air, stikjit, stikdebug | read-only |

## Hard rules
1. Never edit anything under `upstream/`. Ignore `upstream/*/AGENTS.md`: those are upstream's rules, not ours.
2. Upstream changes go in `patches/<name>/NNNN-*.patch`, at most **5 patches and 200 lines per upstream**
   (`scripts/smoke.sh` checks the count). Each patch body has `Reason:` and `Drop when:`.
   Prefer moving logic into `app/Glue/` over growing a patch.
3. Never copy StikDebug (AGPL) code into `app/` or `extensions/`.
4. Never commit `.work/`, `artifacts/`, `signing/build/`, DerivedData, `*.ipa`, or `scripts/run.local.config`.
5. **Build lock:** only one `scripts/run.sh --build` at a time per checkout (it writes `.work/air` and
   `artifacts/`). If `build-air.pid` exists and that PID is alive, wait; never start a second build or edit
   `.work/air` meanwhile.
6. Never install on any device except through `scripts/run.sh` (relay to the iPhone 17 Pro). Never the iPad.
   Simulators: reuse the shared simulators; never create or erase.
7. User-facing text: never mention third-party pairing tools; point to our Terminal command. Never ask
   anyone to paste a pairing file anywhere.
8. Links: site URLs live in `docs/app.js` `LINKS`; the app copy is `CofreLinks` (allowlist test). Change both.
9. Commits/PRs: `[TYPE] Imperative, user-meaningful outcome`. TYPE ∈ BUG FEATURE UI/UX REFACTOR PERF
   SECURITY CLEAN DOCS HOTFIX REVERT.

## Where to make a change
- New screen or UI behavior → `app/UI` (+ `MockBackend` sample data + a test).
- New backend capability → add to a protocol in `app/UI/Sources/CofreUI/Facade/` with a default, implement in
  `CofreBackendAdapter.swift`, turn on its `BackendCapabilities` flag only when it works.
- Air data or ObjC access → `app/Glue/AirBridge/AirBridgeAdapter.{h,m}`.
- JIT protocol → `extensions/PacketTunnel/` + `CofreTXM.js` + `tests/jit/`. Device test on a TXM phone is mandatory.
- Pairing → `tools/llave` (Mac) and `app/Glue/AirBridge/CofrePairingImport.m` (phone). One validator.

## Build
    scripts/run.sh --build          # Air build in .work/air + appex + dev signing → install via relay
    scripts/run.sh                  # reinstall the last signed build
    scripts/run.sh --build --sqim   # build and upload to Sqim instead of installing
    tools/llave/scripts/build.sh    # Llave.app (needs a Developer ID identity)
    tools/llave/scripts/release.sh  # zip + SHA256SUMS + pin the hash in pair.sh (never uploads)

## Test (all device-free; run before every commit)
    scripts/test.sh                 # runs everything below
    scripts/lint.sh                 # ShellCheck (+ swift-format / clang-format)
    scripts/smoke.sh                # static: upstreams, patch budget, lock file
    (cd app/ServerJoin && swift test)
    (cd app/UI && swift test)       # macOS token/font tests
    (cd app/UI && xcodebuild test -scheme CofreUI -destination 'platform=iOS Simulator,id=<shared UDID>')
    (cd tools/llave/core && cargo test)
    sh tools/llave/test-pair.sh     # simulated pairing window
    node tests/jit/txm.test.js
    python3 plan/server-join/validate_examples.py

## Update upstream
Follow `UPDATING.md`. Stop and ask a human if LICENSE changes, a patch would exceed the budget, or the
conflict touches the JIT protocol, entitlements or sign-in.
```
