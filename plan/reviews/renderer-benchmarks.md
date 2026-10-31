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
| 10-31 | 26.2 | Fabric + Metallum mod + Sodium + Iris | Metal (mod) | ❌ | — | — | 677 | Iris: `No GLCapabilities instance set` |
| 10-31 | 1.21.11 | vanilla | Metal (Auto, after 12ee163) | ❌ | — | — | 1377 | `NoSuchMethodError SymbolLookup.findOrThrow`: agent needs Java 22+, game got Java 21. Fix in progress |
| 10-31 | 1.21.11 | vanilla | MobileGlues requested | ✅ | ✅ title | — | — | Air attached the Metal agent anyway and Metal drew; picker choice ignored on manifest versions |
| 10-31 | 26.3 | vanilla | MobileGlues requested | ✅ | — | — | 755 | Agent attached too; `Using graphics device: ANGLE … MobileGlues` this time |
| 10-31 | 1.21.1 | NeoForge + JEI + Sodium + ModernFix | MobileGlues | ✅ | ✅ | ~30 (mod-warning screen) | 1236 | ModernFix warns FerriteCore missing |

## iPhone 17 Pro (A19 Pro, 12 GB)

| Date | MC | Loader + mods | Renderer | Launch | Picture | FPS avg / low | Peak MB | Notes |
|---|---|---|---|---|---|---|---|---|
| 10-30 | 1.21.x | Fabric, <20 mods | GL path | ✅ | ✅ | <20 | — | User report: CPU ~100%, GPU idle, ticks lagging |
| 10-30 | 1.21.x | NeoForge, <20 mods | GL path | ✅ | ✅ | <20 | — | Same |

## Can it run on Metal?

| MC | Vanilla | Fabric | Forge / NeoForge | Notes |
|---|---|---|---|---|
| 26.3 / 26.4 / 26.1 | ✅ Air's agent | ❓ Metallum mod (testing) | ❌ | |
| 26.2 | ✅ | ❓ Metallum mod (testing) | ❌ | Upstream Metallum lists Sodium + Iris for 26.2 |
| 1.21.11 | ✅ in manifest | ❓ | ❌ | |
| 1.20.1 | ❌ | ❌ | ❌ | Older than Minecraft's GPU-device layer (1.21.5+) that Metallum plugs into; would need a new backend |
