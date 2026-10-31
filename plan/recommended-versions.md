# Recommended versions for modded play

Only native Metal is playable with mods; every OpenGL path translates on the CPU (<20 FPS on an iPhone 17 Pro with <20 mods). Numbers: iPad mini 6 (A15, 4 GB), in a world, steady. Details: [reviews/renderer-benchmarks.md](reviews/renderer-benchmarks.md), routes: [reviews/metal-mods.md](reviews/metal-mods.md).

## Recommended (Metal)

| # | Minecraft | Loader | Metal through | FPS | Fabric/NeoForge mods* | State |
|---|---|---|---|---|---|---|
| 1 | **26.2** | **Fabric** | MetalUniversal 1.0.4 + Sodium 0.9.0 | ~57 | 13.6k Fabric | ✅ in app: one-tap "Use Metal" (499f665) |
| 2 | **26.2** | **NeoForge** | Sinytra Connector + Launchpad + Forgified Fabric API + MetalUniversal | ~55 | 7.1k NeoForge | ✅ device-verified; one-tap install in progress. EvilCraft runs here |
| 3 | **1.21.11** | **Fabric** | Graft 1.1.1, Cofre iOS port (no Sodium yet) | ~51 | 18k Fabric | ✅ device-verified; not in the app yet |
| — | 26.3 | Vanilla | Air's built-in Metal agent | — | — | ✅ |

\* Modrinth counts, 2026-10-31.

## Not recommended (OpenGL only, slow)

| Minecraft | Loader | Why |
|---|---|---|
| 1.21.11 | NeoForge | No Connector build, no NeoForge Metal renderer for 1.21.x |
| 1.21.1, 1.20.1 | any | Older than Minecraft's GPU layer (1.21.5+) that Metal mods plug into; MobileGlues only |
| any | Forge | No Metal route |
| any | Quilt | Untested on Metal |

Shaders (Iris/Oculus) need OpenGL: not available on any Metal route yet.
