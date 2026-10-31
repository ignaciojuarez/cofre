# Cofre renderer matrix

Research date: 2026-10-31. Status is evidence-weighted: **works** means a local/device result, **slow** means a measured or strongly indicated performance problem, **black screen/crash** means a reproduced failure, and **unknown** means no iOS proof yet. Android compatibility lists are useful leads, not iOS evidence.

## Picker matrix

The requested rows are the user-facing names in `CofreBackendAdapter.renderers()`. Air also has `VirGL` and `NG-GL4ES` candidates in `LauncherPreferences.m`; they are outside this table and should be removed from the normal Cofre picker unless separately validated. Cofre's `Krypton` row currently maps to `libgl4eszl2.dylib` (ZL2 classic); Air's strings also call the separate `NG-GL4ES` family “Krypton Wrapper,” so the label needs cleanup.

| Renderer | What it is | MC versions | Loaders | iOS status now | Air / Amethyst guidance | Evidence | Proposal |
|---|---|---|---|---|---|---|---|
| **Auto** | Policy/fallback selector; Air native path resolves `auto` to ANGLE, while Cofre Swift policy chooses Metal for manifest-backed vanilla 26.x and MobileGlues for modern/Forge/NeoForge | Policy-dependent | Any | **Mixed**; known black screen on Fabric 26.2 + Sodium + Iris under both MobileGlues and ANGLE | Air log says “Auto renderer resolved … always ANGLE”; Cofre deliberately avoids that for modern versions | `.work/air/Natives/JavaLauncher.m:1983-1991`; `app/UI/Sources/CofreKit/Compatibility.swift:53-72`; renderer-cleanup device table | **Keep+Recommended**, but make the decision/version reason visible |
| **Metal** | Metallum/MetalUniversal native Metal backend; agent or Fabric mod replaces GL/Vulkan | Local manifest: 1.21.11, 26.1–26.4; Java 21+ | Vanilla via Air agent; Fabric only with MetalUniversal mod; no Forge/NeoForge support confirmed | **Works** for vanilla 26.3 on iPad mini (OOM at 8 chunks); **crashes** when changing graphics preset; Fabric + Sodium/Iris through Air agent **crashes** (`IllegalAccessError`) | Air ships the agent and enables it only when manifest version and Java ≥21 match; MetalUniversal says Fabric is required | `plan/reviews/renderer-performance.md`; `.work/air/METAL_TUTORIAL.txt`; `.work/air/Natives/JavaLauncher.m:2098-2138`; [MetalUniversal README](https://github.com/EternityQwQ/MetalUniversal/blob/master/README.md); [Metallum #27](https://github.com/kokodio/metallum/issues/27) | **Keep+Recommended** for supported vanilla; warn on memory/graphics-setting risk; block unsupported loaders |
| **MobileGlues** | Desktop OpenGL implementation translated to host GLES 3.x (often ANGLE); shader/state translation is CPU-heavy | Upstream claims 1.17–26.x; local strings say 1.17+ | Upstream claims Fabric/Forge/NeoForge; compatible list names Sodium/Embeddium, Iris/OptiFine and others | **Slow/unknown** overall; NeoForge 1.21.1 title works but world creation OOM at 8 chunks; Fabric 26.2 + Sodium + Iris **black screen** | Air exposes it as a manual experimental choice and writes its config only when explicitly selected; Amethyst/MobileGlues docs warn device/driver variance | `.work/air/Natives/JavaLauncher.m:585-621`; `plan/renderer-cleanup.md`; [MobileGlues README](https://github.com/MobileGL-Dev/MobileGlues-release/blob/main/README.md); [CompatibleMods](https://github.com/MobileGL-Dev/MobileGlues-release/blob/main/CompatibleMods.md); [ModSupportMatrix](https://github.com/MobileGL-Dev/MobileGlues-release/blob/main/ModSupportMatrix.md) | **Keep** as the tested GL fallback, always label experimental/CPU-heavy; block known 26.2 Sodium/Iris combo until fixed |
| **ANGLE** | MetalANGLE OpenGL ES bridge; exports limited OpenGL 3.2 Core | 1.17+ (Air strings) | Any | **Black screen** for Fabric 26.2 + Sodium + Iris; also implicated in Forge/modded black-screen reports; CPU-bound GL path is slow | Air currently makes it native Auto for 26.2 startup; Amethyst issue reports Forge black screen that recovers only after entering a world | `.work/air/Natives/resources/en.lproj/Localizable.strings:336`; `.work/air/Natives/JavaLauncher.m:1983-1991`; [Amethyst #353](https://github.com/AngelAuraMC/Amethyst-iOS/issues/353); local device table | **Keep** as an emergency/debug fallback, not recommended; block for MC 26.x Sodium/Iris |
| **Zink** | Mesa OpenGL-on-Vulkan; Vulkan then MoltenVK → Metal | Air label Mesa 25.0.7; broad GL versions | Any GL client; shader-capable path intended | **Works but slow** on iPhone 17 Pro (~50 FPS at 32 chunks); no iPad mini proof yet | Air applies Mesa/Zink tuning, keeps shader extensions and disables a MoltenVK-problematic transform-feedback path | `.work/air/Natives/JavaLauncher.m:1497-1515`; `plan/reviews/renderer-performance.md`; [Mesa Zink](https://docs.mesa3d.org/zink.html) | **Keep** as advanced fallback; recommend only when a measured shader/mod case succeeds |
| **LTW** | Large Thin Wrapper: desktop OpenGL Core 3.3 → GLES 3 wrapper | 1.17+ label; Air launch gate says usable through 1.21.x, not 26.x | Any; Sodium/Iris is an upstream Android goal | **Unknown/blocked** for MC 26.x: Air blocks before launch because iOS ES 3.0 lacks `GL_EXT_texture_buffer`; no current iOS success run | Air preloads ANGLE as LTW’s host EGL; code comment claims Sodium/Iris support, but this is not an iOS result | `.work/air/Natives/egl_bridge.m:255-269`; `.work/air/Natives/SurfaceViewController.m:1608-1624`; [LTW README](https://github.com/MojoLauncher/LTW/blob/master/README.md); [Pojav iOS #875](https://github.com/PojavLauncherTeam/PojavLauncher_iOS/issues/875) | **Hide** until an iOS 1.21.x test passes; hard-block 26.x |
| **Vulkan / MoltenVK** | Direct Vulkan loader/bridge to Metal; Cofre picker names the library “Vulkan” | Air label 26.2+; otherwise version-dependent | Any Vulkan-capable client | **Unusable/slow**: local iPhone 17 Pro result is under 10 FPS | Air configures MoltenVK recovery/synchronous submit/prefill settings and uses MobileGlues for LWJGL’s GL bootstrap | `.work/air/Natives/JavaLauncher.m:1993-2022`; `plan/reviews/renderer-performance.md` | **Remove** from normal picker; retain only behind a debug flag for diagnostics |
| **MobileGL** | MobileGL DirectVulkan: desktop GL 3.3 Core → Vulkan → MoltenVK | 1.17+ label | Any | **Unknown** on iOS; no device run in this tree | Air sets `MOBILEGL_BACKEND_TYPE=DirectVulkan` before dlopen and treats MobileGL as a self-EGL renderer | `.work/air/Natives/JavaLauncher.m:1554-1575`; `.work/air/Natives/egl_bridge.m:313-335`; MobileGL integration comments in `.work/air/Natives/utils.h` | **Hide** until an iOS launch/FPS result exists |
| **MobileGL GLES** | MobileGL DirectGLES: desktop GL 3.3 Core → OpenGL ES | 1.17+ label | Any | **Unknown** on iOS; no device run in this tree | Air sets `MOBILEGL_BACKEND_TYPE=DirectGLES`; same self-EGL path | `.work/air/Natives/JavaLauncher.m:1554-1567`; `.work/air/Natives/utils.h:130-141` | **Hide** until an iOS launch/FPS result exists |
| **GL4ES** | Classic OpenGL → GLES translation, OpenGL 2.1 output | ≤1.16.5 is the practical range in Cofre notes | Any old client/loader | **Works for legacy is likely; current versions unsupported**; no new iOS benchmark in this tree | Air’s fallback for old/unspecified GL; Pojav/Amethyst list GL4ES as a core component | `.work/air/Natives/egl_bridge.m:244-248`; `.work/air/Natives/resources/en.lproj/Localizable.strings:335`; [GL4ES](https://github.com/ptitSeb/gl4es); [Amethyst README](https://github.com/AngelAuraMC/Amethyst-iOS#third-party-components-and-their-licenses) | **Keep** for ≤1.16.5; hide for newer versions |
| **Krypton** | Cofre ID is `libgl4eszl2.dylib`: ZL2 classic string-rewrite GLSL→ESSL; not the separately named NG-GL4ES candidate | Air string says ≤26.2 / experimental | Any | **Unknown** on iOS; no device result | Air describes it as an experimental legacy alternative; provenance says ZL2 classic has no glslang/SPIRV-Cross | `.work/air/Natives/LauncherPreferences.m:447-452`; `.work/air/Natives/resources/en.lproj/Localizable.strings:350`; `.work/air/RENDERER_GAP_PROVENANCE.md` | **Hide** until a reproducible iOS version/loader result; fix label/ID ambiguity |
| **SimpleFPEWrapper** | Fixed-function GL 1.x emulation wrapper; defaults to a MobileGlues backend | ≤1.16.x | Old clients/loaders | **Unknown**; no iOS device result; old Java 8 path is sensitive to agent injection | Air says it is for legacy fixed-function clients and requires host EGL; metallum agent is gated off below MC 26/Java 21 | `.work/air/Natives/egl_bridge.m:270-280`; `.work/air/Natives/JavaLauncher.m:1579-1631`; `.work/air/Natives/resources/en.lproj/Localizable.strings:344` | **Keep** only as a conditional legacy option; warn that it is experimental |
| **VGPU** | Pojav VGPU/gl4es fork with enhanced shader syntax | Air string says ≤1.12 | Any old client/loader | **Unknown**; no iOS result | Air provenance calls it opt-in and experimental; it is hidden when the dylib is absent | `.work/air/RENDERER_GAP_PROVENANCE.md`; `.work/air/Natives/resources/en.lproj/Localizable.strings:347`; `.work/air/Natives/LauncherPreferences.m:436-440` | **Hide** until a legacy iOS test proves it better than GL4ES |

### Why the GL paths peg CPU

MobileGlues, ANGLE, LTW, and GL4ES translate desktop GL calls/shaders into GLES (or another intermediate API), then track state and emulate missing features. That work runs largely on CPU; iOS can show a nearly idle GPU while the render thread is saturated. The local iPhone 17 Pro report (<20 FPS, CPU near 100%) is therefore a renderer-path symptom, not evidence that the device GPU is too weak. Zink and MobileGL add Vulkan/MoltenVK translation rather than removing translation; native Metal is the only path in this set that avoids the desktop-GL translation layer.

## Recommended Auto policy

`shaders` means Iris/OptiFine/shader-pack intent, not merely a resource pack. “Block” means Cofre should stop Play with a concrete explanation; “warn” means allow a user override and collect a performance/crash marker.

| MC range | Loader | Shader mods/packs | Auto choice | Confidence / rationale |
|---|---|---|---|---|
| ≤1.16.5 | Any | Any | GL4ES; SimpleFPEWrapper only for fixed-function titles that need it | **High**: GL4ES is the established legacy path; modern backends add no value |
| 1.17–1.20.4 | Vanilla | No | GL4ES first; MobileGlues fallback if GL4ES fails | **Medium**: version coverage is known, but current iOS FPS data is missing |
| 1.17–1.21.4 | Fabric/Forge/NeoForge | No | MobileGlues | **Medium**: upstream lists loader/mod compatibility; local reports show CPU/OOM limits |
| 1.20.5–1.21.4 | Any | Yes | MobileGlues with shaders disabled; otherwise block by default | **High**: current iOS evidence does not establish a usable shader path; translation is CPU-bound |
| 1.21.11 | Vanilla or Fabric + validated MetalUniversal | No | Metal | **High**: native Metal is the fastest path where its version/mod contract is met |
| 26.1–26.4 | Vanilla | No | Metal | **High**: manifest-backed Air agent and local vanilla 26.3 success; still warn about memory and graphics-preset crash |
| 26.1–26.4 | Fabric/Forge/NeoForge | No | MobileGlues only as an experimental fallback; require warning | **Low–Medium**: Air Metal agent is not safe for Fabric Sodium/Iris; MobileGlues has local OOM/black-screen evidence |
| 26.x | Any | Yes (Sodium/Iris or shader pack) | No automatic choice; block until a validated MetalUniversal build or another iOS result exists | **High**: Fabric 26.2 is black on MobileGlues and ANGLE; Metal via Air agent crashes; current notes say no reliable iOS shader setup |

Implementation note: this policy should be one shared Cofre decision used by picker, instance creation, and Play. Do not silently call Air’s `auto` for modern versions, because Air’s native resolver still forces ANGLE.

## UI proposal

### Normal picker

| Show | One-line note | Badge / behavior |
|---|---|---|
| Auto | “Chooses a tested renderer for this version and loader.” | **Recommended** when it resolves to Metal or a tested legacy path |
| Metal | “Native Metal; fastest on supported vanilla 1.21.11/26.x.” | **Recommended** only for a supported version/loader; warn about 4 GB memory and graphics-preset crash |
| MobileGlues | “OpenGL over GLES; broad coverage, high CPU cost.” | Keep visible; “Experimental” badge; warn for 26.x and mod-heavy packs |
| Zink | “OpenGL over Vulkan; slower, useful for advanced compatibility.” | Advanced; warn that iPhone result is ~50 FPS and iPad is unverified |
| GL4ES | “Legacy OpenGL path for 1.16.5 and older.” | Only show for legacy instances |
| SimpleFPEWrapper | “Fixed-function compatibility for very old clients.” | Only show for ≤1.16.x; experimental warning |

Put ANGLE, LTW, MobileGL, MobileGL GLES, Krypton, and VGPU under an “Advanced/debug renderers” disclosure. Remove Vulkan/MoltenVK from the production picker. Do not show VirGL or NG-GL4ES until their stale extra entries are either validated or deleted.

### Warnings and blocks

- **Block before Play:** Metal on Forge/NeoForge; Metal outside its manifest; LTW on 26.x; Vulkan/MoltenVK; known Fabric 26.2 + Sodium/Iris on MobileGlues or ANGLE; shader packs on an unvalidated 26.x setup.
- **Warn, allow override:** MobileGlues on 26.x or >~20 mods; Zink; all advanced/debug renderers; Metal on 4 GB devices at high chunk distance.
- **Show “Recommended”:** only after resolving the exact instance (MC version, loader, shader intent) and only when the result has a passing device test. Never badge a generic renderer globally.

## Device test matrix (ordered by value; no tests run in this research pass)

| # | Device | Case | Measure |
|---:|---|---|---|
| 1 | iPad mini, 4 GB | Vanilla 26.3, Metal, 2 vs 8 chunks | launch, first frame, OOM, FPS/1% low, memory |
| 2 | iPad mini, 4 GB | Vanilla 26.3, Metal, change graphics preset | reproduce/clear AGXMetal SIGSEGV |
| 3 | iPad mini, 4 GB | Fabric 26.2 + Sodium, MobileGlues | black screen/first frame and CPU/GPU split |
| 4 | iPad mini, 4 GB | Fabric 26.2 + Sodium + Iris, MobileGlues | shader startup failure and log marker |
| 5 | iPad mini, 4 GB | Same as #4, ANGLE | compare black-screen path and framebuffer status |
| 6 | iPad mini, 4 GB | NeoForge 1.21.1, no mods, MobileGlues | world-create OOM threshold and FPS |
| 7 | iPad mini, 4 GB | Vanilla 26.3, Auto | verify Cofre resolves Metal, not Air ANGLE |
| 8 | iPad mini, 4 GB | Vanilla/Fabric 1.21.1, Zink | first frame, 8/12 chunks, shader on/off |
| 9 | iPad mini, 4 GB | Vanilla 1.16.5, GL4ES | legacy correctness and FPS |
| 10 | iPad mini, 4 GB | Vanilla 1.12.2, SimpleFPEWrapper and VGPU | compare against GL4ES; crash/first frame |
| 11 | iPad mini, 4 GB | Fabric 1.21.x, Sodium, LTW and Krypton | determine whether either deserves a visible option |
| 12 | iPhone 17 Pro | 26.3 vanilla Metal vs modded MobileGlues vs Zink | FPS/1% low, thermal, CPU/GPU utilization, memory |

## Open questions

- Which exact MetalUniversal jar/version and loader combinations are supported for Fabric 1.21.11 and 26.2–26.4? The upstream README says Fabric is required, while the Air agent path currently fails for Fabric Sodium/Iris.
- Can Zink on iPad mini produce a stable first frame with Iris, or is the local iPhone result the only usable shader-capable path?
- Does LTW work on any iOS 1.21.x instance after the 26.x texture-buffer gate, and is it materially faster than MobileGlues?
- Should Cofre delete the stale `NG-GL4ES`/VirGL picker entries now, or keep them behind a developer-only flag while their provenance is resolved?
- What memory ceiling/chunk distance makes Metal safe on the 4 GB iPad mini, and can the graphics-preset crash be fixed or must that control be disabled?
- Is `Krypton` intended to mean ZL2 classic (`libgl4eszl2.dylib`) or NG-GL4ES? The current code and Air localization disagree.

## Sources

- Local: `plan/renderer-cleanup.md`, `plan/reviews/renderer-performance.md`, `.work/air/README.md`, `.work/air/RENDERER_GAP_PROVENANCE.md`, `.work/air/METAL_TUTORIAL.txt`, `.work/air/Natives/JavaLauncher.m`, `.work/air/Natives/egl_bridge.m`, `.work/air/Natives/SurfaceViewController.m`, `.work/air/Natives/LauncherPreferences.m`, `.work/air/Natives/resources/en.lproj/Localizable.strings`, `app/Glue/AirBridge/CofreBackendAdapter.swift`, `app/UI/Sources/CofreKit/Compatibility.swift`.
- Web: [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS), [PojavLauncher iOS](https://github.com/PojavLauncherTeam/PojavLauncher_iOS), [MobileGlues](https://github.com/MobileGL-Dev/MobileGlues-release), [MobileGlues compatible mods](https://github.com/MobileGL-Dev/MobileGlues-release/blob/main/CompatibleMods.md), [MobileGlues support matrix](https://github.com/MobileGL-Dev/MobileGlues-release/blob/main/ModSupportMatrix.md), [MetalUniversal](https://github.com/EternityQwQ/MetalUniversal/blob/master/README.md), [Metallum](https://github.com/kokodio/metallum), [LTW](https://github.com/MojoLauncher/LTW/blob/master/README.md), [Amethyst #353](https://github.com/AngelAuraMC/Amethyst-iOS/issues/353), [MobileGlues #470](https://github.com/MobileGL-Dev/MobileGlues-release/issues/470), [MobileGlues #469](https://github.com/MobileGL-Dev/MobileGlues-release/issues/469), [Metallum #27](https://github.com/kokodio/metallum/issues/27), [Pojav iOS #875](https://github.com/PojavLauncherTeam/PojavLauncher_iOS/issues/875).
