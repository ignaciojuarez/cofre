# Cofre quick menu and touch controls: redesign directions and spec

**Surface type:** *Operate.* This overlay sits on top of moment-to-moment play. It should stay quiet and fast to reach with a thumb. Power features belong one level deeper than the game.

**Positioning:**
- Bedrock players expect a clean screen with Pause at the top.
- Pojav players expect any key on demand.

Cofre should ship Bedrock-clean defaults and put Pojav-level power behind **Edit**.

**Assumptions and missing evidence:**
- I haven't seen the current QuickTray code, the tile sizes or the exact current behaviour of the Minimal ≡ button. I'm assuming tapping it opens the tray.
- I don't know whether `GameInputService` supports separate press and release events or chords.
- I don't know whether an in-game settings sheet already exists.

---

## 1. Directions

### A. Smarter Fixed Tray
- Keep the tray fixed, but improve the default actions.
- Move Drop to the hotbar.
- Add two "Mod key" slots, configured only in Settings → Controls.
- No in-game editing.

### B. Editable QuickTray *(recommended)*
- The tray is a 2×4 grid: 6 slots the user chooses, plus 2 fixed tiles (**Pause**, **Edit**).
- **Edit** opens a configuration screen with two parts:
  - a live preview of the tray;
  - an action catalog: Common, Advanced, Debug and Custom keys.
- Custom keys support **Tap / Hold / Toggle** behaviour and chords.
- Actions are data-driven definitions.

### C. Pinned Keys (Pojav-lite)
- Everything in B, plus "Pin to screen": any action can become a floating button on the gameplay screen.
- This needs a position editor and its own hit-testing against the look gesture.

### Comparison

| | A. Smarter Fixed | **B. Editable Tray** | C. Pinned Keys |
|---|---|---|---|
| Build effort | Low | Medium | High (needs a placement editor) |
| Mod support | 2 keys, buried in Settings | Good: unlimited definitions, 6 visible | Best |
| Gameplay obstruction | None | None (tray is transient) | Grows with every pin |
| Discoverability | Low | Medium (the Edit tile teaches it) | High |
| Fits pixel/block system | Yes | Yes | Risk of Pojav-style clutter |
| Familiar to | Bedrock | Bedrock by default, Pojav when edited | Pojav |

**Recommendation: B.** It solves the mod-key need without adding anything permanent to the screen, and it reuses the existing SwiftUI grid and primitives.

Leave C as a possible phase 2, limited to at most 2 pins, and only if users ask for it.

---

## 2. Gameplay behaviour

### Opening the tray
- **Dock / Classic:** tap the top-right button to send Esc (pause). Hold it for 300 ms to open the tray.
- **Minimal:** tap ≡ to open the tray. The tray's fixed **Pause** tile replaces the missing pause button.
  - Pause also appears in Dock/Classic, so tile positions match across all layouts.

### Selecting an action
- **Drag-to-select:** hold the button, slide onto a tile, release to fire.
  - Light haptic when the tray opens.
  - `.selection` haptic each time the finger enters a tile.
- **Sticky fallback:** if the finger is released on the button or in empty space, the tray stays open so the user can tap a tile.
- **Dismiss:** tap outside the tray, tap the button again, or fire any Tap action.
- The tray never pauses the game. That matches Java behaviour, and multiplayer can't pause anyway.

### Discoverability
- Add a 3 px pixel notch in the button's bottom-left corner. This is the "more on hold" hint.
- On the first tap in Dock/Classic, show a one-time pixel tooltip. *Proposed copy:* "Hold for quick actions."

### Accessibility
- Give the button an `accessibilityAction(named: "Quick actions")`, because long-press is hard to perform with VoiceOver.

### Placement and motion
- The tray anchors to the button, top-aligned, and opens leftward.
- Maximum 2 rows, so the crosshair and the centre third of the screen stay clear.
- Tiles are 48 pt on iPhone and 56 pt on iPad, with a 4 pt gap.
- On iPhone the tray is about 208 × 100 pt.
- Motion: 120 ms opacity plus scale from 0.96, anchored at the button. With Reduce Motion on, use opacity only.

### Gameplay wireframe (Dock, tray open)
```
┌──────────────────────────────────────────────────────────────┐
│                               ┌────┬────┬────┬────┐  ┌──┐    │
│                               │PAUS│VIEW│PLYR│SWAP│◀─│II│hold│
│                               │ ⎋  │ F5 │Tab │ F  │  └──┘    │
│                               ├────┼────┼────┼────┤ [M ×]    │← toggle chip
│                               │HUD │DBG │KBD │EDIT│          │  (only when
│                               │ F1 │ F3 │    │ ✎  │          │   latched)
│                 ┼             └────┴────┴────┴────┘          │
│   ( ○ ) ghost stick                                   [JUMP] │
│                                                              │
│      [CHAT][1][2][3][4][5][6][7][8][9][INV]                  │
└──────────────────────────────────────────────────────────────┘
```

### Tile anatomy
- Uses the existing dark-glass square, light top-left bevel and darker bottom-right bevel.
- Pixel icon (20 pt) in the centre.
- Label below the icon, in the existing pixel font at the smallest crisp integer size of at least 10 pt. Labels are at most 8 characters; anything longer is truncated.
- Key badge (for example "F5") in a corner. The badge may be smaller, because it repeats information.
- Keep the glass at roughly 0.75 opacity or more, so white text passes AA over snow and sky.

### Tile states

| State | Treatment |
|---|---|
| Default | Standard bevel |
| Highlighted (finger over the tile) | Bevel inverts, as if pressed |
| Latched | Inverted bevel plus the existing Cofre accent outline |
| Disabled | 40% opacity; for example Keyboard while hardware keyboard mode is on |
| Focused | 2 px light outline, for keyboard and VoiceOver focus |

---

## 3. Actions

### Default tray (all layouts)

| Slot | Action | Binding | Mode | Editable? |
|---|---|---|---|---|
| 1 | Pause | Esc | Tap | Fixed |
| 2 | View | F5 | Tap | Yes |
| 3 | Players | Tab | **Hold** | Yes |
| 4 | Swap hands | F | Tap | Yes |
| 5 | Hide HUD | F1 | Tap | Yes |
| 6 | Debug | F3 | Tap | Yes |
| 7 | Keyboard | system (shows the soft keyboard) | — | Yes |
| 8 | Edit | system | — | Fixed |

**Drop moves to the hotbar.** Long-press a hotbar slot for 500 ms:
- it selects that slot and sends Q;
- if the finger keeps holding, it repeats Q at about 6 per second.

This avoids opening the tray for every single drop. **Fallback:** if hotbar drop doesn't ship in the same release, put Drop (Q) back in slot 6 in place of Debug.

**Hide HUD sends F1 only.** The tile has no latched state, because Cofre can't know the game's real F1 state. A hardware F1 press would make any displayed state wrong.

### Catalog: Advanced section (available in Edit, not on screen by default)
- **Common:** Drop (Q), Drop stack (Ctrl+Q), Screenshot (F2), Advancements (L), Commands (`/`), Pick block (middle mouse), Social (P)
- **Debug chords:** Chunk borders (F3+G), Hitboxes (F3+B), Advanced tooltips (F3+H), Reload resources (F3+T), Copy coordinates (F3+C, which opens the crash countdown if held too long, so send it as a quick chord)
- **Custom keys:** user-defined (see below)

### Custom-key behaviour
- **Label:** at most 8 characters.
- **Icon:** an automatic 1–2 character monogram, or a choice from the existing pixel icon set.
- **Binding:** a chord of 1–3 keys, or a key plus a mouse button.
  - Keys are pressed in order and released in reverse order.
  - There's no gap between them, so chords like F3+G register.
- **Key entry:** either
  - "Record from keyboard", when a hardware keyboard is attached, or
  - a grouped picker: Letters, Numbers, F1–F12, Modifiers, Arrows/Nav, Mouse.
- **Behaviour options:**
  - **Tap:** key down, then key up after about 50 ms (at least 2 frames). The tray closes.
  - **Hold:** key down while the finger stays on the tile; key up on release. This works with both drag-select and direct touch. The tray stays open until release.
  - **Toggle:** key down on tap, and the tray closes. A pixel chip `[M ×]` appears under the menu button; tap it to release the key.
- **Toggle auto-release:** Cofre sends key-up when the app backgrounds, Edit opens, chat or the keyboard opens, the layout changes, or a hardware mode activates. This prevents stuck keys.
- **Deleting a custom key** that's in the tray leaves the slot empty ("+" tile). The saved data stays valid.
- **Storage:** global in v1. Per-instance overrides make sense later, because mod keys differ between modpacks.

### Model sketch (fits the current enum and GameInputService)
```swift
enum ActionMode: String, Codable { case tap, hold, toggle }
enum InputKey: Codable, Hashable { case key(KeyCode), mouse(MouseButton) }

struct QuickActionDef: Codable, Identifiable, Hashable {
    let id: String            // "builtin.perspective" | UUID string
    var title: String         // ≤ 8 chars displayed
    var glyph: Glyph          // icon asset or monogram
    var chord: [InputKey]     // 1–3
    var mode: ActionMode
}

enum TrayItem: Codable, Hashable {
    case pause, edit, keyboard          // system, not key-driven
    case action(id: String)             // resolves via catalog; missing → empty
}
```
- Built-in actions are static `QuickActionDef` presets. Custom keys are stored as JSON in UserDefaults.
- The tray stores `[TrayItem]`: 6 editable slots, with Pause and Edit always inserted at fixed positions.
- The executor maps `chord` and `mode` to `GameInputService` press/release calls.
- **To confirm:** this needs separate down and up events. If the service only offers "send key", Hold and Toggle need that addition.

---

## 4. Configuration screen

**Entry points:**
- the tray's **Edit** tile;
- Settings → Controls → Quick menu.

Both open the same view as a full-screen cover. When opened in-game, show a small note. *Proposed copy:* "Game keeps running in multiplayer."

```
┌ Quick menu ─────────────────────────────────── Reset   Done ┐
│ YOUR TRAY  (tap a slot)          │ ACTIONS                   │
│ ┌────┬────┬────┬────┐            │ Common                    │
│ │PAUS│VIEW│PLYR│SWAP│            │  Drop            Q     +  │
│ ├────┼────┼────┼────┤            │  Screenshot      F2    +  │
│ │HUD │▣DBG│KBD │EDIT│            │ Debug                     │
│ └────┴────┴────┴────┘            │  Chunk borders  F3+G   +  │
│ Pause & Edit are fixed           │ Custom keys               │
│                                  │  Map     M   Tap    ✎  +  │
│ Selected: Debug · F3             │  Zoom    C   Hold   ✎  +  │
│ [◀ Move] [Move ▶] [Remove]       │  ＋ New custom key        │
└──────────────────────────────────┴───────────────────────────┘
```

**Behaviour:**
- **Placing actions:**
  - With a slot selected, tapping an action's `+` replaces that slot.
  - With no slot selected, `+` fills the first empty slot.
  - If all slots are full and nothing is selected, `+` is disabled. *Proposed hint:* "Tap a slot to replace."
- **Reordering:** drag tiles in the preview (`onDrag`/`onDrop`). The Move buttons and VoiceOver actions do the same thing, so dragging is never required.
- **Already-placed actions** show a check mark instead of `+`.
- **Reset:** restores the defaults and asks for confirmation. Custom-key definitions are kept.
- **Narrow iPhone:** the catalog column scrolls, and the preview pane stays pinned.

### Custom key editor
```
┌ New custom key ──────────────────────── Cancel   Save ┐
│ Label     [Map     ]            8 max                 │
│ Icon      [M] monogram          [Choose icon…]        │
│ Key       [ M ]   [Record from keyboard]              │
│ Chord     + [Shift] [Ctrl] [Alt]  [+ Add key]         │
│ Behavior  ( Tap | Hold | Toggle )                     │
│ Preview   ┌──┐  "Taps M once."                        │
│           │M │                                        │
└───────────────────────────────────────────────────────┘
```

**Rules:**
- Save is disabled until there's a label and at least one key.
- If the binding already exists, show an inline warning but still allow saving.
- *Proposed preview copy:*
  - "Taps M once."
  - "Holds C while touched."
  - "Holds M until you tap the chip."

---

## 5. Left-stick zone bug

### Likely causes, most probable first

1. **Touches fall through to the game surface.** If the stick zone is `Color.clear` (or similar) without `.contentShape(Rectangle())`, it isn't hit-testable. Until the floating stick view exists, those touches reach the game surface or the full-screen look gesture underneath. That would explain "only before the joystick appears".
2. **The look and stick gestures compete.** A full-screen look `DragGesture` attached as `simultaneousGesture` or as a parent gesture moves the camera before the stick claims the touch. SwiftUI's default `minimumDistance` of 10 pt widens this window.
3. **Coordinate-space mismatch.** The zone is tested in `.global`, but the overlay is laid out inside safe-area insets (or the reverse), so touches near the edge are misclassified.

### Minimal fix
- **Decide ownership once, at touch-down, in one named coordinate space.** Use `.coordinateSpace(name: "overlay")` on the overlay root, and test against `zoneRect = CGRect(x: 0, y: 0, width: size.width * pct, height: size.height)`.
- **Make the zones siblings, not layers.** Replace "full-screen look underneath plus stick on top" with an `HStack` of two hit-testable regions:
  - stick zone: width `pct`;
  - look area: the remainder.
  - Both use `.contentShape(Rectangle())`.
  - Gestures on sibling views don't compete, and separate views can track separate touches at the same time (stick plus look).
- **Stick zone gesture:** `DragGesture(minimumDistance: 0, coordinateSpace: .named("overlay"))`. It claims the touch immediately, and its first point spawns the floating stick.
- **If the look gesture must stay full-screen,** guard it in `onChanged`: if `value.startLocation` is inside `zoneRect`, return without setting a baseline or applying a delta.
- **Look gesture baseline:** reset it in `onEnded`, and set it on the first `onChanged`, so no stale or initial delta is ever applied.
  - Don't change tap-to-attack/use timing as part of this fix.
- **Buttons always win:** hotbar, chat and other buttons inside the left strip must be layered above the stick zone.
- **UIKit path:** if touches are handled in a `UIViewRepresentable`, apply the same rule per `UITouch`. Keep a `[ObjectIdentifier: Owner]` map filled in `touchesBegan` and cleared in `touchesEnded` and `touchesCancelled`.

### Visual affordance
- **During gameplay:** show a ghost stick ring at the zone's rest point, a 1 px light pixel outline at about 30% opacity. Don't draw a persistent strip.
- **In Settings:** while the stick-area slider is being dragged, overlay a live preview of the zone (dashed pixel border, 15% fill, "40%" label). It fades out 600 ms after the finger lifts, or switches instantly with Reduce Motion on.

---

## 6. Critique and key correction

The biggest risk in a configurable tray is assuming every action is a single tap. Players (Tab), zoom mods and many mod keys only work while the key is held. A tap-only tray would make the custom-key feature look broken.

The fix is the **Tap / Hold / Toggle** behaviour setting, drag-to-select, and a visible way to release toggled keys (the chip, plus auto-release). Treat these as required, not optional extras.

The second risk is that hold-to-open is hard to discover. The pixel notch, the one-time tooltip and the VoiceOver action address it.

---

## Implementation and visual-verification checklist
- [ ] `TrayItem` migrated to `.pause/.edit/.keyboard/.action(id:)`; built-in catalog defined as `QuickActionDef` presets.
- [ ] `GameInputService` supports separate down and up events and ordered chords (confirm, or add).
- [ ] Hold-to-open at 300 ms with drag-to-select and sticky fallback; haptics on open and on tile entry.
- [ ] Toggle chip appears when a key is latched; keys auto-release on background, Edit, chat, layout change and hardware mode.
- [ ] Hotbar long-press drop works, or Drop is restored to default slot 6.
- [ ] Config screen works with VoiceOver only (no drag needed); Reset keeps custom keys.
- [ ] Stick zone uses sibling hit regions or ownership at touch-down. Verify: touching and slowly dragging in the left strip moves the camera by 0 px at 20%, 40% and 60%, on iPhone with notch-side insets in both landscape orientations and on iPad.
- [ ] Stick and look work at the same time with two fingers; hotbar and chat buttons inside the strip still fire.
- [ ] Visual check: tray labels pass AA over snow, sky and night scenes; no tile is smaller than 44 pt; the crosshair stays visible with the tray open on the smallest supported iPhone.
- [ ] Reduce Motion makes the tray and zone preview fade only; focus outlines are visible with a hardware keyboard.
