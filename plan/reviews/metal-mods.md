# Modded Minecraft Java on native Metal (Cofre)

Research date: 2026-10-31. This is a source review, not an iOS validation run.

## Decision

**Ship the managed Fabric 26.2 Metal kit first.** It is the only released iOS-targeted mod backend that has rendered in Cofre. Stabilize its backend selection, pin its exact jars, and permit only a tested mod allowlist. In parallel, port **Graft** to the existing Cofre view for a 1.21.11 track and evaluate **Ciderlight** for NeoForge 26.3. Keep Air’s agent for vanilla; do not make it the first mod-loader bridge.

“Native Metal” here means a renderer that submits to Metal directly (Metallum/MetalUniversal, Graft, Ciderlight, or a Cofre port). Zink, VulkanMod/MoltenVK, ANGLE, MobileGlues, LTW and GL4ES are translation/fallback routes, not the product target.

## Ranked routes

| Rank | Route | Versions / loader | Evidence today | Effort | Risk | Next proof |
|---:|---|---|---|:---:|---|---|
| 1 | **MetalUniversal + Sodium** as a Cofre-managed Fabric kit | 26.2 now; source track 26.3; later 1.21.11/26.1 if a build appears | MetalUniversal 1.0.4 is an iOS/macOS Fabric jar; local 26.2 rendered once at ~57 FPS. Identical second launch selected GlBackend and crashed; Iris fails with No GLCapabilities instance set. | M | Backend selection/native load is flaky; exact Sodium mappings matter | Three cold 26.2 launches; assert Using graphics backend Metal, capture first world frame and 60 s FPS; test no duplicate metallum jar |
| 2 | **Port Graft** (and optional GraftShaders) to Cofre | 1.21.11 first; also 26.2/26.3; Fabric; legacy Forge later | Graft v1.1.1 publishes Metal jars for 1.21.5–1.21.11 and 26.2/26.3; GraftShaders publishes matching Iris fork jars. It is macOS-only: hard-coded Cocoa/NSView and MACOS shader platform. | L | iOS surface, shaderc/spvc and native packaging; LGPL obligations; upstream churn | Port one 1.21.11 surface to Cofre’s existing UIView/CAMetalLayer; run vanilla + Sodium + one GraftShaders pack |
| 3 | **MetalUniversal 26.3 dev → release**, then target 26.3 | 26.3 Fabric, Java 25 | 26.3-fabric branch is an alias of 26.2; 26.3-fabric-dev is real source (MC 26.3/Fabric 0.19.5/Sodium 0.9.2), no release. Official Metallum v0.0.25 is macOS 26.3 Fabric. | M | RenderPearl/SDL API churn; no signed iOS 26.3 artifact | Build dev commit, verify native load and Metal first frame on iPad; pin commit if successful |
| 4 | **Ciderlight** iOS port for NeoForge | 26.3 Fabric and NeoForge beta | v0.1.17 publishes both jars and a native Metal backend. It explicitly rejects Sodium/Iris/Sodium Extra; macOS-only source. | L | AppKit/Cocoa, macOS guard and MACOS shader target; no Sodium chunk renderer | Port native surface and NeoForge jar; launch a no-Sodium NeoForge content mod |
| 5 | Loader-aware Air Metallum agent | Agent class sets cover 1.21.11/26.1–26.4; vanilla verified | Forced Fabric 26.2 crashes IllegalAccessError in MetalCrossShaderCompiler; local agent already has Fabric/Forge detection and widening logic, so “just use Knot’s loader” is not a fix. | L–XL | transform ordering, duplicate class definitions, loader-specific APIs | Instrument class name, defining loader, code source and Spv* modifiers; prove AW/public transform on the actual game class before another bridge |
| 6 | VulkanMod over MoltenVK | Official VulkanMod 0.6.8: 1.21.11 and 26.1–26.1.2; Fabric/Quilt; NF forks exist | VulkanMod is a real non-GL engine; MoltenVK officially runs Vulkan on iOS/Metal. No credible Cofre/iOS VulkanMod FPS proof. | L | iOS Vulkan feature limits, LWJGL/native packaging, translation overhead | One isolated iOS VulkanMod boot; measure first frame/CPU/FPS; abandon if below Metal kit |
| 7 | Other native Metal backends (MetalCraft, mcopt, Minecraft Metal Renderer) | Mostly 1.21.11 or 26.3, Fabric | Real macOS experiments/releases, no iOS artifacts. Useful source material, not drop-in routes. | L–XL | Each owns window/native/shader stack | Only pursue after route 1–4 fail |
| 8 | GL translation (MobileGlues/ANGLE/Zink/LTW/GL4ES) | Broad | Compatibility fallback; Cofre measurements show GL paths under 20 FPS with <20 mods and high CPU. Zink/MoltenVK is still translation. | S | Does not meet product goal | Keep hidden/debug-only; never market as Metal |

### Route-specific source notes

- **Official Metallum** ([repo](https://github.com/kokodio/metallum), [versions](https://modrinth.com/mod/metallum-mc/versions)): MIT; Fabric only; macOS Apple Silicon. v0.0.24 (2026-10-08) targets MC 26.2/Fabric ≥0.19.2/Java 25/Sodium 0.9.1; v0.0.25 (2026-10-10) targets 26.3/Fabric ≥0.19.5/Java 25/Sodium 0.9.2. There are 24 releases from Apr 19–Oct 10, with bursty cadence (Jul 30→Oct 8 gap). Published metadata covers 26.2 and 26.3; no official 1.21.11, 26.1 or 26.4 mod build found. No committed Forge/NeoForge port or plan found.
- **MetalUniversal** ([repo](https://github.com/EternityQwQ/MetalUniversal), [1.0.4](https://github.com/EternityQwQ/MetalUniversal/releases/tag/MetalUniversal_1.0.4)): MIT; five public releases Jul 22–Aug 18, latest 1.0.4 targets MC 26.2/Fabric ≥0.19.2/Java 25/Sodium 0.9.0. The actual jar id is metallum (do not install alongside another Metallum jar or Air injection). Jar contains natives/ios/libmetallum.dylib and libspvc.dylib; both are arm64 Mach-O, with the Metal library marked iOS min 14. README/source prefers signed app-bundle libraries and the host view’s existing CAMetalLayer; extracting an unsigned jar dylib is not sufficient on iOS. The 26.3-Fabric branch currently aliases 26.2; 26.3-fabric-dev is the real 26.3 source.
- **Graft** ([repo/release](https://github.com/kkorenn/Graft/releases/tag/v1.1.1)): LGPL-3.0. v1.1.1 (Oct 13) ships Fabric jars for 1.21.5–1.21.11, 26.2 and 26.3, plus Forge 1.7.10/1.8.9/1.12.2. Direct Java FFM→ObjC/Metal for 1.21.x/26.x; source hard-codes macOS Cocoa/NSWindow and a MACOS shader platform. **GraftShaders** ([release](https://github.com/kkorenn/GraftShaders/releases/tag/v1.0.1)) is an LGPL Iris fork with 26.2/26.3/1.21.11 jars; it is not stock Iris and must match Graft.
- **Ciderlight** ([repo](https://github.com/riccqi/ciderlight), [v0.1.17](https://github.com/riccqi/ciderlight/releases/tag/v0.1.17)): Apache-2.0 + NOTICE. MC 26.3 Fabric and NeoForge beta. Native Metal is valid with shaders off or its built-in shader pipeline, but Sodium/Iris/Sodium Extra are intentionally incompatible (missing multi-draw). README benchmarks are macOS M1 Pro, not iOS.
- **MetalCraft** ([repo](https://github.com/Im-Fran/MetalCraft)): GPL-3.0, 1.21.11 Fabric, macOS 14+/M5 test; Cocoa/MACOS native assumptions. **mcopt** ([repo](https://github.com/noahdunnagan/mcopt)) and [Minecraft Metal Renderer](https://github.com/Kausik-Velaga/minecraft-metal-renderer) are 26.3 macOS experiments. They are fallback research, not current Cofre dependencies.
- Screened-out forks are not hidden iOS solutions: lodeframe, Prisma and SergeyWithNormalName/metallum are macOS/pre-alpha or built-in-shader experiments; Vitrail-Shaders-Metal is a shader engine, not a NeoForge Metal backend; MetalMC still keeps a macOS OpenGL HUD; Infatoshi/metal-mc-terrain accelerates terrain only. None has a reproducible Cofre/iOS full-renderer build.

## Iris, shaders, and renderer-mod compatibility

- Stock Iris is OpenGL-only according to Metallum maintainers ([#8](https://github.com/kokodio/metallum/issues/8#issuecomment-4903831521), [#7](https://github.com/kokodio/metallum/issues/7#issuecomment-4853820400)); local stock Iris crashes with No GLCapabilities instance set.
- Metallum’s own renderer translates vanilla/core GLSL through SPIR-V/MSL; that is built-in core-shader/resource-pack support, not a compatible stock Iris shader-pack loader.
- Metallum [#27](https://github.com/kokodio/metallum/issues/27) contains a community claim of a Discord Iris+Metallum build that crashes entering the Nether. No public artifact, version or hash is linked; it is not a supported release.
- MetalUniversal’s [Iris branch](https://github.com/EternityQwQ/MetalUniversal/tree/feat/iris-26.2-msl-pipeline) pins 26.2/Sodium 0.9.1/Iris 1.11.2. [PR #13](https://github.com/EternityQwQ/MetalUniversal/pull/13) was later reverted before 1.0.4. The strongest iOS shader lead is open [PR #18](https://github.com/EternityQwQ/MetalUniversal/pull/18), whose preview fork reports BSL, Complementary, MakeUp, Sildur, Mellow, Solas and Bliss on an iPad Air M3; no release and no Cofre proof. Photon custom images/SSBO are reported unsupported. Treat this as a separate experimental profile.
- Renderer mods that call OpenGL or own framebuffers/shaders need an explicit port: Iris, Flywheel/Create, Embeddium, Veil and custom renderers. ImmediatelyFast changes render buffers/batching and may work only after a per-version test; do not promise it. MetalUniversal issues record failures/artifacts in BetterClouds (#6), JourneyMap (#14), Essential/Xaero (#16/#21), ChunksFadeIn (#20), Sodium 0.9.2-alpha (#22) and F3+1 (#23): use these as exclusions until retested. Vanilla core-shader/resource-pack support is narrower than Iris pack compatibility.

## Metal-safe starter mods

“Metal-safe” means **no renderer proof required** (gameplay/data/network/performance code using normal Minecraft APIs), not “device verified.” Start with one mod at a time and a fixture world.

| Category | Good first candidates (Fabric builds exist for 26.2 unless noted) | Gate |
|---|---|---|
| Core/performance | Fabric API 0.161.0+26.2; Lithium 0.25.3; FerriteCore 9.0.0; Krypton 0.3.1; ServerCore 1.5.19; spark 1.10.187; C2ME 0.4.2-alpha.0.60+26.2 | C2ME and spark need memory/native profiling tests; keep optional |
| UI/inventory | Mod Menu 20.0.3; AppleSkin 3.0.10+mc26.2; JEI 30.48.0.244; REI 26.2.820; Jade 26.2.11+fabric | UI mixins can still trigger rendering; smoke-test menus |
| Content/worldgen | Terralith 2.6.4; Tectonic 3.0.28; Incendium 5.5.1; Nullscape 1.2.20; Dungeons & Taverns 5.3.2; Waystones 26.2.0.12; Traveler’s Backpack 26.2-11.3.3; Biomes O’ Plenty 26.2.0.0.28 + TerraBlender; Farmer’s Delight Refabricated 26.2-3.6.30; Veinminer 2.12.1; Tom’s Storage 26.2-2.11.4 | Generate a new fixture world for each worldgen combination; entity/block renderers are second-stage |
| Compatibility cautions | EntityCulling, ImmediatelyFast, Sodium Extra/RSO | These hook rendering; require a Metal-specific test before inclusion |

Exact build availability was queried from the Modrinth version API; it is not evidence that the build renders on iOS. ModernFix, Noisium and Indium had no exact target builds in the query and should not be cargo-culted into the kit. Cobblemon, Create-Fabric, Chipped, Handcrafted and Sophisticated Backpacks likewise had no exact target build in the query; do not advertise them as available for 26.2.

## Why the Air agent fails on Fabric, and the viable loader design

The JVM defines a **run-time package** by package name **and defining class loader** ([JVMS §5.3](https://docs.oracle.com/javase/specs/jvms/se25/html/jvms-5.html#jvms-5.3); access control §5.4.4). The reported failing reference is from com.metallum.MetalCrossShaderCompiler to com.mojang.blaze3d.vulkan.glsl.SpvUniformBuffer; merely putting both classes in Knot is insufficient because these are different package names. The access-widener must make the actual game SpvUniformBuffer, SpvSampler and SpvVariable definitions public before verification/linking. A duplicate parent/Knot definition, a missed transform, or transform ordering can still produce the observed IllegalAccessError.

The local v16 agent already contains loader detection, a Spv* accessible-class list and special loader handling. Therefore the minimal experiment is diagnostic, not another blind premain:

The local agent’s manifest gate covers 1.21.11 and 26.1–26.4, but its Java 21-era launcher is not enough for 1.21.11: the verified vanilla run needs Java ≥22 because of FFM SymbolLookup.findOrThrow.

1. On the crashing launch, log MetalCrossShaderCompiler.class.getClassLoader(), each Spv* class loader, code source and Modifier.toString(...) of the classes/members.
2. Prove the widened modifier in the resulting bytecode and prove only one owner for each FQCN.
3. For Fabric, prefer a normal version-pinned mod: Fabric preLaunch entrypoint configures SPVC before LWJGL initializes; access widener makes the Mojang Spv* classes public; Mixins replace PreferredGraphicsApi and install Metal. MetalUniversal already does this and explicitly requires preLaunch ordering.
4. If a premain remains, use it only for instrumentation/native setup. Do not define a second backend copy in a parent loader.
5. For NeoForge, use a separate port with ModLauncher/NeoForge Access Transformers (the docs describe widening classes/methods/fields) and version-specific render hooks. This is a larger service/AT/module task; class-loader placement alone will not port Fabric mixins or GL-dependent mods.

## Version choice and ecosystem

Modrinth API facet counts (projects tagged with loader + game version; counts are projects, not installable files) and Sodium Fabric version-download sums:

| Game tag | Fabric mod projects | Fabric modpacks | Sodium Fabric downloads |
|---|---:|---:|---:|
| 1.21.11 | 18,191 | 2,922 | 42,275,067 |
| 26.1 | 11,133 | 466 | 7,215,587 |
| 26.1.2 | 13,545 | 1,370 | 16,279,746 |
| **26.2** | **13,583** | **1,597** | **19,350,282** |
| 26.3 | 9,005 | 765 | 8,851,767 |
| 26.4 | 0 | 0 | 0 (final not released; only snapshot-6 had 129 Fabric projects) |

Counts are not unique users and include all project releases matching the facet. 26.2 is the best intersection of a released iOS Metal backend, Sodium, and a broad mod catalog. 1.21.11 has the largest ecosystem and official Graft/GraftShaders assets but requires a Cofre Graft port. 26.3 is the forward track with official Metallum and Ciderlight desktop builds, but fewer tagged projects. Do not target 26.4 snapshots for the first kit.

Popular pack evidence is version-specific only when a pack version exists: Fabulously Optimized has matching Fabric builds/downloads of 3,462,589 (1.21.11), 2,568,107 (26.2) and 1,300,008 (26.3); Better Adventures+ has 71,269, 74,765 and 17,551 respectively. These packs include Iris/other renderer mods and are **ecosystem signals, not Metal-safe presets**. Adventure-pack facet counts are approximately 907 (1.21.11), 480 (26.2), 200 (26.3); query method and API snapshot should be recorded with any later refresh.

## Vulkan, MoltenVK and MetalFX

- Official [VulkanMod](https://github.com/xCollateral/VulkanMod) 0.6.8 supports 1.21.11 and 26.1–26.1.2 on Fabric/Quilt; NeoForge forks target other ranges. [MoltenVK](https://github.com/KhronosGroup/MoltenVK) is a Vulkan implementation over Metal on iOS, but this is still a translation layer and not a direct Metal backend. VulkanMod issue #329 discusses macOS/M1 MoltenVK requirements; PR #474 (Pojav iOS) is closed/unmerged. No reproducible Cofre/iOS FPS result was found. Air’s direct MoltenVK result (<10 FPS) is not a VulkanMod benchmark, so do not conflate them.
- MetalFX is useful only after a native backend is stable: it reduces GPU pixels, not Java tick/render translation cost. Metallum issue #15 says the spatial overhead often outweighs gains unless scale is below roughly 70%; MetalUniversal has an unmerged MetalFX/upscale branch. Add render-scale controls only with a native HUD, screenshot/rotation tests and a GPU-time acceptance threshold.

## Concrete Cofre plan

1. **Lock the 26.2 baseline:** one MetalUniversal 1.0.4 jar, one tested Sodium 0.9.0 jar, Fabric API and Mod Menu; bundle signed iOS libmetallum/libspvc through the existing framework path. Reject duplicate IDs and any Air agent injection in this profile.
2. **Deterministic startup:** set the preferred backend explicitly to Metal (do not rely on DEFAULT ordering); log backend, native paths, MC/Fabric/Sodium versions and a first-frame marker. Fail with a repair action if backend falls to GL.
3. **Metal kit resolver:** lock a JSON/profile per MC version/loader/backend, verify jar hashes, Java floor, native architecture and required access widener. Install only the starter allowlist; show a warning and offer a diagnostic launch for unknown render hooks.
4. **Mod preflight:** classify jars by declared dependencies and known render packages (com.mojang.blaze3d, org.lwjgl.opengl, Iris/Flywheel/Veil/Embeddium/ImmediatelyFast/EntityCulling). Block GL-only/renderer-owning mods on Metal with a clear explanation; allow gameplay/data mods after smoke test.
5. **Validation matrix:** vanilla → Sodium → each performance mod → UI/recipe mod → one worldgen mod → content stack; cold launch, join world, Nether, respawn, resource reload, suspend/resume, 10-minute thermal run. Acceptance: Metal log every launch, first frame, no GL context, stable 1% low and no memory/OOM regression.
6. **Parallel tracks:** port Graft 1.21.11 to Cofre’s existing CAMetalLayer; build MetalUniversal 26.3 dev; spike Ciderlight NeoForge 26.3 only after Fabric baseline. Keep shaders behind an experimental profile.
7. **Agent decision gate:** revisit Air loader bridging only if step 2 cannot be made deterministic; use the class-loader proof above before changing premain.
8. **Fallback policy:** retain GL/Vulkan translators behind Advanced/Debug; never call them the Metal kit or use their FPS as success evidence.

## Sources

- [Metallum](https://github.com/kokodio/metallum) · [Metallum releases](https://github.com/kokodio/metallum/releases) · [Metallum #27](https://github.com/kokodio/metallum/issues/27)
- [MetalUniversal](https://github.com/EternityQwQ/MetalUniversal) · [1.0.4 release](https://github.com/EternityQwQ/MetalUniversal/releases/tag/MetalUniversal_1.0.4) · [Iris PR #18](https://github.com/EternityQwQ/MetalUniversal/pull/18)
- [Graft](https://github.com/kkorenn/Graft) · [Graft v1.1.1](https://github.com/kkorenn/Graft/releases/tag/v1.1.1) · [GraftShaders](https://github.com/kkorenn/GraftShaders)
- [Ciderlight](https://github.com/riccqi/ciderlight) · [v0.1.17](https://github.com/riccqi/ciderlight/releases/tag/v0.1.17)
- [VulkanMod](https://github.com/xCollateral/VulkanMod) · [MoltenVK](https://github.com/KhronosGroup/MoltenVK)
- [JVMS §5.3/§5.4.4](https://docs.oracle.com/javase/specs/jvms/se25/html/jvms-5.html) · [Fabric access wideners](https://wiki.fabricmc.net/tutorial:accesswidening) · [NeoForge access transformers](https://docs.neoforged.net/docs/advanced/accesstransformers/)
- [Modrinth API](https://api.modrinth.com/v2/search) (facets/counts queried 2026-10-31)

