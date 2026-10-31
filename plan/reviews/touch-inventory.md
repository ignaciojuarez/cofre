# Touch-friendly inventories

Source: Gemini research pass, 2026-10-31.

## Verdict

**No Java mod gives a Bedrock-style touch inventory** (big slots, tap-and-hold split, touch recipe book). Android and iOS launchers (PojavLauncher, FCL, Zalith, Amethyst) solve it in the **launcher's touch layer**: when Minecraft frees the cursor (an inventory or menu is open), touches become mouse events. They pair that with a couple of helper mods.

## Options

| # | Option | Loaders / versions | What it fixes | License | Effort |
|---|---|---|---|---|---|
| 1 | **Cofre gestures in menus** (no mod) | All | Tap = left click; hold ≥250 ms = right click (split / place one); floating **Shift** toggle (quick-move) and **Drop**; drag = held mouse | Ours | M |
| 2 | **[Mouse Tweaks](https://modrinth.com/mod/mouse-tweaks)** | Fabric/Forge/NeoForge, 1.12 → 26.3 | Drag across slots spreads or collects items | BSD-3, safe to bundle | S |
| 3 | **[Inventory Profiles Next](https://www.curseforge.com/minecraft/mc-mods/inventory-profiles-next)** | Fabric/Forge/NeoForge, 1.19 → 26.3 | One-tap Sort / Move all / Dump buttons in containers | AGPL-3.0, so recommend it as an optional install rather than bundling | S |
| 4 | [TouchController](https://github.com/TouchController/TouchController) | Fabric/Forge/NeoForge, 1.12 → 26.x | Bedrock-style in-game HUD controls; **no inventory work** (menus are planned) | LGPL-3.0 | L (launcher bridge) |
| 5 | [Item Scroller](https://modrinth.com/project/JygyCSA4) | Fabric/NeoForge/Forge ≤1.21.x | Move items by scrolling (needs a two-finger scroll mapping) | LGPL-3.0 | S |
| 6 | [Legacy4J](https://www.curseforge.com/minecraft/mc-mods/legacy-minecraft) | 1.20–1.21.x | Console-style tabbed crafting; better with a controller | MIT | M |
| — | MidnightControls / Controlify / Controllable | many | Controller cursor snapping; no real touch | MIT / LGPL | — |
| — | Bedrock UI resource packs (OreUI…) | any | Looks only; can't change hitboxes | various | — |

Keep vanilla "Touchscreen Mode" **off**: it fights simulated clicks ([Pojav FAQ](https://github.com/PojavLauncherTeam/PojavLauncher/wiki/Frequently-asked-questions)).

## Plan

1. Cofre's touch overlay in menus: tap → left click at that spot, hold → right click, Shift and Drop toggles on the edge.
2. A one-tap "Touch kit" in Mods that installs Mouse Tweaks, with IPN as an option.
3. Later: TouchController's HUD, if Cofre's own controls fall short.
