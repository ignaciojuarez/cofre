# Server join research (verified 2026-10-28)

## Payloads and sync

| Option | Verified behavior/source | License | Verdict |
|---|---|---|---|
| packwiz | `pack.toml`, generated `index.toml`; metafiles can set `side`, `optional`, `preserve`; `packwiz-installer` fetches index and updates on launch. [docs](https://packwiz.infra.link/), [installer](https://github.com/packwiz/packwiz-installer) (accessed 2026-10-28) | MIT (packwiz and installer repos) | Adopt as an accepted payload; preserve semantics are useful for user configs. |
| Modrinth `.mrpack` | ZIP contains `modrinth.index.json`; files have SHA-1/SHA-512 hashes, `env` client/server, downloads and `allowed` host list. [format](https://support.modrinth.com/en/articles/8802351-modrinth-modpacks), [spec](https://github.com/modrinth/code/blob/master/packages/backend/src/models/v2.ts) (2024–2026) | Format permissive; Modrinth services/API terms apply to hosted assets | Primary interchange; Prism and Modrinth App import it. |
| CurseForge | `manifest.json` identifies Minecraft/loaders/files; third-party download is restricted when project `allowModDistribution` is false, requiring the CurseForge API/key or user-mediated download. [manifest docs](https://support.curseforge.com/en/support/solutions/articles/9000196985-custom-modpack-manifest), [API](https://docs.curseforge.com/) (accessed 2026-10-28) | Manifest schema proprietary/service terms; do not mirror restricted JARs | Card may point to pack, but must stop and request user CF key/download. |
| AutoModpack / ServerSync / Mod Director | AutoModpack advertises server-side pack sync and client download; ServerSync syncs configured files; Mod Director manages mod sets. Each is implementation-specific and not a common wire format. [AutoModpack](https://modrinth.com/mod/automodpack), [ServerSync](https://modrinth.com/mod/serversync), [Mod Director](https://modrinth.com/mod/mod-director) (accessed 2026-10-28) | Project-specific licenses; check each release | Treat as server implementations that can publish a card, not dependencies. |
| Vanilla resource packs | `require-resource-pack=true` and `resource-pack-sha1` in `server.properties`; 1.20.3 added multiple server resource packs and pack IDs in protocol. [Minecraft Wiki](https://minecraft.wiki/w/Server.properties), [1.20.3 notes](https://minecraft.wiki/w/Java_Edition_1.20.3) (accessed 2026-10-28) | Mojang terms for server content | Model server-pushed packs separately; card can declare required packs and detect duplicates. |

## Discovery and protocol facts

- Forge/NeoForge status ping can expose a `forgeData` object with loader/version and mod list; it is part of the status response and may be absent or size-limited by proxy/server implementations. It is not a complete pack manifest and is not compressed by the vanilla status protocol. [Forge `ForgeStatusPing`, 1.20.x source](https://github.com/MinecraftForge/MinecraftForge/search?q=forgeData), [NeoForge server list ping](https://docs.neoforged.net/docs/misc/networking/) (accessed 2026-10-28).
- Fabric does not standardize an equivalent mod-list field in vanilla status ping; absence is expected. Fabric API's server list ping extensions are optional. [Fabric API](https://github.com/FabricMC/fabric-api/tree/1.21/fabric-networking-api-v1) (accessed 2026-10-28).
- 1.21 introduced server links in the play protocol; they are server-provided links, not a pack discovery contract. Transfer packets can move a client to another host; cookies carry opaque server-scoped data and must not be treated as trust. [1.21 protocol](https://minecraft.wiki/w/Java_Edition_protocol/1.21), [Server Links](https://minecraft.wiki/w/Server_links) (accessed 2026-10-28).
- No broadly adopted `/.well-known/minecraft-server` manifest exists. This spec defines `/.well-known/cofre-server.json`; unknown fields are ignored.

## Launchers

- Modrinth App imports `.mrpack` and updates instances; CurseForge imports its own manifests; Prism/PolyMC/ATLauncher/FTB import `.mrpack` or pack-specific exports. They generally discover packs from a file/link or launcher catalog, not a Minecraft server tap. [Prism instance import](https://prismlauncher.org/wiki/instance-management/import/), [Modrinth App](https://support.modrinth.com/en/articles/8802351-modpacks) (accessed 2026-10-28).
- Therefore a thin signed server card is the interoperability layer; desktop users can download the referenced `.mrpack` into Prism.

## Decision

Adopt `.mrpack` as primary and packwiz as a compatible alternative. Build only discovery, signing, iOS overrides, and transactional install policy. A new pack format would duplicate mature hashing, side/optional/preserve, and desktop tooling, and would strand desktop friends.

## Fixture validation

Command: `cd launcher-plan/server-join && python3 validate_examples.py`

Output:
```
examples/ios-override.json: PASS
examples/forge-curseforge-restricted.json: PASS
examples/http-malicious.json: FAIL as expected
examples/update-diff.json: PASS
examples/missing-required-invalid.json: FAIL as expected
examples/fabric-modrinth.json: PASS
examples/path-malicious.json: FAIL as expected
```
The validator applies the required schema constraints and explicitly expects the three negative fixtures to reject.
