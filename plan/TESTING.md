# Overnight test plan

One agent drives Cofre on two shared simulators all night, through computer use:
**explore → find a bug → log it → fix it (or hand it off) → retest → explore more.**
Results go in [`testing-log.md`](testing-log.md). The code wins over this file when they disagree.

Legend: ✅ testable on the simulator · ⚠️ partly (UI states only) · 📱 device only (log it in the Device queue, never test on a phone)

## 1. Setup

### Simulators (shared pool, read `<local-volume>/Developer/kiwios/docs/simulators.md` first)

| Role | Device | UDID | If busy |
|---|---|---|---|
| iPhone | Momentum Preview (iPhone 18 Pro, iOS 27) | `SIMULATOR_UDID` | Primary phone `SIMULATOR_UDID` |
| iPad | iPad Pro 11-inch (M5, iOS 27) | `SIMULATOR_UDID` | Wait; there's only one |

- `device_list`, then `device_open` with the exact UDID. Never create, clone, rename or erase a simulator; never download runtimes.
- Don't drive a device another thread is using. Preserve other apps and data.
- Restore everything you change (Dynamic Type, appearance, Stage Manager, rotation) before you stop. Shut down only if nobody else needs it.

### Simulator build

> **Verified 2026-10-30 (disposable real-app probe):**
> - Air has `PLATFORM=7` (`iossimulator`) and its Swift target compiles with `SDKPATH=$(xcrun --sdk iphonesimulator --show-sdk-path)`.
> - The normal native recipe is not end-to-end simulator-clean: several commands remain hard-coded to `xcrun -sdk iphoneos` and `actool --platform iphoneos`. Do not run this against `.work/air` during device builds.
> - Existing device payload binaries report `LC_BUILD_VERSION platform IOS` (including Air, renderer dylibs, Java runtime dylibs, and CofreCore). A disposable copy was retagged with `vtool ... -set-build-version 7`, every nested Mach-O was ad-hoc signed, and the VPN plug-in/provisioning profile were removed from that copy.
> - Real bundle ID: `com.ignaciojuarez.cofre`. Install/relaunch: `xcrun simctl install <UDID> <app>` · `xcrun simctl launch <UDID> com.ignaciojuarez.cofre`.
> - Probe result: real Cofre launcher UI runs on both shared devices. It reaches the setup screen; no PreviewHost or mock data was installed. Screenshots: `/tmp/cofre-sim-probe-1793344038/iphone-2.png` and `/tmp/cofre-sim-probe-1793344038/ipad.png`.
> - Installed probe UDIDs: iPhone `SIMULATOR_UDID`; iPad `SIMULATOR_UDID`.
> - This is launcher-only evidence. The full game is not verified: the probe has no PacketTunnel (Network Extension is unavailable in Simulator), no JIT pairing/TXM, and no Microsoft account. Do not enter credentials in logs or files; owner must provide the test account at runtime.
> - JIT/game launch, first frame, VPN setup, pairing, device-only Metal behavior, and Forge/NeoForge JVM installation remain device-only or unverified. Re-tagging is not a release build; a proper simulator build needs simulator-native Air/Java/renderer outputs and a simulator-safe app target.

### Test Microsoft account
- Comes from a secret at run time (`request_secret`, `delivery: "file"`). **Never** write it in the repo, the log, a commit or a screenshot name.
- If sign-in asks for a code or approval only the owner has, stop that area, log it as `blocked`, move on. Max 2 tries (lockouts).
- Sign out at the end only if the owner asked; otherwise leave it signed in.

### Can't test on a simulator (📱)
| Thing | Why |
|---|---|
| JIT, Test JIT, setup checks (Developer Mode, pairing, disk image) | Needs a paired device and StikJIT |
| PacketTunnel VPN | Network Extensions don't run in the simulator |
| Gameplay: first frame, touch overlay in game, crash after launch, Play again | The JVM needs JIT |
| Metal renderer specifics, FSR, Metal reload crash | Simulator GPU isn't the device's |
| Forge/NeoForge installers (if they need the JVM) | If they fail with a JVM error, it's 📱, not a bug |
| Over-the-air update install (`itms-services`) | Device only |
| Cellular, airplane mode, real low storage | No such switches; never cut the Mac's network (shared) |
| Modrinth 429 / timeouts | Cover with CofreKit unit tests (URLProtocol stub), not live |

### Handy commands
```sh
U=<UDID>; B=<bundle>; D=$(xcrun simctl get_app_container $U $B data)
xcrun simctl io $U screenshot /tmp/cofre-test/shots/B-001-1.png      # evidence
xcrun simctl terminate $U $B && xcrun simctl launch $U $B             # kill + reopen
xcrun simctl openurl $U 'cofre://join?server=mc.hypixel.net'          # links
xcrun simctl ui $U content_size extra-extra-extra-large               # restore: large
xcrun simctl ui $U appearance light                                   # restore: dark
grep -a '\[Cofre\]' "$D/Documents/latestlog.txt" | tail -40 | \
  sed -E 's/(accessToken|clientToken|refreshToken|uuid|xuid)([": =]+)[^",[:space:]]+/\1\2<redacted>/gI'
```
- **Files to import:** make them in `/tmp/cofre-test/files/` (never in the repo), then copy into the Files app's
  On My iPhone: `find ~/Library/Developer/CoreSimulator/Devices/$U/data/Containers/Shared/AppGroup -type d -name 'File Provider Storage'`.
- **Oracle:** after every write, check the game file on disk, not just the UI.

| Action | Check on disk (`$D/Documents/…`) |
|---|---|
| Instance create/rename/duplicate/delete | `launcher_profiles.json`, `<instance>/cofre.json`, `.trash/` |
| Server add/copy/delete | `<instance>/servers.dat` (unknown tags and order kept) |
| Content on/off/delete | `mods/`, `resourcepacks/`, `shaderpacks/`, `saves/<world>/datapacks/`, `.cofre-trash/content/` |
| World backup/delete | `saves/`, backups, Recently deleted |
| Accounts | `accounts/*.json` (never print contents) |

## 2. The loop and rules

```
explore an area ─▶ something's off? ─▶ reproduce twice ─▶ log entry (screenshot + log lines)
      ▲                                                        │
      │                       small, safe, in app/UI or app/Glue? ── no ─▶ status: handoff
      │                                                        │ yes
      └── retest exact repro + a neighbour ◀─ checks pass ◀─ smallest fix
```

| Rule | Detail |
|---|---|
| One bug = one entry | Next ID `B-###`. Duplicate? Add a note to the existing entry |
| Reproduce twice | Not reproducible → status `can't-repro`, keep the evidence |
| Evidence | Simulator screenshot (`/tmp/cofre-test/shots/B-###-n.png`) + the relevant `[Cofre]` lines from `Documents/latestlog.txt`, redacted |
| Fix | Smallest change that fixes the cause. No refactors, no new features, no demo data |
| Checks | `cd app/UI && swift test` **and** the whole-app compile check below. Both green or no commit |
| Retest | The exact repro, plus one neighbour (same screen, other device class, or kill + reopen) |
| Commit | `[BUG] <user-visible outcome>` through a temp index; one bug per commit; sha goes in the log |
| Hand off | Upstream, patches, JIT protocol, entitlements, sign-in, pairing, VPN, big redesigns, anything 📱 |

Whole-app compile check (take the build lock per AGENTS.md rule 5 first; release it even on failure):
```sh
(cd .build-tools/signing && xcodegen generate --spec project.yml --quiet && xcodebuild -project CofreSigning.xcodeproj -scheme CofreSigning -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/cofre-test-core CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '^\*\* |\.swift:[0-9]+:[0-9]+: error:')
```

Commit through a temp index (the checkout is shared; never stash, checkout or reset others' files):
```sh
export GIT_INDEX_FILE=/tmp/cofre-idx-test; git read-tree HEAD
git update-index --add <your files>     # or: git diff <files> > /tmp/b.diff && git apply --cached /tmp/b.diff
git commit -m "[BUG] …" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
unset GIT_INDEX_FILE; git reset -q -- <your files>
```

**Never:** edit `upstream/` · add a patch (5/5 used) · install on or capture a physical device · run `scripts/run.sh` ·
print tokens, account data, `accessToken`/`uuid`/`xuid` · paste or open pairing files · push · start sub-agents.

## 3. Feature checklist

Each pass: walk an area on **both** devices, then kill + reopen and check the state survived.

### Play and launch
- [ ] ✅ Play with no account, demo account, expired account: banner and Sign in
- [ ] ✅ "Jump back in" world cards; Back up / Export / Copy to instance / Delete + Undo from a card
- [ ] ✅ Instance picker on Play; Memory and Resolution summaries match Settings
- [ ] ⚠️ Update banner ("Update available · … · What's new"): shows once per launch; Update is 📱
- [ ] ⚠️ Launch screen: Cancel launch, Hide (confirm), Copy log, "Lower memory" path; reaching the game is 📱
- [ ] ✅ "Your pairing key is missing" banner wording (no third-party tool names)

### Instances
- [ ] ✅ Create each loader: Vanilla, Fabric, Quilt, Forge, NeoForge (Forge/NeoForge may be 📱)
- [ ] ✅ Versions: 1.7.10, 1.8.9, 1.12.2, 1.16.5, 1.20.1, 1.21.1, 1.21.11, 26.2, 26.3, a snapshot; Release/Snapshot filter; loader version list; "Couldn't load versions" + Try again
- [ ] ✅ "Add Fabric API" offer on a new Fabric instance
- [ ] ✅ Duplicate with and without worlds; name clash ("Try another name.")
- [ ] ✅ Rename, icon, notes, group, ★ Favorites first
- [ ] ✅ Delete → Recently deleted → Restore; restore when that name now exists
- [ ] ✅ Export `.zip` / `.mrpack` → Share; import it back; Drop to import (iPad drag)
- [ ] ✅ Before you play: Java version, Auto RAM / manual, JVM args (bad args roll back), renderer
- [ ] ✅ Overview / Content / Worlds / Servers tabs; Open in Mods, Open in Play

### Accounts
- [ ] ✅ Sign in with Microsoft (test account); Active marker
- [ ] ✅ Remove (confirm) → "You can sign in again any time."
- [ ] ⚠️ "Signed out · sign in again" row and Play banner (edit expiry only via the app, never by hand-editing tokens)
- [ ] ✅ Demo / "doesn't own Java Edition" warning (if a demo account is available)
- [ ] ✅ CurseForge key: paste, save, remove; "Your own key. Never bundled."

### Mods, resource packs, shaders, data packs
- [ ] ✅ Search: typing fast (debounce, no stale results), empty query, no results, "Can't reach…" + Try again
- [ ] ✅ Filters: per instance, "Only versions for this instance", loader, channel, version; "No versions match these filters"
- [ ] ✅ "Big mods have hundreds" (Sodium): versions load, UI stays responsive
- [ ] ✅ Install with required deps (Mod Menu → Fabric API); optional deps unchecked by default; "Already has …"
- [ ] ✅ Declared incompatibility / "No fit" / "Get anyway"; "Not on Metal · 26.3" badge (Iris, Sodium, Distant Horizons)
- [ ] ✅ Installed ✓ in search; Installed · N; Update / Update N; Switch to older version
- [ ] ✅ On/off ("Installed, off"), Delete, the file moves on disk; "In use" is read-only
- [ ] ✅ Shaders (Complementary, BSL), resource packs (Faithful), data packs (per world)
- [ ] ✅ CurseForge without key: "Browse · needs key", "Add key" goes to Accounts
- [ ] ✅ Mods on a Vanilla instance: "Mods run in their own instance" → New mods instance
- [ ] ✅ Install sheet: Hide · keeps going; two installs at once ("Waiting for the other install")

### Modpacks
- [ ] ✅ Import `.mrpack` from Files (Fabulously Optimized); "Made a new instance"
- [ ] ✅ Import from a link (Modrinth URL)
- [ ] ✅ CurseForge `.zip` without key → clear error, nothing left behind
- [ ] ✅ Bad files: 0 bytes, random bytes renamed `.mrpack`, plain `.txt`, zip with no index, zip-slip (`../../evil`), huge pack, pack for another loader/version
- [ ] ✅ Rollback: kill mid-import → no half instance, no staging leftovers

### Servers
- [ ] ✅ Worlds · Servers switch; empty state; Paste (valid, invalid "That isn't a server address.", empty clipboard)
- [ ] ✅ Ping: online, `example.com` (timeout), `127.0.0.1:1` (refused), `nope.invalid` (DNS); ping bars; "Can't reach server"
- [ ] ✅ SRV: a host with `_minecraft._tcp` (`dig +short SRV _minecraft._tcp.<host>` to find one)
- [ ] ✅ IPv6 `[::1]:25565`, LAN `192.168.1.20:25565`, duplicate address (never added twice)
- [ ] ✅ Recommended: Add (row moves up), Join without saving, Show N more, "Nothing new"
- [ ] ✅ Copy to › another instance; Copy address; Delete (confirm); servers.dat keeps order and unknown tags
- [ ] ⚠️ Join a server needing another version → "Needs X" sheet: Join with <instance>, New X instance (pre-filled), Try anyway
- [ ] ⚠️ Join a modded server with a card → requirements sheet; one that "Won't work on iPhone"; launching is 📱
- [ ] ✅ `cofre://join?server=…` with and without a card, malformed, very long, `cofre://open`, `cofre://settings`; with 0 instances ("Create an instance first")
- [ ] 📱 Writes refused while the game runs ("Close the game first")

### Worlds
- [ ] ✅ Back up → Restore; Export `.zip` → Import world (and `.mcworld` error)
- [ ] ✅ Copy to another instance (older version warning?)
- [ ] ✅ Delete → Undo; Recently deleted → Restore; restore into a clashing name

### Downloads
- [ ] ✅ Downloads strip on Play; Downloads screen; Cancel, Resume, Retry; "Nothing downloading."
- [ ] ✅ Kill the app mid-download → reopen → resumes or offers Retry, no corrupt file
- [ ] ⚠️ "Use cellular data" switch and "Waits for Wi‑Fi" text (real cellular is 📱)
- [ ] ⚠️ Disk-space preflight ("Not enough space"): UI only unless a unit test covers it

### Settings
- [ ] ✅ Renderer per instance; FSR row hidden unless MobileGlues; Auto never shows FSR
- [ ] ✅ Resolution: Full / Balanced / Battery (only where ⅓ is exact) / Custom; size labels; "Sizes between the presets may look uneven"; iPhone vs iPad numbers differ
- [ ] ✅ Memory: Auto RAM, manual slider bounds, "Closes while loading? Lower this."
- [ ] ✅ JVM args / env variables: garbage, huge, emoji → rollback, no crash
- [ ] ✅ Controls: Auto/Touch/Controller/Keyboard, layouts (Dock/Classic/Minimal), button size, opacity, fade, stick area %, Hold to break, left-handed, haptics, look sensitivity, Invert Y, Gyro, Reset touch controls
- [ ] ✅ Storage, Clear cache, Verify files; Credits and licenses open; links are allowlisted

### Logs and reports
- [ ] ✅ Live log, search, filter (Errors/Warnings); empty log
- [ ] ✅ Share report… → `report.zip`: names, account IDs, tokens, server addresses, paths redacted (unzip and grep it)
- [ ] ⚠️ Crash screen paths (memory, Metal reload clue, missing library, mods needing GL, Turn shaders off, Copy details): reachable only via a seeded log, else 📱

### App lifecycle and system
- [ ] ✅ Background/foreground on every screen and mid-sheet; Simulate Memory Warning
- [ ] ✅ Force quit mid-install, mid-import, mid-delete, mid-restore → reopen: consistent state
- [ ] ✅ Rotate (iPhone and iPad), Split View and Stage Manager sizes on iPad, Slide Over
- [ ] ✅ Dynamic Type XS → AX5: no clipped or overlapping text
- [ ] ✅ VoiceOver basics (Accessibility Inspector): every button labeled, order makes sense
- [ ] ✅ Light system appearance: Cofre stays dark-only
- [ ] ✅ First launch on an empty container (no instances, no account, no log)

## 4. Ways to break it

| Idea | Try it on |
|---|---|
| Rapid double/triple taps | Create, Install, Delete, Play, Join, Restore, Undo |
| Type fast, paste 5,000 chars | Search, names, notes, JVM args, server address |
| Emoji, RTL, zero-width, `/`, `..`, `:` in names | Instance, group, world copy, export file name |
| Very long and duplicate names | Instance, duplicate, restore, import |
| 0 instances / 50 instances | Play, pickers, Mods "for" menu, server Copy to |
| Offline first launch (📱) or server down | Versions, search, ping, sign-in |
| Cancel mid-flow | Install sheet, import, sign-in, new instance, launch |
| Switch instance while installing | Mods, modpack, loader install |
| Delete the instance being installed into | Mods install, modpack, server-card install |
| Corrupt or wrong-loader pack | `.mrpack`, `.zip`, world zip |
| Restore a deleted instance whose name now exists | Recently deleted |
| Same thing on iPhone and iPad at once (two installs) | Only if the build uses separate containers |
| Kill the app at each step of a multi-step flow | Everything that writes files |
| Change a setting, kill, reopen | Every Settings row |

When every area has one pass, combine: one idea × one area you haven't paired yet. Note the pairs in the log.

**Suspects to check first** (seen while writing this plan, not yet verified):
- `CofreKit/Modpacks.swift`: `"cofre-import-(UUID().uuidString)"` and the CurseForge `"…/mods/(file.projectID)/files/(file.fileID)…"` strings are missing `\(`. Two imports may share one staging folder; CurseForge pack downloads hit a literal URL.

## 5. Results log

Lives in [`plan/testing-log.md`](testing-log.md). Add a row to the summary table and one entry per bug.

Severity: **S1** crash or data loss · **S2** feature broken · **S3** wrong or confusing · **S4** polish.
Status: `open` · `fixed` · `handoff` · `device-only` · `blocked` · `can't-repro` · `wontfix`.

```markdown
### B-001 · Instances · Duplicate accepts a name that already exists
- Date: 2026-10-31 02:14 · Device: iPad EF17… · Build: <HEAD sha>
- Steps: 1. … 2. … 3. …
- Expected: …
- Actual: …
- Evidence: /tmp/cofre-test/shots/B-001-1.png · `[Cofre] …` (redacted)
- Severity: S2 · Status: fixed · Commit: abc1234
- Retest: repro ✅ · neighbour (iPhone, kill + reopen) ✅
```
