# Looking good at 50% resolution

Source: Gemini research pass, 2026-10-31, with Cofre-side checks noted. Goal: play at 50% on the iPhone 17 Pro (2622×1206 → 1311×603) for FPS, heat and battery, without the image going muddy.

## Ranked options

| # | Option | Effort | Visual gain | Cost | Works on | Notes |
|---|---|---|---|---|---|---|
| 1 | **RenderScale mod**: world at 50%, HUD and text at 100% | S | Very high | ≈0 | MobileGlues + Metal | [Modrinth](https://modrinth.com/project/Va8PJBFX), MIT, active (2026-10-17). Checked: Fabric 1.20.1–26.3, **NeoForge 1.21.1/1.21.4/1.21.5/1.21.11/26.x**, Forge 1.20.1. A fork of the archived ResolutionControl++ |
| 2 | Mipmap levels 4 → 1–2 (`options.txt`) | S | Medium | 0 | All | Less blur on distant textures at low resolution |
| 3 | **FSR1 in MobileGlues, ported to ESSL 3.00** | M | High | ~0.5–1 ms | MobileGlues | Black screen cause: `FSRShaderSource.h` hard-codes `#version 450` and ANGLE only accepts `#version 300 es`. ES ports exist ([web-fsr](https://github.com/Hajime-san/web-fsr), [atyuwen mobile FSR](https://gist.github.com/atyuwen/78d6e810e6d0f7fd4aa6207d416f2eeb)). Needs a MobileGlues source patch in Air's build |
| 4 | **MetalFX spatial scaler** | M (Metal) / L (MobileGlues) | High | 0.15–0.35 ms | Metal easily; MobileGlues needs ANGLE present hooks | iOS 16+, A13+ ([Apple](https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerdescriptor)). Prior art: [flycast #2565](https://github.com/flyinghead/flycast/pull/2565), [LifeDreamer24/metallum](https://github.com/LifeDreamer24/metallum) |
| 5 | Post-AA packs (SMAA + CAS) | S | Medium–high | 0.2–0.5 ms | Metal 26.3 ([Grindstone](https://modrinth.com/project/uKUzCNsg)); Iris packs fail on MobileGlues | |
| — | Nearest-neighbour layer scaling | — | — | 0 | All | **Already on**: Air sets `kCAFilterNearest` (`SurfaceViewController.m:1091`), so 50% is crisp 2×2 pixels today |
| ✗ | MSAA | L | Low | 1.5–3 ms | Neither | No vanilla toggle; [Salt's AA](https://modrinth.com/project/Ak070HpD) needs Vulkan |

## Simplest first step

Get **RenderScale** into the NeoForge 1.21.1 instance, set the Cofre resolution back to 100%, and let RenderScale draw the world at 50%. The world gets the speed-up, and text and inventory stay sharp. If it works on device, Cofre can offer it as a one-tap "Sharp UI at low resolution" option.

## Measure on device

- F3 FPS and the 1% low over 60 s at 50% (Cofre) vs 100% plus RenderScale 50%.
- Thermal state over 15 minutes.
- Check RenderScale against Sodium and MobileGlues for black screens or a broken HUD.
