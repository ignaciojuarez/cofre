# Cobble: modded Java Edition on iPhone, one app

> "Cobble" is a placeholder name. Status: plan only, nothing built yet.
> **Distribution:** TestFlight, App Store and Ad Hoc builds remove `get-task-allow`, and without it there is no JIT. So Cobble ships as a **development-signed build installed from a link**: registered UDIDs only, up to 100 iPhones a year, and each build expires after 1 year.

## 1. Architecture

```
┌──────────── Cobble.ipa  (Apple Development, your team, get-task-allow) ────────────┐
│                                                                                          │
│  Host app  ── com.ignaciojuarez.cobble                                                   │
│  ├─ New shell (SwiftUI): Setup wizard · Play · Instances · Mods · Settings               │
│  ├─ Air engine (ObjC, GPL-3.0): JVM 8/17/21/25 · LWJGL · renderers · installers          │
│  │    Modrinth + CurseForge · .mrpack/.zip · Fabric/Quilt/Forge/NeoForge                 │
│  └─ JIT26 client (already in Air): brk #0xf00d / #0x69 → region 64 MB → detach           │
│            │  NETunnelProviderSession.sendProviderMessage {pid, pairing bytes, script}   │
│            ▼                                         ▲ progress / errors                  │
│  PacketTunnel.appex ── com.ignaciojuarez.cobble.tunnel   (separate process, ≤50 MB)       │
│  ├─ Loopback tunnel: route 10.7.0.1/32 only, swap src⇄dst  (our own code, about 60 lines) │
│  └─ JIT helper: StikJIT.xcframework (MPL-2.0, idevice inside)                            │
│       RemotePairing 10.7.0.1:49152 (via utun) → RSD → mount DDI → debugproxy             │
│       → attach(host pid) → UniversalJIT26.js → prepare RX region → detach                │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

| Why it is built this way | Evidence |
|---|---|
| The debugger can't run in the host process because a debugger attached to its own process deadlocks | [StikJIT INTEGRATION.md](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md) |
| An appex is the only second process an iOS app can have, and the packet tunnel stays alive while the app is backgrounded | NE design |
| On TXM devices, a page becomes executable only after an attached debugger writes to it | [Play--CodeGen #34](https://github.com/jpd002/Play--CodeGen/pull/34) |
| Air already attaches the debugger again on TXM and waits for it (5.1.0) | [Air #133](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered/issues/133), `JavaLauncher.m:1254+` |
| Packet tunnels need only a paid team, with no approval step | [Apple DTS](https://developer.apple.com/forums/thread/814047) |

**Fallback (proven, 2 apps):** if spike S1 fails, the tunnel stays built in and StikDebug (rebuilt by us, dev-signed, already done) is the second app, called through `stikjit://enable-jit?bundle-id&pid&script-data`. Air already supports this.

## 2. Build phases

| # | Phase | Output | Effort |
|---|---|---|---|
| 0 | **Spikes (go/no-go)**: S1 StikJIT inside the appex reaches 10.7.0.1 through its own utun (`requiredInterface = virtualInterface` or `IP_BOUND_IF`) and attaches to the host. S2 a **fresh iPhone** that has never seen Xcode gets the Developer Mode toggle after an OTA dev install. S3 on TXM, JIT keeps working **after detach**. S4 Sqim takes a 254 MB IPA and a link that friends can open. | Yes/no for each | 2–3 d |
| 1 | Rebrand and signing: new bundle IDs, appex target, profiles with NE + memory entitlements, `sign-development.py` signs the appex first | Signed IPA | 2 d |
| 1b | Repo and update tooling: submodules, `patches/`, `UPSTREAM.lock`, `update-upstream.sh`, `smoke.sh` (see §7) | Easy upstream pulls | 1–2 d |
| 2 | Built-in loopback tunnel (our own code, no LocalDevVPN license problem) | VPN toggle | 1 d |
| 3 | Built-in JIT: StikJIT in the appex, IPC, pairing import, DDI cache, real error messages | One-tap JIT | 4–6 d |
| 4 | Setup wizard (6 checks) and a JIT/expiry status model | Onboarding | 2–3 d |
| 5 | UI: Horizon-style theme over Air's UIKit screens, plus new Home/Instances/Settings shells. **Reskin, don't rewrite** the 130+ Air view controllers | Polished app | 8–12 d |
| 6 | Distribution tools: UDID intake, `add-friend.sh` (ASC API registers the device, regenerates 2 profiles, re-signs, uploads), install page, source link | 1 command per friend | 2 d |
| 7 | Beta on 3 phones: 17 Pro (TXM), an older 6 GB iPhone, one friend's phone over cellular | Go-live | 3–5 d |

**Total:** about 4–6 weeks for one developer. Phases 1–2 can run alongside phase 0.

## 3. Distribution flow

```
Friend ──UDID (udid.tech or self-hosted profile page)──▶ Ignacio
Ignacio: add-friend.sh NAME UDID → register device → regenerate app+appex profiles → re-sign → upload
Ignacio ──private install link (Sqim, or GitHub Release + itms-services manifest)──▶ Friend
```
- A new friend gets a new build. People who already have it keep working until their next update.
- 100 iPhone slots a year. Removing a device frees its slot only at membership renewal.
- Expiry: the cert/profile lasts 1 year. The app shows a banner when 30 days are left. To fix, re-sign and install over the old app, which keeps the data.

## 4. Friend setup (one computer session, then phone only)

| Where | Step | Time |
|---|---|---|
| Phone | Send UDID | 1 min |
| **Computer (once)** | iloader → Trust → export pairing file → AirDrop to phone. This probably also makes the Developer Mode toggle appear | 10 min |
| Phone | Open link → Install | 3 min |
| Phone | Settings → Privacy & Security → Developer Mode → On → Restart → Turn On | 2 min |
| Phone (Cobble) | Wizard: Dev Mode ✓ → Trust ✓ → Import pairing → Allow VPN → Test JIT → Microsoft sign-in → Play | 3 min |
| After that | Tap Play. JIT and the VPN turn on by themselves. The DDI is mounted again after each reboot | 0 |

## 5. Edge cases

| Risk | Mitigation | Status |
|---|---|---|
| A debugger attached to its own process deadlocks | Run the debugger client in the PacketTunnel appex | ✅ doc |
| Traffic from the appex skips its own tunnel | `NWParameters.requiredInterface = virtualInterface` or `IP_BOUND_IF`. Fallback: StikDebug app | ⚠️ S1 |
| Appex memory limit is 50 MB (jetsam) | Download and verify the DDI in the host, stream it into the appex, drop JSC heaps | ⚠️ measure |
| TXM: must the debugger stay attached? | StikJIT/iCube say prepare all regions, then detach; Air detaches after the first brk with a 64 MB code cache. Play PR says keep it attached. The appex can do either | ⚠️ S3 on 17 Pro |
| App goes to the background or is suspended | The game process is suspended, but the appex/VPN keeps running. Minecraft's RAM makes jetsam kill likely, so autosave and show a "Stay in app" hint | ✅ design |
| User's other VPN (Nord, work, ad-block DNS VPN) | iOS allows only one VPN at a time. Connect only during launch and disconnect after JIT is ready (if S3 passes). Tell the user | ⚠️ |
| iCloud Private Relay | Doesn't touch 10.7.0.1. Split tunnel, no default route | ✅ |
| Cellular only | The tunnel wants Wi-Fi. Without it: connect the VPN, then turn on Airplane Mode, which means single-player only | ✅ doc |
| Pairing file breaks after an iOS update, a reset, or at random | Detect heartbeat −9 and show "Redo pairing (computer)". Tell friends to turn off auto-updates. 26.4 forced RPPairing files | ✅ [guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md) |
| DDI: personalized cryptex image (26.4+), unmounted on reboot, first mount needs internet | Mount again automatically at launch and keep a cached copy. An iOS change can break this, so ship app updates | ✅ doc |
| Developer Mode with no computer | The toggle appears after a dev-signed app is installed (community reports). The friend's iloader session probably triggers it too | ⚠️ S2 |
| Trusting the cert | A paid-team dev build on a registered device should need no Trust step. The wizard shows the fallback path anyway | ⚠️ verify |
| Getting the UDID with no computer | udid.tech, or our own Profile Service .mobileconfig (shows as Unsigned). Stolen Device Protection can add a delay | ✅ |
| 100-device cap, new profile per friend | Script it. Keep a device ledger | ✅ |
| Expires after 1 year | Expiry banner, a calendar reminder, reinstall over the old app | ✅ |
| Memory (increased-memory-limit, extended-VA) | Already in the paid profile. Older 4–6 GB iPhones use Auto RAM, keep packs to about 150 mods or fewer, use resolution 50–70% | ✅ profile |
| iOS 27 | TXM on every device except iPad8,11/12, so the debugger protocol is mandatory. Apple could patch it in any update | ✅ `ProcessInfo+TXM.swift` |
| Microsoft login | Air uses `00000000402b5328` (believed to be the official launcher's ID; reuse is against MS terms). Our own Azure app needs Mojang's allowlist ([form](https://aka.ms/mce-reviewappid), ~1–2 weeks) | ❓ decide |
| Minecraft EULA | Never bundle game files (Air downloads them from Mojang). Require Microsoft accounts that own the game, and hide offline/demo accounts | ❓ decide |
| Licenses | Air GPL-3.0 + StikJIT MPL-2.0 (compatible) + idevice. **Don't copy StikDebug's AGPL code.** Write our own tunnel because StosVPN's license forbids rebranding. Give friends the source (a public fork plus a link in About) | ✅ |
| CurseForge key | Never embed one. Each user pastes their own key (stored in Keychain). Modrinth is the default (official, has hashes). The keyless mcimirror.top fallback is a third party, so make it opt-in and keep "Verify files" on | ❓ decide |
| Storage | App is about 760 MB installed (4 JREs). Each instance is 1–6 GB. Need about 8 GB free. Option: slim IPA plus Java downloaded on demand | ❓ decide |
| Heat and battery | FPS cap, resolution scale, FSR1, Performance HUD. Warn about Low Power Mode | ✅ Air has it |
| Pairing file = full device access | Data protection Complete, never uploaded or logged, delete on reset | ✅ |
| Apple program terms | Dev profiles are for "developing and testing"; registered devices must be "affiliated" people. Small private group is a gray area. StikDebug's own Apple account was terminated | ❓ decide |
| Sqim hosting | Third-party: size and link sharing unverified. Fallback: GitHub Release + Pages manifest (HTTPS) | ⚠️ S4 |

✅ verified (doc or code) · ⚠️ needs a spike or device test · ❓ the user decides

## 6. Open questions (your call)

1. **One app or two first?** Ship the proven 2-app version (Cobble + StikDebug) now, or wait for S1 to pass for the single app?
2. **Apple team:** use the main team, or a separate $99 team so a ban can't touch your other apps?
3. **Microsoft login:** reuse Air's client ID now, or register our own Azure app (1–2 weeks of waiting)?
4. **Accounts:** Microsoft only (needs owning the game), or keep offline accounts?
5. **CurseForge:** each person's own key / Modrinth only / allow the mirror?
6. **IPA:** full (254 MB, every Java version) or slim with Java downloaded on demand?
7. **Hosting:** Sqim, or GitHub Releases + Pages (public source repo either way)?
8. **Name and icon** for "Cobble". Hide Air's AI Agent, news and capes? Keep LAN rooms (Terracotta/ZeroTier)?
9. **Upstream cadence:** follow Air **tags** (stable, about monthly) or `main` (faster fixes, more breakage)? And weekly checks through a T3 scheduled task or GitHub Actions?

## 7. Upstream updates (AI-friendly)

```
cobble/
├─ upstream/                ← pinned git submodules, never edited in place
│  ├─ air/                    herbrine8403/Amethyst-iOS-MyRemastered · GPL-3.0 · tags (1.4 GB, LFS, nested submodules → submodule, not subtree)
│  ├─ stikjit/                StikDebug/StikJIT · MPL-2.0 · main (single-app JIT)
│  └─ stikdebug/              StikDebug/StikDebug · AGPL-3.0 · tags (fallback app only)
├─ patches/<name>/NNNN-*.patch  ← ≤5 per upstream, ≤200 lines; commit body has "Reason:" + "Drop when:"
├─ app/Shell  app/Glue/AirBridge.{h,m}  extensions/PacketTunnel   ← all of our code
├─ scripts/ update-upstream.sh · smoke.sh · build.sh · sign-development.py · add-friend.sh · watch/*.txt
├─ UPSTREAM.lock · UPDATING.md · CHANGELOG.md · NOTICE.txt
└─ .work/<name>             ← generated: worktree at the pinned SHA + patches (gitignored; we build from here)
```

```
update-upstream.sh all ─▶ fetch tags ─▶ newest tag ─▶ .work worktree ─▶ git am --3way patches ─▶ build ─▶ smoke --static
                               │ same SHA → skip          │ conflict → exit 2 + .work/CONFLICT.md (AI follows UPDATING.md)
                               ▼                          ▼ LICENSE changed → exit 5 (human)
                         bump UPSTREAM.lock ─▶ prepend CHANGELOG ─▶ branch upstream/YYYYMMDD ─▶ device smoke ─▶ PR ─▶ add-friend.sh --all
```

| Piece | Design |
|---|---|
| Change ladder (prefer the top) | 1) Overrides at build or sign time (bundle ID, name, icon, entitlements, Xcode settings) → 2) Runtime defaults (Air already has accent/card/text colors) → 3) Adapter `AirBridge` → 4) a patch, as the last resort |
| Planned patches | **Air: 3.** `0001` Makefile links CobbleKit and embeds the appex · `0002` SceneDelegate root-VC hook · `0003` "builtin" JIT enabler → IPC to the appex. **StikJIT: 0** (used as a framework). **StikDebug: 0**: today's 3 local edits become xcodebuild overrides plus `script-data` in the URL |
| `UPSTREAM.lock` | Tab-separated: name · url · track · ref · SHA · SPDX · license hash · date. Pinned now: air `c4797387` (5.1.0+79, device-tested) · stikjit `32287268` · stikdebug `17b1e1d9` (3.1.15+1) |
| `scripts/update-upstream.sh` | One command. Exits 0/1/2/3/4/5, which UPDATING.md maps to actions. `--dry-run`, `--to=REF`, `--export-patches` (after a fix by hand) |
| `UPDATING.md` | Runbook for an AI: run → conflict policy (drop the patch if upstream now does it, otherwise make the smallest fix, ask a human if it touches the JIT protocol, entitlements or sign-in) → device smoke → changelog → PR |
| Static smoke (script/CI) | Patch budget and `Reason:` lines · appex, StikJIT and JS script present · Java 8/17/21/25 · entitlements after signing · no CurseForge key in the binary · NOTICE lists the SHAs |
| Device smoke (10 min) | Setup ✓ → Test JIT on 17 Pro → vanilla title screen → Fabric+Sodium+Iris world → Modrinth install → .mrpack import → MS session → background and return → share logs |
| CI | Weekly: a T3 scheduled task on the Mac mini (or GitHub Actions macOS) runs `--dry-run` and reports or opens a PR. Signing stays on the Mac mini, never in CI |

| Upstream risk | Mitigation |
|---|---|
| Air moves fast (79 commits in a week, mixed CN/EN) and refactors break patches | Track **tags**, not main. Small patch budget. Logic lives in `AirBridge` |
| JIT protocol drift (brk codes, script API, StikJIT integration) means a crash at launch | Watch list forces a mandatory TXM Test JIT. Update Air and StikJIT together |
| iOS update breaks things (26.4 RPPairing, cryptex DDI) | Same script, `--to=<fix tag>`. Friends reinstall from the link |
| Upstream force-pushes, gets deleted or renamed | `merge-base` check → exit 5. Keep mirror forks (also needed for the source offer) |
| **Licenses** | Every build we hand out = GPL-3.0 (Air) + MPL-2.0 (StikJIT) + MIT (idevice), so friends must get the matching source: our repo tag + submodule SHAs + patches + build scripts. AGPL applies only if we ship the StikDebug app. Never paste StikDebug code into our app. A LICENSE change → exit 5 |
| AI over-edits | `upstream/` is read-only, patch budget enforced in `smoke.sh`, "ask a human" triggers |

Drafts (not run): [`UPDATING.md`](UPDATING.md) · [`scaffold/UPSTREAM.lock`](scaffold/UPSTREAM.lock) · [`scaffold/scripts/update-upstream.sh`](scaffold/scripts/update-upstream.sh) · [`scaffold/scripts/smoke.sh`](scaffold/scripts/smoke.sh) · [`scaffold/scripts/watch/`](scaffold/scripts/watch/)

## 8. Design

Mockup: `ui/index.html`. Styled after playhorizon.dev: **Pixelify Sans** for headings and buttons, **Geist** for body text, **Geist Mono** for labels; purple palette (`#0f0d17` page, `#5b3fd6` face, `#9a86ff` accent); 2 px outline blocks with a bevel and a 4 px lip, square corners. The art is our own: the pixel scene, stone and icons are drawn by code and none of Horizon's assets are copied.
