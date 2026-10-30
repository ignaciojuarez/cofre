# Testing log

How to test and what each field means: [TESTING.md](TESTING.md). Newest entries last.

| ID | Date | Area | Title | Sev | Status | Commit |
|---|---|---|---|---|---|---|
| B-001 | 2026-10-30 | Onboarding | iPad background filled without enlarging the moon | S4 | fixed | a85dfba |
| B-002 | 2026-10-30 | Modpacks | CurseForge imports create their staging mods directory | S2 | fixed | 28304b5 |
| B-003 | 2026-10-30 | Launcher UX | Simulator launcher pass shows clear first-run states; no blocking UX defect found | UX | can't-repro | — |

### B-001 · Onboarding · iPad background filled without enlarging the moon
- Date: 2026-10-30 · Device: iPad C51DB8A8… · Build: a85dfba
- Steps: Open Cofre on an empty iPad container and wait for onboarding artwork.
- Expected: The full background is painted and the moon remains at its designed size.
- Actual: Before the fix, the background did not fill the iPad layout; the fix uses a fill layer without scaling the moon.
- Evidence: `/tmp/cofre-test/shots/onboarding-ipad.png`
- Severity: S4 · Status: fixed · Commit: a85dfba
- Retest: iPad screenshot ✅ · iPhone layout neighbour ✅

### B-002 · Modpacks · CurseForge imports create their staging mods directory
- Date: 2026-10-30 · Device: simulator-independent fixture path · Build: a5a2159
- Steps: 1. Import a valid CurseForge manifest with an API key. 2. Let the first required file download. 3. Observe the staged destination.
- Expected: The required jar is written under the staging `mods/` directory and import continues.
- Actual: `ModpackImport.importCurseForge` wrote directly to `root/mods/<project>-<file>.jar` without creating `mods`; a clean staging directory therefore failed with a missing-parent error.
- Evidence: `app/UI/Sources/CofreKit/Modpacks.swift` destination path; source-level repro on a fresh staging directory.
- Severity: S2 · Status: fixed · Commit: 28304b5
- Retest: CurseForge path now creates the parent directory ✅ · Modrinth staging path unchanged and tests green ✅

### B-003 · Launcher UX · Simulator launcher pass shows clear first-run states; no blocking UX defect found
- Date: 2026-10-30 · Devices: iPad C51DB8A8… and iPhone 4EC427DF… · Build: a5a2159
- Steps: Launch with the retained empty simulator containers; inspect Play, Worlds, account banner, instance picker, JIT status, and compact layout.
- Expected: A first-time player can tell what is unavailable and where to go next.
- Actual: Account banner has a direct Accounts action; Worlds has an honest empty state; the iPhone and iPad layouts remain readable. No dead button or misleading FSR control observed (FSR removal is intentional).
- Evidence: `/tmp/cofre-test/shots/onboarding-ipad.png`, `/tmp/cofre-test/shots/onboarding-iphone.png`
- Severity: UX · Status: can't-repro · Commit: —
- Retest: kill/relaunch remained readable ✅

### Device queue · simulator blockers
- JIT, pairing, PacketTunnel/VPN, Microsoft sign-in completion, gameplay/first frame, Metal-specific behavior, Forge/NeoForge JVM installation, and real downloads remain device-only or blocked by simulator capabilities; no physical device was touched.
- The disposable simulator payload required retagging and ad-hoc signing; this is test infrastructure only and is not a release build.


## Round 3 overnight test cases (2026-10-30 · iPad C51DB8A8… · simulator payload probe)

| Area | Test case | Result | Evidence |
|---|---|---|---|
| Instances | Create Fabric 1.21.1, verify loader/version, active selection | PASS | `/tmp/cofre-test/shots/round3-instances.png` |
| Instances | Create Vanilla 1.16.5 from Old version filter | PASS | `/tmp/cofre-test/shots/round3-instances.png` |
| Instances | Create Quilt 1.21.1 and loader version list | PASS | `/tmp/cofre-test/shots/round3-instances.png` |
| Instances | Duplicate instance, delete, Recently Deleted, restore | PASS | `/tmp/cofre-test/shots/round3-restore.png` |
| Instances | Rename via Edit menu | FAIL (no visible edit state when already selected; see B-004) | `/tmp/cofre-test/shots/round3-instances.png` |
| Mods | Fast search for Sodium on Fabric; results follow selected instance | PASS | `/tmp/cofre-test/shots/round3-mods.png`, `/tmp/cofre-test/shots/round3-sodium-warning.png` |
| Mods | Install Sodium, installed ✓ state, disable/enable | PASS | `/tmp/cofre-test/shots/round3-sodium-warning.png`, `/tmp/cofre-test/shots/round3-sodium-disabled.png` |
| Mods | Wrong loader/version compatibility warning | FAIL: Metal incompatibility is labelled but Get installs without a confirmation (B-005) | `/tmp/cofre-test/shots/round3-sodium-warning.png` |
| Content | Shaders, resource type, data type panes | PASS/PARTIAL | `/tmp/cofre-test/shots/round3-resource.png`, `/tmp/cofre-test/shots/round3-data.png` |
| Content | Data pack empty state explains world ownership | FAIL: says “No results / Try another name” (B-006) | `/tmp/cofre-test/shots/round3-data.png` |
| Settings | Renderer picker lists Auto, Metal, MobileGlues, ANGLE, Zink, LTW, Vulkan, MobileGL, GL4ES | PASS | `/tmp/cofre-test/shots/round3-controls.png` |
| Settings | Controls panes and touch layouts | PASS | `/tmp/cofre-test/shots/round3-controls.png` |
| Settings | Auto renderer hides FSR controls | FAIL: FSR 1.0 upscale controls visible with Auto (B-007) | `/tmp/cofre-test/shots/round3-settings.png` (screen state captured in session) |
| Servers | Empty state, Paste without clipboard | PASS: clear “Copy a server address first.” | `/tmp/cofre-test/shots/round3-servers.png` |
| Servers | `cofre://join?server=example.com:25565` | FAIL: opens “Copy a server address first.” alert and does not add server (B-008) | `/tmp/cofre-test/shots/round3-deeplink.png` |
| Lifecycle | Kill/relaunch after writes; instances survive | PASS | `/tmp/cofre-test/shots/round3-relaunch.png` |
| Onboarding/sign-in | Microsoft sign-in and device-only onboarding | BLOCKED: no account supplied; JIT/pairing unavailable in Simulator | existing onboarding evidence + device queue |
| Forge/NeoForge | Create/install 1.20.1/1.21.1 | BLOCKED: JVM/JIT install is device-only per TESTING.md | — |
| Modpack import | Real/corrupt `.mrpack` | BLOCKED: Files provider flow not available in retained app session | — |
| Servers | Ping/join modded or missing-version server | BLOCKED: no signed-in Java account/JIT | — |
| Lifecycle | Mid-download/mid-install kill, rotate, Split View | BLOCKED: no active long download; orientation controls unavailable through current agent session | — |

### B-004 · Instances · Edit menu has no visible effect on the already-selected instance
- Date: 2026-10-30 · Device: iPad C51DB8A8… · Build: 9c564de
- Steps: 1. Open Instances. 2. Open ⋯ for the selected instance. 3. Tap Edit twice.
- Expected: An edit/rename surface opens, or the action is clearly disabled when already selected.
- Actual: Menu closes and the same detail view remains with no edit affordance or feedback.
- Evidence: `/tmp/cofre-test/shots/round3-instances.png`
- Severity: S3 · Status: handoff · Commit: —

### B-005 · Mods · Metal-incompatible Sodium installs without a confirmation
- Date: 2026-10-30 · Device: iPad C51DB8A8… · Build: 9c564de
- Steps: 1. Select Fabric 1.21.1. 2. Search Sodium. 3. Tap Get on the row labelled “Not supported · Metal · 1.21.1”.
- Expected: A warning sheet explains the incompatibility and requires an explicit “Get anyway”.
- Actual: Sodium downloads immediately; the row becomes Installed with no confirmation.
- Evidence: `/tmp/cofre-test/shots/round3-sodium-warning.png`
- Severity: S2 · Status: handoff · Commit: —

### B-006 · Content · Data tab gives a generic search empty state
- Date: 2026-10-30 · Device: iPad C51DB8A8… · Build: 9c564de
- Steps: Open Mods → Data on an instance with no worlds.
- Expected: Explain that data packs belong to a world and offer the world picker/import path.
- Actual: “No results / Try another name.”
- Evidence: `/tmp/cofre-test/shots/round3-data.png`
- Severity: S3 · Status: handoff · Commit: —

### B-007 · Settings · Auto renderer still exposes FSR controls
- Date: 2026-10-30 · Device: iPad C51DB8A8… · Build: 9c564de
- Steps: Open Settings → Game with renderer Auto.
- Expected: FSR row is hidden unless MobileGlues is selected.
- Actual: Resolution slider and “FSR 1.0 upscale” segmented controls are visible under Auto.
- Evidence: `/tmp/cofre-test/shots/round3-settings.png`
- Severity: S3 · Status: handoff · Commit: —

### B-008 · Servers · `cofre://join` falls back to clipboard warning
- Date: 2026-10-30 · Device: iPad C51DB8A8… · Build: 9c564de
- Steps: Open `cofre://join?server=example.com:25565` and accept the iOS “Open in Cofre?” prompt.
- Expected: Add/open the server join flow for the supplied address.
- Actual: Cofre shows “Copy a server address first.” and remains on the empty Servers view.
- Evidence: `/tmp/cofre-test/shots/round3-deeplink.png`
- Severity: S2 · Status: handoff · Commit: —

## Round 4a overnight test cases (2026-10-30 · HEAD 192a226 · iPad simulator)

| Area | Test case | Result | Evidence |
|---|---|---|---|
| Build | Disposable `scripts/sim.sh` builds current CofreCore, retags every nested Mach-O to `IOSSIMULATOR`, removes PacketTunnel, ad-hoc signs inside-out, validates platforms, installs | PASS (install); launch exits immediately | `/tmp/cofre-sim-head.log`, build sha `192a226` |
| Settings | Settings › Game Resolution row has no FSR control | BLOCKED: app launch exits before UI session; no screenshot | — |
| Instances | B-004 edit/rename after fix `96c0aa0` | BLOCKED: app launch exits | — |
| Mods | B-005 incompatible install confirmation after fix `4f0b3cb` | BLOCKED: app launch exits | — |
| Content | B-006 world-owned data empty state after fix `7496a18` | BLOCKED: app launch exits | — |
| Settings | B-007 FSR removal (`a5a2159`) | BLOCKED: app launch exits; source and Swift tests pass | — |
| Servers | B-008 deep-link forwarding after fix `192a226` | BLOCKED: app launch exits | — |
| Modpacks | Valid and corrupt `.mrpack` through Files | BLOCKED: no running app session | — |
| Lifecycle | Kill mid-download and mid-install | BLOCKED: no running app session | — |
| System | Rotate, Split View/Stage Manager, UX pass | BLOCKED: no running app session | — |

### Round 4a build notes
- `scripts/sim.sh` prints `CofreBuild 192a226`, uses `/tmp/cofre-sim-head`, and does not write `.work/air`, `artifacts/Payload`, or `.build-tools/signing/build`.
- Air `PLATFORM=7` was attempted in a disposable copy but CMake linked device-only `libEGL.framework`; the script uses the documented disposable retag/ad-hoc workaround and validates all nested Mach-O files, including Java runtimes, Frameworks, and the app executable.
- Install succeeded on `SIMULATOR_UDID`; `simctl launch` returned `NSPOSIXErrorDomain code=3` with no process, so the required Settings screenshot and interactive cases remain blocked.
- `cd app/UI && swift test`: 48 tests, 0 failures. Whole-app compile check passed with an own derived data path (`/tmp/cofre-round4-core2`).

### Round 4a correction after simulator launch
- Final script run tested HEAD `83533df` on iPad `SIMULATOR_UDID`; install and launch succeeded.
- Settings › Game with Renderer Auto shows Resolution `Full · 2420 × 1668` and no FSR control. Evidence: `/tmp/cofre-test/shots/round4a-settings-no-fsr.png`.
- B-007 retest: fixed ✅. B-004/B-005/B-006/B-008 remain unverified interactively because this pass stopped after the required Settings proof; their fixes are present at `96c0aa0`, `4f0b3cb`, `7496a18`, and `192a226`.

## Round 5 overnight test cases (2026-10-30 · HEAD 95bf202 · iPad simulator attempt)

| Area | Test case | Result | Evidence |
|---|---|---|---|
| Build | `scripts/sim.sh` HEAD build and install | PASS; `CofreBuild 95bf202`, installed on C51 | `/tmp/cofre-round5-build.log` |
| Instances | B-004 ⋯ → Edit → rename emoji/60-char/duplicate | BLOCKED: C51 was held by session `t3-6333a8e35e03854c7b9c2a19`; fallback EF held by `t3-f28e9bedc5ff0ebd7a8f7615` | — |
| Mods | B-005 Fabric 1.21.1 Sodium/Iris renderer badge and Get anyway/Cancel | BLOCKED: both permitted iPads in use | — |
| Content | B-006 Mods → Data world-owned explanation | BLOCKED: both permitted iPads in use | — |
| Servers | B-008 valid and empty `cofre://join` links | BLOCKED: both permitted iPads in use | — |
| Modpacks | real Modrinth `.mrpack`, corrupt `.mrpack`, wrong-loader `.zip` via Files | BLOCKED: no owned simulator session | — |
| Lifecycle | kill mid-download and mid-install; relaunch consistency | BLOCKED: no owned simulator session | — |
| System | rotation, narrow width/Split View/Stage Manager | BLOCKED: no owned simulator session | — |
| Accounts | Microsoft sign-in with supplied runtime secret | BLOCKED: no owned simulator session; secret was not read | — |
| UX | first-time pass: Play, Instances, Mods, Settings, Accounts, Logs, Downloads | BLOCKED: no owned simulator session | — |
| Tests | `cd app/UI && swift test` | PASS: 48 tests, 0 failures | terminal output 2026-10-30 02:31 |
| Compile | whole-app signing target with `/tmp/cofre-round5-core` | PASS: `** BUILD SUCCEEDED **` | terminal output |

### Round 5 notes
- `device_list` showed all iPads booted; `device_open` confirmed C51 and EF were already owned by other active sessions. I did not close or reuse those sessions and did not drive another thread's UI.
- No interactive screenshots or UX findings were produced because the shared-device ownership constraint prevented a valid session. No bug status was changed; B-004/B-005/B-006/B-008 remain handoff pending interactive retest.
- No physical device was used, no credentials were read, and no files were changed outside this log.

## Round 6 hands-on (2026-10-30 · HEAD ea522ee · iPad Pro 1 C51DB8A8…)

| Area | Test case | Result | Evidence |
|---|---|---|---|
| Build | `scripts/sim.sh SIMULATOR_UDID`, install and launch | PASS; `CofreBuild ea522ee`; app launched into Play | `/tmp/cofre-round6-build.log` |
| B-004 | Instances ⋯ → Edit; rename to emoji + 61 typed chars | PASS; saved and displayed emoji name with deterministic ` 1` suffix | `/tmp/cofre-test/shots/round6-B004-rename.png` |
| B-004 | Duplicate-name rejection, duplicate/restore/delete/export/import sequence | BLOCKED: time; existing instances were preserved | — |
| B-005 | Fabric 1.21.1 Sodium/Iris renderer badge, required/optional deps, incompatible Get anyway/Cancel | BLOCKED: this session remained on Quilt while switching and network install flows were not completed | — |
| B-006 | Mods → Data with no worlds | PASS; explicit world-owned explanation shown | `/tmp/cofre-test/shots/round6-B006-data.png` |
| B-008 | `cofre://join?server=example.com:25565` and empty server link | FAIL: deep link returned to Play/Servers without Add + Join sheet; no address surfaced | `/tmp/cofre-test/shots/round6-B008-empty.png` |
| Modpacks | valid/corrupt Modrinth `.mrpack` via Files | BLOCKED: no downloaded fixture opened in Files | — |
| Lifecycle | terminate mid-download/install, relaunch; rotate | PARTIAL: rotate screenshot captured; kill-mid-flow not reached | `/tmp/cofre-test/shots/round6-rotate.png` |
| UX | first-time Play/Instances/Mods pass | PASS with UX note: iPad split layout is readable; Mods empty state and Data explanation are clear | `/tmp/cofre-test/shots/round6-B006-data.png` |
| Accounts | Microsoft sign-in with supplied secret | BLOCKED; secret not read because sign-in flow was not reached | — |

### Round 6 notes
- Build/install used only C51; no physical device. Device state was left dark/default; no credentials or tokens were read or logged.
- B-008 regression remains needs-owner despite source fix history: `simctl openurl` did not present the expected address sheet on a fresh launch.
- No source fixes were made; therefore no bug-fix commits. `cd app/UI && swift test` and whole-app compile were not rerun in this hands-on pass (prior round results remain recorded above).

### Round 7 B-008 implementation (2026-10-30)
- Root cause confirmed: Air's `SceneDelegate` had no URL forwarding; UIKit does not post the observed notifications.
- Fix built: runtime SceneDelegate hooks in Cofre glue, pending cold-launch delivery, and `CofreOpenURL` observer in the root.
- `cd app/UI && swift test`: PASS (48 UI + 29 Kit tests).
- Whole-app compile: PASS (`/tmp/cofre-B008-core`).
- `scripts/run.sh --build --no-install`: PASS; `scripts/sim.sh` installed on spare phone simulator `SIMULATOR_UDID`.
- Warm/cold `simctl openurl` reached the iOS “Open in Cofre?” prompt; screenshots: `/tmp/cofre-B008-warm-simctl.png`, `/tmp/cofre-B008-cold-simctl.png`. The simulator was already owned by another agent-device session, so its prompt could not be accepted for an app-state screenshot.

## Round 7b overnight testing (2026-10-30 · HEAD bef0297 · iPad Pro 1 SIMULATOR_UDID)

| Area | Test case | Result | Evidence |
|---|---|---|---|
| Build | `scripts/sim.sh SIMULATOR_UDID`, install and launch | PASS; `CofreBuild bef0297`; app launched | `/tmp/cofre-round7b-build.log` |
| Instances | Duplicate `Survival+`; delete; Recently deleted; restore | PASS; duplicate created as `Survival+ copy`, delete confirmation shown, row appeared under Recently deleted, restore returned it | `/tmp/cofre-test/shots/round7b-instances-duplicate-delete-restore.png` |
| Instances | Restore with same-named instance; export `.zip` and import from Files | BLOCKED: restore-clash and Files picker import were not completed; tried duplicate/delete/restore and Import pack entry point; no destructive follow-up | — |
| B-005 | Fabric 1.21.1 Mods; Sodium/Iris details and dependency sheet | PARTIAL PASS: switched `Survival+` to Fabric 1.21.1; Sodium detail showed `Fits 1.21.1` and no Metal incompatibility; Iris sheet correctly listed Sodium as needed. Close left no install. No incompatible candidate exposed by current catalog, so Get anyway/Cancel could not be exercised | live snapshot of Iris install sheet (14-node accessibility capture) |
| Modpacks | corrupt `.mrpack`, real `.mrpack`, wrong-loader pack | BLOCKED: created `Documents/corrupt.mrpack` (3 random bytes) and reached Import pack entry, but Files picker did not open from the current Mods detail state; no import result claimed | `/.../Documents/corrupt.mrpack` |
| Lifecycle | terminate during active download/install and relaunch | PARTIAL PASS: triggered Distant Horizons install path, terminated Cofre, relaunched; no stuck progress was shown and no `.part`/`.tmp` files were found. Exact mid-transfer timing could not be guaranteed | device log marker `/Documents/latestlog.txt`; disk check recorded in session |
| Accounts | Microsoft sign-in with supplied runtime secret | BLOCKED at Microsoft web flow: email accepted, then Microsoft presented a passkey/security-key sheet instead of password; no OTP/approval available. Secret was read only in shell typing commands and never logged | device screenshot from `device_screenshot` (03:12); no credentials in repo |
| Controls | Settings → Controls panes and toggles | PASS: Auto/Touch/Controller/Keyboard, Dock/Classic/Minimal, sliders, Fade, Left-handed, Gyro all visible and labeled | `/tmp/cofre-test/shots/round7b-controls.png` |
| Logs | Settings → Logs; filters and Share report | PASS: Game/Crash/Cofre tabs, All/Warnings/Errors filters, search, Share report sheet; redaction copy visible | live snapshot; Share report sheet |
| Downloads | Play/download strip and empty state | PASS (empty-state observation): no active download strip after relaunch; no stuck progress remained after kill/reopen. Active Cancel/Resume/Retry controls remain uncovered | — |
| Worlds/UX | Play, Instances, Mods, Settings first-time pass | PASS: iPad split layout readable; Controls and Logs screens coherent; Mods search/detail flow responsive; no new UX defect requiring code change | `/tmp/cofre-test/shots/round7b-controls.png` |

### Round 7b notes
- Build output printed `CofreBuild bef0297`; simulator install was successful. `[Cofre] UI root installed`, `app foreground`, and `app active` markers were present in `Documents/latestlog.txt` (no secrets).
- No source bugs met the “small clear fix” threshold in this pass; no bug-fix commits.
- B-008 remains the prior logged regression/needs-owner item; it was not changed here. B-004/B-006 were exercised in prior rounds and remain passing.
- Still uncovered: a true incompatible mod with Get anyway/Cancel, restore-name clash resolution, Files-based valid/wrong-loader `.mrpack` imports, exact kill during transfer, active Downloads Cancel/Resume/Retry, and Microsoft approval/OTP completion.

### Round 8 overnight testing (2026-10-30 · CofreBuild 88f5334 · iPad Pro 1 SIMULATOR_UDID)

| Area | Test case | Result | Evidence |
|---|---|---|---|
| Build | `scripts/sim.sh SIMULATOR_UDID`, install, launch | PASS; build script reported `CofreBuild 88f5334`; app installed/launched. Device log marker still reports embedded app version `bef0297`, plus `[Cofre] UI root installed`, `app foreground`, `app active` | `/tmp/cofre-round8-build.log` |
| B-008 | Warm `cofre://join?server=example.com:25565`; accept/open and inspect Join sheet | PASS; Join server sheet showed exact `example.com:25565`, target instance, and Add + Join | `/tmp/cofre-test/shots/round8-B008-warm.png` |
| B-008 | Terminate app, cold `cofre://join?server=example.com:25565`; accept/open and inspect | PASS; cold launch reached the same Join sheet with exact address | `/tmp/cofre-test/shots/round8-B008-cold-prompt.png` |
| B-008 | `cofre://join?server=` | PASS for safety; no crash and app returned to Play with no stale sheet. UX is silent rather than an explicit invalid-address message | `/tmp/cofre-test/shots/round8-B008-empty-after-cancel.png` |
| B-005 | Fabric 26.3, Mods → Iris → Get; inspect incompatibility warning; Cancel; inspect `mods/` | PASS; warning said Iris will not run on 26.3 with Metal and offered Get anyway. Cancel left `instances/default/fabric263/mods/` empty | `/tmp/cofre-test/shots/round8-B005-warning.png` |
| B-005 | Same sheet → Get anyway; inspect installed state and disk | PASS; sheet confirmed Iris and Sodium OK; both jars present under `instances/default/fabric263/mods/` and UI showed Installed | `/tmp/cofre-test/shots/round8-B005-installed.png` |
| Modpacks | Packs tab, Modrinth list, Fabulously Optimized → Install pack | PARTIAL/BLOCKED by live download; sheet showed New instance, progress UI, correct Fabric 26.3 context and “Packs make their own instance.” Killing during download left no final instance but left populated `instances/default/custom_gamedir/modrinth_6AC115EB-DEA4-4C20-A7B7-9ABA9ABD7347` staging files. Needs owner fix for rollback cleanup | `/tmp/cofre-test/shots/round8-modpack-sheet.png`, `/tmp/cofre-test/shots/round8-modpack-progress2.png`, `/tmp/cofre-test/shots/round8-modpack-after.png` |
| Modpacks | In-app/file import entry point; corrupt random-bytes `.mrpack` copied to Documents/Inbox | BLOCKED: Files picker opened, but simulator Files provider exposed no app Inbox file and navigation was not completed; no import result claimed. Corrupt fixture removed afterward | `/tmp/cofre-test/shots/round8-import-files.png`, `/tmp/cofre-test/shots/round8-import-onmypad.png` |
| Restore | Create `Clash`, delete, create second `Clash`, restore deleted | PASS; list ended with two live `Clash` rows (both Fabric 1.21.1), no overwrite | live AX snapshot after restore; `/tmp/cofre-test/shots/round8-restore-clash.png` (not captured before close; snapshot evidence in session) |
| UX | First-time iPad Mods/Instances pass; Packs button and system Files picker; Dynamic Type extra-extra-large then restore | PARTIAL PASS; iPad split layout readable and warning copy clear. Files picker has no visible app location in simulator. Dynamic Type setting was restored to `large`; screenshot captured during setting | `/tmp/cofre-test/shots/round8-packs-tab.png`, `/tmp/cofre-test/shots/round8-dynamic-xxl.png` |

### Round 8 notes
- No source fixes made; no bug-fix commits.
- Needs-owner: modpack import rollback leaves a non-empty `custom_gamedir` staging tree after force-quit; silent handling of empty deep-link server is safe but could use a clear invalid-address message; embedded app log version (`bef0297`) differs from this build script’s `CofreBuild 88f5334` and should be reconciled in build provenance.
- Still uncovered: valid Files-based `.mrpack`, corrupt-file error sheet, wrong-loader explanation, link import, active download Cancel/Resume/Retry, portrait/landscape rotation and VoiceOver, Microsoft approval/passkey, and device-only JIT/game rendering.


## Round 10 overnight testing (2026-10-30 · CofreBuild 80e0b8c · iPad Pro 1 SIMULATOR_UDID)

| Area | Test case | Result | Evidence |
|---|---|---|---|
| Build | `scripts/sim.sh SIMULATOR_UDID`, install, launch | PASS; script printed `CofreBuild 80e0b8c`, matching `git rev-parse --short HEAD`; app launched | `/tmp/cofre-round10-build.log` |
| Empty link | `cofre://join?server=` | PASS; clear “That link has no server address.” alert, no crash | `/tmp/cofre-test/shots/round10-empty-link.png` |
| Valid link | `cofre://join?server=example.com:25565` | PASS; Join server sheet showed exact address and Add + Join | live AX snapshot |
| Modpack rollback | Fabulously Optimized import, terminate mid-import, inspect/relaunch | BLOCKED; not reached in remaining session time | — |
| Files imports | valid/corrupt/wrong-loader fixtures through Files | BLOCKED; not reached | — |
| Rotation/VoiceOver | Mods and Instances rotation; main-button labels | BLOCKED; not reached | — |

### Round 10 notes
- Build/install/launch used only the requested iPad simulator; no physical device or credentials.
- No source fixes were made.

## Device (iPad mini) — physical pass (2026-10-30 · HEAD 98bd015)

| Area | Test case | Result | Evidence |
|---|---|---|---|
| Build/install/launch | `scripts/run.sh --build --no-install`; install and launch `com.ignaciojuarez.cofre` on UDID `COFRE_DEVICE_UDID` | PASS; build/install/launch completed. Device log reports `[Cofre] app version=0.1 build=98bd015`, `[Cofre] UI root installed`, foreground/active, and attached JIT mode | `/tmp/cofre-ipad-build.log`, `/tmp/cofre-ipad-install.log`, `/tmp/cofre-ipad-launch.log`, `/tmp/cofre-ipad-logs/latestlog.txt` |
| Physical UI control | agent-device session for the owner iPad mini | BLOCKED: `device_list` exposed simulators only and `device_open` rejected the requested physical UDID; CLI therefore refused to start without a device session | tool output in session; no non-Cofre screen captured |
| Vanilla / loaders / versions / configurations / modpacks | requested launch matrix | BLOCKED pending physical agent-device session; no result claimed | — |

### Physical pass notes
- App process remained present after launch (filtered `devicectl` process list); no new crash was observed in the launch log.
- The app-data log was copied from `Documents/latestlog.txt`; pairing/account files were not printed. Existing system crash index entries were only listed by filename and were not opened.
- No source fix was made because no reproducible launch failure was reachable without the physical UI session.

### Physical pass continuation (2026-10-30 · HEAD 98bd015)

| Instance | Version / loader | Renderer | Configuration | Result | Evidence |
|---|---|---|---|---|---|
| Survival+ | Minecraft 1.21.1 / NeoForge 21.1.265 (22 mods) | Auto → MobileGlues | Balanced/Auto | PASS: launched through Cofre, reached Minecraft title screen, first frame rendered; relaunch returned to Cofre Play | `/tmp/cofre-ipad-neoforge-title.png`, `/tmp/cofre-ipad-logs3/latestlog.txt` |
| Survival+ | Minecraft 1.21.1 / NeoForge 21.1.265 (22 mods) | MobileGlues | Full resolution, manual 1 GB | PASS: launched through Cofre and reached title screen; first-frame markers present; relaunch returned to Cofre Play | `/tmp/cofre-ipad-mobileglues-full-1gb-2.png`, `/tmp/cofre-ipad-logs3/latestlog.txt` |
| Settings | Game settings | — | Renderer picker, Resolution picker, Auto RAM off/manual memory | PASS: Auto, Metal, MobileGlues and other renderer choices visible; Full 2266×1488 selected; Auto RAM off enabled manual slider | agent-device snapshots `s594128`–`s594145` |
| Requested matrix | Vanilla 26.x/1.21.11/1.21.1/1.20.1/1.16.5; Fabric; Quilt; Forge; NeoForge; two packs | — | — | BLOCKED: creating additional instances and game-menu quit were not completed in this pass; no results claimed | — |

### Physical continuation notes
- The NeoForge title-screen launch produced `[Cofre] first-frame source=metal`, `[Cofre] first-frame source=gl/air`, `launch overlay dismissed after first frame`, and MobileGlues renderer markers.
- The game log contains mod/Iris warnings and a `MetallumAgent` `NoSuchMethodException` flow snapshot, but no fatal launch error; this is not a Cofre fix candidate.
- Cofre was relaunched and left on Play. Manual settings remain selected in the instance preferences.

### Physical matrix continuation (2026-10-30 · HEAD 98bd015)

| Instance | Version / loader | Renderer | Result | Evidence |
|---|---|---|---|---|
| Vanilla263 | Minecraft 26.3 / Vanilla | Metal preflight; incompatible Iris/Sodium warning offered Turn off and play | PASS: Cofre explained the 26.3 Metal incompatibility, Turn off and play proceeded, Minecraft 26.3 title screen rendered | `/tmp/cofre-ipad-v263-title.png`, agent-device warning snapshot `s417692` |
| Vanilla12111 | Minecraft 1.21.11 / Vanilla | Auto → Metallum selection, Air resolved EGL to ANGLE | FAIL: black screen; GUI shaders failed to compile and framebuffers were zero-sized. Root cause is Air’s Metal-to-auto handoff resolving to ANGLE on Java 8 | `/tmp/cofre-ipad-v12111-title.png`, `/tmp/cofre-ipad-logs4/latestlog.txt` |
| Vanilla263 / Vanilla12111 | world entry and game-menu quit | — | BLOCKED: game surface exposes only Keyboard/Close to agent-device; touch taps did not activate Singleplayer, so no world-entry claim is made. Game process was terminated and Cofre relaunched between cases | screenshots above; process/relaunch logs |
| Remaining requested cases | 1.21.1, 1.20.1, 1.16.5, Fabric, Quilt, Forge, packs, FPS comparison | — | BLOCKED pending remaining device time; no results claimed | — |

### Matrix notes
- 26.3’s preflight warning correctly identified incompatible Iris/Sodium and provided a safe “Turn off and play” path; no Cofre fix needed.
- 1.21.11’s failure is reproducible and needs an Air-side renderer-selection fix. I did not edit upstream or consume the exhausted patch budget.
- Player flow requires a full Cofre relaunch after each game process; relaunch returned to Play reliably.
