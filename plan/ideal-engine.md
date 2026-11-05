# Ideal engine: Minecraft 26.2+ on iOS, the way macOS runs it

Status: 🎯 approved (2026-11-05, decisions in §8).
- **Scope: Minecraft 26.2 and newer only.** 1.17–1.21.4 (raw OpenGL, 2–3 translation layers) and legacy versions are out of scope for performance work.
- **Targets:** iPhone 17 Pro (A19 Pro, 12 GB) and the new iPad mini (A20). The 4 GB iPad mini 6 is best effort.
- Facts were checked against primary sources (Mojang, GitHub, Mesa, LunarG, Apple) on 2026-11-05. ⚠️ marks unverified items.

## 1. Why 26.2+ is the right bet

- Since 26.2 the game renders through Blaze3D: a GPU abstraction with an official **Vulkan** backend plus OpenGL. 26.3 moved it to `com.mojang.renderpearl`. 26.4 snapshots **prefer Vulkan by default**.
- **On macOS**, Mojang runs that Vulkan backend through the MoltenVK bundled in LWJGL's natives, so Mac is 1 layer. iOS can do exactly the same, or use a Metal backend for 0 layers.
- **Mods are converging on the same seam:** Sodium 0.9 and Distant Horizons 3.1 render through Blaze3D, so they run on any backend.
- **One Java:** 26.x needs Java 25, so we own a single JDK, and every Java 25 feature (compact object headers, AOT cache) applies.
- **26.3 replaced GLFW with SDL**, and SDL3 has a native UIKit backend.
- **It already works decently:** 26.2 NeoForge with 35 mods on Metal runs 50–58 FPS at 16 chunks on the iPhone 17 Pro. Air's notes report vanilla Metal at 105+ FPS at 32 chunks.

## 2. Ideal stack

```
Cofre (SwiftUI) ─ instance · loader · mods · backend picker
      │  same process
      ▼
JIT setup: VPN up → StikJIT blesses N MB → detach → VPN down
      ▼
HotSpot JDK 25 (iOS port) · mirror-mapped code cache · compact headers · thread QoS
      ▼
Minecraft 26.2+ · Fabric / NeoForge
      ▼
LWJGL 3.4 (signed natives overlay) · SDL3 UIKit · OpenAL Soft
      ▼
Blaze3D / renderpearl
  ├─ Metal backend  (Cofre Metallum)            0 layers  ← fastest
  ├─ Vulkan backend (Mojang) ▸ MoltenVK ▸ Metal 1 layer   ← exactly macOS, auto-tracks new versions
  └─ OpenGL ▸ MobileGlues ▸ ANGLE ▸ Metal        emergency fallback only
```

| | macOS | Cofre today | Ideal |
|---|---|---|---|
| JIT | `MAP_JIT`, no limits | debugger **kept attached** (`JIT mode=attached dyld_bypass=on`) | debugger blesses one region, then **detaches**; VPN down |
| Code cache | 240 MB | 64 MB | 192–256 MB |
| RAM | swap, no limit | ~6 GB jetsam budget on 12 GB phones | 3.5–4 GB heap + native headroom; compact headers |
| Natives | signed arm64 | extracted at runtime + dyld bypass | signed **natives overlay** in `Frameworks/` |
| Render | Vulkan → MoltenVK (1) | Metal (0) via Air's agent or MetalUniversal | Metal (0) **and** Vulkan → MoltenVK (1) |

## 3. What still hurts on 26.x (Phase 0 measures these)

| # | Problem | Evidence |
|---|---|---|
| 1 | Memory climbs **+2–3 MB/s** in Metallum (title and world) | `[Cofre] perf` footprint 1492 → 2846 MB in 500 s |
| 2 | Worldgen dips (integrated server competes for 2 P-cores) | 17 Pro: 0–30 FPS during worldgen, server 2–3.5 s behind |
| 3 | Heat → FPS halves | `thermal=serious`, 57 → 28 → 10 on long runs |
| 4 | Frame pacing snaps to half rate | steady 28.6 FPS = 60 / 2 |
| 5 | Debugger kept attached | breakpoint-only exception ports, but traced signals still go through XNU |
| 6 | Code cache 64 MB with 100 mods | unmeasured |
| 7 | Slow modded start | 100 mods: ~95 s to first frame (iPad) |
| 8 | Shader/pipeline compile stutter | no persistent pipeline cache yet |

## 4. Phases

### Phase 0 — Measure (≈1 week, iPhone 17 Pro)
- One bench: fixed seed and camera path, flight through new chunks plus standing still. Record FPS avg, 1% low, frame-time p95, footprint over 30 min, thermal and first-frame time.
- In-game **JFR** (`-XX:StartFlightRecording`) analyzed in JDK Mission Control; `-Xlog:codecache`; Metal Performance HUD in dev builds.
- Reference setups:
  - A: vanilla 26.3 on Metal
  - B: vanilla 26.3 on Vulkan → MoltenVK
  - C: Fabric 26.2/26.3 + Sodium 0.9 + 30 mods
  - D: NeoForge 26.2 + 100 mods
- ✅ Exit: a "where the 16.6 ms go" page per setup.

### Phase 1 — JVM and JIT (≈2 weeks)
| # | Change | Verify |
|---|---|---|
| 1.1 | **Natives overlay**: every native ships signed in `Frameworks/` (LWJGL 3.4 modules, SDL3, JNA, libmetallum, spvc, shaderc, MoltenVK, mod natives). Redirect `org.lwjgl.librarypath`, `jna.boot.library.path` and `java.library.path`; log every `dlopen` | 100-mod pack loads with no dyld bypass |
| 1.2 | **Detach after blessing** (StikJIT documents prepare → alias → detach); VPN down after launch | same-build A/B: FPS, 1% low, temperature |
| 1.3 | Code cache 192–256 MB | `-Xlog:codecache` peak < 70% |
| 1.4 | `-XX:+UseCompactObjectHeaders` (our signing has extended VA, so compressed class pointers stay on) | heap after GC −10–20% |
| 1.5 | GC A/B: G1 vs generational ZGC vs Parallel | best 1% low |
| 1.6 | **Thread QoS** agent: render = user-interactive, server = user-initiated, chunk/GC/C2 = utility | 1% low, temperature |
| 1.7 | Heap model: 3.5–4 GB for big packs on 12 GB devices; optional `increased-debugging-memory-limit` (+~0.5 GB) | 30 min, no jetsam |
| 1.8 | AOT cache (JEP 483/514/515) for vanilla and app-loader libraries | cold start time |
| 1.9 | Own a single **JDK 25 iOS build** (from `angelauramc-openjdk-build`, mirror-mapping patch) | reproducible build |

### Phase 2 — Backends (the core)
**2A · Cofre Metallum (0 layers)**
- Fork kokodio/metallum (0.0.25 already supports 26.3), add the iOS host layer (as in our Graft patch) and send it upstream. This replaces MetalUniversal, which is stuck on 26.2.
- Building from source also settles the Metallum license/provenance question for public release.
- First fixes: cut the per-draw-call log line (7 MB in 3 min), fix the memory climb, and fix the crash when Graphics, mipmaps or resource packs change mid-game.
- Add `MTLBinaryArchive` pipeline caches, triple buffering, `preferredFrameRateRange` pacing (60 / 120), and MetalFX upscaling (Graft has a reference).
- Port every new MC version within days; 26.4 is next.

**2B · Mojang Vulkan → MoltenVK (1 layer)**
- MoltenVK on iOS has the required dynamic rendering and push descriptors. An Amethyst fork reports 26.x Vulkan working on iOS ⚠️.
- Re-measure Air's "single-digit FPS" with a release MoltenVK config: no validation, Metal argument buffers, pipeline cache, correct present mode.
- Works with **NeoForge without the Connector kit** (it's vanilla code).
- Future: KosmicKrisp (Mesa, Vulkan 1.4 conformant on Mac; LunarG has an internal iOS build) as a drop-in replacement for MoltenVK.

**2C · Auto choice**
- Pick per version, loader and mod set from bench results: Metal when the mod set is Metal-clean, Vulkan otherwise.
- Keep OpenGL only as the emergency fallback.

**2D · SDL3** for 26.3+: native UIKit window, touch, keyboard, mouse and pointer lock.

### Phase 3 — Mods on 26.x
- Sodium 0.9 and Distant Horizons 3.1 on both backends.
- NeoForge: Vulkan natively; on Metal, the Connector kit (or Ciderlight on 26.3, which has no Sodium).
- Shaders: Iris refuses Vulkan and needs GL, so none today. Its successor **Aperture** builds on Slang, which emits MSL: track it.
- `known-mods` verdicts per backend; natives overlay for Simple Voice Chat (Opus) and Distant Horizons (sqlite).
- Check popular performance mods (Sodium, Lithium, FerriteCore, ModernFix, ImmediatelyFast; C2ME after a worldgen A/B) on both backends and record verdicts. There's no bundled Performance pack (decided against in the roadmap).

### Phase 4 — Product
- Backend picker: **Metal · Vulkan · OpenGL (fallback)**. The other ~10 renderers come out of the UI.
- Version picker: 26.2+ by default; older versions sit under a **"Not optimized"** disclosure.
- Debugger detach becomes the default once the Phase 1 A/B passes.
- The game's Video Settings own quality and frame rate. Presets, heat-aware lowering and heat banners stay decided against (ROADMAP). Backend features like MetalFX surface as in-game options.
- Dev-only benchmark scenario with a shareable report.
- 💡 Optional: host the world on the paired Mac (Llave) so the phone only renders.

## 5. Repos in scope

| Layer | Repo | License | Plan |
|---|---|---|---|
| JIT | StikDebug/StikJIT · jkcoxson/idevice | MPL-2.0 · MIT | ✅ keep, add detach mode |
| JVM | AngelAuraMC/angelauramc-openjdk-build (JDK 25 + mirror mapping) | GPL-2.0+CE | 🆕 own the build |
| Engine host | Air (Amethyst-iOS-MyRemastered) | GPL-3.0 | ✅ keep JVM, surface, input; shrink |
| LWJGL | LWJGL/lwjgl3 3.4.x + iOS fork | BSD | 🆕 signed natives overlay (PrismLauncher/meta model) |
| Window/input | libsdl-org/SDL 3 | zlib | 🆕 for 26.3+ |
| Audio | kcat/openal-soft | LGPL | ✅ |
| Metal backend | kokodio/metallum 0.0.25 | MIT | 🆕 Cofre Metallum fork |
| Metal refs | EternityQwQ/MetalUniversal (26.2) · korendotcs/Graft 1.1.1 (26.2/26.3, MetalFX) · riccqi/ciderlight (26.3, NeoForge) | MIT · LGPL-3.0 · Apache | reference / fallback |
| Vulkan | KhronosGroup/MoltenVK | Apache | 🆕 co-primary |
| Vulkan next | Mesa KosmicKrisp | MIT | 🔬 iOS bet |
| GL fallback | MobileGL-Dev/MobileGlues · google/angle | LGPL · BSD | emergency only |
| Shaders | SPIRV-Cross · shaderc · shader-slang/slang | Apache | ✅ + MTLBinaryArchive |
| Mods | Sodium 0.9 · Distant Horizons 3.1 · Lithium · FerriteCore · ModernFix · ImmediatelyFast · Sinytra Connector + Forgified Fabric API · Iris/Aperture | various | presets |
| Tooling | JDK Mission Control (JFR) · Metal Performance HUD · Instruments | — | Phase 0 |

## 6. Out of scope (❌)
- 1.17–1.21.4 and legacy performance work (Zink, LTW, GL4ES, MGL, Graft legacy, VulkanMod, Java 8).
- HotSpot Zero / `-Xint`, GraalVM native image, BrowserEngineKit JIT, TrollStore.
- Tuning for 4 GB devices.

## 7. Targets (iPhone 17 Pro)
| Setup | Goal |
|---|---|
| Vanilla 26.x | 120 FPS at 12–16 chunks; 60 locked at 32 |
| Fabric + Sodium + 50 mods | 60 locked, 1% low ≥ 45 |
| NeoForge + 100 mods | ≥ 50 FPS at 12 chunks |
| Flying through new chunks | 1% low ≥ 30 |
| Memory | flat after 10 min; 30 min without jetsam |
| Cold start | vanilla < 20 s, 100 mods < 60 s |

## 8. Decisions (Ignacio, 2026-11-05)
| # | Decision |
|---|---|
| 1 | ✅ Fork Metallum as **Cofre Metallum** (from kokodio/metallum; MetalUniversal is reference only) |
| 2 | ✅ Mojang Vulkan → MoltenVK is a **co-primary backend**. Metal stays the default where its mod set is clean; Vulkan covers the rest (NeoForge without the kit, new MC versions before Metallum is ported). Phase 0 numbers decide the Auto rules |
| 3 | ✅ Versions older than 26.2 are hidden in the picker behind a **"Not optimized"** disclosure |
| 4 | ✅ Detaching the debugger becomes the default once the same-build A/B passes on the iPhone 17 Pro |

## Sources
[MC 26.2](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-2) · [26.4 Snapshot 1](https://www.minecraft.net/en-us/article/minecraft-26-4-snapshot-1) · [NeoForged 26.3 primer](https://docs.neoforged.net/primer/docs/26.3/) · [LWJGL Vulkan natives with MoltenVK](https://libraries.minecraft.net/org/lwjgl/lwjgl-vulkan/3.4.1/lwjgl-vulkan-3.4.1-natives-macos-arm64.jar) · [Sodium 0.9.0](https://github.com/CaffeineMC/sodium/releases/tag/mc26.2-0.9.0) · [DH 3.1.0-b](https://modrinth.com/mod/distanthorizons/version/3.1.0-b-26.2) · [Iris 26.3 Vulkan refusal](https://github.com/IrisShaders/Iris/blob/26.3/common/src/main/java/net/irisshaders/iris/compat/sodium/config/ShaderPackScreenPlaceholder.java) · [Aperture](https://github.com/IrisShaders/docs/blob/main/src/content/docs/aperture/migration.mdx) · [MoltenVK](https://github.com/KhronosGroup/MoltenVK) · [iOS 26.x Vulkan report](https://github.com/Taylen27/Amethyst-iOS/releases/tag/1.0.0) · [KosmicKrisp 1.4](https://www.khronos.org/news/permalink/kosmickrisp-achieves-vulkan-1.4-conformance-on-apple-silicon) · [LunarG Oct 2026](https://www.lunarg.com/the-state-of-vulkan-on-apple-oct-2026/) · [Metallum 0.0.25](https://github.com/kokodio/metallum/releases/tag/v0.0.25) · [MetalUniversal](https://github.com/EternityQwQ/MetalUniversal) · [Graft 1.1.1](https://github.com/korendotcs/Graft/releases/tag/v1.1.1) · [Ciderlight](https://github.com/riccqi/ciderlight) · [StikJIT integration](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md) · [Amethyst JIT extension](https://github.com/AngelAuraMC/Amethyst-iOS/blob/main/Natives/resources/UniversalJIT26Extension.js) · [XNU traced signals](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sig.c#L2715) · [JDK mirror patches](https://github.com/AngelAuraMC/angelauramc-openjdk-build/tree/duy/buildjre17-21-25-ios/patches) · [Apple capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios/) · [17 Pro Max memory](https://developer.apple.com/forums/thread/834805) · [JEP 519](https://openjdk.org/jeps/519) · [JEP 483](https://openjdk.org/jeps/483) · [QoS](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/PrioritizeWorkWithQoS.html) · [Prism meta overrides](https://github.com/PrismLauncher/meta/blob/main/meta/common/mojang-library-patches.json)
