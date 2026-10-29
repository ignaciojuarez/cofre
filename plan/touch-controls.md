# Touch controls: research, 3 variations, recommendation

> Status: design (phase 1). Mocks: `app/UI/Sources/CofreUI/Screens/Game/TouchControlsMock.swift`, rendered with
> PreviewHost `-screen touch -touch a|b|c|ipad|settings|sheet -canvas …`. Input API: `GameInputService` in
> `Facade/Requirements.swift` and `plan/input.md`.

**Goal (user):** the game should play like Bedrock on an iPhone. Touch controls are on screen until a controller or a keyboard and mouse is used, then those take over automatically, with a manual override in Settings. The on-screen controls should be minimal and touch-first.

**Today:** Air's "custom" layout fills the screen with square buttons, a QWERTY drawer, an FPS/MEM pill and a floating gear, and the iOS keyboard opens when nobody asked for it.

## 1. Research

### Minecraft Bedrock (iPhone)
| Topic | What Bedrock does | Source |
|---|---|---|
| Schemes | **Joystick & tap to interact** (default), **Joystick & aim crosshair**, **D-pad & tap to interact**, plus a **Split controls** toggle (crosshair with the D-pad). The 2022 redesign renamed Touch/Crosshair/Classic to these. | [Controls](https://minecraft.wiki/w/Controls), [beta feedback](https://feedback.minecraft.net/hc/en-us/community/posts/4681918652045-Updated-Touch-Controls-Feedback-Bedrock-Beta) |
| Look | Drag anywhere outside the HUD. | Controls |
| Break / place | Tap mode: hold on the block to break (with a radial progress ring), tap to place or use. Crosshair or split mode: aim, then hold anywhere to break and tap anywhere to place. "Show action buttons" off keeps taps working at the crosshair. | Controls, beta feedback |
| Jump / fly | Jump becomes **swim up** in water. In Creative, **double-tap jump** starts flying and jump becomes **fly up**. Double-tap fly up or fly down to land. | Controls |
| Sneak | **Double-tap toggles** sneak and shows a pressed icon. Sneak becomes **swim down** in water and **fly down** while flying. | Controls |
| Sprint | "Sprint on movement": push the stick to its edge. Otherwise use a sprint button, or double-tap forward on the D-pad. | beta feedback |
| Static joystick | Optional. The default joystick appears where the thumb lands. | beta feedback |
| Context | One **interact button above the hotbar** (Ride, Feed, Leave boat, Sit, Trade…), plus **dismount** buttons for horses and boats. | Controls, [HUD](https://minecraft.wiki/w/Heads-up_display) |
| Menus | A row at the top: **chat · emote · pause**, with optional perspective. **•••** at the end of the hotbar opens the inventory. | HUD |
| Hotbar | Tap a slot to select it. Long-press about 2 s to drop the stack. | Controls |
| Options | Per-button position, size and opacity. **Main hand = left mirrors the touch controls.** Hide HUD hides the buttons too. | HUD |

**What Bedrock players expect:** move on the left, jump at the bottom right with sneak next to it, drag to look, tap to place, hold to break, double-tap jump to fly, double-tap sneak to lock it, sprint by pushing the stick, **•••** for the inventory, pause and chat in the top corner, and mirroring when left-handed.

### TouchController (Java mod)
- A Fabric/Forge/NeoForge client mod (LGPL-3.0) that brings Bedrock-style touch to Java, including **tap to interact at the finger** (it raycasts in-game). It has customizable layouts, presets, conditional layers (e.g. riding, holding an item), a minecart forward button and a hide-HUD button. ([Modrinth](https://modrinth.com/mod/touchcontroller), [releases](https://github.com/TouchController/TouchController/releases))
- An Amethyst fork already runs it on iOS through a JNI ring buffer. That fork fixed low-FPS issues: lost taps, and double-taps for fly and sneak that never fired. ([issue #379](https://github.com/TouchController/TouchController/issues/379))
- **Takeaway:** "tap where you touch" needs a game-side mod. A launcher only sends keyboard and mouse events, so **without a mod every action lands at the crosshair** (Bedrock's split controls). When the mod is installed (`touchControllerMod` pref), Cofre's overlay should step aside.

### PojavLauncher / Amethyst / ZalithLauncher
- These use a free-form editor of buttons, drawers and joysticks saved as JSON controlmaps. The defaults are dense keyboard grids, and users trade custom maps because "defaults are usable but not user-friendly". ([Pojav custom controls](https://pojavlauncher.app/wiki/getting_started/CUSTOM-CONTROLS.html), [NodeLoc thread](https://www.nodeloc.com/t/topic/73975?tl=en))
- Zalith auto-switches between touch, mouse and gamepad, but forcibly remaps gamepads to keys. Users ask Zalith to copy **Amethyst's default layout** because Zalith's handles the hotbar badly. ([Zalith docs](https://www.zalithlauncher.cn/en/docs/control2_help/overview.html), [#1776](https://github.com/ZalithLauncher/ZalithLauncher2/issues/1776), [#378](https://github.com/ZalithLauncher/ZalithLauncher2/issues/378))
- Air (our engine) inherits this model. That's why it shows a QWERTY drawer and a wall of keys.
- **Takeaway:** an editor is a power-user escape hatch, not a default. Ship one good opinionated layout.

### Console radial and context menus
- Console games put rare actions behind one hold: Bedrock's emote wheel, Fortnite's and Apex's comms wheels, Zelda's quick menus. A hold-to-open radial or tray works best with **6–8 items** and **release to select**. A tap still does the button's primary job.
- **Takeaway:** use one "hold for more" entry point, so perspective, players, drop, swap hands, hide HUD and keyboard never need permanent buttons.

### Constraints this sets for Cofre
| Fact | Consequence |
|---|---|
| Java acts at the crosshair; Air already turns a world tap into use and a long-press into attack (`plan/input.md`) | Every variation uses **split controls**: drag to look, tap to use or place, hold to break, all at the crosshair. The crosshair is always visible in-world. |
| Fly up, swim up and riding forward are all Space; fly down, swim down and dismount are all Shift | **Jump and sneak already cover every movement context.** Context only changes the glyph, so controls work even before we know the game state. |
| Reliable state today: text-input start/stop (patch 0005) and in-world vs. GUI (cursor grabbed) | Menu mode and keyboard-only-when-needed ship in v1. Flying, swimming and riding glyphs need a state source later (TouchController layers or a tiny Fabric hook). See §5 gaps. |
| Double-tap Space = fly is vanilla Java | Pass jump through raw, and keep each touch as a separate press and release at low FPS (TouchController's fix). |

## 2. Three variations

All three use the stand-in game frame with the Java HUD at auto GUI scale, sit inside the landscape safe area, and use Cofre's square block style: dark glass fill, a 2 pt light outline and a pixel glyph. On-states use the accent `face` color.

| | **A · Bedrock** | **B · Ghost** | **C · Dock** ⭐ |
|---|---|---|---|
| Idea | Bedrock's default layout, recreated | Almost nothing on screen; gestures do the rest | Bedrock positions with Ghost's quiet behavior. System buttons sit on the hotbar line. |
| Visible by default | 6: stick, jump, sneak, chat, pause, ••• | 2: jump, ≡ (the stick appears only under the thumb) | 4 clusters / 6 targets: stick · jump+sneak · pause · hotbar dock (chat ⟦hotbar⟧ •••) |
| Stick | Fixed square, bottom-left | Floating: appears where the left thumb lands (left 40% of the screen) | Rests bottom-left at 35%. Touching anywhere in the left 40% re-centers it under the thumb. |
| Sprint | Push the stick to its top edge (the edge lights up and SPRINT shows) | Same | Same |
| Jump | Bottom-right, 60 pt. Double-tap = fly (vanilla). | Same, plus **swipe down on jump = sneak toggle** | Same as A |
| Sneak | Left of jump, 52 pt. Double-tap locks it (accent fill). | A gesture on jump (the hint "▼ sneak" shows under it) | Up and left of jump, 46 pt, so the thumb rolls between them. Double-tap locks it. |
| Contextual | Jump and sneak become fly ↑↓ or swim ↑↓; sneak becomes **Dismount** when riding | The jump glyph swaps; ≡ gets a dot when context actions exist | Glyph swaps as in A. Sneak shows a **Dismount** label. Nothing new is added to the screen. |
| Inventory | ••• after the hotbar | **Swipe up on the hotbar** | ••• docked on the hotbar's right end |
| Chat | Top-right button | ≡ tray | 💬 docked on the hotbar's left end |
| Pause | Top-right button | ≡ tray | **Tap ⏸ = pause.** **Hold ⏸ (or swipe down from it)** opens the quick tray: View (F5) · Players (Tab) · Drop (Q) · Swap hands (F) · Hide HUD (F1) · Keyboard |
| Hotbar | Tap a slot to select; swipe sideways to scroll; long-press to drop the stack | Same | Same |
| Opacity / idle | 80%, no fade (Bedrock behavior) | Dims to **35% after 3 s**; at 35% it's practically gone | Dims to **35% after 3 s**; any touch brings it back to 80% within 150 ms |
| Discoverability | Best | Worst (two hidden gestures) | Good: every action has a visible home or one hold |
| Screen used | Most (two top buttons over the sky) | Least | Low: the top-right has one 36 pt button, and the rest hugs the hotbar and corners |

### Shared rules (every variation)
- **Gestures in the world:** drag (≥ 10 pt) = look. Tap (< 200 ms, < 10 pt) = use or place. Hold (≥ 250 ms) = attack or break, and dragging after the hold keeps breaking while looking (Bedrock). Multi-finger: none by default. Two-finger tap = pick block is an opt-in in "Edit layout". **No pinch**, because it would fight with look.
- **Menu mode:** when the cursor is released (inventory, chests, pause, chat), all world controls hide. One finger moves a pointer and tap clicks. Top-right shows only ⌨ (when the screen has a text field) and ✕ (Esc).
- **Keyboard only when needed:** it opens on the game's text-input start and closes on stop (`CofreKeyboardPolicy`). It never opens in-world. ⌨ in menu mode and the quick tray is the manual override.
- **Controller or keyboard and mouse:** the overlay hides completely. Pointer lock comes on for the mouse. The first touch brings touch controls back, faded in over 150 ms.
- **Left-handed:** mirror positions only (stick on the right, jump and sneak on the left, tray opening from top-left). Glyphs, the hotbar and the Java HUD stay unmirrored. The mock does this with `layoutDirection = .rightToLeft` on the overlay layer.
- **iPhone vs. iPad:** the control scale is `clamp(shortSide / 402, 1, 1.35)` × the user's button size, so iPhone gets 60 pt jump and 112 pt stick, and iPad up to 81 / 151. Layout uses the same corners and reads the **window**, not the device (DESIGN_SYSTEM rule 2), so Stage Manager windows work.
- **Safe area and Dynamic Island (landscape):** the game renders full-bleed under the island. Controls stay inside the safe area (62 pt on the island side, and the same on the other side for symmetry; 21 pt bottom). Island on the left or right doesn't matter. The overlay defers system gestures on the **bottom and top edges** (`preferredScreenEdgesDeferringSystemGestures`) so hotbar swipes and the tray don't trigger Home or Control Center, and it hides the home indicator in-world.

## 3. Recommendation: **C · Dock**

- It keeps **Bedrock's muscle memory**: the stick bottom-left, jump and sneak bottom-right, ••• by the hotbar, pause top-right, double-tap to fly or lock sneak, and push to sprint.
- It is nearly as **quiet as Ghost**. The middle of the screen is empty, the top has one 36 pt button, chat and inventory sit on the hotbar line the eye already reads, and everything dims to 35% when idle.
- **There are no hidden must-know gestures.** The extras live behind one hold on pause, the same pattern as a console wheel.
- **It works on day one with only reliable signals** (menu, text input). Context glyphs come later with a state source.
- B stays available as a "Minimal" layout for players who want it. A stays as "Classic Bedrock".

Mockups (simulator renders, nothing from a device):
- `/tmp/cofre-shots/agentS-sheet.png`: all variations, iPad, menu mode and the settings pane.
- `agentS-a.png`, `agentS-b.png`, `agentS-c.png`: each at rest and in context.
- `agentS-ipad.png`, `agentS-settings.png`.

## 4. Settings → Controls (replaces X03's Touch/Controller segment)

| Section | Control | Default | Notes |
|---|---|---|---|
| Input | Segmented **Auto · Touch · Controller · Keyboard & mouse** | Auto | Stored as `cofre.input.mode`. Under it, a "Using now: Touch · DualSense paired" row with an AUTO badge. |
| Touch layout | Three thumbnail tiles: **Classic (A) · Minimal (B) · Dock (C)** | Dock | The tiles are live mini renders of the overlay. |
| Touch | Button size slider, 60–150% | 100% | |
| | Opacity slider, 20–100% | 80% | |
| | Fade when idle | On | Dims to 35% after 3 s |
| | Left-handed | Off | Mirrors the layout |
| | Haptics | On | Light tick on button press and break start; `.selection` on hotbar change |
| | Edit layout | | Phase 2: drag and resize in place; reset per layout. Air's editor goes away. |
| Look | Look sensitivity, 0.25–3× | 1× | Shared by touch drag and right stick |
| | Invert Y | Off | Touch and controller |
| | Gyro aim | Off | Tilt to fine-aim (existing pref) |

Controller and keyboard-and-mouse options (bindings, deadzone) stay in their own rows below. They're out of scope here.

## 5. UX rules

| # | Rule |
|---|---|
| U1 | **Never more than 6 tappable targets in-world** (C: stick, jump, sneak, pause, chat, •••). Nothing new appears unless something it replaces disappears. |
| U2 | **Nothing in the middle third of the screen**, horizontally or vertically. The crosshair, the world and the mobs live there. |
| U3 | **Context swaps glyphs in place**, within **150 ms** of the state change. It never adds a new button, except a single labeled chip on the sneak slot (Dismount). |
| U4 | **Idle: dim to 35% after 3 s** with no touch. **Any touch: back to 80% within 150 ms.** A held control never dims. Reduce Motion: snap, no fade. |
| U5 | **Every target is ≥ 44 × 44 pt** hit area, even when its visual is 36 pt (pause) or the hotbar's height. |
| U6 | **Size scales with the window's short side**: `clamp(short / 402, 1, 1.35)` × user size. Same corners on every device. |
| U7 | **Controls stay inside the safe area.** The game draws full-bleed. Bottom and top edge gestures are deferred in-world. |
| U8 | **The keyboard opens only on a game text-input request or a ⌨ tap.** It never opens in-world. It closes on stop. |
| U9 | **Menu mode shows only ⌨ (if there's a text field) and ✕.** One-finger pointer. |
| U10 | **A hardware input hides the overlay at once. The first touch restores it** (Auto). The last input used wins, not "something is paired". |
| U11 | **Rare actions live behind one hold** (pause → quick tray, up to 6 items, release to select). |
| U12 | **Each touch is a real press then release**, never coalesced. Releases are held until the game has read the press (TouchController's low-FPS fix), so double-tap fly and sneak survive 15 FPS. |
| U13 | **Hide HUD (F1) hides our overlay too**, except a 30% pause button. |
| U14 | VoiceOver: each control is a labeled button ("Jump", "Sneak, locked"). The overlay is hidden from VoiceOver in menu mode. |

### Facade gaps for Agent R (phase 2 needs these)
1. **Screen state:** `func screenUpdates() -> AsyncStream<GameScreen>` with `.world` (cursor grabbed) and `.menu(hasTextField: Bool)`. Without it, menu mode can't hide the world controls.
2. **More keys:** `F1`, `TAB` (players), `F` (swap hands), and the mouse `middle` button (pick block), plus `scroll(steps:)` for hotbar swipes. Pointer-in-menu also needs `pointer(x:y:)`, or Air's existing GUI pointer.
3. **Auto rule:** prefer **last-used** input over "a GCController exists" (U10). A paired pad in a bag shouldn't hide touch.
4. **Hotbar rect:** the GUI scale (from `options.txt` or auto) so the dock and slot taps line up with the game's hotbar.
5. **Optional (later):** a player-state stream (flying, swimming, riding, creative) for context glyphs.

## 6. Built (phase 2): C · Dock by default

| Piece | Where |
|---|---|
| Rules (visibility, frames, mirroring, scale, hotbar, fade, stick, tap/hold/drag, sneak lock) | `Screens/Game/TouchLayout.swift`, tested in `TouchControlsTests` |
| Overlay model, view and UIKit host (`TouchOverlayController`, pass-through hit test) | `Screens/Game/TouchOverlay.swift`, `TouchOverlayParts.swift` |
| Settings → Controls (`SettingsPane.touch`, titled "Controls") | `Screens/Game/ControlsPane.swift`. Touch options are saved as `cofre.touch.settings` and read live by the overlay. |
| Review renders | `TouchOverlayPreview.swift`, PreviewHost `-screen touch -touch c\|a\|b\|ipad\|settings\|sheet` |
| Air hosting | `CofreGameOverlayHost` asks `CofreCoreEntry.touchOverlay` for the controller; R's debug buttons are gone |

**Touch ownership:** in the world, the overlay takes every touch except the game's hotbar. Drag = `look` (points × screen scale × sensitivity, Invert Y), tap = right click, hold 250 ms = left button held, which keeps breaking while dragging. On game screens it takes only ⌨ and ✕, and Air handles the pointer. The hotbar always falls through to Air's own slot taps, and the host forces `control.gesture_hotbar` on. Air's touch look ignores `mouse_speed` and has no Invert Y, which is why the overlay owns look.

**Facade gaps (§5):**
| Gap | Status |
|---|---|
| World vs. menu | Done: `screenUpdates()` polls Air's `isGrabbing` at 10 Hz |
| F1 / Tab / F / middle click / scroll | Done: GLFW keys and the middle button in `CofreGameInput.m`, plus `scroll(steps:)` → `nativeSendScroll`. The overlay doesn't use scroll or pick block yet. |
| Auto = last input used | Done: `CofreInputModeTracker`, fed by touches (including touches that fall through), `GCControllerDidBecomeCurrent`, `GCMouseDidBecomeCurrent`, and the pad and keyboard handlers chained after Air's. If Air replaces a handler later, only the "became current" notifications switch modes. |
| GUI scale | Done: Air's `guiScale` plus the framebuffer's pixels per point. Falls back to Minecraft's auto rule. |
| Player state (flying, swimming, riding) | **Stub:** glyphs stay jump/sneak, since those keys already fly, swim and dismount |

**Deferred:** an in-place "Edit layout" editor (the old Air controls editor still edits Air's hidden layout), Minimal's swipe up on the hotbar (its ≡ tray has Inventory instead), two-finger pick block, and stepping aside for the TouchController mod.
