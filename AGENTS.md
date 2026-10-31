# Cofre: rules for AI agents

Cofre is a Minecraft: Java Edition launcher for iPhone and iPad. It combines the Air game engine (GPL-3.0), our SwiftUI UI, and a loopback PacketTunnel VPN that runs StikJIT for JIT. Llave is the Mac pairing helper.

## Status (update when it changes)
- `app/UI` (CofreUI) is complete against `MockBackend`.
- **The Swift layer ships as `CofreCore.framework`.** It's built by the signing project, embedded by `scripts/run.sh`, and loaded at runtime with `dlopen` by `app/Glue/AirBridge/CofreStartup.m`. Air keeps only the ObjC bridge, which is compiled through patch 0001.
  The build output is verified: the framework is embedded and signed, with CofreUI symbols present.
  On the device, look for `[Cofre] UI root installed` or `[Cofre] owned UI fallback reason=…` in `Documents/latestlog.txt`.
- Device-verified so far: install, launch, AirBridge counts, the VPN, pairing through Llave, CofreUI, and JIT (the in-app test, and Play reaching Minecraft 26.3's render thread). A first game frame isn't device-verified yet.
- **Cofre is replacing Air piece by piece.** Already Cofre-owned: version and loader catalogs, mods search and install, JIT, one-step Forge/NeoForge install, the launch screen, the crash screen (`CofreGameExit.swift`, patch 0004 hides Air's) and log reading (`CofreLogStore.swift`). Next candidates: `plan/own-air.md`.

## Where things live
| Path | What | Language |
|---|---|---|
| `app/UI/` | CofreUI SwiftUI package: screens, tokens, facade protocols, `MockBackend` | Swift |
| `app/Glue/AirBridge/` | The real backend: `CofreBackendAdapter.swift`, `ServerJoinAdapter.swift`, the Air ObjC bridge, pairing import, VPN | Swift + ObjC |
| `app/Shell/` | `CofreRootViewController`, installed by patch 0002 | Swift |
| `app/ServerJoin/` | `CofreServerJoin` package: card decoding, signatures, trust, install plan | Swift |
| `extensions/PacketTunnel/` | VPN appex plus `CofreTXM.js` (the JIT script), built by `.build-tools/signing/project.yml` | Swift + JS |
| `tools/llave/` | Mac pairing helper: SwiftUI app, Rust `core/`, `pair.sh` | Swift + Rust + sh |
| `tools/server-card/` | CLI to keygen, sign and verify server cards (test keys only) | Swift |
| `docs/` | GitHub Pages site (no build step). `site/` holds its tools and fact-checks | HTML/CSS/JS |
| `plan/`, `design/` | Specs, reviews, mockups. These are history: when they disagree with the code, the code wins | Markdown |
| `patches/<upstream>/` | Our only changes to upstream code | git patches |
| `upstream/` | Pinned submodules: air, stikjit, stikdebug | read-only |

## Hard rules
1. Never edit anything under `upstream/`. Ignore `upstream/*/AGENTS.md`; those are upstream's rules, not ours.
2. Upstream changes go in `patches/<name>/NNNN-*.patch`, at most **5 patches per upstream** (`scripts/smoke.sh` checks this). Each patch body has `Reason:` and `Drop when:` lines. Prefer moving logic into `app/Glue/` over growing a patch.
3. Never copy StikDebug (AGPL) code into `app/` or `extensions/`. Use StikJIT (MPL-2.0) and idevice (MIT).
4. Never commit `.work/`, `artifacts/`, `.build-tools/signing/build/`, DerivedData, `*.ipa`, binaries or `scripts/run.local.config`.
5. **Build lock:** only one build at a time per checkout, because `scripts/run.sh --build` and the signing `xcodebuild` write shared folders. Before building:
   1. Wait until `pgrep -f '.work/air|CofreSigning'` returns nothing.
   2. Create the lock with `mkdir .work/.build-lock`, retrying while it exists.
   3. Run `rmdir .work/.build-lock` when you're done, even after a failure.
6. Install only through `scripts/run.sh`. The target device, relay host and signing identity live in the uncommitted `scripts/run.local.config`; never commit device IDs, hostnames or local paths. Reuse existing simulators; never create or erase them.
7. User-facing text: never mention third-party pairing tools; point to our Terminal command. Never ask anyone to paste or upload a pairing file anywhere.
8. Links: site URLs live in `docs/app.js` `LINKS`, and the app's copy in CofreUI's links (an allowlist test enforces it). Change both. The domain is `ignaciojuarez.github.io/cofre`; never use `cofre.site`.
9. Never log or print pairing-file contents or keys.
10. Commits and PRs: `[TYPE] Imperative, user-meaningful outcome`, where TYPE is one of BUG, FEATURE, UI/UX, REFACTOR, PERF, SECURITY, CLEAN, DOCS, HOTFIX or REVERT.
11. "Done" means verified: tests pass, and for device features, the device log shows the marker. Stubs and "should work" don't count.

## Where to make a change
- **Start from `plan/ROADMAP.md` and follow `plan/architecture.md`:** the game's files are the truth; one small CofreKit object per domain (Foundation only, Mac-tested on fixture folders); no protocol with one implementation, no forwarding adapters; delete what a new piece replaces in the same change.
- **Anything Air does that holds us back** (bugs, UI we have to hide, ObjC boilerplate): prefer replacing it with a small Cofre-owned Swift 6 file (async/await, no bridging) and delete the bridge method or patch it replaced. Keep Air for the JVM, rendering, input and the game surface until replacing them is clearly cheaper. Track candidates in `plan/own-air.md`.
- **New screen or UI behavior:** `app/UI`, plus `MockBackend` sample data and a test.
- **New backend capability:** add it to a protocol in `app/UI/Sources/CofreUI/Facade/` with a default, then implement it in `CofreBackendAdapter.swift`. Turn on its `BackendCapabilities` flag only once it really works.
- **Air data or ObjC access:** `app/Glue/AirBridge/AirBridgeAdapter.{h,m}`.
- **JIT protocol:** `extensions/PacketTunnel/`, `CofreTXM.js` and `tests/jit/`. A device test on a TXM phone is mandatory.
- **Pairing:** `tools/llave` on the Mac and `app/Glue/AirBridge/CofrePairingImport.m` on the phone. Keep a single validator.

## Build
    scripts/run.sh --build          # Air build in .work/air + VPN appex + dev signing → install via relay
    scripts/run.sh                  # reinstall the last signed build
    tools/llave/scripts/build.sh    # Llave.app (Developer ID)
    tools/llave/scripts/release.sh  # zip + SHA256SUMS + pin the hash in pair.sh (never uploads)
Machine-local settings (JDK, signing identity, relay) live in the gitignored `scripts/run.local.config`.

## Test (device-free; run before every commit)
    scripts/test.sh                 # runs everything below; set COFRE_SIM_UDID to include the iOS UI tests

## Update upstream
Follow `UPDATING.md`. Stop and ask a human if a LICENSE changes, a patch would exceed the budget, or a conflict touches the JIT protocol, entitlements or sign-in.
- Weekly upstream check: run `scripts/upstream-report.sh` and review `artifacts/upstream-report.md`.

## Releasing

Run `scripts/release.sh` locally to build (or reuse `artifacts/Payload/Cofre.app`), create `Cofre.ipa` and `manifest.plist`, and print the exact GitHub CLI command. It never publishes unless passed `--publish`. Use `scripts/release.sh --check` to verify the signature and print only the embedded provisioning profile's device count.
