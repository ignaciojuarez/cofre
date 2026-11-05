# Cofre Metallum: build, fixes and what still needs a device (2026-11-05)

Build: `scripts/metallum.sh` → `/tmp/metallum-build/metallum-cofre-mc{26.2,26.3}-0.0.25-cofre.1.jar`. Recipe and patch list:
`patches/metallum/README.md`.

## Findings

| # | Topic | Finding | Status |
|---|---|---|---|
| 1 | Native | Upstream left the Swift `libmetallum.dylib` behind (MetalUniversal forked `4544c79`, before that). 26.2/26.3 Metallum is pure FFM via metal-jvm 0.1.0 (nested jar, no natives) | No dylib to build or sign |
| 2 | iOS blocker | `MetalCommandEncoder` waited for frames with `ObjCBlock.withRunnable` → `addCompletedHandler`. Blocks are FFM upcall stubs, which SIGBUS on iOS | Fixed: poll `MTLCommandBuffer.status`, `waitUntilCompleted` for the per-frame wait |
| 3 | iOS blocker | 26.3 presents via `SDL_Metal_CreateView`, 26.2 via the GLFW Cocoa NSView; `setDisplaySyncEnabled:` is macOS-only | Fixed: Air's published CAMetalLayer (`IosHost`), no display sync on iOS |
| 4 | Per-draw log | Upstream has no per-draw log: its only `LOGGER` calls are errors, one-time lines and `Stats` (no callers). macOS run: 8 KB log in ~5 min. The 7 MB/3 min spam came from MetalUniversal 1.0.4 or Air's agent (`[metallum] SETSCREEN #…` is in `metallum_agent.jar`) | Nothing to gate in Metallum |
| 5 | Memory climb | Air's render thread is a plain JVM thread with no run loop, so objects Metal autoreleases outside Metallum's scoped pools are never drained there (on macOS the SDL/GLFW pump drains them) | Mitigated: iOS-only per-frame pool (`IosHost.drainFramePool`, called at the end of `submit`). It's a likely cause, not proven |
| 6 | Memory climb | `MetalCommandEncoder.dynamicBackingPool` (per-size buckets of recycled uniform backings) never shrinks. That's a high-water mark, not a per-frame leak | Not changed; watch if world memory still climbs |
| 7 | Reload crash | `MetalCompiledRenderPipeline.close()` released pipeline states and the descriptor immediately, even though the open encoder and 3 in-flight command buffers may still use them. It also left `descriptor` dangling, so `getNativePipeline` on a closed pipeline ran `descriptor.copy()` on a freed object | Fixed: release through the destruction queue, `null` the descriptor, return `null` once closed |

## macOS smoke test (M4 Pro, macOS 27.2, Loom `runClient`, offline account)

| MC | Log | Title screen | Footprint |
|---|---|---|---|
| 26.3 | `Using graphics backend Metal`, `Metal device: Apple M4 Pro` | ✅ panorama + UI (`/tmp/metallum-mac.png`) | `phys_footprint` 1195 → 1198 MB over 60 s; RSS (19 samples, 3 min) fell 1118 → 553 MB from compression |
| 26.2 | same | ✅ UI (`/tmp/metallum-mac-26.2.png`) | 1100 → 1104 MB over 30 s |

The 2–3 MB/s climb does **not** reproduce on macOS, which supports #5: the iOS render thread differs, and the renderer doesn't.

## Device-only (iPhone/iPad)

- Upcall-free frame pacing and the frame pool: look for `Metallum: iOS host layer 0x…` and a first frame.
- **26.3 conflict (handled):** Air's agent logs "Fabric Loader + 26.3 - official mod does not support 26.3, injecting via agent" and would inject its own Metallum next to ours. Its route comes from `mcFamily()`, which reads `-Dmetallum.route.family` first, so on Fabric 26.3 with a `metallum` jar enabled Cofre adds `-Dmetallum.route.family=262` and the agent stands aside as on 26.2 (`MetalMod.agentJVMFlags`). Device check: the log must say "Fabric Loader detected - skipping injection".
- **Device runs:** `scripts/metallum.sh`, then `COFRE_PUSH=/tmp/metallum-build/metallum-cofre-mc26.3-0.0.25-cofre.1.jar scripts/bench.sh --only bench-fabric-26.3-cofre-metallum` (and the same for 26.2). The jars are reproducible (`scripts/metallum.sh` fixes every zip timestamp, including the nested `metal-jvm`), so once a device run passes they can replace MetalUniversal in `MetalMod.pin` by sha.
- metal-jvm `dlopen`s `/usr/lib/libobjc.A.dylib` and `/System/Library/Frameworks/*` by absolute path, with no fallback. That should go through Air's hooked `dlopen`; confirm it does.
- SPIRV-Cross: `IosHost.prepareNatives` picks `Frameworks/libspirv-cross-c-shared.0.dylib`, then `libspvc.dylib`. MSL 4.0 needs iOS 26+.
- Memory: 10 min on the title and in world with `[Cofre] perf`. Target is flat footprint.
- Reload: change Graphics, mipmaps and the resource pack in-world; no AGXMetal SIGSEGV.
- Wiring: `MetalMod.pin` still points at MetalUniversal 1.0.4. Switching to these jars needs hosting and sha512 pins.
