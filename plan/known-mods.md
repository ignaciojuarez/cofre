# Known mod compatibility

This table is generated from [`known-mods.json`](../app/UI/Sources/CofreKit/Resources/known-mods.json).

| Mod | Where it fails | Why | Evidence |
|---|---|---|---|
| Iris | Metal | Iris needs OpenGL; Metal runs without shaders for now. | device ([evidence](../plan/reviews/metal-mods.md)) |
| Distant Horizons | Metal | Distant Horizons draws with OpenGL; turns Metal black. | device ([evidence](../plan/reviews/metal-mods.md)) |
| Oculus | Metal | Oculus uses OpenGL; the Metal renderer has no integration for it. | expected |
| Embeddium | Metal (fabric, forge, quilt, vanilla, unknown) | Embeddium uses OpenGL; the Metal renderer has no integration for it. | expected |
| Embeddium | Metal (neoforge) | This NeoForge renderer uses OpenGL; the 26.2 Metal kit has not validated it. | expected |
| Sodium | Metal (neoforge) | This NeoForge renderer uses OpenGL; the 26.2 Metal kit has not validated it. | expected |
| Sodium | Metal (unknown; 1.21.11) | Metal runs this mod only in the validated 26.2 kit for now. | expected |
| Sodium | Metal (fabric; 1.21.11) | Sodium may not render with Graft yet. | expected |
| OptiFine / OptiFabric | Metal | OptiFine uses OpenGL; the Metal renderer has no integration for it. | expected |
| ImmediatelyFast | Metal | ImmediatelyFast changes OpenGL render buffers; Metal has no integration for it. | expected |
| Voxy | Metal | Voxy owns an OpenGL renderer; the Metal renderer has no integration for it. | expected |
| Nvidium | Metal | Nvidium requires NVIDIA-specific OpenGL features unavailable on iOS. | expected |
| VulkanMod | Metal | VulkanMod uses a separate Vulkan renderer; Metal has no integration for it. | expected |
| Canvas | Metal | Canvas owns an OpenGL renderer; the Metal renderer has no integration for it. | expected |
| Exordium | Metal | Exordium changes the OpenGL display path; Metal has no integration for it. | expected |
| Iris addon | Metal | Iris addons use the OpenGL shader path; the Metal renderer has no integration for them. | expected |
| Sound Physics Remastered | Any renderer | PC-only: doesn't run on iPhone/iPad. | expected |
| Simple Voice Chat | Any renderer | PC-only: doesn't run on iPhone/iPad. | expected |
| Plasmo Voice | Any renderer | PC-only: doesn't run on iPhone/iPad. | expected |
| ReplayMod | Any renderer | PC-only: doesn't run on iPhone/iPad. | expected |
| Physics Mod | Any renderer | PC-only: doesn't run on iPhone/iPad. | expected |
| Iris | 26.x on MobileGlues/ANGLE | On {renderer}, Iris keeps Minecraft {gameVersion} on a black screen. | device ([evidence](../plan/reviews/renderer-benchmarks.md)) |
