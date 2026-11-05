# Renderer benchmarks on device

## How to run Phase 0

```sh
# Mac-only verification; dry-run performs no launches, copies or writes.
bash tests/perf/check.sh
scripts/bench.sh --dry-run --device "$COFRE_DEVICE_UDID"
# iPhone 17 Pro attached to this Mac; debug Cofre installed via scripts/run.sh.
scripts/bench.sh --device "$COFRE_DEVICE_UDID"
# Optional 30-minute collection, then compare saved logs (delta = B minus A).
COFRE_WORLD_SECONDS=1870 scripts/bench.sh --device "$COFRE_DEVICE_UDID"
scripts/perf-summary.sh --skip-seconds 60 --window-seconds 1800 A.txt B.txt
# Default summary: 60-second warmup + 600-second window; window 0 = all remaining.
scripts/perf-summary.sh A.txt B.txt
```

- The suite enables `-cofrePerfLog 1`; waits up to 3600 seconds per install/join;
  collects **670 seconds after world join** (60 warmup + 600 steady + sampling margin).
  `--device` / `--timeout` pass through; `COFRE_DEVICE_UDID` also works. `scenario.sh`
  has **no relay flag**: run on the attached Mac.
- Evidence: `artifacts/bench/<UTC timestamp>/<scenario>.txt`, `.runner.txt` verdicts,
  `summary.txt`, `vanilla-ab.txt`. Failures retain logs and the suite continues,
  exiting nonzero for failed verdicts, game exits, logged backend mismatches,
  missing logs or incomplete windows.
- Every case requests **Bench, seed 1337, render 12, simulation 8, resolution 1.0,
  VSync, 120 FPS cap**, written before launch. Matching seeds/settings do not imply
  identical terrain across versions/worldgen mods. Keep orientation, brightness,
  power and starting temperature consistent; cool before repeats. Sequential cases
  inherit heat: read the thermal timelines.

| Case / A/B | Purpose |
|---|---|
| A: vanilla 26.3 Metal | Baseline frame pacing and Metallum memory climb |
| B: vanilla 26.3 Vulkan/MoltenVK vs A | Isolate the vanilla backend; verify **Vulkan** actually logged |
| C: Fabric 26.2 Metal + Sodium 0.9.0 + 28 additions | Representative client/performance workload; 30 pinned jars including MetalUniversal/libraries |
| D: NeoForge 26.2 Metal + existing 100-mod list | Large-pack heap, GC and code-cache pressure; C/D is not a loader-only A/B |
| Same case/build, change one JIT/GC/cache/heap setting | Compare its two saved logs to isolate that experiment |

Read **FPS average**, **min** (1%-low proxy), **frame p95 proxy**, footprint growth
MB/s, thermal durations, GC pauses, code cache and outside-bundle dylib count.
Frame p95 is nearest-rank p95 of logged five-second p95 values, not individual frames.
Warmup starts at the first post-join perf sample, otherwise perf `t=0`. FPS/frame
metrics use the steady window; memory/thermal/GC/cache cover the whole log. Thermal
states persist to the next sample, with no extrapolation; missing instrumentation
prints **N/A**. Cache peak uses aggregate `max_used` or summed heap peaks (an upper
bound). **+2–3 MB/s** matches the known leak; **CodeCache is full** means compilation
stopped. Require **PASS in-world**, **600 observed steady seconds**, expected backend,
and no game exit.

Fabric's 29 Modrinth builds (Sodium plus 28 additions) were checked on **2026-11-05**
through `project/<slug>/version?game_versions=["26.2"]&loaders=["fabric"]`, including
required dependency closure; versioned URLs pin the files. No Iris/shaders or
applicable broken-Metal catalog entries. Published support still needs an iOS check.
D reuses all 100 existing NeoForge slugs and its Connector/Launchpad/FFAPI/MetalUniversal
kit; those slugs resolve current compatible versions.

**Engine experiments (A/B).** Every bench scenario logs GC pauses and code cache (`"engine": {"logGC": true,
"logCodeCache": true}`). Run one case twice, once with an experiment, and compare:

```sh
scripts/bench.sh --only bench-vanilla-26.3-metal --device "$COFRE_DEVICE_UDID"                     # A
scripts/bench.sh --only bench-vanilla-26.3-metal --engine '{"detachJIT": true}' --device "$COFRE_DEVICE_UDID"   # B
scripts/perf-summary.sh A.txt B.txt
```

Experiments (`EngineOptions`, all off by default): `codeCacheMB` (Air: 64), `compactHeaders` (Java 25),
`collector` (`g1` / `zgc` / `parallel`), `flightRecorder` (JFR chunks in `<game>/cofre-jfr/`), `detachJIT`,
`threadQoS`. 26.3 scenario worlds start from a 26.2-format world that 26.3 upgrades. The Vulkan case forces
Mojang's backend with `--graphicsBackend vulkan`, so the run must log `Using graphics backend Vulkan`. Still
missing from the schema: camera paths and the Metal HUD.

## Recorded results

Measured results only: what launched, what rendered, frame rate, memory, limits. Research and policy proposals live in [renderer-matrix.md](renderer-matrix.md); goals in [../renderer-cleanup.md](../renderer-cleanup.md).

**Targets** (popular setups): latest vanilla (26.3), modded 26.x (Fabric 26.2), 1.21.11 (has Metal support), 1.20.1 (most popular for mods: Forge/Fabric). Goal: run as many as possible on Metal.

**How:** `scripts/scenario.sh scripts/scenarios/<case>.json` with `COFRE_LAUNCH_ARGS="-cofrePerfLog 1"`, then `scripts/perf-summary.sh <latestlog>`. Same spot and settings per run; FPS = average over 60 s after the world loads.

## iPad mini 6 (A15, 4 GB, iPadOS 27)

| Date | MC | Loader + mods | Renderer | Launch | Picture | FPS avg / low | Peak MB | Notes |
|---|---|---|---|---|---|---|---|---|
| 10-31 | 26.3 | vanilla | Metal | ✅ | ✅ | — | 2412 → OOM | World at 8 chunks: iOS killed it. Heap 768 MB that run |
| 10-31 | 26.3 | vanilla | Metal | ✅ | ✅ | — | ~2100 | World at 2 chunks OK |
| 10-31 | 26.3 | vanilla | Metal | ✅ | ✅ | — | 2781 → OOM | Spike +650 MB in 2 s on tapping ⋮ in game |
| 10-31 | 26.3 | vanilla | Metal | ✅ | ✅ | — | — | Video › Graphics Custom→Fast: SIGSEGV in AGXMetal driver |
| 10-31 | 1.21.1 | NeoForge, no mods | MobileGlues | ✅ | ✅ | — | 2867 → OOM | Title OK; creating a world at 8 chunks: OOM |
| 10-31 | 26.2 | Fabric, no mods | MobileGlues | ✅ | ⬛ black | — | — | All shaders fail: ANGLE context is GLES 2 (`'es' : invalid version directive`) |
| 10-31 | 26.2 | Fabric + Sodium + Iris | MobileGlues | ✅ | ⬛ black | — | — | Same |
| 10-31 | 26.2 | Fabric + Sodium + Iris | ANGLE | ✅ | ⬛ black | — | — | |
| 10-31 | 26.2 | Fabric + Sodium | Metal (Air agent forced) | ❌ | — | — | — | IllegalAccessError under Fabric's Knot loader |
| 10-31 | 26.2 | Fabric + Sodium + Iris | Metal (Air agent forced) | ❌ | — | — | — | Stock Iris needs OpenGL |
| 10-31 | 26.2 | Fabric, no mods | MobileGlues (after 097a82f) | ✅ | ✅ title | — | 1158 | Black screen fixed; title only (UI-automation sheet blocked taps) |
| 10-31 | 26.2 | Fabric + Sodium + Iris | MobileGlues (after 097a82f) | ✅ | ⬛ black | — | 1149 | Still black with Sodium/Iris |
| 10-31 | 26.2 | Fabric + **Metallum mod 1.0.4** + Sodium 0.9.0 | Metal (mod) | ✅ | ❓ screenshot black | **~57 / 55** (title) | 1104 | Run A: `Using graphics backend Metal`, steady 17.9 ms frames, thermal serious. Run B (same files): picked GlBackend → crash `no OpenGL context`. Flaky; investigating |
| 10-31 | 26.2 | Fabric + **Metallum mod 1.0.4** + Sodium 0.9.0 | Metal (mod, canonical handoff) | ✅ | ⬛ black after first frame | **57.2 / 55** (t=60 s) | 1015 | Fresh process: `libmetallum.dylib`, `AMETHYST_METAL=1`, Metal/A15/CAMetalLayer; no GL crash. The screenshot stayed black despite Metal drawables, so visibility is still unresolved. |
| 10-31 | 26.2 | Fabric + **MetalUniversal 1.0.4 (stock)** + Sodium 0.9.0 | Metal (mod, after 062e3e3) | ✅ | ✅ title ×3, ✅ world | **57.4 / 34** (world, 60 s; median 59.2) | 1957 | Black screen was the scenario runner deleting the instance at first frame (Fabric lost `.fabric/processedMods`). 4 runs in a row on Metal, all visible. Heap 960 MB; at 1280 MB, opening Create World hit ~2.5 GB and jetsam |
| 10-31 | 26.2 | Fabric + MetalUniversal (own native) | Metal (mod) | ✅ | ✅ title | ~57 (title) | — | No Sodium. Jar's own `libmetallum.dylib` (ad-hoc signed) loads from instance `tmp/` with JIT; stock jar instead loads Air's `Frameworks/libmetallum.dylib` |
| 10-31 | 26.2 | vanilla | Metal (Air agent) | ❌ | — | — | — | `NoClassDefFoundError org/slf4j/LoggerFactory` in `Metallum.<clinit>` |
| 10-31 | 26.2 | Fabric + Metallum mod + Sodium + Iris | Metal (mod) | ❌ | — | — | 677 | Iris: `No GLCapabilities instance set` |
| 10-31 | 1.21.11 | vanilla | Metal (Auto, after 12ee163) | ❌ | — | — | 1377 | `NoSuchMethodError SymbolLookup.findOrThrow`: agent needs Java 22+, game got Java 21. Fix in progress |
| 10-31 | 1.21.11 | vanilla | MobileGlues requested | ✅ | ✅ title | — | — | Air attached the Metal agent anyway and Metal drew; picker choice ignored on manifest versions |
| 10-31 | 1.21.11 | vanilla | Metal (Auto, after 09fd2fa) | ❌ | — | — | — | Java 25 now (`java-25-openjdk`), no `findOrThrow`. New crash: `NoClassDefFoundError com/metallum/agent/ShaderVersionBump`; Air's `metallum_agent.jar` lacks that class |
| 10-31 | 1.21.11 | Fabric 0.19.5 + Graft iOS (before 0077933) | Metal (Graft) | ✅ | — | — | 801 | SIGBUS in `UpcallStub::create` ~5 s after first frame: FFM upcall stubs can't be created on iOS |
| 10-31 | 1.21.11 | Fabric 0.19.5 + **Graft iOS** (0077933), no Sodium | Metal (Graft) | ✅ | ✅ world | **~51 steady** (t≥280 s) / 43 avg incl. chunk load; 1%-low ~32 | 2149 | Title → world (`joined the game` at t≈150 s); thermal serious; Java 25; heap 1024 MB |
| 10-31 | 26.3 | vanilla | MobileGlues requested | ✅ | — | — | 755 | Agent attached too; `Using graphics device: ANGLE … MobileGlues` this time |
| 10-31 | 1.21.1 | NeoForge + JEI + Sodium + ModernFix | MobileGlues | ✅ | ✅ | ~30 (mod-warning screen) | 1236 | ModernFix warns FerriteCore missing |
| 10-31 | 26.2 | NeoForge 26.2.0.93, no mods (Air agent route D) | Metal requested | ✅ | ❌ crash | — | — | Air skips its agent (`manifest has no support for neoforge-26.2.0.93`), falls back to ANGLE GL, clouds shaders fail to link → crash. Route D/noearly can't work without an Air change |
| 10-31 | 26.2 | **NeoForge 26.2.0.93 + Sinytra Connector 3.1.0-beta.4 + Launchpad + FFAPI + MetalUniversal 1.0.4** (no Sodium) | Metal (MetalUniversal via Connector) | ✅ | ✅ world | ~20 first 30 s in world (chunk gen, server tick ~80 ms, thermal serious); steady value not measured yet | 2044 | `Using graphics backend Metal, using drivers: iOS 27.0`; F3 `Metal iOS 27.0`; first NeoForge on Metal |
| 10-31 | 26.2 | NeoForge 26.2.0.93 + Connector kit + MetalUniversal + **Sodium 0.9.0 (NeoForge build)** | Metal (MetalUniversal via Connector) | ✅ | ✅ title | ~58 title, later ~28.6 (thermal serious) | 1477 | Sodium's NeoForge build loads and renders through MetalUniversal; Connector logs harmless `Failed to remove URL from classloader` (PojavClassLoader). In-world not measured |
| 10-31 | 26.2 | NeoForge 26.2.0.93 + Connector kit + **EvilCraft + Cyclops Core** | Metal | ✅ | ✅ title | ~29 title (thermal serious) | 1548 | |
| 11-01 | 26.2 | NeoForge 26.2.0.93 + Connector kit + **100 popular mods** | Metal | ❌ | — | — | 956 | All 100 downloaded (22 min), then NeoForge stopped on missing dependencies: TerraBlender (Biomes O' Plenty), MidnightLib (Cull Leaves), and Vein Miner (the Paper plugin file was installed instead). Installer fix in progress |
| 11-01 | 26.2 | NeoForge 26.2.0.93 + Connector kit + 100 mods (after the installer fixes 28ec92e / a6f1296) | Metal | ✅ | ✅ title | 47–52 on the title screen | 2180 | Every dependency resolved; mods took ~95 s to load before the first frame (Cofre's 60 s first-frame limit wrongly reported a failure, now 10 min for modded). Then `OutOfMemoryError: Java heap space`: the 4 GB iPad leaves only a 768 MB heap. 100 mods need a bigger device |
| 10-31 | 1.21.11 | vanilla | Metal (Air agent, repaired) | ✅ | ✅ title | ~30 title | 1355 | Steady after the 9e678ca agent repair |
| 10-31 | 1.21.11 | Fabric + Graft iOS port + **Sodium** | Metal (Graft) | ✅ | ❌ crash | — | 811 | `There is no OpenGL context current` in `MetalGpuDevice.createIdleGlContext`: Graft makes an idle GL context for Sodium, iOS has none. Marked broken in known-mods.json |
| 10-31 | 26.2 | vanilla | Metal (Air agent) | ✅ | ❌ crash | — | 789 | After Cofre's Spv preload (59dd735 → f0bde51): starts on Metal, then `NoClassDefFoundError IrisMetalTerrainBridge` in the first GUI frame (Air picked `classes262iris/`). b847d19 forces `classes262/`; device run pending |
| 11-01 | 26.2 | vanilla | Metal (Air agent, 87e07a2) | ✅ | ✅ title | ~54 title, ~28 once thermal serious | 1456 | Routing fixed: a single `classes262/` route, `Using graphics backend Metal`. Memory climbs ~3 MB/s while idle on the title screen (828 → 1456 MB in 210 s) |
| 11-01 | 26.2 | Fabric + MetalUniversal + Sodium | Metal (mod) | ✅ | ✅ title | 57 → 28 → 10 (thermal serious, t≈650 s) | 2861 | Left on the title screen for 14 min: memory grew ~2 MB/s, FPS fell to 10. Same climb as vanilla, so it's likely in Metallum's title rendering |
| 11-01 | 26.2 | Fabric + MetalUniversal + Sodium | Metal (mod) | ✅ | ✅ world | **28.6 steady in world** (60 Hz vsync half rate; ~19 avg during the first 15 s of chunk loading) | 2846 | First scripted in-world run (scenario world `Bench`, seed 1337, render 6). Joined 80 s after launch. Memory still climbs ~2.3 MB/s in world (1492 → 2846 MB in 500 s): a 4 GB iPad would run out after ~15–20 min |

## iPhone 17 Pro (A19 Pro, 12 GB)

| Date | MC | Loader + mods | Renderer | Launch | Picture | FPS avg / low | Peak MB | Notes |
|---|---|---|---|---|---|---|---|---|
| 10-30 | 1.21.x | Fabric, <20 mods | GL path | ✅ | ✅ | <20 | — | User report: CPU ~100%, GPU idle, ticks lagging |
| 10-30 | 1.21.x | NeoForge, <20 mods | GL path | ✅ | ✅ | <20 | — | Same |
| 10-31 | 26.2 | **NeoForge 26.2.0.93, 35 mods** (Connector kit + MetalUniversal 1.0.4, EvilCraft, Biomes O' Plenty, Waystones, JEI, Friends&Foes, Villages&Pillages, T&T, Naturalist, Paraglider…) | Metal (MetalUniversal via Connector) | ✅ | ✅ world | 50–58 when chunks settle; dips to 0–30 during worldgen | 3596 | Render 16, simulation 12, Fancy graphics. After the forced-OpenGL fix (c76287d, 260f351): `Graphics backend forced to default by launch argument`, `Using graphics backend Metal`. World load 9.7 s; server 2–3.5 s behind early (CPU-bound worldgen). Thermal fair |

## Can it run on Metal?

| MC | Vanilla | Fabric | Forge / NeoForge | Notes |
|---|---|---|---|---|
| 26.3 / 26.4 / 26.1 | ✅ Air's agent | ❓ Metallum mod (testing) | ❌ | |
| 26.2 | ✅ Air agent (after 87e07a2) | ✅ MetalUniversal 1.0.4 + Sodium 0.9.0 | ✅ NeoForge via Connector + MetalUniversal (10-31) | Upstream Metallum lists Sodium + Iris for 26.2; Iris still fails |
| 1.21.11 | ✅ Air agent (after 9e678ca) | ✅ Graft iOS port (~51 FPS) | ❌ | |
| 1.20.1 | ❌ | ❌ | ❌ | Older than Minecraft's GPU-device layer (1.21.5+) that Metallum plugs into; would need a new backend |
