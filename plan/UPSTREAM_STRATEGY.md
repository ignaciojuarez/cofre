# Cofre upstream strategy

> **Recommendation: choose A now — keep Air as a pinned submodule, keep Cofre-specific code outside it, and run a weekly “spy” report.** Rebase to Amethyst only if Air has no meaningful release or commit activity for **3 consecutive months**, or if Air diverges from Amethyst on a required fix for two update cycles. Do not rewrite the launcher core.

## 1. What we own and what we use

Measured with `git ls-files` and `wc -l` (tracked source files; generated/binary assets excluded):

| Area | Files | Lines | Ownership/use |
|---|---:|---:|---|
| `app/` | 74 | **11,634** | Cofre Swift/ObjC UI, adapters, shell, server-card logic |
| `extensions/` | 3 | **224** | Cofre packet tunnel and TXM script |
| `tools/` | 28 | **2,253** | Llave pairing helper and server-card CLI |
| `scripts/` | 7 | **315** | Cofre build/update/sign tooling |
| **Our tracked code total** | **112** | **14,426** | |
| Air's own code (Natives + JavaApp, excluding vendored trees) | ~600 | **156,901** | UI 78k (replaced by CofreUI), services 41k (mods, downloads, installers, auth, worlds, servers), launch core 37k (JVM boot, GL/Metal bridges, input, JIT/TXM, audio) |
| Third-party vendored in Air (`Natives/external`, `ThirdParty`) | — | **~4,977,000** | JREs, LWJGL, renderers, shader compilers, ZeroTier: not Air's work |
| Air `JavaApp/` | 68 | **9,084** | Air Java-side launcher/services |
| Air `installers/` | 0 | 0 | No directory in this checkout; installers live under Air `Natives` |

About 97% of the Air tree is vendored third-party code. Air's own code is ~157k lines, about 11× ours, and we have already replaced its 78k-line UI. The part we truly depend on is the ~37k-line launch core.

**Strategy refinement (shrink, don't rewrite):** keep Air for the launch core. Move services (mods, downloads, worlds, servers) into Cofre's Swift code when we touch them, as server join already is. If Air ever goes away, forking just the launch core is a manageable job. `upstream/air/ThirdParty` and `lwjgl-lib` contain vendored renderer/runtime source and binaries; JREs, LWJGL, MobileGlues/GL4ES/ANGLE/Metal layers, ZeroTier/idevice and StikJIT remain third-party regardless of architecture. They are not Cofre-owned code.

### Air runtime still used

CofreUI is the replacement shell, but `CofreBackendAdapter` delegates the game lifecycle to Air. Runtime dependencies are:

- JVM launch and Java 8/17/21/25 selection; JIT/TXM launch path.
- LWJGL and GLFW/SDL/input shims.
- Renderer stack and tuning (MobileGlues, GL4ES/Zink/ANGLE/Metal/MobileGL variants as available in the pinned Air tree).
- Microsoft authentication/session handling.
- Minecraft version metadata, Java/library/asset downloads and caches.
- Fabric/Quilt/Forge/NeoForge installers; Forge/NeoForge direct-install paths.
- Mod/modpack services (Modrinth, CurseForge, `.mrpack`/zip handling).
- Touch/controller/controls data and the Air controls editor.
- JIT capability/detection and the native launch bridge.

Cofre replaces Air’s home/navigation UI with **CofreUI** (`Play`, `Instances`, `Mods`, setup, settings, logs, renderer/JIT/account screens). Air screens still presented through `AirScreensAdapter` are the **controls editor** and **Forge installer**; Air’s full-screen game/launch controller remains the launch implementation. The adapter also intentionally leaves Air’s data and launch lifecycle authoritative.

Air extras we do not need to preserve as product identity: its AI assistant, Air update/news/capes presentation, and Air-specific branding. They can remain unreachable while their underlying engine APIs are retained.

## 2. Lineage and activity

**PojavLauncher → Amethyst-iOS (AngelAuraMC) → Amethyst-iOS-MyRemastered (“Air”) → Cofre.** The Air remote is `https://github.com/herbrine8403/Amethyst-iOS-MyRemastered`; `UPSTREAM.lock` pins tag `5.1.0-79-gc4797387` at `c4797387…` (GPL-3.0).

| Project | Evidence window | Activity | People / release signal |
|---|---|---:|---|
| Air | local `git log --since=2026-04-29`; remote above | **1,114 commits** Apr 29–Oct 29 2026: May 7, Jun 72, Jul 459, Aug 194, Sep 303, Oct 79; **1,614** in 12 months | 6-month author counts: yitenchen123 672, herbrine8403 305, Drwei 74, yiyeshi0-hash 41, others 20. Tags: 5.0.0 (Aug 24), 5.1.0 (Sep 30); 25 open issues via GitHub API. Bus factor is effectively 2 maintainers despite several contributors. |
| Amethyst-iOS (AngelAuraMC) | GitHub API `repos/AngelAuraMC/Amethyst-iOS` | **16 commits** Apr 29–Oct 29; last push 2026-10-17; 199 open issues | No GitHub releases; activity is sporadic and has a larger issue backlog. Treat as a useful fallback, not a faster feed. |

Recent Air history directly relevant to Cofre includes Minecraft 26.3, TXM/JIT startup fixes, MobileGlues crash/black-screen fixes, Metal/MobileGL and GL4ES renderer work, dual LWJGL 3.3.3/3.4.1, Forge/NeoForge and OptiFine/modpack fixes, and Java 25 detection (see `git log -- Natives/JavaLauncher.m Natives/resources/ Natives/authenticator/ Natives/installer/`). Air 5.0/5.1 release notes name contributors `yitenchen123`, `herbrine8403`, `yiyeshi0-hash`, `herbrine8403`, and others.

Air adds on top of the AngelAuraMC line: a rebrand, large UI refresh, resource management, CurseForge source, Forge/NeoForge direct install, Minecraft 26.x support, Metal Universal Mod, newer renderer integrations, LWJGL dual runtimes, and synchronization/bug fixes. Cofre needs the engine fixes and installers; it does not need Air’s assistant/news/capes identity.

## 3. Options

Estimates assume one experienced maintainer and a device smoke test for every runtime change.

| Option | Initial effort | Ongoing / month | Risk | Benefit |
|---|---:|---:|---|---|
| **A. Track Air (current submodule, ≤5 patches)** | 1–3 days to automate reports and keep patches small | **4–8 h** | Patch conflicts; Air bus factor | Lowest cost; receives renderer/JIT/MC fixes; preserves clear GPL provenance |
| **B. Rebase on Amethyst-iOS** | **2–6 weeks** to port bridge, build files, and integrations | **8–16 h** | Amethyst is currently much quieter; lose Air-only fixes | Removes one fork hop if Air stalls; closer to original lineage |
| **C. Hard fork Air source + scheduled cherry-picks** | **1–2 weeks** to vendor/normalize source and notices | **16–32 h** | Permanent merge debt; easy to miss security/JIT fixes | Full local control and branding; no submodule friction |
| **D. Clean-room launcher-core rewrite** | **12–24+ months** (multi-person project) | **80–160+ h** | Highest technical and compatibility risk | Maximum architectural ownership; still cannot avoid third-party JVM/renderers/LWJGL licenses and bugs |

A rewrite does not remove the hard dependency class: iOS JVM execution, JIT/TXM, LWJGL/GLFW, renderer implementations, Java libraries/assets, and Mojang/Microsoft service protocols still have to be implemented or integrated.

## 4. Licensing and “ownership”

- Air/Amethyst code is **GPL-3.0**. For A–C, Cofre is a combined/derivative distribution: provide corresponding source (our code, exact upstream commit, patches and build scripts), retain GPL notices and license text, and preserve downstream users’ GPL freedoms. A submodule or vendored copy does not change that.
- A true clean-room rewrite of code not copied from GPL sources could be separately licensed, but interfaces/protocol knowledge and all third-party components still carry their own obligations. A rewrite is not a way to relicense JRE, LWJGL, renderers, StikJIT or idevice.
- **Credits cannot simply be removed.** Copyright notices, license texts and required notices survive a derivative work. Move attribution to an in-app **Licenses/About** screen and source `NOTICE`, and use Cofre name, UI and branding; do not claim Air/Amethyst code as authored by Cofre.
- StikJIT is MPL-2.0; idevice is MIT; bundled JRE/LWJGL/renderers each retain their own licenses. StikDebug is AGPL-3.0 and must not be copied into Cofre’s app/appex.

## 5. Lightweight “spy” mechanism

Existing support:

- `scripts/watch/air.txt`, `stikjit.txt`, and `stikdebug.txt` already list high-value paths (JIT script/launcher, auth, installers, entitlements, integration files).
- `scripts/update-upstream.sh --dry-run` fetches and validates pins, reapplies patches in a temporary worktree, and detects conflicts.

Missing: the updater does not read `scripts/watch/*`, emit a diff summary, or schedule itself. Add a weekly read-only job (T3 scheduled task or GitHub Actions; signing stays on the Mac mini):

1. Fetch Air and Amethyst refs; compare each with `UPSTREAM.lock`.
2. Run `scripts/update-upstream.sh all --dry-run`.
3. For changed commits, filter `git diff --name-status OLD..NEW` through the relevant watch file.
4. Summarize commit subjects, changed watched paths, patch conflicts, and license changes in `artifacts/upstream-weekly.md` (or open a draft PR).
5. Label `worth pulling` when a watched path changes, a release/tag appears, a license changes, or the age threshold is exceeded; otherwise report `no action`.

Never auto-merge or auto-sign. A watched JIT/entitlement/auth change requires the existing human review and device smoke rules in `UPDATING.md`.

## 6. Decision rule

Stay on **A** while Air produces a meaningful fix or release at least once per 3 months and watched patches apply. Switch to **B** when Air is quiet for 3 months *or* Amethyst contains a required fix Air has not carried after two update cycles. Consider **C** only if submodule/build constraints become the bottleneck and we can fund 16–32 maintenance hours/month. Do not choose **D** unless Cofre becomes a staffed launcher platform with a multi-year maintenance budget.

### Sources and commands

- Repository: `AGENTS.md`, `UPSTREAM.lock`, `UPDATING.md`, `plan/PLAN.md`, `scripts/watch/*.txt`, `scripts/update-upstream.sh`.
- Counts: `git ls-files … | wc -l`; tracked source summed with Python `open(...).readlines()`.
- Air activity: `git -C upstream/air log`, `git shortlog`, `git remote -v`, `git tag`; relevant-path log listed above.
- Amethyst/Air issues, pushes, commits and releases: GitHub REST API `GET /repos/{owner}/{repo}`, `/commits`, `/releases` on 2026-10-29.
- Licensing: GPL-3.0, MPL-2.0, MIT and AGPL-3.0 license files/metadata in the pinned upstreams and existing `NOTICE.txt`/plan notes.
