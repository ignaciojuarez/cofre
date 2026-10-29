# Cofre design system

> Status: spec only, nothing built. Mockups: [`ipad.html`](ipad.html) (iPad, self-contained, 124 KB) and [`../../launcher-plan/ui/index.html`](../../launcher-plan/ui/index.html) (approved iPhone, still says "Cobble").
> Facade it binds to: `cofre/app/CofreBackendAdapter/CofreBackendAdapter.swift` (`AirBridge`, `TunnelService`, `JITService`, `PairingStore`, `SetupStatus`), read on 2026-10-28.

## 0. Rules

| # | Rule |
|---|---|
| 1 | **One screen, one implementation.** iPhone and iPad render the same pane views. Only the container around them changes. |
| 2 | **Layout reads the window, never the device.** Use the size class plus the shell's measured width. No `UIDevice.idiom` and no model checks in the UI. |
| 3 | **Tokens are the only colors, fonts and metrics.** SwiftUI and Air's UIKit screens read the same `CofreTheme`. |
| 4 | **System-owned surfaces stay native:** alerts, context menus, share sheet, document picker, menu bar, keyboard. This is already the rule in the iPhone mockup (S05). |
| 5 | **Square blocks.** 2 pt outline, a bevel on top, a lip below. No corner radius except system surfaces and controller glyphs. |

---

## 1. Tokens

### 1.1 Color

The theme is dark by default. Light and Auto are set in X07. Every token is one dynamic `UIColor`, and SwiftUI wraps it with `Color(uiColor:)`, so both stacks resolve the same value.

| Token | Role | Dark | Light |
|---|---|---|---|
| `page` | Window background (+ stone texture) | `#0f0d17` | `#ece7f7` |
| `side` | Sidebar, rail, tab bar, inspector | `#0b0a11` | `#e2dbf2` |
| `panel` | Block fill | `#1a1727` | `#f8f6fd` |
| `raised` | Selected row, active nav item | `#221e34` | `#e9e3f8` |
| `button` / `buttonBevel` | Secondary button face / top highlight | `#2b2641` / `#3d3560` | `#ddd4f3` / `#f4f0fe` |
| `well` | Inset surfaces: fields, tracks, logs | `#0c0b12` | `#f3f0fb` |
| `bevel` / `lip` | Block top highlight / bottom shade | `#342d52` / `#07060b` | `#ffffff` / `#c3b8e2` |
| `outline` | 2 pt block outline | `#05040a` | `#2b2244` |
| `outlineHC` | Outline when Increase Contrast is on | `#8a82a3` | `#2b2244` |
| `ink` / `inkSoft` / `muted` | Text: primary / secondary / labels | `#ecedf3` / `#c5c7d1` / `#a29cb8` | `#1b1530` / `#3b3354` / `#585071` |
| `accent` | Focus ring, selection bar, links | `#9a86ff` | `#5333c9` |
| `face` / `faceBevel` / `faceLip` / `onFace` | Primary button, on-state | `#5b3fd6` / `#8a74ff` / `#3a2694` / `#fff` | `#5b3fd6` / `#8069ef` / `#3a2694` / `#fff` |
| `success` / `warn` / `danger` | Status text and tints | `#45c27a` / `#f0b84f` / `#f07a68` | `#136336` / `#7a4f00` / `#a3301d` |
| `hover` | Overlay on hovered large blocks | ink 8% | ink 6% |
| Tints (badges, banners) | Tone mixed into `panel`: Fabric = accent 22%, Forge = warn 24%, NeoForge = danger 24%, Quilt = `#5ad1e8` 22%, ok 24%, bad/update 26%, banner 16% | precomputed | precomputed |

The accent swatches in X07 swap one `AccentFamily` (`face`, `faceBevel`, `faceLip`, `accent`) and push the same hex to Air's `general.accent_color`.

**Measured contrast (WCAG 2.x).** All text pairs pass AA.

| Pair | Dark | Light |
|---|---|---|
| ink / page | 16.5 | 14.5 |
| muted / panel (smallest text) | 6.7 | 7.0 |
| muted / side | 7.5 | 5.6 |
| accent / panel (focus ring, links) | 6.0 | 7.3 |
| onFace / face (primary button) | 6.7 | 6.7 |
| success · warn · danger / panel | 7.7 · 9.8 · 6.4 | 6.8 · 6.7 · 6.5 |
| outline / panel (dark block edge) | **1.2** → `outlineHC` 4.9 | 13.9 |

In dark mode, block edges are decorative and the label carries the meaning. Fields and switches add a label and a state glyph. Under Increase Contrast, `outline` becomes `outlineHC`.

### 1.2 Type

Every role scales with Dynamic Type through `Font.custom(_:size:relativeTo:)` in SwiftUI and `UIFontMetrics` in UIKit.

| Role | Font | pt / line | Weight | `relativeTo` | Use |
|---|---|---|---|---|---|
| `display` | Pixelify Sans | 31 compact · 34 regular / 1.05 | 700 | `.largeTitle` | Welcome, Ready, hero instance name |
| `title` | Pixelify Sans | 26 / 1.08 | 600 | `.title` | Step titles, mod name |
| `title2` | Pixelify Sans | 21 | 600 | `.title2` | Secondary headings |
| `header` | Pixelify Sans | 22 column · 17 compact bar | 600 | `.headline` | ColumnHeader |
| `buttonL` · `button` · `buttonS` | Pixelify Sans | 19 · 15 · 13 | 500 | `.body` / `.subheadline` | BlockButton sizes. Segmented 13, chip 12 |
| `nav` | Pixelify Sans | 16 sidebar · 11.5 tab/rail | 500 | `.body` / `.caption` | NavChrome |
| `badge` | Pixelify Sans, uppercase, +0.03em | 11 | 500 | `.caption2` | Badge |
| `body` | Geist | 15 / 1.55 | 400 | `.subheadline` | Paragraphs |
| `rowTitle` | Geist | 14 (13.5 in mock) | 500 | `.subheadline` | Row title |
| `secondary` | Geist | 13 / 1.45 | 400 | `.footnote` | Lede, row subtitle 11 → `caption` |
| `label` · `meta` | Geist Mono, uppercase, +0.07em | **11** (10 in mock) | 400 | `.caption2` | Section labels, row trailing meta |
| `code` | Geist Mono | 11.5 · log 10.5→11 | 400 | `.caption` | Logs, JVM args |

Mono labels go up from the mock's 10 pt to 11 pt, Apple's minimum legible size. That is the only change to type.

### 1.3 Space and size

| Token | pt | Use |
|---|---|---|
| `s1` | 2 | Outline, segmented inner padding |
| `s2` | 4 | Dense list gap, badge gap |
| `s3` | 6 | Grid and chip gap |
| `s4` | 8 | Split gap, dense pane stack |
| `s5` | 10 | Default pane stack gap |
| `s6` | 12 | Row horizontal padding |
| `s7` | 16 | Compact pane margin |
| `s8` | 20 | Regular pane margin, column header inset |
| `s9` | 28 | Card padding |

| Size | pt |
|---|---|
| Hit target (every control) | **≥ 44 × 44** (visual can be smaller: small button 30, switch 22) |
| Row min height | 44 (40 visual in mock + hit padding) |
| Button height S / M / L | 30 / 42 / 50 |
| Field | 38 visual · 44 hit |
| Sidebar · rail · tab bar | 248 · 76 · 56 + safe area |
| List column · aside · inspector | 320–360 · 380 · 360 |
| Readable column · card | 720 max · 560 |

### 1.4 Block geometry

| Token | Value |
|---|---|
| `outline` | 2 pt stroke, square |
| `bevel` | 2 pt inset highlight on top (`bevel`, or `buttonBevel`/`faceBevel` on buttons) |
| `lip` | Bottom inset shade: **2** on panels, rows, chips and segments · **4** on buttons M/L · **3** on small buttons |
| Pressed | Lip shrinks to 1 and content moves down 2 pt. Total height stays the same, so the block looks pushed in. |
| Selected | `raised` fill + 4 pt `accent` bar on the leading edge (rows, sidebar). Tab bar uses a 3 pt top bar. |
| Focus ring | 2 pt `accent`, offset 2 pt **outside** the outline, square. Contrast is measured against the surrounding surface (6.0+). |
| Hover | `hover` overlay on top of the fill. The fill color itself never changes, so one rule covers every variant. |
| Disabled | 42% opacity, no bevel, no lip, no pointer effect |

### 1.5 Motion

| Token | Value | Use | Reduce Motion |
|---|---|---|---|
| `press` | Down instantly, up in 90 ms linear | Buttons, rows | No movement. Fill darkens instead. |
| `toggle` | 120 ms, 3 steps | Switch thumb, segment | Instant |
| `select` | 120 ms ease-out | Selection bar, nav highlight | Instant |
| `column` | 220 ms ease-in-out | Sidebar ↔ rail, split ↔ stack | 150 ms crossfade |
| `push` / `sheet` | System | NavigationStack, sheets | System (already crossfades) |
| `xp` | Fills in 9 pt segments, no tween | ProgressBar | Same |
| `blink` | 1 s, `steps(1)` loop | Spinner (4 pixels) | Static, with "62%" text |

Pixel scenes are static (no parallax). Haptics: `.selection` on segment and switch, `.success` when JIT is ready or a launch finishes.

---

## 2. Components

**Shared states.** Every interactive component uses these. The mock's *Component states* panel shows each one.

| State | Visual | Input |
|---|---|---|
| Default | Block recipe | — |
| Hover | `hover` overlay. On small controls the system pointer also morphs to the rectangle (`.hoverEffect(.highlight)` + `contentShape(.hoverEffect, Rectangle())`). On large blocks (rows, cards) only the overlay shows (`.onHover`), as Apple recommends for big targets. | Trackpad, mouse |
| Active | Pressed (buttons, rows), on (switch, chip, segment), editing (field) | Touch, click, Space/Return, controller Ⓐ |
| Focus | Accent ring. The system focus effect is turned off (`.focusEffectDisabled()`) and we draw our own. | Tab and arrow keys, Full Keyboard Access, controller |
| Disabled | 42%, flat | — |

**Shared accessibility.**
- Dynamic Type at every size. At accessibility sizes, rows put their trailing content under the title (`ViewThatFits` / `isAccessibilitySize`), grids drop to one column, and the tab bar uses the Large Content Viewer.
- VoiceOver reads one element per row. Labels come from text, never from color alone.
- Increase Contrast switches to `outlineHC`, and `muted` becomes `inkSoft`. Bold Text adds 100 to Geist weights (Pixelify Sans is already bold).
- Smart Invert is ignored on scenes and pixel icons.

| # | Component | Variants | Specific states | Accessibility notes |
|---|---|---|---|---|
| 1 | **Block** | panel · raised · well · button · primary · tinted(tone) | selected | Container only. Not focusable unless it wraps an action. |
| 2 | **BlockButton** | primary · secondary · ghost · destructive · icon-only × S/M/L · full or hug width | pressed, loading (Spinner replaces the icon, label stays) | `Button` semantics. Icon-only buttons need `accessibilityLabel`. Shortcut appears in the hint (`.keyboardShortcut`). |
| 3 | **Badge** | neutral · fabric · forge · neoforge · quilt · ok · bad · update × regular/big | — | Read as part of its row ("Fabric 1.21.1"). Never the only signal of state. |
| 4 | **Row** | two-part · leading icon · index (01) · big · with trailing switch/button/meta/chevron | selected, dimmed | `.accessibilityElement(children: .combine)`. A trailing switch becomes the row's toggle trait. Chevron rows get the button trait. |
| 5 | **ListSection** | label + 4/5 pt stack · static `VStack` or data `List` (see §4.4) | — | The label becomes a header (`.isHeader`). |
| 6 | **Segmented** | regular · small | on, focus per segment | `accessibilityRepresentation { Picker }`, so VoiceOver reads "1 of 3" |
| 7 | **Switch** | — (ToggleStyle) | on/off, disabled | Toggle trait. When the "On/Off Labels" setting is on, draws I/O pixel glyphs. Off thumb is `inkSoft`, so the state is visible at ≥ 3:1. |
| 8 | **Slider** | value text right · with a range note ("Keep ≤ 75%") | dragging | `accessibilityRepresentation { Slider }` + adjustable. Value read with its unit ("6,144 megabytes"). |
| 9 | **Field** | plain · search (⌕) · secure (CF key) · mono (JVM args) | editing (accent hairline + caret), error (danger outline + message under it) | Label is always visible above (ListSection label) or given via `accessibilityLabel`. The error is announced. |
| 10 | **SelectButton** | instance picker · version picker (opens a native `Menu`) | open | Button + "pop-up" hint. Shortcut ⌘K for the instance picker. |
| 11 | **Chip / ChipGroup** | single-select · toggle | on | Selected trait. The group is a Picker representation. |
| 12 | **Radio** | — (row lead) | on | Selected trait on the row |
| 13 | **ProgressBar** | XP (success segments) · neutral · small | indeterminate (Spinner + text) | `ProgressView` semantics, value "62 percent". Stage changes are announced, throttled to every 2 s. |
| 14 | **Spinner** | 4-pixel blink | — | Hidden from VoiceOver. The parent row says "Loading". Static under Reduce Motion. |
| 15 | **StepBar** | bars only (compact) · bars + names (regular) | done, current, pending | Reads "Step 3 of 6, Pairing file" |
| 16 | **PixelIcon** | 8×8-grid glyphs (grass, stone, ore(tint), book, gear, play, bolt, cmd, key, shield, check, paper, chest, head, cross; blocks dirt, cobble, planks, sand, gravel, log, bricks) and 12×12 loader marks (fabric, quilt, forge, neoforge; vanilla uses grass) × any size. Instance icons: pack PNG, else the user's pick, else the loader's mark or a block picked from the instance ID | dimmed (55% in nav) | Decorative (`accessibilityHidden`) unless it's the only content. Then it gets a label. |
| 17 | **AppIcon** | placeholder `cofre-design/icons/01-vanilla.png` | — | Decorative |
| 18 | **PixelScene** | seeded moonlit lake (square moon, cube-tree forest, glowing cabin, mirrored water) × pixel size | — | Decorative. Ignores Smart Invert. Rendered once per seed and size, then cached. Keeps a dark top for white titles and the moon near the middle, so narrow crops keep it. |
| 19 | **Stat** | value + label, tone | — | Combined: "142, mods" |
| 20 | **Banner** | warn · ok · bad · info + optional action | — | Announced when it appears for errors (`AccessibilityNotification.Announcement`) |
| 21 | **EmptyState** | no instances · no results · offline · needs CF key | — | Title is a header. The action is the first focus. |
| 22 | **Sheet** | form (centered on regular, `.presentationSizing(.form)`) · bottom sheet with detents (compact) | — | `presentationBackground(panel)`, no glass. Escape closes it. |
| 23 | **DropZone** | file types (plist · mrpack/zip · jar) | targeted (accent dashed + 14% tint) | It's a button ("Choose pairing file"). Drop is an extra path, never the only one. |
| 24 | **LogView** | live · static, color by tag | — | One text element with the label "Log". Share action. |
| 25 | **InputHint** | key cap (⌘ ⇧ ⌥ ↩ esc) · controller glyph (A B X Y LB RB ≡) · hint strip | — | Hidden from VoiceOver (shortcuts are exposed through the menu bar). Glyphs come from `GCController` so they match the user's controller. |
| 26 | **ColumnHeader** | title + trailing actions · back (only when pushed) | — | Title has the header trait |
| 27 | **NavChrome** | tabBar · rail · sidebar (+ pinned instances, JIT and account blocks) | selected, badge count | Tab and selected traits. ⌘1–⌘4. The rail shows labels so nothing is icon-only. |

**27 components** + **7 layout containers** (§3). Alerts, menus, share sheet, document picker and the menu bar are native and aren't counted.

---

## 3. Adaptive layout

### 3.1 Width classes

Breakpoints come from the **size class**, refined by the shell's own width. The device is never checked.

| `WidthClass` | Condition | Shell | List + detail | Split panes | Typical windows |
|---|---|---|---|---|---|
| `compact` | `horizontalSizeClass == .compact` | **TabBar** | Push | Fallback: stack, or a Segmented that picks one pane | iPhone portrait · Slide Over · narrow Split View and Stage Manager windows |
| `medium` | regular and shell width < **1100** pt | **Rail** 76 | Side by side, list 320–330 | Side by side if both minimums fit, else fallback | Every iPad in portrait · half-screen windows |
| `expanded` | regular and ≥ 1100 pt | **Sidebar** 248 | Side by side, list 340–360 | Side by side + third panel | Every iPad in landscape · large windows |

- **Height:** when `verticalSizeClass == .compact` (iPhone landscape), Launch and Setup switch to their side-by-side form. iPhone Max landscape reports regular width, so it gets the rail, which is intended.
- **Measurement:** one `onGeometryChange` at the shell root publishes `\.widthClass` to the environment. Inner containers measure their own width, because a pane in a 360 pt column is effectively compact.
- **Switching keeps state:** all navigation state lives in `NavModel`, not in view identity. Resizing a Stage Manager window from compact to regular moves the same selection from a pushed stack into a side-by-side column (W1 → I1).
- **One window only:** Cofre declares a single scene, because there is one JVM per process. Stage Manager resizing is fully supported.
- **Orientation:** the shell rotates freely. The game itself is locked to landscape by Air's `SurfaceViewController`.

### 3.2 Containers

| Container | Compact | Regular | Used by |
|---|---|---|---|
| `AdaptiveShell` | `NavigationStack` per section + TabBar | Rail or Sidebar + columns | App root |
| `AdaptiveListDetail` | List pushes detail | List column + detail column, selection in `NavModel` | Instances, Mods, Settings |
| `AdaptiveSplit` | Fallback `.stack` or `.segmented(titles)` | Primary (min width) + secondary (fixed width) | Play home + Worlds (`.segmented`), Launch scene + stages/log (`.stack`) |
| `AdaptiveGrid` | 1–3 columns | `LazyVGrid(.adaptive(minimum:))` | Stats, loader picker, (future) mod cards |
| `ReadableColumn` | Full width | Max 720 pt, centered | Detail panes, settings panes, mod page |
| `CenteredCard` | Full screen | 560 pt card over a PixelScene | Setup wizard, Ready |
| `FullScreenTakeover` | Full screen, shell hidden | Same | Launch, controls editor, game |

`AdaptiveSplit` and `AdaptiveShell` switch with `AnyLayout` (HStack ↔ VStack), which keeps child state. `ViewThatFits` would rebuild the children.

### 3.3 Navigation model

```
NAV = [Play, Instances, Mods, Settings] ──► TabBar (compact) | Rail (medium) | Sidebar (expanded)
NavModel { section, instance?, mod?, settingsPane, path[section] }   // one per window
```
- The sidebar adds **Pinned** instances (the first 3), a JIT status block and the account. In the rail these become icons. On compact they live on the Play tab.
- The Mods item shows an update count badge. ⌘1–⌘4 switch sections. ⌃⌘S toggles sidebar ↔ rail.
- The section and selection are saved per scene in `stateRestorationActivity`.

### 3.4 Pointer, keyboard, controller, drag and drop

| Input | Design |
|---|---|
| Pointer | Hover state (§2). Context menus on rows: instance (Play, Edit, Duplicate, Export, Delete), world (Back up, Open folder, Delete), mod (Toggle, Update, Delete). |
| Keyboard | Arrows move within a list. Tab moves between columns. Return activates. Esc goes back or closes. Every command also lives in the menu bar (table below). |
| Menu bar (iPadOS 26) | **Instance:** New ⌘N · Import Pack ⇧⌘I · Edit ⌘E · Duplicate ⌘D · Delete ⌘⌫. **Game:** Play ⌘↩ · Play Last World ⇧⌘↩ · Stop ⌘. · Test JIT ⌥⌘J · Show Log ⌘L · Controls Editor ⇧⌘K. **View:** sections ⌘1–⌘4 · Search ⌘F · Switch Instance ⌘K. Settings ⌘, |
| Controller | When a `GCController` is connected, a hint strip appears (N1). D-pad moves focus, Ⓐ activates, Ⓑ goes back, Ⓨ searches, LB/RB switch section, ≡ plays. Implemented as a small `ControllerFocusBridge` that maps to the same `@FocusState` order each screen declares. Check iPadOS 26's native controller-focus support first and drop the bridge if it covers this. |
| Drag and drop | Pairing `.plist` onto Setup S04 and X04. `.mrpack`/`.zip` onto Instances (imports a new instance). `.jar`/`.zip` onto Installed (mod/resource/shader). Logs drag out as a file. |

### 3.5 Changes to the approved iPhone mockup

1. On compact, the **Settings root becomes the grouped index** (Game · Controls · System) instead of a segmented control, so iPhone and iPad share one index component.
2. **Instance detail** is a new pane. iPhone pushes it from P03, which previously only had a ⋯ menu.
3. Mono labels go from 10 to **11 pt**. Rows and controls get **44 pt hit areas**.
4. The switch off-thumb becomes `inkSoft` so its state shows at ≥ 3:1.
5. Rename Cobble to **Cofre**. The mark becomes the chest app icon.

---

## 4. Screen map

**Containers:** C = compact, R = regular. **Binds:** exact `AirBridge` and CofreBackendAdapter members. ⚠ = needs a facade addition (§4.2).

| ID | Screen | Container C → R | Components | Binds |
|---|---|---|---|---|
| S01 | Welcome | CenteredCard | PixelScene, AppIcon, Stat×3, BlockButton(primary L) | `SetupStatusStore.value` (skip the wizard when everything is ready) |
| S02 | Developer Mode | CenteredCard | StepBar, PixelIcon, Row+Badge, ListSection(index rows), BlockButton×2 | `SetupStatus.devMode`, `SetupStatusStore.updates` |
| S03 | Trust | CenteredCard | StepBar, Row(check)×4, Block(well) | `SetupStatus.trust` · ⚠ signing info |
| S04 | Pairing | CenteredCard | StepBar, ListSection, DropZone(.plist), BlockButton | `PairingStore.hasPairing()`, `.importPairing(_:)`, `SetupStatus.pairing` |
| S05 | Local VPN | CenteredCard | StepBar, diagram Block, Rows, BlockButton + **native** alert | `TunnelService.start()`, `.isRunning`, `SetupStatus.vpn` |
| S06 | JIT test | CenteredCard | StepBar, Row(check or Spinner)×6, Banner(ok), Badge | `JITService.enable(pid:)`, `.isEnabled`, `SetupStatus.jit` · ⚠ step stream |
| S07 | Account | CenteredCard | StepBar, BlockButton(MS), Row(account) | `AirBridge.signInMicrosoft()`, `.accounts()`, `SetupStatus.account` |
| S08 | Ready | CenteredCard | PixelScene, Badge(big), Rows, Banner(tip), BlockButton(primary L) | `SetupStatusStore.value` |
| P01 | Play home + Worlds | AdaptiveSplit(.segmented) | ColumnHeader, Banner, PixelScene, SelectButton, BlockButton(L), AdaptiveGrid(Stat), ListSection(Row) · Worlds: Row+Button, servers Row+meta | `instances()`, `worlds(instanceID:)`, `servers(instanceID:)`, `accounts()`, `preferences(instanceID:)`, `launch(instanceID:)`, `JITService.isEnabled` |
| P02 | Launch | FullScreenTakeover + AdaptiveSplit(.stack) | PixelScene, ProgressBar(XP), Row(stage)×8, LogView, BlockButton×2 | `launchStages`, `launch(instanceID:)` · ⚠ progress, cancel, log |
| P03 | Instances | AdaptiveListDetail | Field(search), Row(big)+Badge, BlockButton, DropZone (on drag) | `instances()`, `importPack(_:instanceID:)` |
| I02 | Instance detail (new) | pushed → detail column | ColumnHeader, PixelScene, Badge×4, Segmented, AdaptiveGrid(Stat), Rows, Switch, BlockButton(ghost destructive) | `preferences(instanceID:)`, `setPreferences(_:instanceID:)`, `mods(instanceID:)`, `worlds(instanceID:)` · ⚠ duplicate/export/delete |
| P04 | New instance | Sheet(form) | Field, SelectButton, Segmented, AdaptiveGrid(loader tiles), Rows, Switch | `createInstance(name:version:loader:)`, `installLoader(instanceID:loader:version:)` · ⚠ version catalog · Forge/NeoForge → Air `ForgeInstallSchemeViewController` |
| M01 | Browse mods | AdaptiveListDetail | Segmented, Field(search), ChipGroup, Switch, Row+BlockButton(S)/Badge | `searchModrinth(query:)`, `searchCurseForge(query:)`, `install(pack:instanceID:)` · ⚠ project metadata |
| M02 | Mod page | detail column / pushed | PixelIcon(64), Badge, AdaptiveGrid(Stat), PixelScene(gallery), Radio rows, Row(dependency), BlockButton | `install(pack:instanceID:)` · ⚠ versions, dependencies |
| M03 | Import pack | Sheet(form) | Rows, DropZone, ProgressBar, Row(stage) | `importPack(_:instanceID:)` · ⚠ progress |
| M04 | Installed | AdaptiveListDetail (filters ↔ list) | Segmented, Field(filter), Row+Switch, Badge(update/needs dep), BlockButton | `mods(instanceID:)`, `shaders(instanceID:)`, `resourcePacks(instanceID:)`, `toggleMod(instanceID:id:enabled:)`, `deleteMod(instanceID:id:)`, `updateMods(instanceID:)` |
| X00 | Settings index | AdaptiveListDetail | ListSection×3, Row+PixelIcon | — |
| X01 | Game | ReadableColumn | Slider, Switch, Segmented, Rows | `preferences(instanceID:)`, `setPreferences(_:instanceID:)` (`ramMB`, `renderer`, `resolution`, `fsr`) |
| X02 | Renderer | ReadableColumn | Radio rows, Badge, Rows | `preferences.renderer` · ⚠ renderer list |
| X03 | Controls editor | **Air UIKit** `CustomControlsViewController`, full screen, themed | (Air) + Cofre tokens via §5.3 | ⚠ `AirScreens.controlsEditor()` |
| X04 | JIT & Java | ReadableColumn | Banner(ok), Rows, BlockButton×2, Badge×4, Field(mono) | `JITService.isEnabled`, `TunnelService.isRunning`, `PairingStore.*`, `SetupStatusStore`, `preferences.java`/`.jvmArgs` · ⚠ Java runtimes |
| X05 | Accounts & data | ReadableColumn | Row(account), BlockButton, Segmented, Switch, Field(secure), stacked bar, Legend | `accounts()`, `signInMicrosoft()`, `removeAccount(id:)` · ⚠ storage, CF key |
| X06 | Logs & about | ReadableColumn | Segmented, LogView, BlockButton×3, Rows | ⚠ logs, signing info |
| X07 | Look & more | ReadableColumn | Segmented(theme), swatches, Rows, Switch | `CofreTheme` (local) + ⚠ Air appearance push |
| — | Forge/NeoForge installer | **Air UIKit**, themed | — | ⚠ `AirScreens.forgeInstaller(instanceID:)` |

The six `SetupStatus` fields map one-to-one to the six wizard steps, and the shell needs nothing else for setup routing.

### 4.2 Facade gaps (proposals for the `cofre/app` owner, not built)

| Need | Screens | Proposed |
|---|---|---|
| Launch progress, cancel | P02 | `struct LaunchProgress { stage: Int; of: Int; title: String; fraction: Double?; detail: String? }` replaces the bare `LaunchStage` stream; `cancelLaunch()` |
| Logs | P02, X06 | `logLines(_ kind: LogKind) -> AsyncStream<LogLine>`, `exportLog(_:) -> URL` |
| Instance metadata and actions | P03, I02 | Add `modCount`, `sizeBytes`, `lastPlayed`, `loaderVersion`, `iconPNG` to `CofreInstance`; `duplicate`, `delete`, `export(format:) -> URL` |
| Version catalog | P04 | `gameVersions(_ kind: VersionKind)`, `loaderVersions(loader:game:)` |
| Project metadata | M01, M02 | `CofreProject { id, title, author, iconURL, downloads, updated, loaders, fits }`, `versions(projectID:instanceID:)`, `dependencies(versionID:)` |
| Install/import progress | M02, M03 | Return `AsyncThrowingStream<InstallProgress, Error>` instead of `async throws` |
| JIT test steps | S06, X04 | `JITService.test() -> AsyncThrowingStream<JITStep, Error>` (pairing, VPN, DDI, debugger, region, detach) |
| Signing info | S03, X06 | `SigningInfo { team, expires, deviceRegistered }` |
| Lists | X02, X04, X05 | `renderers()`, `javaRuntimes()`, `storage()`, `clearCache()`; CF key in Keychain (CofreBackendAdapter) |
| Air screens (UIKit) | X03, P04 | `protocol AirScreens { func controlsEditor() -> UIViewController; func forgeInstaller(instanceID: String) -> UIViewController }`. It goes in **Glue**, not CofreBackendAdapter, so CofreBackendAdapter stays UI-agnostic. |
| Air appearance | all Air VCs | `applyAirAppearance(accentHex:cardHex:textHex:)` writes `general.accent_color`/`card_color`/`text_color` and `background_glass_style` |

---

## 5. Implementation recommendation

### 5.1 Recommendation: SwiftUI for every Cofre screen, inside Air's UIKit root

| | SwiftUI | UIKit |
|---|---|---|
| One adaptive screen | Size class + `AnyLayout` + `onGeometryChange` in a few lines | Trait observation + constraint swapping per screen |
| Component library | Public `ButtonStyle`, `ToggleStyle`, `ProgressViewStyle`, `ViewModifier`, `accessibilityRepresentation` | `UIView` subclasses + configurations, about 2–3× the code |
| Dynamic Type, VoiceOver, focus | Mostly automatic with `relativeTo:` fonts and `@FocusState` | Manual `UIFontMetrics`, `adjustsFontForContentSizeCategory`, focus guides |
| Hosting in Air | `CofreRootViewController` (already the SceneDelegate hook, patch 0002) embeds one `UIHostingController` | Native |
| Air leftovers | Presented from the host, themed through UIAppearance (§5.3) | Same |
| Risk | iPadOS 26 system chrome is Liquid Glass (see below). Long lists need `List`. | Slower to build. Encourages per-device branches. |

**Pick SwiftUI** with our own chrome:
- **Don't use `NavigationSplitView` or `TabView(.sidebarAdaptable)` for chrome.** On iPadOS 26 both draw a floating Liquid Glass sidebar or tab bar that can't be made into a square block. The only opt-out is the app-wide `UIDesignRequiresCompatibility` key, which Apple says is temporary. Air's own `AmeRootTabController` notes also show the iOS 26 tab bar misbehaving outside a full-screen root.
- **Use `AdaptiveShell`** (HStack of `NavChrome` + columns). Each column is a `NavigationStack` with the bar hidden (`.toolbar(.hidden, for: .navigationBar)`) and our `ColumnHeader`. That keeps system push, back-swipe and keyboard handling.
- **Long data lists** (instances, mods, worlds) use `List(.plain)` with `.listRowBackground(BlockBackground())`, `.listRowSeparator(.hidden)` and `.scrollContentBackground(.hidden)`. That gives swipe actions, selection, keyboard navigation and laziness for free. Short static stacks use `VStack`.
- **Floor:** the shell needs iOS 17 (Observation, `focusEffectDisabled`). Cofre targets iOS 26/27 devices anyway. Use `presentationSizing(.form)` behind `#available(iOS 18)`. Air keeps its own floor.

### 5.2 Swift API (signatures)

```swift
// Theme ─ one source for SwiftUI and UIKit
public struct CofreTheme: Sendable {
    public var palette: Palette = .purple          // dynamic light/dark UIColors
    public var accent: AccentFamily = .purple      // X07 swatch
    public var space = Spacing(); public var block = BlockMetrics(); public var motion = Motion()
    public static let standard = CofreTheme()
}
public enum TextRole { case display, title, title2, header, buttonL, button, buttonS, nav, badge, body, rowTitle, secondary, caption, label, code }
public extension Font    { static func cofre(_ role: TextRole) -> Font }                 // Font.custom(_, size:, relativeTo:)
public extension UIFont  { static func cofre(_ role: TextRole) -> UIFont }               // UIFontMetrics-scaled
public extension Color   { static let cofre: CofreColors }                               // Color(uiColor:) wrappers
public extension UIColor { static let cofre: CofreUIColors }                             // same tokens for Air VCs
public extension EnvironmentValues {
    @Entry var cofreTheme: CofreTheme = .standard
    @Entry var widthClass: WidthClass = .compact
}
public enum WidthClass: Comparable, Sendable { case compact, medium, expanded }

// Block
public enum Tone: Sendable { case neutral, accent, success, warn, danger, fabric, forge, neoforge, quilt }
public enum BlockKind: Sendable { case panel, raised, well, button, primary, tinted(Tone) }
public struct BlockBackground: View { public init(_ kind: BlockKind = .panel, lip: CGFloat = 2, selected: Bool = false) }
public extension View {
    func block(_ kind: BlockKind = .panel, lip: CGFloat = 2, selected: Bool = false) -> some View
    func blockHover() -> some View                       // large blocks: hover overlay via onHover
    func blockFocusRing() -> some View                   // reads isFocused, draws the accent ring, disables the system effect
}

// Controls
public struct BlockButtonStyle: ButtonStyle {
    public enum Role { case primary, secondary, ghost, destructive }
    public enum Size { case small, regular, large }
    public init(_ role: Role = .secondary, size: Size = .regular, fullWidth: Bool = true)
}
public extension ButtonStyle where Self == BlockButtonStyle {
    static func block(_ role: BlockButtonStyle.Role = .secondary, size: BlockButtonStyle.Size = .regular) -> Self
}
public struct BlockToggleStyle: ToggleStyle { public init() }                        // Switch
public extension ToggleStyle where Self == BlockToggleStyle { static var block: Self { .init() } }
public struct XPProgressStyle: ProgressViewStyle { public init(tone: Tone = .success) } // ProgressBar
public struct Segmented<Value: Hashable>: View {
    public init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [(Value, LocalizedStringKey)], size: ControlSize = .regular)
}
public struct BlockSlider: View {
    public init(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1, valueText: @escaping (Double) -> String)
}
public struct Field: View {
    public enum Kind { case plain, search, secure, mono }
    public init(_ title: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey? = nil, kind: Kind = .plain, error: LocalizedStringKey? = nil)
}
public struct SelectButton<Value: Hashable>: View { public init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [(Value, String)]) }
public struct ChipGroup<Value: Hashable>: View { public init(selection: Binding<Value>, options: [(Value, LocalizedStringKey)]) }

// Content
public struct Badge: View { public init(_ text: LocalizedStringKey, tone: Tone = .neutral, big: Bool = false) }
public struct Row<Leading: View, Trailing: View>: View {
    public init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isSelected: Bool = false,
                @ViewBuilder leading: () -> Leading = { EmptyView() }, @ViewBuilder trailing: () -> Trailing = { EmptyView() })
}
public struct ListSection<Content: View>: View { public init(_ label: LocalizedStringKey? = nil, spacing: CGFloat = 5, @ViewBuilder content: () -> Content) }
public struct Stat: View { public init(_ value: String, label: LocalizedStringKey, tone: Tone = .neutral) }
public struct StepBar: View { public init(steps: [LocalizedStringKey], current: Int) }        // names when widthClass > .compact
public struct PixelIcon: View { public init(_ glyph: PixelGlyph, size: CGFloat = 16, tint: Color? = nil) }
public struct PixelScene: View { public init(seed: UInt32, pixels: CGSize = .init(width: 120, height: 80)) }
public struct Banner<Action: View>: View { public init(_ title: LocalizedStringKey, icon: PixelGlyph, tone: Tone = .warn, @ViewBuilder action: () -> Action) }
public struct EmptyState<Action: View>: View { public init(_ title: LocalizedStringKey, message: LocalizedStringKey, icon: PixelGlyph, @ViewBuilder action: () -> Action) }
public struct DropZone: View { public init(_ title: LocalizedStringKey, types: [UTType], onDrop: @escaping ([URL]) -> Void, onChoose: @escaping () -> Void) }
public struct LogView: View { public init(lines: [LogLine]) }
public struct KeyHint: View { public init(_ keys: String, _ label: LocalizedStringKey) }
public struct ColumnHeader<Trailing: View>: View { public init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) } // back only when pushed
public extension View { func blockSheet<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View }

// Navigation + layout
@Observable @MainActor public final class NavModel {
    public enum Section: String, CaseIterable, Codable { case play, instances, mods, settings }
    public var section: Section = .play
    public var instance: CofreInstance.ID?; public var mod: String?; public var settingsPane: SettingsPane = .game
    public var paths: [Section: NavigationPath] = [:]
}
public struct NavChrome: View { public enum Style { case tabBar, rail, sidebar }; public init(style: Style, nav: NavModel) }
public struct AdaptiveShell<Content: View>: View { public init(nav: NavModel, @ViewBuilder content: @escaping (NavModel.Section) -> Content) }
public struct AdaptiveListDetail<Item: Hashable, L: View, D: View>: View {
    public init(selection: Binding<Item?>, @ViewBuilder list: () -> L, @ViewBuilder detail: @escaping (Item) -> D)
}
public struct AdaptiveSplit<P: View, S: View>: View {
    public enum Fallback { case stack, segmented(LocalizedStringKey, LocalizedStringKey) }
    public init(primaryMin: CGFloat = 480, secondaryWidth: CGFloat = 380, fallback: Fallback = .stack,
                @ViewBuilder primary: () -> P, @ViewBuilder secondary: () -> S)
}
public struct AdaptiveGrid<C: View>: View { public init(minItem: CGFloat = 120, spacing: CGFloat = 6, @ViewBuilder content: () -> C) }
public struct ReadableColumn<C: View>: View { public init(maxWidth: CGFloat = 720, @ViewBuilder content: () -> C) }
public struct CenteredCard<C: View>: View { public init(width: CGFloat = 560, scene: UInt32 = 7, @ViewBuilder content: () -> C) }
```

Usage looks the same on every device:

```swift
AdaptiveListDetail(selection: $nav.instance) {
    InstancesList()                                // P03 pane
} detail: { id in
    InstanceDetail(id: id)                         // I02 pane
}
Button("Play") { play() }.buttonStyle(.block(.primary, size: .large)).keyboardShortcut(.return, modifiers: .command)
Toggle("Own folder", isOn: $ownFolder).toggleStyle(.block)
```

**Proposed files** (go in `cofre/app/Shell/` when building starts):
- `DesignSystem/Tokens.swift`: the only place hex values are written
- `Theme.swift`, `Fonts.swift`, `Components/*.swift` (one file per §2 row)
- `Layout/*.swift` (§3.2)
- `Screens/*.swift` (§4)
- `AirUIKitTheme.swift`

### 5.3 Air's leftover UIKit screens use the same tokens

The change ladder from PLAN §7 applies. Nothing here needs a new Air patch except the menu-bar forward.

1. **UIAppearance, scoped.** Present every Air view controller inside `CofreAirHostController: UINavigationController`, then scope the appearance proxies to it so they don't leak into the game or system pickers:
   ```swift
   @MainActor enum CofreUIKitTheme {
       static func apply(_ t: CofreTheme = .standard) {
           let scope = [CofreAirHostController.self]
           let bar = UINavigationBarAppearance(); bar.configureWithOpaqueBackground()
           bar.backgroundColor = .cofre.side; bar.shadowColor = .cofre.outline
           bar.titleTextAttributes = [.font: UIFont.cofre(.header), .foregroundColor: UIColor.cofre.ink]
           let nb = UINavigationBar.appearance(whenContainedInInstancesOf: scope)
           nb.standardAppearance = bar; nb.scrollEdgeAppearance = bar; nb.compactAppearance = bar; nb.tintColor = .cofre.accent
           UITableView.appearance(whenContainedInInstancesOf: scope).backgroundColor = .cofre.page
           UITableView.appearance(whenContainedInInstancesOf: scope).separatorColor = .cofre.outline
           UITableViewCell.appearance(whenContainedInInstancesOf: scope).backgroundColor = .cofre.panel
           UISwitch.appearance(whenContainedInInstancesOf: scope).onTintColor = .cofre.face
           UISlider.appearance(whenContainedInInstancesOf: scope).minimumTrackTintColor = .cofre.face
           let seg = UISegmentedControl.appearance(whenContainedInInstancesOf: scope)
           seg.selectedSegmentTintColor = .cofre.face
           seg.setTitleTextAttributes([.font: UIFont.cofre(.buttonS)], for: .normal)
       }
   }
   ```
   Call it once before the first presentation. Appearance only affects views created afterward.
2. **Air's own color prefs** (ladder step 2). Push `general.accent_color`, `general.card_color` and `general.text_color` (Air already reads these in `LauncherPreferences.m`) through `AirBridge.applyAirAppearance(...)`.
3. **The `AMEGlassStyle` hook.** Set `background_glass_style = "native"` and `background_glass_handdrawn = NO`, then post `AMEGlassStyleChanged`. Air's surfaces then use system materials instead of Liquid Glass and sit quietly behind our opaque blocks.
4. **Light/dark.** Cofre's theme switch sets `overrideUserInterfaceStyle` on the window, so the dynamic `UIColor.cofre` tokens resolve the same way in both stacks.
5. **Fidelity limit (accepted).** Air's view controllers get our colors, fonts, tints and bars, but not per-cell bevels and lips. The controls editor (X03) and Forge installer are rarely opened, and keeping them as Air's code is the plan's "reskin, don't rewrite" rule.
6. **Menu bar.** Air's AppDelegate owns `buildMenu(with:)`. Add a one-line forward to `CofreCommands.build(_:)` in the existing patch 0002, or use iPadOS 26's main-menu configuration API if it works without the AppDelegate (verify). Patch budget stays at 3.

### 5.4 Fonts: licenses and bundling

| Font | License | Copyright line (from `google/fonts` OFL.txt) | Reserved Font Name |
|---|---|---|---|
| Pixelify Sans | SIL OFL 1.1 | © 2021 The Pixelify Sans Project Authors (github.com/eifetx/Pixelify-Sans) | None declared |
| Geist, Geist Mono | SIL OFL 1.1 | © 2024 The Geist Project Authors (github.com/vercel/geist-font) | None declared |

- **Bundling is allowed.** OFL 1.1 permits embedding and redistributing the fonts with any software, commercial included. The fonts can't be sold on their own.
- **Requirements:** ship `OFL.txt` with the copyright lines in the bundle (e.g. `Fonts/OFL.txt`) and list both fonts in About → Licenses and in `NOTICE.txt`.
- **Subsetting and instancing are allowed.** Neither font declares a Reserved Font Name, so modified versions can keep their names.
- **GPL:** the fonts ship as separate files, aggregated with the GPL-3.0 app, which is fine. Don't paste font data into GPL source files.
- **Files:**
  - Geist and Geist Mono: use the static TTFs from the Geist release (Regular/Medium/SemiBold, Regular/Medium).
  - Pixelify Sans: instance static Medium/SemiBold/Bold from the variable font at build time (`fontTools varLib.instancer`).
  - Register them at launch with `CTFontManagerRegisterFontsForURL(_, .process, _)` from the Shell, so Air's Info.plist isn't patched. Total is well under 1 MB.
- The mockup embeds Latin subsets of the same three fonts as base64, under the same license.
