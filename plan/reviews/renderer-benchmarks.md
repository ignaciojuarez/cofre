# Renderer benchmarks on device

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
| 10-31 | 1.21.11 | vanilla | Metal (Air agent, repaired) | ✅ | ✅ title | ~30 title | 1355 | Steady after the 9e678ca agent repair |
| 10-31 | 1.21.11 | Fabric + Graft iOS port + **Sodium** | Metal (Graft) | ✅ | ❌ crash | — | 811 | `There is no OpenGL context current` in `MetalGpuDevice.createIdleGlContext`: Graft makes an idle GL context for Sodium, iOS has none. Marked broken in known-mods.json |
| 10-31 | 26.2 | vanilla | Metal (Air agent) | ✅ | ❌ crash | — | 789 | After Cofre's Spv preload (59dd735 → f0bde51): starts on Metal, then `NoClassDefFoundError IrisMetalTerrainBridge` in the first GUI frame (Air picked `classes262iris/`). b847d19 forces `classes262/`; device run pending |

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
| 26.2 | ⚠️ Air agent crashed 10-31 (slf4j) | ✅ MetalUniversal 1.0.4 + Sodium 0.9.0 | ✅ NeoForge via Connector + MetalUniversal (10-31) | Upstream Metallum lists Sodium + Iris for 26.2; Iris still fails |
| 1.21.11 | ❌ agent jar bug (fix in progress) | ✅ Graft iOS port (~51 FPS) | ❌ | |
| 1.20.1 | ❌ | ❌ | ❌ | Older than Minecraft's GPU-device layer (1.21.5+) that Metallum plugs into; would need a new backend |
