# Mods search filters: design proposal

Source: Claude design pass, 2026-10-30. Not yet implemented when written.

User requirements:
- One Filters button and one filters sheet shared by Mods, Modpacks, Shaders and Resource Packs; each kind has its own fields.
- Filters auto-preselect from the selected instance (compatibility).
- A small Modrinth ⇄ CurseForge toggle button, not a full segmented picker.
- The Filters button shows how many filters are applied.

## 1) Layout and hierarchy

```
ColumnHeader "Get mods"                         [Installed · n]
ModsInstanceSwitcher
[ 🔍 Search mods…              ] [Modrinth ⇄] [Filters · 3]
ChipGroup: Mods | Packs | Shaders | Resource
"For 1.21.1 · Fabric · Client"         ← muted summary line, tapping it opens the sheet
results…
```

- **Type stays as chips.** The kind decides which filter fields exist, so it isn't one of the filters itself.
- **Row 3 replaces the `Segmented` picker.** The Field takes the free width; the two buttons use `.fixedSize()`.
- **iPhone (compact):** same rows with 16pt padding. At accessibility text sizes, `ViewThatFits` moves both buttons onto their own row under the field.
- **iPad (regular):** same pane on the list side of `AdaptiveListDetail`, with 20pt padding. `blockSheet` already shows a centred form sheet on regular and a bottom sheet with detents on compact.

## 2) Fields per kind

All option values below are Modrinth facets.

| Field | Mods | Modpacks | Shaders | Resource packs |
|---|---|---|---|---|
| Game version: This instance (1.21.1) / Any | ✅ | ✅ | ✅ | ✅ |
| Loader: This instance (Fabric) / Any | ✅ | ✅ | — | — |
| Shader loader: Iris / OptiFine / Any | — | — | ✅ | — |
| Side: Runs on client / Any | ✅ | ✅ | — | — |
| Resolution: Any / 16x / 32x / 64x / 128x+ | — | — | — | ✅ |
| Categories (multi-select) | worldgen, technology, magic, utility, optimization, storage, decoration, adventure, library… | adventure, kitchen-sink, lightweight, quests, technology, magic, multiplayer, optimization | style (realistic, vanilla-like, fantasy, cartoon), performance (potato → screenshot) | vanilla-like, realistic, simplistic, themed, gui, audio, models, tweaks |
| Sort: Relevance / Downloads / Updated / Newest | ✅ | ✅ | ✅ | ✅ |

- **Version and Loader only offer "This instance" or "Any".** Another version would show things that can't be installed into the current instance.
- **Side has no server option.** Cofre installs into client instances.

## 3) Auto-selected vs user-selected

- **Each field defaults to following the instance.** Version, loader and side derive from the current instance and update live when it changes.
- **Shaders default to Iris** when the instance uses Fabric, Quilt or NeoForge, and to Any otherwise.
- **A user override is kept per kind** and shown with the normal selected chip.
- **When the user switches instance:** version and loader overrides reset to the instance; categories, resolution and sort are kept.
- **Sheet footer:** "Reset to instance" (secondary) and "Done" (primary). Changes apply live through the existing 250ms debounce; no Apply button.
- **With no instance**, the "This instance" options are hidden and the defaults are Any.

## 4) Source toggle

- A `BlockButton(size: .small)` labelled with the current source plus ⇄ ("Modrinth ⇄"). One tap switches to the other source.
- CurseForge without a key still switches; the existing "Needs a CurseForge key" EmptyState handles it.
- **On CurseForge only version, loader and sort are supported** (what `air.searchProjects` maps today: `mcVersion`, `loader`). Other fields are disabled with a muted "Modrinth only" note and left out of the query and the count.

## 5) Active-count rules

- **Counted:** every field that isn't Any, auto-selected ones included. Mods on a Fabric 1.21.1 instance starts at 3 (version, loader, client).
- **Each selected category counts as 1.** So does Resolution when set.
- **Not counted:** sort, search text, kind, source, and fields the current source doesn't support.
- **At 0** the button reads "Filters"; otherwise "Filters · N" (same pattern as "Installed · n").

## 6) Wireframes

**Compact (iPhone)**
```
┌───────────────────────────────┐
│ Get mods          [Installed] │
│ ▸ Survival 1.21.1 (Fabric)    │
│ [🔍 Search mods…  ]           │
│      [Modrinth ⇄][Filters · 3]│  ← under the field only at large text sizes
│ (Mods)(Packs)(Shaders)(Res…)  │
│ For 1.21.1 · Fabric · Client  │
│ ▢ Sodium     …   [Get]        │
└───────────────────────────────┘
Sheet (bottom, hugs content):
┌───────────────────────────────┐
│ Filters · Mods                │
│ Version  (1.21.1 ✓)(Any)      │
│ Loader   (Fabric ✓)(Any)      │
│ Side     (Client ✓)(Any)      │
│ Category (tech)(magic)(util)… │
│ Sort     (Relevance ✓)(Dl)…   │
│ [Reset to instance]   [Done]  │
└───────────────────────────────┘
```

## 7) Primitives and model/API changes

| Element | Primitive |
|---|---|
| Filters button, source button | `BlockButton(size: .small)` |
| Sheet | `.blockSheet(isPresented:, hugsContent: true)` |
| Single-select rows | `ChipGroup` |
| Categories | Standalone `Chip(isOn:)` in a wrapping `AdaptiveGrid` (`ChipGroup` only scrolls horizontally) |
| Footer | Two `BlockButton`s |
| Unsupported note, summary line | `Badge` / muted text |

Model (in `Models.swift`):
```swift
public enum FilterScope: Hashable, Sendable { case instance, any }
public enum ProjectSort: String, Hashable, Sendable { case relevance, downloads, updated, newest }
public struct ProjectFilters: Hashable, Sendable {
    public var version: FilterScope = .instance
    public var loader: FilterScope = .instance
    public var shaderLoader: String?        // nil = auto
    public var clientOnly: FilterScope = .instance
    public var resolution: String?
    public var categories: Set<String> = []
    public var sort: ProjectSort = .relevance
    public func activeCount(kind: ContentKind, source: ProjectSource, hasInstance: Bool) -> Int
}
// ProjectQuery gains: public var filters = ProjectFilters()
```
- `CofreStore` keeps `[ContentKind: ProjectFilters]` and swaps `query.filters` when the kind changes.
- `.task(id: store.query)` keeps working, since `ProjectQuery` stays Hashable.

Backend (`CofreBackendAdapter+Mods.swift` search):
- Add version and loader facets only when the field is `.instance`, replacing the unconditional `instanceID` check.
- `clientOnly` adds `["client_side:required", "client_side:optional"]`.
- Shader loader, resolution and each category add their own AND group, `[["categories:x"]]`.
- `sort` goes to the `index:` argument `Modrinth.search` already takes.
- CurseForge passes only `mcVersion` and `loader`.

## 8) Edge cases and accessibility

- **Version = Any:** `fits: true` is hard-coded today. Decode `versions` from the Modrinth search hit and set `fits` from it, or show `Badge("Other version", tone: .warn)`.
- **Vanilla instance:** the Loader row is hidden for Mods; Packs default to loader Any.
- **Data packs:** out of scope (no chip).
- **Zero results with filters on:** "No results" EmptyState gets a "Clear filters" button.
- **Instance change while the sheet is open:** auto values update in place.
- Accessibility: Filters button label "Filters", value "3 active"; source button label "Source, Modrinth", hint "Switches to CurseForge"; chips expose `.isSelected`; auto chips read "1.21.1, from this instance"; 44pt targets; announce result-count changes; `ViewThatFits` for Dynamic Type; the summary line is a button that opens the sheet.
