# CPU optimization mods for 26.2 on Metal (researched 2026-10-31)

On Metal the bottleneck is the CPU: integrated server ticks and worldgen (60–80 ms/tick on the iPad while generating; target 50). Only pure-logic mods: no OpenGL calls, no desktop natives. Not yet device-tested.

| # | Mod | NeoForge 26.2 | Fabric 26.2 | Helps | License |
|---|---|---|---|---|---|
| 1 | Lithium | `J9CowDXK` | `f7vZ0VWU` | server tick, physics, AI | LGPL-3.0 |
| 2 | FerriteCore | `LtVvw4uS` | `d5ddUdiB` | memory, fewer GC hitches | MIT |
| 3 | ServerCore | `88gv0DMz` | `edrtnY9v` | dynamic tick distance, activation ranges | MIT/GPL-3.0 |
| 4 | ScalableLux | `I6jcny72` | `FuGn0NlI` | lighting during chunk gen | LGPL-3.0 |
| 5 | BadOptimizations | `IDYkXahy` | `JmPs4Wie` | lightmap/sky caching | MIT |
| 6 | Clumps | `FPYWjnnE` | `dEMopoOJ` | XP orb entities | MIT |
| 7 | Dynamic FPS | `NIDCSqrK` | `pC2JjFw1` | idle FPS drop → less heat | MIT |
| 8 | Krypton | via Connector | `5WeL0Nkz` | network buffers | LGPL-3.0 |
| opt | Entity Culling / More Culling | `ZQ9bW7LG` / `dKLDGs8Q` | `uXe0pIaz` / `D5oVCouK` | client rendering (CPU culling, no GL queries) | tr7zw / GPL-3.0 |

- **No 26.2 build:** ModernFix, Noisium, Saturn, Starlight (use ScalableLux), AI Improvements (26.1 only).
- **C2ME** (`XpuI7aLS` / `4wjXxrDQ`): only with `globalExecutorParallelism = 1–2`; default threads starve the 2 performance cores and heat the phone.
- **Settings:** simulation distance 4 (4 GB) / 6 (12 GB); render 6–8 / 8–10; entity distance 50% / 75%.
