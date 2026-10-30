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
