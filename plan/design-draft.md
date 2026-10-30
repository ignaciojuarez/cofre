# Design draft: launcher features (P0/P1) and performance presets

Draft for review. Mock data only; nothing is wired. It covers the approved items from `plan/missing-features.md` (P0/P1) and `plan/performance.md`. Servers are agent W's (`plan/servers.md`), and touch controls and mod version filters are out of scope.

- Code: `app/UI/Sources/CofreUI/Screens/Draft/` (9 files, real components, draft-only data in `DraftData`).
- Preview: `-screen draft -draft <area> -draftState <state>` (table at the end).
- Contact sheets: `/tmp/cofre-shots/agentZ-1-play-worlds.png` through `agentZ-8-ipad.png`.

## Separation of concerns

**The game's own files are the only source of truth:** `saves/`, `servers.dat`, `options.txt`, `resourcepacks/`, `shaderpacks/`, `config/iris.properties` and `mods/`. Cofre reads and writes them directly and never keeps a parallel copy, so a change in the game shows up in Cofre and the other way round.

**Cofre only does what the game can't do, or does badly on a phone:**

1. **Jump in.** Play a recent world or join a server straight from launch (Quick Play), skipping the title menus.
2. **Settings chosen before launch.** These can't change, or are painful to change, once the game runs: the preset, renderer, memory/Java/JVM, loader, GUI scale and language.
3. **File operations.** Back up and restore, import and export, copy to another instance, delete with undo.
4. **Checks before launch.** Version fit, missing mods, disk space.

If the game already has a feature, Cofre links to it ("…in game: Options › Resource Packs") instead of rebuilding it.

| Thing | In the game (owner) | In Cofre |
|---|---|---|
| Worlds | Create, world settings, game rules, data packs at creation | List from `saves/`, Play (Quick Play), back up and restore, import and export, copy to an instance, delete with undo |
| Servers | Add, edit, order (agent W) | Join, ping, copy (agent W) |
| Video, Audio, Controls | Every in-game menu | Nothing, except the preset's few keys plus GUI scale and language, all read back |
| Resource packs | On/off, order | Install, update, delete; shows "In use · 1" |
| Shaders | Pick and tune (Iris menu) | Install, update, delete; shows which one is in use |
| Data packs | On/off per world (`/datapack`) | Install into a world, update, delete |
| Mods | No mod manager | Everything: get, on/off (`.jar.disabled`), update, delete, fix missing dependencies |
| Engine | — | Renderer, memory, Java, JVM arguments, loader version, preset, heat-aware |

## Where it lives: one home per thing

```
Play ── Play home ── banners (one at a time) · Downloads strip · hero · Play
   │                 Jump back in (3 recent worlds, Play = Quick Play) · Performance row → Before you play
   ├─ Worlds ─────── list from saves/ · Import · long-press: Back up, Backups…, Export…, Copy to instance…, Delete
   └─ Servers ────── agent W
Instances ── list (★ Favorites, then groups) → detail: [Overview | Before you play]
                    Overview: stats · links (Worlds › Content › Servers ›) · group + notes · version · Duplicate/Export/Delete
                    Before you play: Performance · Game · Engine · Performance pack · Reset to Cofre defaults
Mods ─────── Get mods → Installed [Mods | Packs | Shaders | Data]
Settings ─── Logs (live tail, search, filter, Share report…) · Accounts & data (expired, demo, remove)
Sheets ───── Import pack · Open in Cofre · Version / Loader picker · Downloads · Duplicate · Export · Backups · Copy world
```

| # | Feature | Home | Also reached from |
|---|---|---|---|
| 1 | Duplicate, export/import, delete with undo | Instances: ⋯ menu and Overview › Manage | Long-press, ⌘D, ⌘⌫ |
| 1 | Groups, favorites, notes | Instances list sections; Overview › Group and notes | ★ in the detail header |
| 1 | Java, RAM, JVM, loader version | Detail › Before you play › Engine | Overview › Version |
| 2 | Modpack import | Instances › Import pack (file or link) | Open in Cofre; drag and drop onto Instances |
| 3 | Content parity | Mods › Installed, four tabs, one row pattern | Overview › Content › |
| 4 | Worlds | Play › Worlds | Play home "Jump back in"; Overview › Worlds › |
| 5 | options.txt before launch | Before you play › Performance + Game | Play home › Performance row |
| 6 | Preset, heat-aware, renderer, Performance pack | Before you play › Performance (+ the pack card) | Play home row and banners |
| 7 | Logs and share bundle | Settings › Logs › Share report… | Crash screen "Share log", failed import "Share report" |
| 8 | Versions, loaders, preflight | Version / Loader sheets (New instance, Overview › Version) | Open in Cofre, Copy world |
| 8 | Resume and retry | Downloads sheet | Downloads strip on Play |
| 9 | Open in Cofre, background downloads, Low Power/heat banner, autosave note | Sheet over the current screen; Play home | — |
| 10 | Expired, demo, remove account | Settings › Accounts & data | Play home banner |

**What changes in today's UI**

- **Instance detail:** the Mods and Worlds tabs become link rows (each thing gets one home), and Options becomes **Before you play**.
- **Play home:** the four stats (JIT, Memory, Resolution, FPS) become one Performance row, and Recent instances becomes **Jump back in** with worlds. JIT shows only as a banner when it's broken.
- **Settings › Game and Renderer:** these overlap Before you play (see open questions).
- **Crash screen** (`GameExitScreen.swift`): "Share log" opens the Share report sheet. The draft only presents the sheet over the real screen; the screen file is untouched.

## Patterns, each used more than once

| Pattern | Rule | Used by |
|---|---|---|
| **Owner decides the control** | A switch when Cofre owns on/off; a read-only status badge when the game does | Installed tabs, Before you play summary |
| **Game owns note** | A grass icon and a caption naming the in-game menu | Worlds, Packs, Shaders, Data, Before you play, Logs |
| **Undo toast** | Delete moves the item to Recently deleted (kept 7 days) and shows "Deleted X · Undo"; there's no alert | Instances, worlds, content |
| **Check before** | One line when it's fine ("Downloads 412 MB · needs 1.1 GB · 18.4 GB free"); a danger banner with two fixes when it isn't | Version picker, Open in Cofre, Copy world, fast copy, Duplicate |
| **Fit list** | Radio rows with a Fits / Older / Newer / No badge; rows that don't fit are dimmed | Open in Cofre (.jar, world), Copy world, versions, loaders |
| **Staged progress** | `StatusMark` rows, an XP bar, "Keeps going if you leave Cofre", and Cancel undoes everything | Import, fast copy, Downloads |
| **Sticky sheet footer** | The primary action stays visible at the 75% detent | Import, Open in Cofre, versions, Share report |
| **One banner at a time on Play** | Priority: signed out › demo › hot › Low Power › downloads › autosave tip | Play home |

## Variations: pick one each

| # | Choice | A | B | Recommend |
|---|---|---|---|---|
| V1 | Instance grouping | Sections: ★ Favorites, then each group | Chips filter one flat list | **A**: nothing is hidden, and favorites always come first |
| V2 | Resource pack and shader on/off | Switches that write `options.txt` / `iris.properties` | Read-only "In use · 1" badge plus "Turn on in game" | **B**: no double ownership |
| V3 | Preset control | Three tiles showing what each preset does | A segmented control | **A**: it matches the loader tiles and explains itself |
| V4 | Performance pack | Goes into a copy ("Vanilla · Fast"); undo by deleting the copy | Goes into this instance after a backup; undo with Remove pack | **A**: keeps vanilla bug reports and worlds clean (`plan/performance.md`) |

## Open questions

1. Should **Settings › Game and Renderer** become "Defaults for new instances" (recommended), or go away so that everything is per instance?
2. **World delete:** drop the confirm alert in favor of the undo toast plus 7-day Recently deleted? The README currently says world delete is always confirmed.
3. Shader crash recovery could be one exception to the rule: after a crash caused by a shader, the crash screen would offer "Turn shaders off" (Cofre writes `iris.properties`). OK?
4. Should **Heat-aware** be on by default? Should the temporary downgrade say what it changed ("Battery · for now")?
5. **Performance pack on 26.x:** hide the card until Sodium declares 26.x, or show it with "Not ready for 26.3 yet"?
6. Where should **notes and groups** be stored: `cofre.json` in the instance folder (it travels with a `.zip` export) or app defaults?
7. **Cellular data:** should downloads over 200 MB wait for Wi‑Fi by default?
8. **`.mcworld`:** is a clear "Bedrock world" error enough, or is a conversion link wanted (a third-party tool, which would need a link review)?

## What each screen needs from the backend

Everything is additive, with defaults and a `BackendCapabilities` flag, in the style of GAP-13. The UI hides a control until its flag is on.

| Screen | Facade addition (proposed) | Flag | Notes |
|---|---|---|---|
| Instances list | `InstanceSummary.favorite`, `.group`, `.notes`; `setMeta(instanceID:favorite:group:notes:)` | `.instanceMeta` | Cofre-owned metadata |
| Duplicate | `duplicate(instanceID:name:includeWorlds:includeOptions:) -> InstanceSummary` | `.duplicateOptions` | APFS clone (`clonefile`); size 0 until changed |
| Export | `export(instanceID:format:includeWorlds:) -> URL`; `exportEstimate(instanceID:format:) -> Int64` | existing `InstanceActions` | No accounts or logs inside |
| Delete with undo | `trash(instanceID:) -> TrashToken`, `restore(_:)`, `recentlyDeleted() -> [TrashItem]` | `.undoDelete` | Purge after 7 days; same calls for worlds and content |
| Import pack | `importPack(_ source: PackSource /* .file(URL) · .link(URL) */, instanceID:) -> AsyncThrowingStream<InstallProgress, Error>` + `ImportSummary { added, skipped: [(name, reason)], rolledBack }` | `.importPack` | Stages: read, Minecraft, loader, mods n/m, packs+config, verify. Cancel and failure roll back and keep the download cache |
| Open in Cofre | `inspect(_ url: URL) -> IncomingFile { kind: .pack/.mod/.world/.resourcePack/.shader/.dataPack/.bedrockWorld, gameVersion, loader, size }`; `targets(for:) -> [FitTarget]` | `.openIn` | Shell: `scene(_:openURLContexts:)` → `nav.open(url)`; `UTImportedTypeDeclarations` for `.mrpack`, `.jar`, `.mcworld` |
| Installed tabs | `installed(_ kind:)` already exists; add `InstalledItem.inUse: Int?` (pack order, active shader) and `.world: String?` (data packs) | — | Read `options.txt resourcePacks`, `iris.properties`, `saves/*/datapacks` |
| Worlds | `WorldSummary.sizeBytes`, `.iconPNG`, `.gameVersion`; `playWorld(instanceID:worldID:accountID:) -> AsyncThrowingStream<LaunchProgress, Error>` | `.quickPlay` (shared with W) | `--quickPlaySingleplayer` on 1.20+; plain launch before |
| Backups | `backups(instanceID:worldID:) -> [WorldBackup]`, `backUpWorld` (existing), `restore(_:)`, `autoBackup` pref + `keepBackups` | `.backUpWorld`, `.restoreWorld` | Restore backs up the current world first |
| Copy / import world | `copyWorld(_:to:) async throws`, `importWorld(_ url:, instanceID:)`; fit = world `DataVersion` vs instance | `.worldFiles` | Older-instance warning; `.mcworld` → `.bedrockWorld` error |
| Before you play | `GamePreferences.preset` (`quality/balanced/battery/custom`), `.heatAware`, `.guiScale`, `.language`; `presetValues(_:) -> [OptionValue]`; `gameOptions(instanceID:) -> [String: String]` (read back from `options.txt`) | `.presets` | "Changed in game" = file value ≠ preset value. Keep the user's preset apart from the thermal override |
| Heat / Low Power | `thermalUpdates() -> AsyncStream<ThermalState /* nominal…critical, lowPower */>` | `.heatAware` | Steps: FPS 120→90→60→30, resolution, simulation distance |
| Engine | `javaRuntimes()` (existing); `preferences.loaderVersion`; JVM-argument validation and rollback: `lastGoodJVMArgs` | — | Renderer label = `RendererOption.autoResolved(for: gameVersion)` ("Auto (Metal for 26.x)") |
| Performance pack | `performancePack(instanceID:) -> PackOffer? { mods: [(name, purpose)], sizeBytes, testedFor }`; `applyPerformancePack(instanceID:, mode: .copy/.inPlace) -> AsyncThrowingStream<InstallProgress, Error>` | `.performancePack` | Pinned versions with hashes; `nil` while untested for that version |
| Logs | `logLines(_:)` (existing); add `LogLine.source` (mod/tag) for the Mods filter | — | Filter client-side |
| Share report | `reportBundle(include: ReportParts) -> URL` + `redactionPreview() -> [String]` | `.shareReport` | Hides username, UUID, tokens, server addresses and the home path before zipping |
| Versions / loaders | `gameVersions(_:)` (existing) + `GameVersion.sizeBytes`, `.installed`, `.releaseDate`; `loaderVersions` → `[LoaderVersion { id, stable, recommended, installed }]` | — | |
| Preflight | `preflight(instanceID:version:loader:) -> Preflight { downloadBytes, needBytes, freeBytes, javaReady, network }` | `.preflight` | One call per sheet |
| Downloads | `downloads() -> AsyncStream<[DownloadItem /* title, done/total, state: running/waitingWiFi/paused/failed(reason) */]>`; `resume(id)`, `retry(id)`, `pauseAll()`; prefs `cellular`, `pauseInLowPower` | `.backgroundDownloads` | Background `URLSession`, resumable from where it stopped; verify by hash |
| Accounts | `Account.state: .ok/.expired/.demo`; `removeAccount(id:)` (existing, throws today) | `.removeAccount` | The demo state comes from the entitlement check |
| Autosave note | `willSuspend()` hook → flush saves (`/save-all` equivalent) | — | Copy only; the behavior is in `plan/performance.md` (lifecycle) |

## Preview states

| `-draft` | `-draftState` |
|---|---|
| `play` | `home` · `hot` · `lowPower` · `downloads` · `downloadsSheet` · `demo` · `expired` · `autosave` |
| `worlds` | `list` · `menu` · `backups` · `copy` · `undo` · `empty` |
| `instances` | `list` (V1 A) · `chips` (V1 B) · `menu` · `detail` · `duplicate` · `export` · `undo` · wide: `list`, `beforePlay` |
| `import` | `pick` · `progress` · `done` · `failed` |
| `files` | `mrpack` · `jar` · `world` · `bedrock` |
| `content` | `mods` · `packs` (V2 B) · `packsA` (V2 A) · `shaders` · `data` · `empty` |
| `beforePlay` | `main` (V3 A) · `presetB` (V3 B) · `custom` · `engine` · `pack` (V4 A) · `packB` (V4 B) · `packSheet` |
| `logs` | `live` · `errors` · `share` |
| `crash` | — (the real crash screen with Share report) |
| `versions` | `picker` · `snapshots` · `loader` · `noSpace` |
| `accounts` | `list` · `remove` |

For the iPad shots, add `-canvas 1180x820 -snapshot <name>` (the PNG is written to the app's Documents).
