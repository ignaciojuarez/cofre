# Air vs. upstream Amethyst engine review

## Verdict

Do not switch Cofre’s runtime to a clean Amethyst checkout yet. Air is a substantially larger and more fragile fork, and the recent failures are real evidence of that: its automatic renderer chooses ANGLE for 26.3, its JNA/dyld path needs iOS-specific overrides, and its UI/JIT assumptions conflict with Cofre. However, the clean Amethyst tree does not currently provide a demonstrated replacement on the exact iPhone 17 Pro/iOS 27 TXM target: it has Java 25 and JIT26 work, but no Metallum path, no built-in JIT (request still open), and no proof of a first frame for 26.3 on that device. The lowest-risk path is (d): keep Air for the JVM, renderers, input and game surface, while moving data, progress, JIT ownership and screens into Cofre. In parallel, run one small (c) portability spike; switch only if it passes the device checkpoint below with parity.

## Options

| Option | MC 26.x capability | TXM JIT | Loaders | Renderers | Fragility / maintenance | Cofre integration cost | Decision |
|---|---|---|---|---|---|---|---|
| **(a) Stay on Air** | Strongest current path: Java 25, LWJGL 3.4.1/SDL3 selection, JNA 5.13 replacement, dyld validation bypass, and 26.x Metallum integration are present in the pinned tree. | Air has the UniversalJIT26/brk protocol and keep-attached mode. Cofre’s VPN now owns delivery through patch 0003. | Fabric/Quilt/Forge/NeoForge code is present, including direct Forge/NeoForge installers. | ANGLE, MobileGlues, MoltenVK/Vulkan, GL4ES-family renderers, plus Air’s Metallum/Metal path. | Largest tree: 38,482 tracked files, 5,326 under Natives (much of it vendored third-party code); 1,032 local commits since July 1; frequent build and renderer fixes. Four Cofre patches already sit on Air. | **Low now.** Fix Cofre’s launch policy and keep the existing bridge. | **Default while the spike runs.** |
| **(b) Clean upstream Amethyst** | The checkout has Java 25 commits (693be215, 64c5c9c4) and LWJGL/26.x plumbing, but not Air’s forced 26.3 JNA workaround, Metallum artifacts, or Air’s later 26.x fixes. | JIT26 and UniversalJIT26 are present; built-in JIT is still an open request ([#356](https://github.com/AngelAuraMC/Amethyst-iOS/issues/356)). | README documents Fabric, Quilt and Forge; NeoForge parity is not established in this checkout. | GL4ES, ANGLE, MobileGlues and Zink/OSMesa are listed; no Metallum path is present. | Much smaller core (425 tracked files; 126 native source/header files), but the upstream project has 199 open issues and no tagged releases. | **High.** Cofre’s root hook, bridge, JIT ownership and launch progress depend on Air symbols that do not exist upstream. 26.3/JNA/Metal behavior must be rebuilt and retested. | **Not a safe direct replacement.** |
| **(c) Amethyst core + selected Air pieces** | Retain upstream core, port Air’s Java 25/26.3 compatibility, JNA/dyld workarounds, SDL3 fixes and Metallum. | Port Cofre’s VPN provider and the smallest JIT hook; do not copy StikDebug AGPL code. | Port and characterize the loader/install pieces needed by Cofre; NeoForge and direct installers are large migrations. | Porting Metallum is the key blocker. Air contains metallum_agent.jar, libmetallum*.dylib and MetalUniversal; the checked tree does not state their standalone license, so provenance must be cleared before distribution. | Best long-term architecture only if the port becomes a maintained fork. Otherwise it creates two divergent engines and repeats Air’s compatibility work. | **High to very high.** A minimal first-frame port is weeks; full loader/renderer parity is a multi-month engine project. | **Run a bounded spike; do not make it the default yet.** |
| **(d) Air runtime + Cofre-owned outer layers** | Same proven Air capability, with explicit renderer/JNA policy in Cofre instead of Air’s hidden defaults. | Cofre already owns StikJIT delivery, the VPN and the launch decision; Air is bypassed through patch 0003. | Keep Air installers/downloaders behind typed Cofre facades until they can be replaced safely. | Select Metal/Metallum explicitly for 26.x; keep ANGLE/MobileGlues/Vulkan as tested fallbacks. | Reduces the surface Cofre must trust without replacing native-thread/JVM/rendering code. | **Low to medium, incremental.** plan/own-air.md ranks preferences, logs, worlds, profiles, then downloaders/accounts/installers. | **Recommended path.** |

## Evidence

### What the recent failures say

- **Waiting for the game window:** Cofre’s JIT script remained attached while the Air path expected a detach. That is a Cofre launch-policy bug, not evidence that the JVM or renderer is unusable.
- **JNA crash:** Minecraft 26.3 requests JNA 5.17, but iOS needs Air’s 5.13 replacement and dyld library-validation bypass. The device log shows both the initial native-library failure and the later successful JIT mode=attached dyld_bypass=on configuration. This is an engine/platform compatibility requirement exposed by a fragile default path.
- **Wrong orientation/size:** the portrait surface on a landscape display came from Cofre’s launch-flow change. The log later reports drawableSize=1206x2622 and GAME-LANDSCAPE, so this is integration sequencing, not a reason to replace the engine.
- **Vulkan/MoltenVK shader crash:** the device log explicitly says Air’s renderer=auto resolves to ANGLE. Minecraft 26.3 then fails its OpenGL glGetError check and falls toward Vulkan. Air’s own METAL_TUTORIAL.txt says 26.x should use its Metallum Metal path. This is a real Air default/renderer policy defect; Cofre should force an explicit renderer for 26.x.
- **Air UI bypasses:** Cofre has already replaced the launch screen, controls around it, Forge installer entry, overlay and crash presentation. That confirms the value of option (d), but those are integration seams rather than evidence that Air’s JVM/rendering core must be discarded.

### Engine capability and project health

- Both local engine licenses are GPL-3.0. Cofre is GPL-3.0, so combining either engine with Cofre is legally compatible, but a distributed derivative must provide corresponding source under GPL terms. That includes Cofre’s source, patches, build scripts and the exact engine revision. StikJIT is MPL-2.0; StikDebug is AGPL-3.0 and must remain a separate dependency. Air’s Metallum binaries have no clear standalone license notice in the checked tree; resolve that before selecting (c).
- Clean Amethyst’s current upstream API reports 1,618 stars, 556 forks and 199 open issues; its latest listed commit is f98c4133 (4 October) and GitHub shows no releases. Its history does contain Java 25 and JIT26 commits, so it is not an obsolete core, but its current issue list includes [iOS 27.0.1/26.3 crashing (#355)](https://github.com/AngelAuraMC/Amethyst-iOS/issues/355) and the open built-in-JIT request above.
- Air reports 219 stars, 36 forks and 25 open issues. It has tagged releases 5.0.0 (24 August) and 5.1.0 (1 October); the pinned c4797387 tree is 5.1.0 plus many post-release commits. The fork has a higher recent commit rate and more active compatibility work, but that activity is also a maintenance burden: the latest local sequence contains repeated build-fix commits immediately before the pin.
- Neither engine shows a first-party app-level unit/integration test suite in the checked source. Their workflows primarily build/package; native dependency tests are third-party tests. Device smoke tests are therefore the meaningful quality gate.
- Air’s native surface is materially larger: it has 425 top-level-depth .m/.h files before counting the extensive vendored libraries, versus 126 in clean Amethyst. Size alone does not prove worse code, but it raises the review, update and regression surface. The local Air history also contains large renderer imports and binary/class-set changes (for example 7be52f423 and 926629869).
- Air’s renderer provenance is mixed. RENDERER_GAP_PROVENANCE.md documents imports from a teammate fork, while Metallum is shipped as binary artifacts. That is workable for Cofre only with reproducible provenance and license records.

### What Cofre is coupled to

app/Glue/AirBridge/AirBridgeAdapter.m is 1,145 lines and imports JavaLauncher, SurfaceViewController, AmeLaunchProgress, ForgeDirectInstaller, NeoForgeDirectInstaller, WorldService, ServerService, BaseAuthenticator and Air preference/profile helpers. The launch path also hides Air’s private overlay via KVC and waits for Air notifications. The four patches in patches/air/README.md are already near the five-patch budget:

1. compile/load Cofre glue;
2. install Cofre’s root controller;
3. stop Air’s external JIT enablers when Cofre owns JIT;
4. publish a pre-first-frame JVM-exit notification.

A clean Amethyst switch would require replacing those symbols and reworking the launch surface, not merely changing a submodule URL. plan/own-air.md correctly identifies the hard boundary: keep JavaLauncher, JNI/JLI setup, egl_bridge, GL/Vulkan/SDL, input and SurfaceViewController until a replacement is demonstrably cheaper than maintaining the seam.

## Risks

- **False portability signal:** a clean build that reaches the launcher but lacks Metal/JNA/dyld fixes is not a valid 26.3 comparison.
- **Renderer regression:** default ANGLE can pass older Minecraft versions and still fail 26.3’s OpenGL checks; renderer selection must be part of the test matrix.
- **TXM protocol drift:** brk #0x69, brk #0xf00d, debugger-mapped regions and attach/detach state must be tested on the exact iPhone 17 Pro after every engine update.
- **Loader loss:** replacing Air’s direct Forge/NeoForge installers or its 26.x download rewrites means rebuilding large, poorly isolated services. ForgeDirectInstaller.m, NeoForgeDirectInstaller.m and ForgeProcessorExecutor.m are each over 1,100 lines.
- **License/provenance gap:** GPL-3.0 compatibility is fine, but Metallum’s artifact license and source obligations are not established by the GPL file alone.
- **Bus factor:** both projects rely heavily on a small contributor core. GitHub’s contributor list shows upstream dominated by khanhduytran0 and crystall1nedev; Air adds herbrine8403 and yitenchen123, which improves throughput but creates a fork-specific dependency.

## Recommended path

1. **Finish the Air baseline first.** On the iPhone 17 Pro/TXM, set renderer explicitly to Metallum/Metal for 26.3, keep JIT attached, and record three cold launches through the first Minecraft frame. Keep the existing Cofre JIT and surface fixes.
2. **Make Cofre own policy, not native runtime.** Move renderer choice, JIT state, launch progress, logs and crash state behind Cofre facades. Follow plan/own-air.md: preferences, logs, worlds, then profiles; leave JVM/render/input/surface in Air.
3. **Run one portability spike from clean Amethyst.** Port only the root hook, Cofre’s JIT provider, the launch callback and the minimum Java 25/26.3 compatibility fixes. Do not port the complete Air UI or installer stack.
4. **Characterize both engines with the same inputs:** vanilla 26.3, Fabric 26.3, one Forge or NeoForge instance, a pre-26 version, and the same JIT script, account, memory limit and renderer.
5. **Clear Metallum provenance before shipping option (c).** Record source, license, build inputs and whether the binary can be redistributed in a GPL-3.0 Cofre release.

### Decision checkpoint

Use the same development-signed build conditions on the exact iPhone 17 Pro/iOS 27 TXM phone. A candidate engine passes only if it produces a first frame in **3/3 cold launches** for vanilla 26.3 and **3/3** for Fabric 26.3, keeps the landscape surface correctly sized, survives Cofre’s JIT attach/keep-attached flow without an Air overlay, and reaches one Forge/NeoForge launch plus one pre-26 launch. If clean Amethyst passes this matrix with only the small selected ports, switch to (c). If it fails because it lacks Metallum/JNA/dyld/TXM behavior, keep Air and continue option (d); reassess only when upstream adds the missing capability or Cofre has a tested replacement.

