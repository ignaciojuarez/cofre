# Ready-made Cofre presets

**Snapshot:** 2026-10-31. Modrinth `/v2/project/<slug>/version` was queried with the exact game version and loader. A pin is not a shipping claim: a preset is shown as **Recommended** only after its scenario has a first frame, 60-second run, and no compatibility marker on the target device.

**Safety labels:** ✅ no direct OpenGL/Vulkan calls found or expected; ⚠ renderer integration or device proof still required; ❌ GL-only/unknown and excluded from a Metal preset. Sodium is ✅ only as the tested MetalUniversal/Metallum pairing; stock Sodium is an OpenGL renderer.

## Availability checks for optional additions

These were queried too, but are **not** in the default fast kits until the renderer scanner and device run pass. `NONE` means Modrinth returned no matching release for that exact version/loader on 2026-10-31.

| Project | Fabric 26.2 | Fabric 1.21.11 | Policy |
|---|---|---|---|
| `inventory-profiles-next` (`O7RBXm3n`) | `oQFRysLk` · `InventoryProfilesNext-fabric-26.2-2.3.8.jar` | `YKjWPbto` · `InventoryProfilesNext-fabric-1.21.11-2.2.6.jar` | Optional touch helper; AGPL acknowledgement. |
| `midnightcontrols` (`bXX9h73M`) | `5kdN2hnR` · `midnightcontrols-fabric-1.12.1+26.2.jar` | `yXQyceiT` · `midnightcontrols-fabric-1.12.0+1.21.11.jar` | Alternative to Controlify; choose one. |
| `entityculling` (`NNAgCjsB`) | `uXe0pIaz` · `entityculling-fabric-1.11.3-mc26.2.jar` | `CTabrwB1` · `entityculling-fabric-1.11.3-mc1.21.11.jar` | GL/occlusion audit required; excluded. |
| `emi` (`fRiHVvU7`) | **NONE** | **NONE** | Use JEI on NeoForge; scan any future build before Metal. |
| `jei` (`u6dRKJwZ`) | `j62WSkzi` · `jei-26.2-fabric-30.48.0.244.jar` | `e56U66Sq` · `jei-1.21.11-fabric-27.54.0.116.jar` | Recipe UI; scan before adding to Metal. |
| `journeymap` (`lfHFW1mp`) | `C6LURNke` · `journeymap-fabric-26.2-6.0.10.jar` | `6Np0S5K2` · `journeymap-fabric-1.21.11-6.0.0.jar` | Large optional map surface; never a fast default. |
| `xaeros-minimap` (`1bokaNcj`) | `kYWdcLLn` · `xaerominimap-fabric-26.2-26.6.2.jar` | `g0LRDWwe` · `xaerominimap-fabric-1.21.11-26.6.2.jar` | Optional map; same audit rule. |
| `xaeros-world-map` (`NcUtCpym`) | `W8qSt5Gs` · `xaeroworldmap-fabric-26.2-1.47.2.jar` | `ksfmc45B` · `xaeroworldmap-fabric-1.21.11-1.47.2.jar` | Optional map; same audit rule. |
| `modernfix` (`nmDcB62a`) | **NONE** | **NONE** | Available for Classic 1.21.1 only in this snapshot. |


## Preset cards

| Preset | Version · loader | Renderer | One-line pitch | State |
|---|---|---|---|---|
| **Vanilla+ · Metal latest** | 26.3 · Vanilla | Metal (Air agent) | “The cleanest, fastest supported Minecraft.” | Candidate; vanilla 26.3 rendered on iPad mini at 2 chunks, but 4 GB OOMs at 8 chunks and changing Graphics can crash AGXMetal. |
| **Fabric Performance · Metal** | 26.2 · Fabric 0.20.1 | MetalUniversal/Metallum + Sodium | “A small, fast kit with the Metal path already selected.” | Candidate; the Metallum handoff rendered ~57 FPS but had a black/visibility run and a flaky second launch. Ship only after three cold launches pass. |
| **Fabric Adventure · Graft Metal** | 1.21.11 · Fabric 0.20.1 | Graft 1.1.1 (external release) | “The biggest Fabric mod library on the native-Metal route.” | Port/validation gate; Graft is macOS-oriented and has no Modrinth project. |
| **NeoForge Starter · experimental** | 26.2 · NeoForge 26.2.0.93 | MobileGlues fallback | “Start a NeoForge pack while the iOS Metal route is investigated.” | Warned, never default-recommended; Metal on NeoForge is blocked until Ciderlight or another route is device-proven. |
| **Classic Modded · slow compatibility** | 1.21.1 · NeoForge 21.1.265 | MobileGlues (OpenGL translation) | “Broad older-mod coverage when speed is secondary.” | Warned; 1.21.1 cannot use Metal. The iPad mini run reached ~30 FPS on a small pack and OOMed at high distance. |

All five are created by the same instance path; no `.mrpack` is required. The first two are the only cards eligible for a future fast-path badge, and only after their scenarios pass.

## Exact contents and why

The table is the canonical project/license record. “Metal-safe” means the jar does not itself submit OpenGL/Vulkan; it does not certify a renderer fork or every transitive dependency.

| Mod / slug | Modrinth project | License | Metal-safe? | Purpose / policy |
|---|---|---|---|---|
| Fabric API · `fabric-api` | `P7dR8mSH` | Apache-2.0 | ✅ | Fabric hooks required by the loader and most helper mods. |
| Metallum/MetalUniversal package · `metallum-mc` | `w79ASAJD` | MIT | ⚠ | Native Metal bridge. Cofre must confirm that the bundled artifact is the reviewed MetalUniversal 1.0.4/iOS build; never install two `metallum` jars. |
| Sodium · `sodium` | `AANobbMI` | Polyform Shield 1.0.0 | ⚠ | Chunk/render optimisation. Direct GL in stock form; allowed only with the pinned MetalUniversal/Metallum handoff. |
| Lithium · `lithium` | `gvQqBUqZ` | LGPL-3.0-only | ✅ | Server/tick optimisation; no renderer calls. |
| FerriteCore · `ferrite-core` | `uXXizFIs` | MIT | ✅ | Reduces memory use, especially on 4 GB devices. |
| ModernFix · `modernfix` | `nmDcB62a` | LGPL-3.0-only | ✅ | Startup/memory fixes. No 26.2 or 1.21.11 release in this snapshot; used only by Classic 1.21.1. |
| Krypton · `krypton` | `fQEb0iXm` | LGPL-3.0-only | ✅ | Networking and packet allocation optimisation. |
| Entity Culling · `entityculling` | `NNAgCjsB` | Protective License (project URL) | ❌/unknown | Uses visibility/occlusion hooks that need a Metal audit; do not bundle. Offer only after the compatibility scanner and device test pass. |
| Mouse Tweaks · `mouse-tweaks` | `aC3cM3Vq` | BSD-3-Clause | ✅ | Drag/quick-transfer behavior that makes Cofre’s touch-to-mouse inventory usable. |
| Inventory Profiles Next · `inventory-profiles-next` | `O7RBXm3n` | AGPL-3.0-or-later | ✅/optional | Sort/move-all controls. Optional install, never bundled, with its license shown before install. |
| Controlify · `controlify` | `DOUdJVEm` | LGPL-3.0-or-later | ✅/optional | Controller mapping and menu navigation. Prefer this over two controller mods at once. |
| MidnightControls · `midnightcontrols` | `bXX9h73M` | MIT | ✅/optional | Alternative controller/touch cursor helper; offer as a mutually exclusive choice with Controlify. |
| Mod Menu · `modmenu` | `mOgUt4GM` | MIT | ✅ | Exposes installed mods/settings; no direct GL expected. |
| EMI · `emi` | `fRiHVvU7` | MIT | ⚠ | Recipe/item search. UI rendering must be scanned for direct GL before a Metal bundle. |
| JEI · `jei` | `u6dRKJwZ` | MIT | ⚠ | Recipe/item search for NeoForge/Classic. Validate the exact loader build; do not assume UI compatibility. |
| JourneyMap · `journeymap` | `lfHFW1mp` | All Rights Reserved | ⚠ | Optional map/QoL; large UI and renderer surface, so never part of the fast default. |
| Xaero’s Minimap · `xaeros-minimap` | `1bokaNcj` | All Rights Reserved | ⚠ | Optional map/QoL; same Metal audit rule. |
| Xaero’s World Map · `xaeros-world-map` | `NcUtCpym` | All Rights Reserved | ⚠ | Optional map/QoL; same Metal audit rule. |
| Graft · external `graft-1.21.11-1.1.1.jar` | **No Modrinth project** | LGPL-3.0 | ⚠ | Native-Metal renderer for the 1.21.11 track; GitHub release asset, macOS assumptions require an iOS port. |
| GraftShaders · external `graftshaders-1.21.11-1.0.1.jar` | **No Modrinth project** | LGPL-3.0 | ⚠ | Optional matching shader fork. Keep off in the initial preset; stock Iris is OpenGL-only and blocked. |
| RenderScale · `renderscale` | `Va8PJBFX` | MIT | ⚠ | Optional 50% world scale with full-resolution UI; useful for the slow Classic card only after a device run. |
| Ciderlight · external | **No Modrinth project** | Apache-2.0 + NOTICE | ⚠ | NeoForge Metal investigation target, not a current preset dependency. |

### Preset 1 — Vanilla+ · Metal latest

- **Exact mods:** none. Metal comes from Cofre/Air’s version-gated agent, so there is no Modrinth jar to resolve.
- **Options on first create:** `renderDistance=4` / `simulationDistance=4` on 4 GB; `8` / `6` on 12 GB; `entityDistanceScaling=0.5` (4 GB) or `0.75` (12 GB); `mipmapLevels=1`; `menuBackgroundBlurriness=0`; `touchscreen=false`; `maxFps=60`; `enableVsync=true`. Do not expose an in-game Graphics preset change until the Metal reload crash is fixed.
- **Memory/performance:** 4 GB is a low-distance profile and must show an OOM caution; 12 GB can start at 8/6 and raise distance after a successful first world. Keep pause/menu blur off because it caused a ~650 MB spike.

### Preset 2 — Fabric Performance · Metal 26.2

- **Loader:** Fabric 0.20.1; **renderer:** MetalUniversal/Metallum kit. The API package below is the candidate pin; the implementation must verify its iOS native payload and provenance against the reviewed MetalUniversal 1.0.4 jar.
- **Bundled mods:** Fabric API (loader hooks); Metallum (Metal handoff); Sodium (render/chunk speed, only in that handoff); Lithium (tick speed); FerriteCore (RAM); Krypton (networking); Mouse Tweaks (touch inventory); Mod Menu (settings); Controlify (controller support). **Do not bundle:** Iris, Entity Culling, IPN, EMI/JEI, maps, shader packs, or any jar flagged direct-GL by the scanner.
- **Options:** 4 GB `renderDistance=4`, `simulationDistance=4`, `entityDistanceScaling=0.5`, `mipmapLevels=1`, blur `0`, touchscreen `false`, 60 FPS; 12 GB `8/6`, `0.75`, mipmap `2`, blur `0`, touchscreen `false`, 90 FPS.
- **Memory/performance:** target ≤1.2 GB peak before world assets on 4 GB and ≤3 GB on 12 GB; keep Java heap conservative and leave OS headroom. A Metal run must log `Using graphics backend Metal`; any `GlBackend`, `No GLCapabilities`, or black frame fails the preset.
- **Optional:** IPN can be installed from the touch card after its AGPL acknowledgement; it creates a fork of the preset if it is later found unsafe.

### Preset 3 — Fabric Adventure · Graft Metal 1.21.11

- **Loader:** Fabric 0.20.1; **renderer:** Graft 1.1.1 external asset. No stock Iris. GraftShaders is an opt-in experiment only.
- **Bundled mods:** Fabric API (hooks); Graft (Metal renderer); Lithium (tick speed); FerriteCore (RAM); Krypton (networking); Mouse Tweaks (touch inventory); Mod Menu (settings); Controlify (controller support). Sodium is deliberately **not** bundled until Graft’s renderer/Sodium contract is proven on iOS.
- **Options:** 4 GB `renderDistance=6`, `simulationDistance=4`, `entityDistanceScaling=0.5`, `mipmapLevels=1`, blur `0`, touchscreen `false`, 60 FPS; 12 GB `12/8`, `0.75`, mipmap `2`, blur `0`, touchscreen `false`, 90 FPS.
- **Memory/performance:** keep shaders off and start without maps; a Graft port must prove a first frame, touch menus, controller input and 60 seconds before the card loses its “port/validation” label.

### Preset 4 — NeoForge Starter · 26.2 experimental

- **Loader:** NeoForge 26.2.0.93; **renderer:** MobileGlues. Metal is blocked for NeoForge by the renderer matrix, so this card is an honest compatibility starter, not a fast preset.
- **Bundled mods:** FerriteCore (RAM); Lithium (tick speed); Mouse Tweaks (touch inventory); Controlify (controller support); JEI (recipe search). Exclude Sodium (its renderer is GL), Entity Culling, shaders and maps. ModernFix/Krypton have no NeoForge 26.2 pin in the API snapshot.
- **Options:** 4 GB `renderDistance=4`, `simulationDistance=4`, `entityDistanceScaling=0.5`, `mipmapLevels=1`, blur `0`, touchscreen `false`, 45–60 FPS; 12 GB `8/6`, `0.75`, mipmap `2`, blur `0`, touchscreen `false`, 60 FPS. Cofre’s MobileGlues FSR stays off (`mobileglues.fsr1_setting=0`).
- **Memory/performance:** always show “OpenGL translation: high CPU / slower”; never put this card above a validated Metal card. The first world must be tested at low distance because the 4 GB iPad run OOMed at 8 chunks.

### Preset 5 — Classic Modded · 1.21.1 slow compatibility

- **Loader:** NeoForge 21.1.265; **renderer:** MobileGlues. This is the explicit warning path for packs that cannot use Metal.
- **Bundled mods:** FerriteCore (RAM); ModernFix (startup/memory); Mouse Tweaks (touch inventory); Controlify (controller); JEI (recipes). RenderScale 2.0.0-beta.1 is an optional “sharp UI at low resolution” add-on, not default.
- **Options:** 4 GB `renderDistance=4`, `simulationDistance=4`, `entityDistanceScaling=0.5`, `mipmapLevels=1`, blur `0`, touchscreen `false`, 45 FPS; 12 GB `8/6`, `0.75`, mipmap `2`, blur `0`, touchscreen `false`, 60 FPS. FSR remains off.
- **Warning:** “This version cannot use native Metal; OpenGL translation can be CPU-bound and under 20 FPS with larger packs.” The user may continue, but Cofre records the override and shows the warning on Play.

## Pin ledger (Modrinth API snapshot)

Each line is `project slug (project id): version id → primary filename; SHA-512`. These are the exact files used by the candidate manifests. Transitive dependencies returned by Modrinth are resolved and pinned too; they are not hand-copied into this list.

### Fabric 26.2

- `fabric-api (P7dR8mSH)`: `ewUK83HI` → `fabric-api-0.161.0+26.2.jar`; `2502fa5ade78e9a120b3747bc1a9a2167d6671743bea45bf115d3174c94121aeda87c549446d1a604a9c11fb828de17a551e3514ce42f3e93069dd14bdaee55b`
- `metallum-mc (w79ASAJD)`: `T69b1wTO` → `metallum-0.0.24.jar`; `01996e0546dadc9c541aae2351c47e93fc87716f1ef962d180b0fca5a7c70dafdf320cc7b60d7272dd165c0a45172b460d0ec9313c7d2542a52d70f9e915ac6c`
- `sodium (AANobbMI)`: `xJZxADzI` → `sodium-fabric-0.9.2+mc26.2.jar`; `9b7a7aade8824543ce2a804fddfd04e37f57d1f91c00574e7dc87e554eb1835d888313ee6f715a7599bd729840cf01fd74e02aeae87b4e5a3c10c34a016e407c`
- `lithium (gvQqBUqZ)`: `f7vZ0VWU` → `lithium-fabric-0.25.3+mc26.2.jar`; `148b638f3c6229fbaf487120a2344a0af5e411a5aa6533d5db9d75da0a8c0d8304f63eb4cca13f4d03b2c9b4c23d559dd74c1d832422ef8a3087bd005e62a8bd`
- `ferrite-core (uXXizFIs)`: `d5ddUdiB` → `ferritecore-9.0.0-fabric.jar`; `d81fa97e11784c19d42f89c2f433831d007603dd7193cee45fa177e4a6a9c52b384b198586e04a0f7f63cd996fed713322578bde9a8db57e1188854ae5cbe584`
- `krypton (fQEb0iXm)`: `5WeL0Nkz` → `krypton-0.3.1.jar`; `b8d9af34cd0050493afb8a6232cb8f785daa9d8887b7045f6e6a53c6bb9b5ffc4318fd9b0347a940eacfeba4773f10cb80ae0be1e79ce4c1888f96eda21e564e`
- `mouse-tweaks (aC3cM3Vq)`: `jOiTBIaB` → `MouseTweaks-fabric-mc26.2-2.31.jar`; `bc77723465dc4aef7a3a8fa2fea3641df1e6ba7cc8a2d86cd2659ef65ca661f6a763d3997fdaed1f8ff6c78a4c6061f8074160ca3162a29021735779a6c55e46`
- `controlify (DOUdJVEm)`: `VDw4mGkG` → `controlify-3.5.3+mc26.2-universal.jar`; `fa590eeebeb7ce4be828456dd796dd786919b7a8c664a4e509fc1c4a82414a349c598a5c968e4b4974abcdb3db1d32d03a7f38a532d924308a5b382bdf28437a`
- `modmenu (mOgUt4GM)`: `iRo7AZXf` → `modmenu-20.0.3.jar`; `c8224aa7a460d0c56ccb9978a112e4ad0d3eb17e2796e0c468a2392d220749f4f602838a11b3666145462c26078a879ab8a2fc177aa440f58e189c92a0088d6e`

### Fabric 1.21.11 / Graft external

- `fabric-api (P7dR8mSH)`: `6qAuTtLR` → `fabric-api-0.141.6+1.21.11.jar`; `852d3682c4f353fd0ca86546af8578513e8bcf628377fa9d49c556bc59c5024c69ab56c92fc6dfba11fed19e4316a3f5636e7e07fd3d96f7043b531aef59b637`
- `lithium (gvQqBUqZ)`: `Ow7wA0kG` → `lithium-fabric-0.21.4+mc1.21.11.jar`; `f14a5c3d2fad786347ca25083f902139694f618b7c103947f2fd067a7c5ee88a63e1ef8926f7d693ea79ed7d00f57317bae77ef9c2d630bf5ed01ac97a752b94`
- `ferrite-core (uXXizFIs)`: `Ii0gP3D8` → `ferritecore-8.2.0-fabric.jar`; `3210926a82eb32efd9bcebabe2f6c053daf5c4337eebc6d5bacba96d283510afbde646e7e195751de795ec70a2ea44fef77cb54bf22c8e57bb832d6217418869`
- `krypton (fQEb0iXm)`: `O9LmWYR7` → `krypton-0.2.10.jar`; `4dcd7228d1890ddfc78c99ff284b45f9cf40aae77ef6359308e26d06fa0d938365255696af4cc12d524c46c4886cdcd19268c165a2bf0a2835202fe857da5cab`
- `mouse-tweaks (aC3cM3Vq)`: `i1duwnJl` → `MouseTweaks-fabric-mc1.21.11-2.30.jar`; `bc2202d067f997a191d6e435d326e12cc5756b72c076e0e342e9f3119dbeb29de7b77fac62d8b48a60e657c79e35bc7e248df969d43f9b5e53492f7890fc2b9c`
- `controlify (DOUdJVEm)`: `qZW7FPjm` → `controlify-3.0.1+lts+1.21.11-fabric.jar`; `1a7bbcba7b721b28ed5e46fa5e94bf795251c9476939f34049a83d64a16ce56cdb2a6841c768f4393fa1b1ba67215c67fe7fdd14a29d1770f03d4c812b10fcde`
- `modmenu (mOgUt4GM)`: `cLkYaVuL` → `modmenu-17.0.1.jar`; `cb68cc39c8da66d05a1d2054a0e7b62144881e0cdb5fd681bc4f337b1313fafac394246f4e0aa0c4b6343db9e9750250a00c1bb72689b762da685ce1ccfee51f`
- External `Graft v1.1.1` → `graft-1.21.11-1.1.1.jar`; SHA-512 `026902fccaf03b3b5f30c3085ea44141706f0751ac46a6202c701297d35fa2994272720af0c0fe568956e27d410d0eb1666c23a1272a8e5688989ec61032aa3a`
- Optional external `GraftShaders v1.0.1` → `graftshaders-1.21.11-1.0.1.jar`; SHA-512 `8369c1ecf07b3b32adb18c03bc6a71678d0d3031cd38ee239b5b20b88e60b567b46e54f258e07cc78ee7d9d128a062b16696cd48e558349ee4f3d32573207a7f`

### NeoForge 26.2 and 1.21.1

- 26.2 `ferrite-core (uXXizFIs)`: `LtVvw4uS` → `ferritecore-9.0.0-neoforge.jar`; `e96a99ac5539f56a1f4cd109d62b668ebd5283f0068491ede956f52e67023beba7abe2e40021499352ffc41ead950bebcabce7792352249a1b45c5dccb3cf99c`
- 26.2 `lithium (gvQqBUqZ)`: `J9CowDXK` → `lithium-neoforge-0.25.3+mc26.2.jar`; `56f5299bc84084f2112abf61ea58bad101a7495cc8a1db3df0963494bce096e474c0bde0975831c30ec15c5c977451a31f82de90a09b769c94df91dbcb9b9286`
- 26.2 `mouse-tweaks (aC3cM3Vq)`: `rokwij6O` → `MouseTweaks-neoforge-mc26.2-2.31.jar`; `2cc9fbf44a704bfcec9a6744ff1c8025c22c6675196e25fbeae213d4e30872478763ffc82e902f0b19cfb7fdd8c4295407dab57f22911e34f299df1b1ed20379`
- 26.2 `controlify (DOUdJVEm)`: `VDw4mGkG` → `controlify-3.5.3+mc26.2-universal.jar`; `fa590eeebeb7ce4be828456dd796dd786919b7a8c664a4e509fc1c4a82414a349c598a5c968e4b4974abcdb3db1d32d03a7f38a532d924308a5b382bdf28437a`
- 26.2 `jei (u6dRKJwZ)`: `lU7Sz0zI` → `jei-26.2-neoforge-30.48.0.244.jar`; `eb9c66808518b5f78e624dfd38c8a541daa19948f0269e42c3d9e6c24f72a8f401124572c1f6be8c711c491301df7a441c7d9db12da1943b8717971e73ede5a9`
- 1.21.1 `ferrite-core (uXXizFIs)`: `x7kQWVju` → `ferritecore-7.0.3-neoforge.jar`; `19af89a2075bb10a63884fa853ebf84b02c79dc3242430ecdad056fd764fdcde367a7303276b329df01b0736e2ef264c5d80c7dc92c6aebd244f556a230bb417`
- 1.21.1 `modernfix (nmDcB62a)`: `ZDZENbHH` → `modernfix-neoforge-5.27.27+mc1.21.1.jar`; `af14a35e51f1c5d94139c6225ae641e8b0ded5a8c68eb4806cf28025d6c043455ac289902cd6b854a867320ab845ad619b186d02b8341822faf03f4476dec555`
- 1.21.1 `mouse-tweaks (aC3cM3Vq)`: `9I21YYxf` → `MouseTweaks-neoforge-mc1.21-2.26.1.jar`; `f95c0cc881211ee0442434976775e07aae40b4a2ba4e3a85455bc57ca9d3c991e239cd98374a8abd442dc9c378dcd9001e2caa1bf69991d424b5652dd7f3483b`
- 1.21.1 `controlify (DOUdJVEm)`: `RqsNKKLK` → `controlify-3.0.1+lts+1.21.1-neoforge.jar`; `cfffb25b9e62ca39cd6f54ab0b83902feda23a763ae9e345a11609f0138de1b6c3ab7a78c8fd5b7b309795e5c6d4911fd37cd7f8722a72cca6ad18e32cec461e`
- 1.21.1 `jei (u6dRKJwZ)`: `j41QZiGx` → `jei-1.21.1-neoforge-19.70.0.468.jar`; `82a037748fdc95d1d5e47247f63c8a47cd43c9e7ef7368c31aa5e24da8ce4068bac549529b36d7eaf14131afc7803dfe9c6ac05cae2c177cbbd02ff8d76b58a9`
- Optional Classic RenderScale: `renderscale (Va8PJBFX)` `PrBFeF1E` → `renderscale-2.0.0-beta.1-neoforge+1.21.1.jar`; `f25ac4acc658a203fe407ae79be260c053de01d18b2e4735a42af60a4605046bdfac732c3df2d0ac309469caf4719d5a42fa1d7fbbda17f696d673fe2783ae0e`

**Unknowns called out by the snapshot:** ModernFix has no 26.2/1.21.11 build; Metallum’s Modrinth 0.0.24/0.0.25 metadata does not prove the reviewed iOS MetalUniversal native payload; Graft and Ciderlight have no Modrinth IDs; Entity Culling, EMI/JEI, map mods, and controller UI must still pass the direct-GL scanner and device smoke tests.

## UX and policy

### New instance flow

1. `NewInstanceSheet`: insert a horizontal **Recommended** row before the current form, then a **Custom** disclosure containing the existing name/version/loader controls.
2. Each card shows name, version, loader, renderer badge, one-line pitch, RAM note, download size, and “Includes N mods”. Tap creates from the manifest; “Details” opens the pin/license list.
3. Keep “From pack” in Custom. A preset is a normal `Instance` plus its `cofre.json` metadata, so duplicate/export/import remain unchanged.
4. Recommended badge is computed from device RAM, OS/device renderer capabilities, exact game/loader and the last passing scenario:
   - **4 GB:** prefer the lowest-distance validated Metal preset; never badge a card that has an OOM or black-frame result. Until a 4 GB scenario passes, show “Experimental” and no star.
   - **12 GB:** prefer the newest validated Metal preset; then a validated Graft/Fabric card; never prefer MobileGlues solely because it has more mod versions.
   - If no fast preset passes, badge “Best available” on Vanilla+ and explain the limitation.

### Warnings and compatibility

- On a Metal preset, a Get/add attempt for a jar whose scan says direct OpenGL/Vulkan (or whose renderer manifest excludes Metal) opens a blocking sheet: **“This mod needs OpenGL and can make Metal black-screen or crash.”** Actions: `Cancel`, `Install and make a slower GL copy`, or `Install anyway (advanced)` with explicit confirmation. The original preset is never silently changed.
- The Play preflight reuses `ContentCompatibility`: block known-bad 26.x Sodium/Iris/MobileGlues/ANGLE, Metal on NeoForge, Vulkan/MoltenVK, and unvalidated shaders; warn/allow override for MobileGlues, Zink, high mod counts, and 4 GB Metal distance.
- Touch kit copy: Cofre’s own menu gestures stay on; `touchscreen=false` is written because vanilla Touchscreen Mode fights simulated clicks. Mouse Tweaks is bundled; IPN is optional and license-gated. Controlify and MidnightControls are mutually exclusive choices.
- QoL: Mod Menu is safe in the default kits. EMI/JEI and map mods are optional until their render paths are scanned; JourneyMap/Xaero are never a reason to recommend a Metal preset.

### Updating a preset

- Show `Pinned` and `Update preset` on the instance detail. The first tap fetches a new manifest, presents a file/license/compatibility diff, and offers `Update`, `Skip`, or `Keep current`.
- Stage every download in the existing install transaction, verify SHA-512, resolve required dependencies with `ModRequirements`, stop the game, move jars atomically, and retain the previous manifest for rollback. Worlds/options are not rewritten.
- An updated preset becomes a normal instance with a visible “based on …” note; users can keep it pinned indefinitely. Never auto-update a running instance or replace an optional mod without consent.

## Implementation sketch

### Manifest

Bundle a signed, app-versioned JSON catalog (Foundation `Codable`, in CofreKit; no parallel game state):

```json
{
  "schema": 1,
  "id": "fabric-performance-metal-26.2",
  "gameVersion": "26.2",
  "loader": "fabric",
  "loaderVersion": "0.20.1",
  "renderer": "metal",
  "status": "candidate",
  "mods": [{
    "project": "AANobbMI", "slug": "sodium", "version": "xJZxADzI",
    "file": "sodium-fabric-0.9.2+mc26.2.jar",
    "sha512": "…", "license": "Polyform-Shield-1.0.0", "metalSafe": "conditional"
  }],
  "options": {"renderDistance4GB": 4, "renderDistance12GB": 8, "simulationDistance4GB": 4, "menuBlur": 0, "touchscreen": false},
  "sourceDate": "2026-10-31"
}
```

- Modrinth entries use project/version IDs and primary-file SHA-512; external Graft entries use the GitHub release URL, tag, and SHA-512.
- Reuse `CofreKit.Modrinth`, `ModpackImport`, `ModRequirements`, and the staged install path in `CofreBackendAdapter+Mods.swift`; do not add a second downloader or dependency resolver.
- Add a compatibility scan before writing jars: declared loader/version, native libraries, direct GL/Vulkan symbols, renderer manifest, license/provenance, and required dependencies. A failed scan marks the card unavailable and explains why.
- Keep `cofre.json` small: `presetID`, manifest digest, pinned file list, last update result, and any user overrides. The game’s `options.txt` and `mods/` remain the source of truth.

### Device scenarios (`scripts/scenarios/`)

Create one scenario per card plus a negative case:

- `preset-vanilla-26.3-metal.json`: first frame, 2/4/8-chunk memory ladder, menu blur spike, Graphics-change crash guard.
- `preset-fabric-26.2-metal.json`: three cold launches; assert Metal backend, no `GlBackend`, Sodium/Lithium/Ferrite/Krypton/Mouse Tweaks/Controlify load, 60-second FPS.
- `preset-fabric-1.21.11-graft.json`: Graft native load, first world frame, touch inventory gestures, controller, no shader pack.
- `preset-neoforge-26.2-mobileglues.json`: expected warning, title/world frame at low distance, CPU/FPS marker, FSR off.
- `preset-neoforge-1.21.1-classic.json`: expected slow warning, JEI/ModernFix/Ferrite load, optional RenderScale run.
- `preset-metal-gl-only-negative.json`: attempt Entity Culling/stock Iris or another scanned GL jar; assert the add warning and that the original preset is unchanged.

Run each with `COFRE_LAUNCH_ARGS="-cofrePerfLog 1"`; summarize with `scripts/perf-summary.sh`. Record first frame, average/1% low FPS, peak MB, CPU/GPU split, thermal state, log markers, and whether the app survives relaunch.

### Test checklist

- [ ] API refresh returns the exact version IDs/files above; missing or yanked pins make the card unavailable.
- [ ] SHA-512 verification rejects a changed file; staged install rolls back on network, dependency, or loader failure.
- [ ] Fabric/NeoForge loader and Java preflight match the manifest; no duplicate `metallum`/renderer jar.
- [ ] Mod list and required dependencies are deterministic offline after the first download.
- [ ] Metal cards show the right RAM options and never write `touchscreen=true`; blur/FSR defaults are correct.
- [ ] GL-only add warning, fork path, Play-time block/warn, and “update preset” diff all have UI tests against fixtures.
- [ ] Every scenario produces a redacted log marker and passes on the supported shared device matrix; no preset is promoted by simulator-only evidence.
- [ ] `scripts/test.sh` passes; release review checks licenses/provenance for Metallum, Graft, AGPL IPN, and all-rights-reserved map mods.

## Open questions (max five)

1. Should the first release ship only Vanilla+ and Fabric 26.2, leaving Graft/NeoForge cards behind an “experimental catalog” switch until device proof exists?
2. Which exact iOS MetalUniversal artifact should Cofre bless: Modrinth Metallum 0.0.24/0.0.25 or the separately reviewed MetalUniversal 1.0.4 build?
3. Is Controlify the default controller kit, with MidnightControls as the alternative, or should controller support remain opt-in on 4 GB devices?
4. Should IPN be offered from the preset card with an AGPL acknowledgement, or only from the Mods screen after instance creation?
5. What 4 GB distance/heap ceiling should be the promotion gate for a “Recommended” Metal badge (the current 26.3 vanilla evidence only proves 2 chunks)?
