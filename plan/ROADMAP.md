# Cofre roadmap

The single list of everything planned, in progress, waiting on a decision, or saved for later. Detailed plans
live next to this file; this one links to them. Update the status here whenever work lands.

✅ done · 🚧 in progress · 🎯 next (approved) · 🤔 needs Ignacio's decision · 💤 later · ❌ dropped

## Principles

- **The game's files are the truth** ([architecture](architecture.md)). Cofre adds only what the game can't do
  on a phone: jump straight in (quick play), settings that must be set before launch, file operations
  (backup, import/export, copy, safe delete), and checks before launch.
- **No redundancy.** If the game has it, Cofre says "Change this in game" instead of copying it.
- **Own Air when owning is simpler** ([own-air](own-air.md)). Air stays the engine.
- **Clean objects, no extra layers, ponytail.** One small Swift type per domain, in CofreKit.

## 🎯 Now: approved features (from the design draft)

The screens were drafted by Z in `Screens/Draft/` ([design-draft](design-draft.md)). Each one is built on CofreKit, and the old path it replaces is deleted in the
same step.

| # | Area | What ships | Status |
|---|---|---|---|
| 1 | **Instances** | Duplicate (with or without worlds, APFS clone), export/import `.zip`, delete with undo, groups (★ Favorites first), notes, per-instance Java, RAM (auto/manual), JVM args with safe rollback, loader version. The instance detail gains a "Before you play" tab (engine settings only; presets wait for a decision) | ✅ `a11a782` `5e60ee0` `9fab9ef` `2ed24ee` |
| 2 | **Accounts** | Remove with confirm, "Signed out, sign in again" row state, "Demo / doesn't own Java" warning, banners on Play | ✅ `263ff9b` `1c4e1b3` |
| 3 | **Logs and crash reports** | Live log with search and filter, a redacted share bundle (Settings › Logs › Share report, and the crash screen's Share). This is also step 1–2 of [auto-triage](auto-triage.md) | ✅ `d52e309` `d81b536` `577d44b` |
| 4 | **Worlds** | "Jump back in" on Play (recent worlds, quick play straight in), back up / restore, export / import `.zip`, copy to another instance, delete with undo plus Recently deleted, world cards | ✅ `8615a1e` `7c060fc` |
| 5 | **Content parity** | Resource packs, shaders and data packs get the mods treatment: installed list, on/off, update, delete. "In use" is read-only from the game | 🚧 BG |
| 6a | **Over-the-air updates** | Play banner checks GitHub Releases once per launch and installs signed IPA via manifest | ✅ |
| 6 | **Downloads and versions** | A downloads strip on Play, resume/retry, background downloads, disk-space preflight, a version picker (releases/snapshots) and loader version list | 🎯 |
| 7 | **Modpack import + Files** | Import `.mrpack`/`.zip` from a file or link with staged rollback, "Open in Cofre" from Files and the share sheet | 🎯 |
| 8 | ~~iOS niceties~~ | ❌ Not in the launcher (Ignacio): no heat/Low Power banner or power-saving switches. Big-download Wi-Fi gating stays in Downloads | — |
| 9a | **Own Modrinth client** | Mod pages load slowly because Air fetches every version (hundreds for Sodium). A CofreKit Modrinth client asks for the instance's versions first and the rest in the background | 🎯 |
| 9 | **Engine seam** | Dissolve `CofreBackendAdapter`, the facade protocols and `MockBackend` into CofreKit + `GameEngine` | 🎯 |

Z's variations, recommended picks taken (Ignacio: "I like it all"):
- instances in sections with ★ Favorites first;
- packs and shaders "In use" read-only from the game;
- the Performance pack goes into a copy.

## 🚧 In progress

- **Mod compatibility with the renderer (AH):**
  - a "Not on Metal · 26.3" badge;
  - a warning before Get;
  - a Play-time sheet ("Iris doesn't run here", with Turn off and play).
- **Servers on the real engine:** W's UI (`1cb801d`) plus V's engine (`1feffeb`, `84f1e3d`, now in `CofreKit/Servers.swift`). Still to wire:
  - ping, join, copy, remove and discover in the app;
  - SRV record lookup;
  - `cofre://join` without a card offers Add + Join;
  - a world's Play uses quick play.
- **CofreKit migration:** started in `c379b09`, with servers moved in first.
- **Computed compatibility (BC)** ([compatibility](compatibility.md)): no hand-kept list. A renderer manifest is read from the Metallum jar we ship, mod jars are scanned for declared problems, desktop natives and direct OpenGL/Vulkan use, and shader packs are scanned too. This replaces AH's hand-written table. 💤 Later: dry-run preflight and a crash-learned feed (needs auto-triage).

## 🤔 Waiting on a decision

| Topic | Question |
|---|---|
| **Performance presets** | 💤 Maybe later, not in the launcher for now (Ignacio): the game's own Video Settings own quality and frame rate, and a second set of switches adds room for bugs. Was: Quality / Balanced / Battery tiles, heat-aware lowering, Performance pack ([performance](performance.md), design-draft §6) |
| Design draft open questions (1–8) | Settings › Game and Renderer as "defaults for new instances"? Undo toast instead of confirm for world delete? ~~Shader-crash "Turn shaders off"~~ ✅ yes, built in `5824a14`. Heat-aware on by default? Performance pack on 26.x? Notes and groups in `cofre.json`? Wait for Wi-Fi above 200 MB? `.mcworld` error only? |
| Auto-triage | ⏸ Ignacio: not yet. Report bundle + Share stay; sending, triage and agent PRs wait |
| ✕ in menus | Change the icon to "← Back"? |
| Companion state mod | An optional tiny Fabric mod that reports exact game state (flying, swimming, which screen is open). Low priority |
| Public release | Our own Azure app for Microsoft sign-in; Metallum license and provenance; GitHub publishing (needs approval) ([PUBLIC_RELEASE](PUBLIC_RELEASE.md)) |

## Decided against (for now)

- Performance presets (Quality/Balanced/Battery), heat-aware lowering, the Performance pack, and heat/Low Power banners.
  They duplicate the game's Video Settings and add room for bugs. The existing engine settings (renderer, memory,
  resolution) stay. The ideas remain in [performance](performance.md) and [design-draft](design-draft.md) §6.

## Done since the roadmap was written

- One dark look; the Look section is gone (`05c873c`).
- A shared CofreKit `Zip` built on Apple's Compression framework (`65f2e01`).
- Computed mod compatibility (`24fb0af`): the hand-written table is gone.
- A 15-second whole-app compile check for agents, which catches glue build breaks.
- NeoForge 1.21.1 runs on the iPad (2026-10-30): installs no longer deadlock and turn on JIT first (`bc3fbcc`, `8dba0f9`), the early window is off (`0470adf`), LWJGL is visible to its modules (`fcdef38`), and Auto picks MobileGlues for Forge/NeoForge before 1.21.11 (`fb248bd`).
- Cofre's crash screen shows for every game exit, including before the first frame (`0470adf`, `1ccd23a`).
- One bounds-checked NBT reader for servers.dat and level.dat (`3441443`); a saved world can't crash Cofre at launch.

## Known issues

| Issue | Plan |
|---|---|
| Changing Graphics, mipmaps or resource packs mid-game crashes Metal (Metallum reload; binary only) | The crash screen explains it (`ea3be34`); set them before launch; report upstream |
| On MC 26.3, Metal runs no Iris or Sodium (Metallum supports Iris only on 26.2, Sodium on 1.21.11 and 26.2); Distant Horizons needs GL | Crash naming (`e2fa287`) + AH's warnings |
| Metallum writes a log line per draw call (7 MB in 3 minutes), which likely costs FPS | Find a log-level switch or filter (performance #4) |
| Touch overlay checks for "menu open" 10 times a second | An Air hook folded into an existing patch |
| Metal on 1.21.11 is a black screen: the bundled Metallum lists 1.21.11, but Air loads its agent only for Minecraft 26+ | Auto uses Metal only on 26+ (`[Cofre] renderer auto`); enabling 1.21.11 needs Air's gate changed (fold into an existing patch) — owner decision |
| MobileGlues FSR turns the screen black: its upscale shader is desktop GLSL 4.50, which ANGLE on iOS rejects | Cofre keeps FSR off (`mobileglues.fsr1_setting = 0` at launch); report upstream to Air/MobileGlues |
| Settings changed in game used to be overwritten at launch | ✅ `0e18921`: the game owns VSync, FPS and language |
| Game untouchable for 45 s after launch | ✅ `aace89e` + the launch state machine `ff659d2` |

## Input and controls

- ✅ Done:
  - Dock / Classic / Minimal layouts and the Controls pane;
  - Auto input mode;
  - keyboard only when needed, with ⌨ toggling it;
  - Cofre owns the hotbar;
  - the old controls editor and Air's two-finger keyboard gesture are gone.
- 💤 Later:
  - edit the layout in place;
  - two-finger pick block;
  - Minimal's swipe-up hotbar;
  - flying, swimming and riding icons (needs game state);
  - let the TouchController mod take over;
  - controller navigation in menus.

## Crash and recovery

- ✅ Done:
  - Cofre's crash screen, with Metal-driver and OpenGL-mod diagnoses;
  - "Play again" rejoins the last world or server (`0af4d10`).
- 🎯 Next: share a report from the crash screen (area 3).
- 💤 Later:
  - crash-safe recovery: back up before loader or content changes, last-known-good profile, quarantine a bad mod;
  - auto-triage steps 3–4 (Mac mini routine, then agent PRs).

## Performance (listed, not started; see the decision above)

1. Metal as the explicit renderer for 26.x, plus a renderer × version × device test matrix.
2. Presets and heat-aware lowering. 🤔
3. Opt-in, version-pinned Performance pack. 🤔
4. Cut Metallum's per-frame logging.
5. Shader/pipeline cache.
6. Per-instance options.txt defaults on first create.
7. Auto-RAM headroom for Metal.
8. AppCDS for faster cold start.
9. Asset prefetch.
10. Game Mode Info.plist keys after validation.

Done already: the frame rate is the game's (`0e18921`), and ProMotion's 30–120 Hz range is on.

## Owning Air ([own-air](own-air.md))

- ✅ Owned already:
  - JIT and the tunnel;
  - the launch screen and launch state;
  - the crash screen;
  - preferences;
  - mod resolution and installed state;
  - servers.dat;
  - logs;
  - touch input and the keyboard;
  - the version catalog;
  - icons.
- 🎯 Next, as part of the areas above:
  - profiles JSON;
  - worlds;
  - content;
  - a Modrinth client;
  - `.mrpack` import;
  - the accounts list;
  - the engine seam.
- Still on Air: JVM, renderers, game surface, input transport, Microsoft sign-in and refresh, Forge/NeoForge installers.
- Patch budget: 5 of 5 used. New hooks are folded into existing patches (0004 now carries the launch hooks).

## Audits

- ✅ Applied:
  - input (AA);
  - launch (AB, applied as AG's state machine);
  - settings ownership (AF).
- 🎯 Still to rerun one at a time (GPT rate limits) and apply:
  - bridge, backend and prefs (AC);
  - SwiftUI app, tests and scripts (AD).

## Release and distribution ([PUBLIC_RELEASE](PUBLIC_RELEASE.md))

- 🤔 Public-release blockers:
  - an Azure app plus Mojang API approval;
  - Metallum license and provenance;
  - GPL source publishing with every build.
- 💤 Llave:
  - rebuild with the lake art;
  - notarize;
  - Windows build.
- 💤 Invite flow and hosting on GitHub Releases. Never cofre.site; never mention iloader.
- 💤 CurseForge key through `request_secret`. Until then CurseForge search shows "needs a key".

## Later (from [missing-features](missing-features.md))

- **P1:**
  - skins and capes;
  - accessibility (Dynamic Type, VoiceOver, Reduce Motion);
  - Shortcuts / App Intents ("Launch instance", "Back up world", "Enable JIT");
  - iCloud backup of worlds and settings;
  - loader upgrade with rollback;
  - modpack update policy;
  - Java runtimes on demand;
  - Swift 6 language mode.
- **P2:**
  - widgets and Live Activity for downloads and launch;
  - Game Center (optional);
  - localization;
  - update notifications;
  - LAN server scan and ping history;
  - world thumbnails and stats.
- **P3 (skip):**
  - news, marketplace and Realms promos;
  - creator social feeds;
  - LAN relay hosting and voice;
  - Air's AI Agent and desktop panels.

## How work runs

- Logic goes to GPT agents and design to Claude agents. At most 6 at once, and GPT runs 2–3 at a time to stay under its rate limit.
- The checkout is shared:
  - commit through a temporary index, then `git reset -- <files>`;
  - take the `.work/.build-lock` before building;
  - for device builds while others have work in progress, build from a clean worktree (`run.sh` uses `cd -P`).
- Install only through `scripts/run.sh` (device set in the local config). Local commits only; publishing needs approval.
- A weekly upstream report runs as a T3 scheduled task ([UPSTREAM_STRATEGY](UPSTREAM_STRATEGY.md)).
