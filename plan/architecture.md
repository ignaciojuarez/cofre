# Cofre architecture: the target

Cofre owns the launcher. Air is the engine: JVM, renderers, game surface, input transport, Microsoft sign-in,
JIT hooks and loader installers. Everything else is small Cofre-owned Swift that reads and writes the game's own
files.

## Rules

1. **The game's files are the truth.** `launcher_profiles.json`, `saves/`, `servers.dat`, `options.txt`, `mods/`,
   `resourcepacks/`, `shaderpacks/` and `datapacks/` are read and written directly. Cofre never keeps a parallel
   copy. Cofre's own extras go in one `cofre.json` per instance (notes, group, favorite, icon), so they travel with
   an export.
2. **One owner per concern.** If the game has a setting, Cofre doesn't duplicate it ("Change this in game").
   If Cofre and Air both do something, one of them stops.
3. **Objects, not layers.** One small `final class` (or `actor` for files and network) per domain, holding its
   own state and behavior. No protocol with one implementation. No adapter that only forwards calls. No
   "service" that wraps a store that wraps a file.
4. **Own Air pieces when owning is simpler.** Replace an Air path when Cofre's version is smaller and clearer,
   and delete the bridge method it used. Keep Air only for the engine list above.
5. **Ponytail.** Prefer the standard library and the platform (URLSession background downloads,
   FileManager/APFS clones, Compression/AppleArchive, Network.framework). One line over fifty. YAGNI.

## Modules

```
app/UI (one Swift package)
├─ CofreKit   Foundation only, no UIKit, no Air. Tested on the Mac with real fixture folders.
│   Instances  Instance, InstanceStore       launcher_profiles.json + cofre.json; create, duplicate (APFS clone), delete with undo, export/import zip
│   Worlds     World, WorldStore             saves/ + level.dat (NBT); backup/restore, export/import zip, copy, recently deleted
│   Servers    ServerList, ServerPinger      servers.dat (NBT), status ping, quick-play args          ← done (Servers.swift)
│   Content    ContentItem, ContentStore     mods/resourcepacks/shaderpacks/datapacks: list, on/off, delete, update
│   Modrinth   Modrinth                      search, versions, files: Cofre's own client (replaces Air's ModrinthAPI)
│   Modpacks   ModpackImport                 .mrpack and zip import with staged rollback
│   Downloads  DownloadQueue                 background URLSession, resume, SHA-1 verify, disk preflight
│   Accounts   AccountStore                  Air's accounts/*.json list, remove, expired and demo state (sign-in itself is the Engine)
│   Logs       LogStore, ReportBundle        latestlog/latest.log tail, search, redacted share bundle
│   Options    GameOptions                   typed options.txt read/write (the game owns it; Cofre writes only on an explicit action)
│   NBT        NBT                           shared reader/writer for servers.dat and level.dat
├─ CofreUI    SwiftUI screens + one @Observable model per feature (InstancesModel, WorldsModel…), each using CofreKit directly
└─ Engine     (in app/Glue) the only code that touches Air
     protocol GameEngine { launch, signIn, refresh, testJIT, input, installLoader }   2 implementations: Air, and Preview
```

- **Previews and tests** run on fixture folders (a sample `Documents/` in test resources) through the real
  CofreKit types, plus `PreviewEngine`. That replaces the 1,200-line `MockBackend` and its drift.
- **The ObjC bridge** (`CofreAirBridging`, 38 methods today) shrinks to the engine. Profiles, worlds, mods,
  servers, accounts and preferences leave it as CofreKit owns them.

## What goes away

| Today | After |
|---|---|
| ~18 facade protocols composed into `CofreBackend`, one real implementation | Concrete CofreKit types plus one `GameEngine` protocol |
| `CofreBackendAdapter` (+Instances, +Mods), ~1,500 lines of forwarding and string dictionaries | Deleted, piece by piece, per domain |
| `MockBackend` + `MockServers` (~1,300 lines) | Fixture folders + `PreviewEngine` |
| Air's ModService, ServerService, WorldService, ModrinthAPI and ModpackImportService calls | CofreKit Content, Servers, Worlds, Modrinth, Modpacks |
| String launch events, KVC polls | Typed launch state machine (done in `ff659d2`) |
| Large `CofreStore` | Small per-feature models |

## Migration (per domain, each one a single PR-sized step)

1. Add the CofreKit type with tests on fixtures.
2. Point the feature's screens at it through a small feature model.
3. Delete the facade protocol methods, adapter code, mock data and bridge methods it replaced.
4. Build for the device, verify the log lines, commit.

Order: Instances → Accounts → Logs → Worlds → Content (+ Modrinth) → Downloads → Modpacks → Engine seam.
