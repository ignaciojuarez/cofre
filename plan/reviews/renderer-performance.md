# Renderer performance: Metal (Metallum) vs MobileGlues

Source: Gemini research pass, 2026-10-31. Numbers marked (local) come from Air's own notes in `.work/air`, not independent benchmarks.

## Verdict

- **Metal (Metallum)** draws Minecraft straight to Metal, with no OpenGL translation. Fastest by far where it works: **105+ FPS at 32 chunks** on the iPhone 17 Pro (local, `.work/air/METAL_TUTORIAL.txt`). It only runs MC **1.21.11 and 26.1–26.4**, with Sodium on 1.21.11/26.2 and Iris on 26.2 only. It has no Forge or NeoForge support.
- **MobileGlues** translates OpenGL 4.0 to OpenGL ES 3.0 over ANGLE. It runs 1.17–26.x on every loader, but costs CPU: about **60 FPS at 8–12 chunks** ([Amethyst-iOS #325](https://github.com/AngelAuraMC/Amethyst-iOS/issues/325)), it runs hotter, and Iris shaders fail (status 36054).
- **Zink + MoltenVK:** about 50 FPS at 32 chunks (local). **MoltenVK direct:** under 10 FPS. **GL4ES:** only for 1.16.5 and older.

| | Metal (Metallum) | MobileGlues |
|---|---|---|
| Source | [kokodio/metallum](https://github.com/kokodio/metallum), iOS: [EternityQwQ/MetalUniversal](https://github.com/EternityQwQ/MetalUniversal) | [MobileGL-Dev/MobileGlues](https://github.com/MobileGL-Dev/MobileGlues) (LGPL-2.1) |
| Versions | 1.21.11, 26.1–26.4 (Java 21+) | 1.17 → 26.x, all loaders |
| Sodium | 1.21.11, 26.2 | ✅ (Embeddium on Forge/NeoForge) |
| Iris / shaders | 26.2 only ([metallum #27](https://github.com/kokodio/metallum/issues/27)) | ❌ on iOS (ANGLE ES 3.0) |
| CPU / heat | Low | High (GLSL translation, state tracking) |
| Trend | Where the community is heading (Blaze3D backends) | Development moving to `MobileGL` |

## Recommendation for Auto renderer

| Version / loader / mods | Renderer | Confidence |
|---|---|---|
| 26.2 Fabric + Sodium/Iris | Metal | High |
| 26.1 / 26.3 / 26.4 vanilla or non-render mods | Metal | High |
| 26.3+ Fabric + Sodium or Iris | MobileGlues (shaders off) | Medium |
| 1.21.11 Fabric + Sodium | Metal | High |
| 1.20.5–1.21.4 any loader, Forge/NeoForge | MobileGlues | High |
| 1.20.5+ with shader packs | none works on iOS today | High |
| ≤1.16.5 | GL4ES | High |

## On-device benchmark (to confirm with our own numbers)

- Low Power Mode off, Airplane Mode on, charging or above 80% battery.
- Fixed seed `benchmark2026`, spectator at `0 100 0`, noon, clear weather. Graphics Fast, VSync off, max FPS unlimited.
- Render distance 8, then 12; simulation distance 8. Wait 30 s after loading, then average F3 FPS and the 1% low over 60 s.
- Record peak memory and temperature. Do 3 cold launches per renderer and keep the median.

## Sources

[metallum](https://github.com/kokodio/metallum) · [metallum #27](https://github.com/kokodio/metallum/issues/27) · [MetalUniversal](https://github.com/EternityQwQ/MetalUniversal) · [MobileGlues](https://github.com/MobileGL-Dev/MobileGlues) · [MobileGlues-release CompatibleMods](https://github.com/MobileGL-Dev/MobileGlues-release/blob/main/CompatibleMods.md) · [MobileGlues V1.2.6](https://github.com/MobileGL-Dev/MobileGlues-release/releases/tag/V1.2.6) · [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) · [Amethyst-iOS #325](https://github.com/AngelAuraMC/Amethyst-iOS/issues/325) · [PojavLauncher Gladiolus (LTW)](https://github.com/PojavLauncherTeam/PojavLauncher/releases/tag/gladiolus) · [LTW](https://github.com/MojoLauncher/LTW) · [gl4es](https://github.com/ptitSeb/gl4es)
