# Unattended overnight testing on the physical iPad mini

Research only (2026-10-31). Nothing here is implemented. When this file and the code disagree, the code wins.

Target: **iPad mini 6 · iPadOS 27.0 · `COFRE_DEVICE_UDID` · USB to the Mac mini · Xcode 27.1**

Checked on this Mac today (read-only):
- `devicectl list devices`: the iPad shows `connected`, wired, paired.
- `devicectl device info lockState`: `passcodeRequired: false`, `unlockedSinceBoot: true`.
- The developer disk image (cryptex DDI) and XCTest services are available.
- `agent-device` 0.21.31 already built its physical runner here on Oct 30 (`~/.agent-device/apple-runner/derived/ios-device`, session `cofre-ipad`). `plan/TESTING.md` § "Driving the real iPad mini" has the env vars.

## TL;DR: recommended setup

```
            ┌──────────── Mac mini (caffeinate, never sleeps) ────────────┐
 Agent ──▶  │ 1. scripts/scenario.sh   headless: devicectl + -cofreScenario│ ── USB ──▶ iPad mini
            │ 2. agent-device CLI      UI: XCTest runner, AX tree, taps    │            no passcode
            │ 3. devicectl             screenshot · reboot · logs · kill   │            auto-lock Never
            └──────────────────────────────────────────────────────────────┘            charging
```

| # | Layer | Use it for | Why |
|---|---|---|---|
| 1 | **Headless scenarios** (`scripts/scenario.sh`) | JIT, real game launches, modpacks, mods, memory (`memoryMB`) | No UI driver and no XCTest runner using RAM. Already works. The log is the oracle |
| 2 | **`agent-device` CLI**, physical mode | UI flows: taps, typing, AX snapshots, alerts, recording | Already set up, MIT, XCTest-based, has an `alert` command. The same tool as on the simulators |
| 3 | **`xcrun devicectl`** (Xcode 27) | Screenshot, kill/launch, copy files, reboot, lock state, memory warning | Apple-native, no tunnel daemon. Xcode 27 brought back `capture screenshot` |

**Fallback:** if `agent-device` breaks after an Xcode or iPadOS update, run headless only (layers 1 and 3), which keeps all the game, JIT and memory testing. Then, only if UI driving is needed, use Appium WebDriverAgent through `mobile-mcp` or `go-ios`.

## 1. Options compared

| Tool | Tap/type/swipe | Screenshot | AX tree | Launch/kill | Logs | Dev-signed app | USB / Wi‑Fi | Needs | Health in 2026 |
|---|---|---|---|---|---|---|---|---|---|
| **agent-device** (Callstack) | ✅ (2-finger in Oct ’26) | ✅ via runner (devicectl crop is iPhone-only) | ✅ XCTest | ✅ CoreDevice | ✅ `logs start` | ✅ (runner signed with your team) | USB (usbmuxd) | Dev Mode, runner signing | 🟢 very active; iPad gaps: [#3899] windowed-app tap offset |
| **devicectl** (Xcode 27) | ❌ | ✅ `device capture screenshot` | ❌ | ✅ | ⚠️ files only (`copy from`) | ✅ | USB + network | Dev Mode | 🟢 Apple; flags change per Xcode |
| **XCUITest target in Cofre** (`xcodebuild test-without-building`) | ✅ | ✅ attachments | ✅ | ✅ | xcresult | ✅ | USB / network | a UI-test target + signing | 🟢 Apple; compiled tests, not agent-driven |
| **Appium + WDA** | ✅ | ✅ | ✅ | ✅ | ✅ syslog | ✅ (sign WDA yourself) | USB, Wi‑Fi | rebuild WDA per Xcode/iOS | 🟡 WDA breaks on new Xcode ([#21643], [xcuitest #2978]: preinstalled WDA quits after about 20 s with Xcode 27) |
| **mobile-mcp** | ✅ (WDA) | ✅ | ✅ | ✅ | ❌ | ✅ | USB (go-ios forward) | go-ios tunnel + WDA running | 🟡 manual WDA start ([wiki]) |
| **Maestro** | stock: ❌ on physical iOS | | | | | | | | 🔴 2.10 still `TODO()` on device; community bridge only ([PR], [devicelab]) |
| **pymobiledevice3** | ❌ (no input) | ✅ `developer dvt screenshot` | ❌ | ✅ | ✅ `syslog live` | ✅ | USB + Wi‑Fi | `sudo … remote tunneld` | 🟢 good for logs/location/screenshots ([recipes]) |
| **go-ios** | via WDA (`ios ui run wda`) | ✅ | ❌ (audit only, iOS ≤18) | ✅ | ✅ | ✅ | USB + Wi‑Fi | `sudo ios tunnel start` | 🟢 v1.3.2 Aug ’26 ([go-ios]) |
| **idb** (Meta) | | | | | | | | | 🔴 no CoreDevice since iOS 17 ([idb #853]) |
| iPhone Mirroring / QuickTime / Switch Control | ❌ / view only / fragile | | | | | | | | 🔴 no iPad mirroring; no API |

Notes:
- The `-cofreScenario` launch argument and file copy need CoreDevice (`devicectl`). The iPad has it.
- `agent-device` deep links, logs and recording also need CoreDevice. It falls back to its XCTest backend only for iOS 15/16 ([#1375]).

## 2. Staying unblocked all night

| Blocker | Fix | Once or per run |
|---|---|---|
| Auto-lock / sleep | Settings › Display & Brightness › Auto-Lock **Never**; keep it plugged in | once |
| Passcode / USB Restricted Mode | **No passcode** on this test iPad (already `passcodeRequired:false`). XCTest can't type a passcode | once |
| Mac sleep drops USB | `caffeinate -dimsu -w <agent pid>` for the run | per run |
| "Trust this computer" | Already paired; never unpair. Supervision can block other hosts | once |
| Developer Mode | On; survives reboots. Turning the passcode off doesn't reset it | once |
| DDI after reboot | iOS 17+ remounts it automatically on the next `devicectl`/XCTest use | auto |
| VPN "Add VPN configurations" | Accept once by hand (or `agent-device alert accept`). Upgrade installs keep it; **uninstalling erases it** ([personal VPN]). Only MDM-pushed VPN profiles skip it ([forum]) | once per uninstall |
| Local Network prompt | The app declares `NSLocalNetworkUsageDescription` → allow once by hand | once |
| Crash dialogs / "app may slow down" | `agent-device alert get` → `alert dismiss`/press label; the headless path doesn't care | per event |
| Notifications covering UI | Focus › Do Not Disturb on, all day | once |
| Overnight iPadOS update + reboot | Software Update › Automatic Updates **off** (a surprise 27.x can also outpace Xcode) | once |
| Windowed apps shift taps | Multitasking › **Full Screen Apps** (not Windowed / Stage Manager) ([#3899]) | once |
| Rotation | Lock portrait or set it with `devicectl device orientation set` | per run |
| Heat during back-to-back launches | 2–3 min cooldown between game launches. Log `thermalState` (see §5) and skip launches at `serious`+ | per launch |
| Low Power Mode prompt | Keep it plugged in; Low Power Mode off | once |
| Runner eats RAM during memory tests | **`agent-device close` before any game or memory scenario** (inference: the XCTest runner plus AX on a 4 GB iPad) | per launch |

Guided Access, Single App Mode and Autonomous Single App Mode (ASAM): **don't use them.** They lock the iPad to Cofre, which blocks the XCTest runner app and Settings. ASAM needs MDM ([esper]). Supervision needs an **erase** ([Apple 102291]), which means re-pairing and a new pairing file. Only worth it if Settings-level hardening proves insufficient (see open questions).

## 3. One-time manual steps (Ignacio)

1. iPad Settings:
   - Auto-Lock: Never
   - Passcode: off (test device only)
   - Automatic Updates: off
   - Do Not Disturb: on
   - Multitasking: Full Screen Apps
   - Low Power Mode: off
   - Keep it plugged into the Mac mini (a powered port)
2. Confirm Developer Mode is on (Settings › Privacy & Security).
3. Open Cofre once: allow **Add VPN configuration**, allow **Local Network**, and run Test JIT once with the pairing file already imported.
4. The runner signing is already done (`AGENT_DEVICE_IOS_TEAM_ID`, …, in `plan/TESTING.md`). After each Xcode update, run one `agent-device open` while you're awake. The first build takes about 4 min and may need `-allowProvisioningUpdates` approval.
5. Mac mini: Energy › prevent sleep when the display is off (or rely on `caffeinate`).
6. Tell the agent which time window, which scenarios, and whether it may reboot the iPad.

## 4. How the agent drives it

```sh
D=COFRE_DEVICE_UDID; B=com.ignacio.cofre
AD="node $AGENT_DEVICE_CLI"
export AGENT_DEVICE_IOS_TEAM_ID=… AGENT_DEVICE_IOS_RUNNER_APP_BUNDLE_ID=… AGENT_DEVICE_IOS_RUNNER_TEST_BUNDLE_ID=…

# Health check (every loop)
xcrun devicectl list devices | grep "$D"               # connected?
xcrun devicectl device info lockState --device $D      # passcodeRequired:false

# Headless game / JIT / pack / memory test
scripts/scenario.sh scripts/scenarios/fabric-1.21.1-sodium.json --timeout 1200   # → PASS in-game | FAIL …

# UI flow
$AD open $B --platform ios --udid $D --session cofre-ipad
$AD snapshot -i --session cofre-ipad                   # AX tree with @refs
$AD press @e12 --settle --session cofre-ipad
$AD fill 'label="Search"' "sodium" --settle --session cofre-ipad
$AD alert get --session cofre-ipad                     # then accept / dismiss
$AD screenshot --out /tmp/cofre-device/shots/x.png --session cofre-ipad
$AD close --session cofre-ipad                         # ALWAYS, before game launches

# Evidence without the runner
xcrun devicectl device capture screenshot --device $D --destination /tmp/cofre-device/s.png
xcrun devicectl device copy from --device $D --domain-type appDataContainer \
  --domain-identifier $B --source Documents/latestlog.txt --destination /tmp/cofre-device/latestlog.txt
```

Screenshots go to the agent with the Read tool (PNG). The AX tree comes from `snapshot -i` text output. Game frames have no AX nodes: use screenshots plus `[Cofre]` log markers.

### Recovery ladder (try each step at most twice, then go to the next)

| Symptom | Step |
|---|---|
| Ref stale / element missing | `snapshot -i` again, then `alert get` |
| Unknown alert | `alert get` → press its label → screenshot evidence |
| App frozen | `devicectl device process terminate` → `$AD open $B --relaunch` |
| Runner errors / `APP_NOT_RUNNING` loops | `$AD close`, `$AD daemon stop --state-dir ~/.agent-device`, reopen |
| devicectl times out | `devicectl device reboot --device $D`, wait until `connected`, re-run health check; VPN must come back (see §5) |
| Still offline after reboot | stop the run, write `blocked: device offline` in `plan/testing-log.md`. Don't loop all night |

## 5. Repo additions to consider (list only)

| Add | Why |
|---|---|
| `scripts/device-health.sh`: connected, lock state, free space, battery/thermal, DDI | One call for each loop; exits non-zero with a reason |
| `scripts/overnight-device.sh`: queue of scenarios, cooldown, retries, summary table | Runs unattended without agent tokens between steps |
| Scenario fields: `expectFirstFrame`, `stayInGameSeconds`, `quitAfter`, `expect: "oom"` | Verify the first frame and memory limits, not just `inGame` |
| Log `[Cofre] thermal=… battery=… memFootprint=…` at launch and on exit | Heat and memory evidence from the log alone |
| VPN auto-start in scenario mode, plus a `[Cofre] vpn=up` marker | After a reboot, JIT must come back with no taps |
| `accessibilityIdentifier`s on key CofreUI controls (0 today) | Stable selectors across copy changes; fewer coordinate taps |
| A `cofre://test/...` deep link (Debug only): open a screen, seed state | Skips long tap paths; works through `devicectl process openURL` |
| Debug-only `isIdleTimerDisabled = true` while a scenario runs | Belt and braces against auto-lock |
| Optional: `CofreUITests` XCUITest target | Apple-native fallback if `agent-device` breaks; replays the core flows |
| Redaction check in `scenario.sh` (fail if a pairing or key pattern appears in copied logs) | Enforces rule 9 |

## 6. Risks

| Risk | Mitigation |
|---|---|
| Each Xcode release changes devicectl flags (screenshot was removed in 26, back in 27 ([#132])) and breaks WDA/runners | Smoke-test `agent-device open` and `scenario.sh` after every Xcode update, while you're awake |
| An iPadOS 27.x update outpaces Xcode's DDI support | Automatic updates off; update the iPad and Xcode together |
| Apple tightening JIT/TXM or developer services | The headless log tells you. Out of scope for this tooling |
| Pairing-file leaks | Never `copy from` the whole container or Documents/*; never `type`/`fill` pairing data (agent-device logs args in `~/.agent-device/logs`); no sysdiagnose uploads; only screenshot Cofre |
| Account tokens in logs | `scenario.sh` already redacts `accessToken/uuid/xuid`; keep it that way for every new script |
| The iPad becomes "unavailable" over USB (cable, hub) | Direct port, Apple cable; the health check stops the run instead of looping |
| Heat and battery wear from overnight charging | Cooldowns; stop on `thermalState ≥ serious` |

## Open questions for Ignacio

1. OK to keep the iPad **passcode-less** with Auto-Lock Never (test device only)?
2. May the agent **reboot** the iPad as a recovery step? Does Cofre's VPN/JIT come back without a tap after a reboot?
3. Supervision (requires erase and re-pairing): skip for now? Recommended: yes, skip.
4. Is a Microsoft test account on the iPad OK for real launches, or offline/demo only?
5. Scope tonight: headless scenarios only, or UI exploration too?
6. Which of the §5 additions to build first? Suggested: `device-health.sh` + thermal/memory log markers + VPN auto-start.

## Sources

- agent-device: local `help physical-device` / `help ios-system-ui` (v0.21.31) · [#132] · [#1375] · [#3838](https://github.com/callstack/agent-device/pull/3838) · [#3839](https://github.com/callstack/agent-device/pull/3839) · [#3895](https://github.com/callstack/agent-device/pull/3895) · [#3899]
- devicectl: `xcrun devicectl help device …` (Xcode 27.1, local)
- Maestro: [devicelab] · [PR]
- Appium/WDA: [#21347](https://github.com/appium/appium/issues/21347) · [#21643] · [xcuitest #2978]
- mobile-mcp: [wiki] · [mcp-ios-device](https://github.com/mgcrea/mcp-ios-device)
- pymobiledevice3: [recipes] · go-ios: [go-ios] · idb: [idb #853]
- Apple: [supervision](https://support.apple.com/guide/deployment/about-device-supervision-dep1d89f0bff/web) · [Apple 102291] · [personal VPN] · [forum] · [Apple Business](https://www.apple.com/newsroom/2026/03/introducing-apple-business-a-new-all-in-one-platform-for-businesses-of-all-sizes/) · [esper]

[#132]: https://github.com/callstack/agent-device/pull/132
[#1375]: https://github.com/callstack/agent-device/pull/1375
[#3899]: https://github.com/callstack/agent-device/issues/3899
[devicelab]: https://devicelab.dev/blog/maestro-ios-real-device-testing
[PR]: https://github.com/BlueShork/maestro-ios-device/pull/1
[#21643]: https://github.com/appium/appium/issues/21643
[xcuitest #2978]: https://github.com/appium/appium-xcuitest-driver/issues/2978
[wiki]: https://github.com/mobile-next/mobile-mcp/wiki/Getting-Started-with-iOS-Real-Device
[recipes]: https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/cli-recipes.md
[go-ios]: https://github.com/danielpaulus/go-ios/releases/tag/v1.2.0
[idb #853]: https://github.com/facebook/idb/issues/853
[Apple 102291]: https://support.apple.com/en-us/102291
[personal VPN]: https://developer.apple.com/documentation/networkextension/personal-vpn
[forum]: https://developer.apple.com/forums/thread/806802
[esper]: https://www.esper.io/blog/what-is-single-app-mode
