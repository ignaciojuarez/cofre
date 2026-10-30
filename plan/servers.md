# Servers

> Status: UI and facade done against `MockBackend` (agent W). Real engine: agent V in `app/Glue`
> (`CofreServerEngine.swift`: servers.dat codec, server list ping, launch args). Screenshots:
> `/tmp/cofre-shots/agentW-servers-sheet.png`. PreviewHost: `-screen servers -servers <state>`.

## Why
The old Worlds pane listed Modrinth's top 50 public servers under "Servers", as if they were the player's. The
player's real servers (servers.dat) showed nowhere.

## Rules
| Rule | So |
|---|---|
| **The game's files are the only truth** | servers.dat (per instance) is the saved list. Cofre keeps no copy and reads it again on every show. Changes made in game show up in Cofre, and the other way round |
| **Cofre does what's awkward on a phone** | Join straight in (Quick Play), version check before launch, server-card mods (GAP-14), add from outside the game, copy to another instance |
| **No duplicated game UI** | No edit sheet, rename, reorder or resource-pack setting. The game owns those |
| **Recommendations stay apart** | "Recommended" (Modrinth) sits below My servers, is labeled, and is never written anywhere unless the player taps Add |

## Layout (picked: A)
| | A · Worlds \| Servers switch ⭐ | B · One stacked list |
|---|---|---|
| Compact | One picker: Play · Worlds · Servers | Play · Worlds, then sections Worlds → My servers → Recommended |
| Regular | Play beside a 380 pt pane with a Worlds · Servers picker | Same pane, longer scroll |
| Why | Mirrors the game's Singleplayer / Multiplayer. Each list grows without burying the other | Everything at once, but many worlds push servers off screen |

Servers pane, top to bottom:
1. Header "Servers", with **Paste** (adds the copied address to this instance).
2. **My servers · <instance>**: servers.dat in the game's order.
3. **Recommended**: "Popular on Modrinth for <loader version>. Cofre doesn't run or check these servers." 6 rows,
   then "Show N more". Anything already saved is hidden.

## Server row
`favicon · name · MOTD (§ codes stripped) · [fit badge] [Modded] players · ping bars · Join`

| Part | Source | Shows |
|---|---|---|
| Favicon | servers.dat `icon` / ping favicon | Else a block picked from the address |
| Fit badge | `gameVersions` vs. the instance | Green "1.21.1" fits · amber "Needs 1.20.4" · nothing when unknown |
| Modded | `hasServerCard` + `.serverJoin` | Join opens the GAP-14 card sheet |
| Ping bars | `pingServer` | Minecraft's 5 steps (150/300/600/1000 ms). Cycling while pinging, ✕ + "Can't reach server" when offline |
| Menu (My servers) | — | Join · Copy to › instance · Copy address · Delete (confirmed) |
| Recommended | — | **Add** (writes servers.dat; the row moves up to My servers) · **Join** (plays without saving) |

## Flows
**Join**
```
Join ─┬─ has server card ────────→ GAP-14 sheet (installs mods, then Launch & Join)
      ├─ fits / unknown ─────────→ launch takeover → joinServer (Quick Play) → in the server
      └─ needs another version ──→ "Needs 1.20.4" sheet
                                    ├─ Join with <instance on 1.20.4>   (a saved server is copied there first)
                                    ├─ New 1.20.4 instance → P04 pre-filled (Vanilla, server name)
                                    │                       → server saved in it → Servers pane, one tap from Join
                                    └─ Try <current> anyway   (ViaVersion servers often let it in)
```
The launch screen names the server: `Survival+ · Fabric 1.21.1 → play.emberfall.net`, last stage "Join <name>".

**Add from outside the game** (all write servers.dat, named after the address; rename in game)
| Path | State |
|---|---|
| Recommended → Add | Built |
| Paste (header) | Built. Reads the clipboard on tap only; invalid text shows "That isn't a server address." |
| `cofre://join?server=…&card=…` | Built (GAP-14) for servers with a card. Plain servers: open question 1 |
| Share sheet | Later: needs a share extension |

**Sync**: servers.dat is read when the pane shows, when the game closes (`showingLaunch` → false), when Cofre comes
back to the foreground, and on pull to refresh. Pings are cached per address for the session.

## States
| State | Shows |
|---|---|
| Loading | "Loading servers…" row; Recommended loads on its own |
| Empty | "No saved servers yet" · "Add one from Recommended, in game, or with a cofre:// link." Recommended still below |
| Pinging | Cycling bars, "Pinging…" |
| One server down | ✕ bars, red "Can't reach server". Join still works |
| All down (offline) | Banner "Can't reach any server. Check your connection." + Retry. Recommended: "Can't reach Modrinth right now." + Retry |
| Nothing recommended | "Nothing new for this version right now." |
| No capability | Each control hides itself (below). With nothing on, the pane is a read-only list |

## Settings
None. Names, order and resource packs belong to the game. Possible later: "Show Recommended" (open question 3).

## API (the boundary for V)
Everything has a default in CofreUI, so the adapter compiles before each piece lands. Turn a flag on only once it works.

| Member | Protocol | V's engine | Flag |
|---|---|---|---|
| `servers(instanceID:) -> [ServerSummary]` | `LibraryService` (exists) | `ServersDatCodec.decode`. Skip `hidden` entries. Fill `instanceID`, `iconPNG`, `hasServerCard` | — |
| `addServer(instanceID:name:address:)` | `OptionalActions` (exists) | Append `{name, ip}` (no `acceptTextures` = Prompt) | `.addServer` |
| `copyServer(_:to:) -> ServerSummary` | `ServerService` | Append the whole `CofreServerRecord` (icon, `acceptTextures`, unknown tags) | `.serverFiles` |
| `removeServer(_:)` | `ServerService` | Remove the record `server.id` names | `.serverFiles` |
| `pingServer(address:) -> ServerPing` | `ServerService` | `MinecraftServerPinger.ping` → `motd`, `online`, `max`, `versionName`, `protocolVersion`, `iconPNG`, `latencyMS`; `gameVersions` from a protocol → versions table | `.pingServers` |
| `joinServer(instanceID:address:accountID:)` | `ServerService` | `launch` + `MinecraftLaunchArguments.server` (`--quickPlayMultiplayer` ≥ 1.20, `--server/--port` before) | `.quickPlay` |
| `discoverServers(instanceID:) -> [ServerSummary]` | `ServerService` | Air `searchServers` source 1 (Modrinth). Filter to the instance's version (and loader when the listing names one), most popular first, ~20 rows. Fill `motd`, players, `gameVersions` | `.discoverServers` |

`ServerSummary` additions (all defaulted): `instanceID`, `iconPNG`, `motd`, `playersOnline`, `playersMax`,
`gameVersions` (newest first), `protocolVersion`; helpers `fit(_:)` and `updated(with: ServerPing)`.
Removed from the first draft: `updateServer`, `moveServer`, `source`, `acceptTextures` (the game owns them).

### Rules for the engine
- `id` only needs to be unique in one list (e.g. `"\(index):\(ip)"`; `ip` alone repeats). The UI reloads after every write.
- Write servers.dat atomically (temp file + rename) and keep unknown tags and order.
- **Never write while that instance's game runs**: Minecraft rewrites servers.dat when it leaves the Multiplayer
  screen and would drop the change. Throw a short error ("Close the game first") instead.
- Ping: 5 s timeout, at most ~4 at a time. Resolve `_minecraft._tcp` SRV for hosts without a port (NWConnection
  doesn't). Any handshake protocol works for status.
- LAN addresses and `[IPv6]:port` are valid. Duplicate addresses: the UI never adds one twice.

## Edge cases
| Case | Behavior |
|---|---|
| Version unknown (no ping yet, old server) | No badge; Join goes straight in |
| Server accepts many versions (ViaVersion) | Fits when the list contains the instance's version |
| Ping says one version, server accepts more | "Needs X" sheet offers "Try anyway" |
| Modded server without a card | Treated as vanilla. Modrinth may list its modpack: later |
| Same server in two instances | Two separate entries, like Minecraft. Delete removes one |
| Join from another instance on a Recommended row | Plays, doesn't save |
| Game running | Writes refused by the engine; the list still reads |
| servers.dat missing or corrupt | Empty list; never overwrite a file we couldn't parse |

## Screens, mocks, tests
| What | Where |
|---|---|
| Pane, rows, sheet | `Screens/Servers/ServersPane.swift`, `ServerRows.swift`, `ServerSheets.swift` |
| Layout B mock | `Screens/Servers/ServersVariationsMock.swift` (`-screen serversMock`) |
| Store logic | `Model/CofreStore+Servers.swift` (route, join, add/copy/delete, pings, Recommended) |
| Mock data | `Mocks/MockServers.swift` |
| Tests | `Tests/CofreUITests/ServersTests.swift` (13) |
| PreviewHost | `-screen servers -servers mine\|loading\|pinging\|offline\|empty\|version\|newInstance\|joining` |

## Open questions
1. Plain `cofre://join?server=…` links (no card) still open the GAP-14 sheet. Offer "Add to <instance>" when no card
   is found? Needs a "no card" result from `CofreServerJoin`.
2. Same principle for worlds: should a world's Play launch straight into it (`--quickPlaySingleplayer`)?
3. A "Show Recommended" switch (families, privacy), or always on?
4. Paste adds to the instance on screen. Ask which instance instead?
