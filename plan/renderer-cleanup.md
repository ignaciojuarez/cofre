# Renderer cleanup: keep what's playable, warn or block the rest

Status: in progress (2026-10-31). Owner: main thread; findings land in `plan/reviews/renderer-matrix.md`.

## Why

- iPhone 17 Pro, Fabric and NeoForge with fewer than 20 mods on the GL path: CPU near 100%, GPU nearly idle, under 20 FPS, ticks lagging. Unplayable.
- Metal (Metallum) on vanilla is fast. The other engines may not be usable yet.
- The picker lists about 13 renderers (Auto, Metal, MobileGlues, ANGLE, Zink, LTW, Vulkan/MoltenVK, MobileGL, MobileGL GLES, GL4ES, Krypton, SimpleFPEWrapper, VGPU). Most are untested and some are known broken.

## North star

Modded play needs Metal. Every OpenGL path translates on the CPU and was unplayable with fewer than 20 mods on an iPhone 17 Pro. So every test round should push at least one popular modded version onto Metal (first: Fabric 26.2 + MetalUniversal + Sodium; routes in `reviews/metal-mods.md`).

**Metal targets (popular modding versions only, decided 2026-10-31):** 1.21.11 Fabric (Graft port; 18k Fabric mods), 26.2 Fabric and NeoForge (MetalUniversal; 13.6k Fabric mods). 26.3 only if its numbers grow. 1.21.1 / 1.20.1 can't get Metal (older than Minecraft's 1.21.5 GPU-device layer); they stay on MobileGlues, labelled slower. Ready-made preset instances: `presets.md`.

## Goals

1. Find out per renderer × Minecraft version × loader: works / black screen / crashes / unplayable FPS. Use Air's and Amethyst's own notes, upstream docs, and our device runs.
2. Remove or hide renderers that are broken or unplayable. Keep a short list.
3. Show **Recommended** on the right pick and a one-line note on each option.
4. Before a user creates or plays an instance that can only run on an unplayable renderer, warn them, or don't allow it.
5. Measure: FPS, 1% low, footprint, thermal (`-cofrePerfLog 1`, `scripts/perf-summary.sh`).

## Known so far (iPad mini 6, 4 GB, iPadOS 27)

| Setup | Renderer | Result |
|---|---|---|
| Vanilla 26.3 | Metal | Title + world OK (2 chunks); OOM at 8 chunks; pause/blur spike +650 MB |
| Vanilla 26.3 | Metal | Graphics preset change in game → SIGSEGV in AGXMetal (driver), engine bug |
| NeoForge 1.21.1, no mods | MobileGlues | Title OK; OOM creating a world at 8 chunks |
| Fabric 26.2 + Sodium + Iris | MobileGlues | Black screen (game running) |
| Fabric 26.2 + Sodium + Iris | ANGLE (libtinygl4angle) | Black screen |
| Fabric 26.2 + Sodium (± Iris) | Metal (Air's agent forced) | Crash: IllegalAccessError under Fabric's Knot loader; stock Iris needs GL |
| Fabric/NeoForge (<20 mods), iPhone 17 Pro | GL path | CPU ~100%, <20 FPS (user report) |

## Ideas to keep

- **Metallum as a Fabric mod** where Air's bundled agent can't run (Fabric 26.x): install the real Metallum mod (+ its Sodium/Iris builds) into the instance. Experiment in progress (`scripts/scenarios/fabric-26.2-metallum-*.json`). If it works, offer it as the Metal path for Fabric on the versions Metallum supports.
- If only Metal is truly playable, steer users to Metal-capable setups (vanilla or Fabric + Metallum on 26.x) and label the rest "experimental / slow".
- **iPhone test kit:** build the app once on the iPhone 17 Pro with a ready-made set of instances (one per renderer × loader case) so the user only taps Play on each and reads FPS. Needs the user's go-ahead before installing on the iPhone.

## Applied (2026-10-31)

- Picker on Metal vanilla versions: Auto, Metal, MobileGlues only (Air's agent ignores other picks there).
- Play warns and offers to turn Iris off on 26.x with MobileGlues or ANGLE (black screen on the iPad).

## Pending device results

Keep these matrix rules provisional until the iPad benchmarks complete:

- **Block:** Metal on Forge/NeoForge or outside its manifest; LTW on 26.x; Vulkan/MoltenVK; known Fabric 26.2 + Sodium/Iris on MobileGlues or ANGLE; shader packs on an unvalidated 26.x setup.
- **Warn and allow override:** MobileGlues on 26.x or mod-heavy packs; Zink; all advanced/debug renderers; Metal on 4 GB devices at high chunk distance.
- **Re-measure before changing Auto:** Fabric 26.x with Sodium/Iris, Zink on iPad mini, LTW/Krypton on 1.21.x, and legacy SimpleFPEWrapper/VGPU against GL4ES.
