# Performance plan: fast, smooth Minecraft on iPhone and iPad

## Decision

- **Best current renderer:** **Metallum Metal for Minecraft 26.x+**; Air’s measured iPhone 17 Pro note reports **105+ FPS at 32 chunks**, versus Zink ~50 and MoltenVK single digits ([`METAL_TUTORIAL.txt:38-42`](../upstream/air/METAL_TUTORIAL.txt)). Native Metal avoids the OpenGL translation path and is the only path with a documented 26.x shader/agent route.
- **Older versions:** benchmark **MobileGlues** (GL4-on-GLES) against ANGLE; keep ANGLE as the compatibility fallback. MobileGlues can be faster for GL4-heavy packs, but Air’s own diagnostics show large frame-time oscillation and a prior black-screen/context bug ([`gl_bridge.m:95-108`](../upstream/air/Natives/ctxbridges/gl_bridge.m), [`gl_bridge.m:1177-1200`](../upstream/air/Natives/ctxbridges/gl_bridge.m)).
- **Do not make Vulkan the default.** Zink/MoltenVK is useful as a fallback and diagnostic path, but it adds two translation layers; the repository documents a 26.x shader failure and invalid `MVK_CONFIG_SWAPCHAIN_PRESENT_MODE` knob ([`AirBridgeAdapter.m:1045-1061`](../app/Glue/AirBridge/AirBridgeAdapter.m), [`JavaLauncher.m:477-496`](../upstream/air/Natives/JavaLauncher.m)).
- **Default instance:** ship **vanilla + an optional, one-tap “Performance pack”**. Do not silently install Fabric/Sodium into every instance: loader changes, mod compatibility, updates, and world reproducibility become launcher responsibilities. Offer a tested Fabric profile/template per MC version.

## Current state versus recommendation

| Area | Cofre today | Recommendation |
|---|---|---|
| Renderer policy | Auto is rewritten to Metal for MC >=26; UI exposes Auto, Metal, MobileGlues, ANGLE, Zink, Vulkan, NG-GL4ES ([`AirBridgeAdapter.m:1045-1061`](../app/Glue/AirBridge/AirBridgeAdapter.m), [`CofreBackendAdapter.swift:342-360`](../app/Glue/AirBridge/CofreBackendAdapter.swift)) | Persist an explicit renderer per version/device after first successful launch; never hide fallback choice. Metal 26+, benchmark MobileGlues/ANGLE older versions. |
| Resolution/FSR | Resolution, MobileGlues FSR1, shader cache, multidraw and compute toggles are typed preferences ([`CofrePreferences.swift:13-16,37-39`](../app/Glue/AirBridge/CofrePreferences.swift)) | Add presets (battery/balanced/quality), thermal downgrades, and per-renderer safe values. |
| FPS/VSync | `Auto`/cap is written to `options.txt`, clamped to display Hz; explicit cap turns VSync back on ([`AirBridgeAdapter.m:1082-1109`](../app/Glue/AirBridge/AirBridgeAdapter.m)) | Default cap = display refresh (120 ProMotion, 60 iPad); use 90/60 when hot; leave VSync on for stable pacing. |
| RAM | First launch enables Air auto RAM; ceiling comes from Air; physical RAM is exposed ([`AirBridgeAdapter.m:883-888`](../app/Glue/AirBridge/AirBridgeAdapter.m), [`CofrePreferences.swift:66-72`](../app/Glue/AirBridge/CofrePreferences.swift)) | Keep auto; cap by device class and thermal state. Never equate physical RAM with a safe Java heap. |
| Java/JVM | Air auto-selects Java 8/17/21/25; Java 17+ gets G1, 64 MB code cache, mirror-mapped JIT, `-Xss1m` ([`README.md:52`](../upstream/air/README.md), [`JavaLauncher.m:2157-2236`](../upstream/air/Natives/JavaLauncher.m)) | Select by MC version; preserve conservative flags; expose an advanced override with validation and crash rollback. |
| JIT | Cofre deliberately keeps debugger attached and enables dyld bypass on iOS 26+ ([`CofreStartup.m:39-50`](../app/Glue/AirBridge/CofreStartup.m)) | Keep attached on 26.x/TXM. Measure overhead; do not detach between launches. |
| Options | Only language, `maxFps`, and `enableVsync` are written automatically ([`AirBridgeAdapter.m:1063-1109`](../app/Glue/AirBridge/AirBridgeAdapter.m)) | Own an `options.txt` profile: render/simulation distance, graphics, clouds, particles, entity distance, mipmaps, biome blend, GUI scale, FOV. |
| Mods | Mod search/install is wired; no performance template policy | Offer version-pinned Fabric/NeoForge templates with compatibility checks and backup-before-update. |
| Cold start | Air downloads and class loading remain on launch path | Pre-fetch manifests/assets, verify once, retain shader/pipeline caches, and do not log per-frame draw calls in release. |

## Renderer matrix

| Minecraft | Default | Why / settings | Fallback and verification |
|---|---|---|---|
| 26.0–26.4 | **Metallum Metal + agent** | Native Metal path; agent injects `[Metal,Vulkan,GL]`, preconfigures SPVC, and Fabric uses `MetalUniversal` ([`METAL_TUTORIAL.txt:12-25`](../upstream/air/METAL_TUTORIAL.txt)). | If `defineMetallumClasses failed` or shader crash: ANGLE, then Zink. Verify `renderer=Metal`, first frame, no `glGetError mismatch`. |
| 1.20.5–1.21.x | MobileGlues first **after device benchmark**; ANGLE safe fallback | MobileGlues exposes GL4 features needed by modern Sodium; its FSR1/cache/multidraw knobs are already present. Air fixed its EGL lifecycle routing, but black-screen regressions remain possible ([`gl_bridge.m:1177-1200`](../upstream/air/Natives/ctxbridges/gl_bridge.m)). | ANGLE for packs that fail GL4; verify `MG-Bridge`, zero GL errors, and stable 1% lows. |
| 1.16–1.20.4 | ANGLE or MobileGlues by measured FPS | ANGLE is OpenGL ES on Metal and broadest compatibility; MobileGlues can win on GL4-heavy Sodium/Forge packs. | Zink if ANGLE/MG fails; compare `buildAvg`/`presAvg` render diagnostics ([`gl_bridge.m:95-108`](../upstream/air/Natives/ctxbridges/gl_bridge.m)). |
| <=1.12 / legacy GL | ANGLE or NG-GL4ES/GL4ES family | Legacy fixed-function/shader translation is the target; NG-GL4ES has shader conversion controls, but current provenance says its competitor import was removed—treat as **unverified until artifact is present** ([`RENDERER_GAP_PROVENANCE.md:7-24`](../upstream/air/RENDERER_GAP_PROVENANCE.md)). | Keep a per-version compatibility override; do not promise Sodium. |
| Any, emergency | Zink over MoltenVK | OpenGL-on-Vulkan can be steadier than MobileGlues in some measured scenes (~37–53 FPS in Air diagnostics), but costs translation and shader compile time. | Vulkan (LWJGL) only as troubleshooting; MoltenVK alone is not a Minecraft renderer default. |

Renderer environment notes:

- Keep `LIBGL_NOINTOVLHACK=1`, `LIBGL_NORMALIZE=1`, and Zink’s `MESA_GL_VERSION_OVERRIDE=4.1` only for GL/Zink paths ([`JavaLauncher.m:470-475`](../upstream/air/Natives/JavaLauncher.m)).
- `POJAV_DISABLE_VSYNC=1` sets Java `enableVsync=false`, EGL interval 0, and Zink IMMEDIATE selection; Air notes that `MVK_CONFIG_SWAPCHAIN_PRESENT_MODE` is not a real MoltenVK 1.4.2 option ([`JavaLauncher.m:480-496`](../upstream/air/Natives/JavaLauncher.m), [`gl_bridge.m:1945-1965`](../upstream/air/Natives/ctxbridges/gl_bridge.m)).
- ANGLE feature toggles and MobileGlues options should be changed only behind a benchmark flag; **hypothesis:** forcing ANGLE threaded submission or MG multidraw may help CPU-bound scenes but can regress correctness.
- Metallum pipeline/shader caches should be keyed by MC version, renderer, GPU family, and mod set; invalidate after renderer/driver changes.

## Java, JIT, heap, and startup

- Use **Java 8** for MC 1.12–1.16 packs that require it; **Java 17** for 1.17–1.20.4; **Java 21** for 1.20.5–1.21.x; **Java 25** for 26.x. Air bundles Azul Zulu 8/17/21/25 ([`README.md:52,153`](../upstream/air/README.md)).
- Keep Air’s current safe baseline: `-XX:+UnlockExperimentalVMOptions`, `-XX:+DisablePrimordialThreadGuardPages`, 64 MB code cache, `-Xss1m`, `-XX:SoftRefLRUPolicyMSPerMB=250`. Java 17+ uses G1, `MaxGCPauseMillis=50`, and string deduplication; Java 8 remains Serial/default ([`JavaLauncher.m:2138-2140`](../upstream/air/Natives/JavaLauncher.m), [`JavaLauncher.m:2176-2236`](../upstream/air/Natives/JavaLauncher.m)).
- Do **not** default to ZGC/Shenandoah/Parallel: availability and pause/throughput behavior on these iOS ports are not established. **Hypothesis:** Parallel may win for a small heap, but only ship it after an A/B test using GC pause logs and 1% FPS.
- TXM’s always-attached debugger costs memory mappings, debugger traffic, and dyld work; it is nevertheless required for iOS 26.x JNA/library loading. Compare attached versus detached only on a non-26 control build; never detach the production 26.x path ([`CofreStartup.m:39-50`](../app/Glue/AirBridge/CofreStartup.m)).
- Heap is not the process limit. `validateVirtualMemorySpace` can reject a nominally available `-Xmx`; increased-memory-limit and extended-virtual-addressing entitlements matter ([`JavaLauncher.m:1758-1769`](../upstream/air/Natives/JavaLauncher.m), [`JavaLauncher.m:2364-2367`](../upstream/air/Natives/JavaLauncher.m)). Use auto RAM, leave headroom for Metal textures/native libraries, and lower the ceiling before lowering resolution when jetsam/VM failures occur.
- Add AppCDS/class-list generation per Java runtime and pack, then verify startup time and class-sharing logs. **Hypothesis:** CDS helps cold start, not steady-state FPS; never share archives across Java major versions or mod sets.
- Prewarm version manifests, parallelize independent library/asset downloads, hash once and cache results, and compile/load shader/pipeline caches on a “first launch preparation” step.

## Mods and instance policy

**Recommended one-tap templates (pin exact versions and loader compatibility):**

| MC range | Fabric template | NeoForge/Forge template | Avoid/default-off |
|---|---|---|---|
| 26.x | Sodium (only a build that declares MC 26.x + renderer compatibility), Lithium, FerriteCore, ImmediatelyFast, EntityCulling/MoreCulling where supported, ModernFix if released | Embeddium, FerriteCore, ModernFix, ImmediatelyFast equivalents | C2ME until iOS thread/IO behavior is verified; Dynamic FPS in foreground because Air reports a 30 FPS AFK issue |
| 1.20.5–1.21.x | Sodium, Lithium, FerriteCore, ModernFix, ImmediatelyFast, EntityCulling, MoreCulling, Krypton | Embeddium, FerriteCore, ModernFix, ImmediatelyFast, EntityCulling | Sodium/Embeddium shader features that require desktop GL 4.5; incompatible shader loaders; C2ME initially |
| 1.16–1.20.4 | Sodium where supported, Lithium, FerriteCore, EntityCulling, Krypton; ModernFix/ImmediatelyFast by version | Embeddium/Rubidium by exact Forge version, FerriteCore, ModernFix | Newer Sodium builds, C2ME, unsupported shader mods |

- Sodium is a rendering rewrite, not a generic “works on every GL” mod. It needs the loader/version build and GL features its release targets; test each renderer. Fabric’s loader/mod metadata is the source of truth ([Fabric Loader](https://fabricmc.net/use/), [Sodium](https://modrinth.com/mod/sodium), [Embeddium](https://modrinth.com/mod/embeddium)).
- MetalUniversal already supplies the Metal integration shape: vanilla gets the Java agent; Fabric gets the mod ([`METAL_TUTORIAL.txt:12-25`](../upstream/air/METAL_TUTORIAL.txt)). Do not install both an incompatible renderer shim and MetalUniversal.
- Ship vanilla as the stable baseline, then “Create performance instance” that clones the instance, installs the exact loader/mod set, records hashes, and offers rollback. This preserves vanilla bug reports and worlds.
- Dynamic FPS is useful for background power saving, but gate it behind “background only”; Air has a known 30 FPS AFK interaction. C2ME/Krypton can improve servers/IO but need iOS thread, JNI, and networking tests before inclusion.
- Measure mods with the same seed/path: average FPS, 1% low, frame time, GC pause, native memory, heat, and first-frame time. A higher average with worse 1% lows is a regression.

## Phone/iPad defaults

| Setting | iPhone 17 Pro | iPad (60/120 Hz) |
|---|---:|---:|
| Renderer | Metal for 26.x; benchmarked MG/ANGLE for older | Same policy; prefer balanced preset on non-Pro iPads |
| Resolution scale | 85% balanced; 70% performance; 100% quality | 80% balanced; 70% performance; 100% quality |
| FSR | Off on Metal; MobileGlues Quality/Performance only when MG selected | Same; never stack FSR with an already low resolution preset |
| Render distance | 12 chunks balanced; 8 hot/battery; 16 quality | 10 balanced; 8 hot; 14 quality |
| Simulation distance | 6 (4 hot) | 6 (4 hot) |
| Graphics | Fast; Fabulous only opt-in | Fast; Fabulous opt-in |
| Clouds/particles | Off / decreased; minimal particles | Off / decreased |
| Entity distance | 75% balanced, 50% hot | 75% |
| Smooth lighting | Minimum/balanced | Minimum/balanced |
| Mipmaps/biome blend | 2 / 0–2 chunks | 2 / 0–2 chunks |
| FPS/VSync | Auto = 120 on ProMotion; 90/60/30 thermal steps; VSync on | Auto = panel max; 60 default on 60 Hz; VSync on |
| GUI scale/FOV | GUI auto or 3; FOV 70–80 | GUI auto or 3; FOV 70–80 |

These are starting points, not universal truths: write them per instance and expose “Quality / Balanced / Battery”. Cofre currently clamps FPS to `UIScreen.maximumFramesPerSecond` and logs the chosen cap ([`AirBridgeAdapter.m:1082-1109`](../app/Glue/AirBridge/AirBridgeAdapter.m)).

## iOS-specific levers

- **ProMotion:** request high refresh with `CADisableMinimumFrameDurationOnPhone` and a `preferredFrameRateRange`; cap game FPS to the actual screen rate to avoid wasted CPU ([Apple: `preferredFrameRateRange`](https://developer.apple.com/documentation/quartzcore/cametallayer/preferredframeraterange), [Apple: `CADisableMinimumFrameDurationOnPhone`](https://developer.apple.com/documentation/bundleresources/information_property_list/cadisableminimumframedurationonphone)).
- **Thermals/Low Power Mode:** observe `ProcessInfo.processInfo.thermalState` and `isLowPowerModeEnabled`; step down FPS, resolution, simulation distance, and downloads before iOS throttles the process ([Apple thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate), [Apple Low Power Mode](https://developer.apple.com/documentation/foundation/processinfo/3883009-islowpowermodeenabled)). Persist the user’s chosen quality separately from the temporary thermal override.
- **Game Mode:** add `LSSupportsGameMode` and `GCSupportsGameMode` only after validating the iOS 18+ behavior and entitlement/profile; treat this as scheduling priority, not extra GPU power ([Apple Game Mode](https://developer.apple.com/documentation/gamecontroller/gcgamecontroller/)). **Unverified:** exact benefit for a JIT/debugged app.
- **Lifecycle:** pause simulation and flush saves on background; stop render/audio threads when suspended; resume without rebuilding the JVM. Do not kill the JVM merely because the launcher is backgrounded.
- **Memory:** request `com.apple.developer.kernel.increased-memory-limit` and `com.apple.developer.kernel.extended-virtual-addressing` where signing permits; show the actual validated ceiling and leave native/Metal headroom. iOS does not promise “all physical RAM” to one app; measure jetsam on the exact 17 Pro build.
- **Debugging:** enable Metal Performance HUD only in developer builds; use Instruments Metal System Trace, GPU counters, thermal logs, and `latest.log`. Remove per-frame logs from release. Air’s renderer diagnostics already separate CPU build from present/GPU wait ([`gl_bridge.m:95-108`](../upstream/air/Natives/ctxbridges/gl_bridge.m)).
- **Storage:** APFS clones make instance duplication cheap; use atomic rename, sparse/clone copies, and a shared content hash store. Keep shader/pipeline caches on-device and exclude them from user backups when safely rebuildable.

## Top 10 actions (impact / effort)

| Rank | Action | Verify |
|---:|---|---|
| 1 | Make Metal explicit for MC 26.x and record a renderer/version/device matrix | Log `[Cofre] renderer auto -> Metal`; 3/3 cold first frames; no `glGetError mismatch`/shader crash |
| 2 | Ship Quality/Balanced/Battery presets with thermal + Low Power Mode overrides | Repeated 10-minute runs: FPS, 1% low, `thermalState`, battery drain |
| 3 | Add a version-pinned Fabric/NeoForge performance template, opt-in and rollbackable | Fresh clone launches; mod loader log; compare vanilla/modded FPS and memory |
| 4 | Remove release per-frame Metallum/GL logging; add a runtime log level | Compare `latest.log` size and CPU/frame-time trace; retain errors/warnings |
| 5 | Add a shader/pipeline cache lifecycle and first-launch preparation | Second launch has lower shader compile time and no visual mismatch |
| 6 | Make `options.txt` performance defaults per instance | Log written render/simulation distance, mipmap, particles, `maxFps`, `enableVsync`; verify in-game values |
| 7 | Tune auto-RAM by validated VM/native headroom, not physical RAM | `[JavaLauncher] Max RAM allocation`; no `validateVirtualMemorySpace` failure or jetsam across 30-minute runs |
| 8 | Add AppCDS/class-list caches per Java major + mod set | JVM CDS log and cold-start stopwatch; archive mismatch must safely fall back |
| 9 | Pre-fetch manifests/assets and verify/download in parallel | Offline relaunch skips network; cold-start wall time and failed-download rate improve |
| 10 | Build an automated renderer/mod benchmark harness on the exact TXM iPhone 17 Pro and iPad | Same seed/camera path; report avg/1% FPS, frame time, GC, native memory, heat, first frame |

## Open hypotheses to test

- Metal’s native path should dominate 26.x, but a heavily optimized Sodium/MobileGlues 1.21 pack may beat it; measure rather than assume.
- Debugger attachment may reduce CPU headroom, yet detaching on iOS 26.x breaks JNA/dyld; correctness wins until a TXM-compatible detach path exists.
- ANGLE threaded features, MobileGlues multidraw/compute, Parallel GC, and C2ME may help specific workloads and hurt others; no default until 3-run cold + 10-minute thermal tests pass.
- MetalFX is not automatically useful for Minecraft’s UI-heavy raster path; test image quality and GPU time before adding it.

## Sources

- Air renderer/Metal evidence: [`METAL_TUTORIAL.txt`](../upstream/air/METAL_TUTORIAL.txt), [`JavaLauncher.m`](../upstream/air/Natives/JavaLauncher.m), [`gl_bridge.m`](../upstream/air/Natives/ctxbridges/gl_bridge.m).
- Cofre policy/preferences: [`AirBridgeAdapter.m`](../app/Glue/AirBridge/AirBridgeAdapter.m), [`CofrePreferences.swift`](../app/Glue/AirBridge/CofrePreferences.swift), [`CofreStartup.m`](../app/Glue/AirBridge/CofreStartup.m).
- [Fabric Loader](https://fabricmc.net/use/), [Sodium](https://modrinth.com/mod/sodium), [Embeddium](https://modrinth.com/mod/embeddium), [Lithium](https://modrinth.com/mod/lithium), [FerriteCore](https://modrinth.com/mod/ferrite-core), [ModernFix](https://modrinth.com/mod/modernfix), [ImmediatelyFast](https://modrinth.com/mod/immediatelyfast), [EntityCulling](https://modrinth.com/mod/entityculling), [MoreCulling](https://modrinth.com/mod/moreculling), [Dynamic FPS](https://modrinth.com/mod/dynamic-fps), [C2ME](https://modrinth.com/mod/c2me-fabric), [Krypton](https://modrinth.com/mod/krypton).
