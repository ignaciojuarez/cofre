# Cofre Server Join Specification (v1.0.0)

*Specification for zero-friction server discovery, profile provisioning, and modpack synchronization in Cofre (iOS).*

---

## 1. Architecture & Flow Overview

```
[Server / Community]
  │ (Deep Link / QR / .well-known / DNS / Status Ping)
  ▼
[Cofre Discovery Layer]
  │ Resolves & fetches server-card.json
  ▼
[Security & Trust Verification]
  │ Ed25519 signature + Host allowlist + Sandbox checks
  ▼
[UI Sheet: Server Join Modal]
  │ User reviews requirements, optional mods, shaders, RAM
  ▼
[Atomic Sync Engine]
  │ Download CAS objects (URLSession) ──▶ Staged folder ──▶ Atomic profile swap
  ▼
[Launch & Connect]
  │ Checks JIT ──▶ Boots Java runtime ──▶ Connects to server address
```

---

## 2. Discovery Mechanisms (Ranked Hierarchy)

Cofre resolves server configuration using a strict priority cascade. When a player taps "Join" or enters a server address `mc.example.com:25565`:

```
Priority 1: Deep Link / QR Code (cofre://join?...)
   │ (Not found / Direct IP entry)
   ▼
Priority 2: HTTPS Well-Known (https://<host>/.well-known/minecraft-server-card.json)
   │ (404 / TLS Failure)
   ▼
Priority 3: DNS SRV / TXT Record (_minecraft-card._tcp.<host> or TXT "cofre-card=...")
   │ (No DNS records)
   ▼
Priority 4: Server List Ping Extension (JSON status ping with "cofre" payload)
   │ (Vanilla ping or unsupported)
   ▼
Priority 5: Forge/NeoForge forgeData Heuristic (Best-effort Modrinth resolution)
   │ (Truncated / Fabric / Inconclusive)
   ▼
Fallback: Prompt manual .mrpack / packwiz URL import
```

### Priority 1: Deep Link & QR Codes
* **URI Scheme**: `cofre://join`
* **Query Parameters**:
  * `server`: Primary Minecraft server hostname and optional port (e.g. `play.example.com:25565`).
  * `card`: Direct HTTPS URL to `server-card.json`.
  * `pin`: Optional expected Ed25519 public key fingerprint (hex or base64url) for pre-pinned trust.
* **Example**:
  `cofre://join?server=play.example.com&card=https%3A%2F%2Fexample.com%2Fserver-card.json&pin=vL10x4tF1n7tM1z9`
* **UX**: Scanned via camera or tapped in Safari/Discord. Immediately pops the Server Join Sheet in Cofre.

### Priority 2: HTTPS Well-Known Endpoint
* If user types or selects a server address `mc.example.com`:
  Cofre attempts an HTTPS GET to:
  `https://mc.example.com/.well-known/minecraft-server-card.json`
  *Fallback*: `https://example.com/.well-known/minecraft-server-card.json` (root domain if subdomain fails).
* **Constraints**:
  * Must be HTTPS with valid certificate.
  * Maximum redirect count: 3 (all must be HTTPS).
  * Max body size: 512 KB.

### Priority 3: DNS SRV & TXT Records
* Server owners unable to host web files on port 443 can configure DNS records on their domain:
  * **SRV Record**:
    `_minecraft-card._tcp.example.com. 3600 IN SRV 0 5 443 web.example.com.`
    (Points Cofre to fetch `https://web.example.com/.well-known/minecraft-server-card.json`).
  * **TXT Record**:
    `example.com. 3600 IN TXT "cofre-card=https://cdn.example.com/cards/smp.json"`

### Priority 4: Server List Ping Payload Extension
* In vanilla Minecraft 1.7+, clients query server MOTD via Status Request packet (`0x00`).
* Spigot/Paper/Fabric/Velocity server plugins can safely append custom fields to the JSON response:
  ```json
  {
    "version": { "name": "Fabric 1.21.1", "protocol": 767 },
    "players": { "max": 100, "online": 12 },
    "description": { "text": "Welcome to Cobblestone!" },
    "cofre": {
      "card_url": "https://cdn.example.com/server-card.json",
      "version": "1.0.0"
    }
  }
  ```
* Vanilla clients ignore unknown JSON keys. Cofre parses `response["cofre"]["card_url"]`.

### Priority 5 (Last Resort): Forge/NeoForge `forgeData` Scraping
* If only modern Forge/NeoForge ping is available:
  1. Inspect `forgeData.mods`.
  2. If `truncated == true`, halt and display warning: "Server mod list is too large to detect automatically. Contact server admin for modpack link."
  3. If not truncated, query Modrinth API v2 (`/v2/version_files`) using mod ID and version marker.
  4. Best-effort resolution only: display as "Detected server mods (unverified)" requiring explicit user approval.

---

## 3. Server Card Schema & Field Specifications

The server card is defined formally in `schema/server-card.schema.json`.

| Field | Type | Description |
|---|---|---|
| `schema_version` | String | Exactly `"1.0.0"`. Required. |
| `id` | String | Unique profile slug / reverse-DNS (e.g. `"play.cobblestone.gg"`). Used as internal instance ID. |
| `name` | String | Human-readable title (e.g. `"Cobblestone SMP"`). |
| `description` | String (Optional) | Server subtitle or description. |
| `icon` | String (URI) | HTTPS image link or base64 PNG data URI. |
| `addresses` | Array of Objects | Ordered connection targets with `host` and `port` (1–65535). |
| `game` | Object | `version` and `java_version` (`8`, `17`, `21`, or `25`). |
| `loader` | Object | `type` and `version`. |
| `pack` | Object | `type`, HTTPS `url`, 128-hex `sha512`, `version`, and optional `size_bytes`. |
| `content` | Object (Optional) | Sets of `optional_mods`, `resource_packs`, `shader_packs`. |
| `recommended_ram_mb` | Integer | Suggested default RAM (e.g. 4096). |
| `min_launcher_version` | String (Optional) | Gate older launcher releases. |
| `platform_overrides` | Object (Optional) | iOS tuning: `exclude_mods`, `replace_mods`, `recommended_ram_mb`, `renderer`, `fsr_enabled`. |
| `curseforge_fallbacks` | Array (Optional) | Instructions/links for mods restricted by CurseForge `allowModDistribution: false`. |
| `changelog` | Object (Optional) | Inline markdown `text` or `url`. |
| `update_policy` | String (Enum) | `"prompt"`, `"enforce"`, or `"silent_client_only"`. |
| `signing` | Object (Required) | Ed25519 `algorithm`, `key_id`, 32-byte base64url `public_key`, and 64-byte base64url `signature`. |

---

## 4. Synchronization & Update Engine

### 4.1 Content-Addressable Storage (CAS)
To avoid duplicating large mod jars across different server instances and updates, Cofre maintains a global, shared CAS cache in the app's sandboxed container:
`Container/Library/Caches/org.cofre.launcher/objects/<algo>/<prefix>/<hash>`
* **De-duplication**: When downloading files for any server pack, if the hash already exists in CAS, Cofre hard-links or clones (via APFS clonefile `copyfile(..., COPYFILE_CLONE)`) the object into the instance folder.
* **Storage Footprint**: Zero redundant disk usage when multiple servers share common mods (e.g. Sodium, Iris, Fabric API).

### 4.2 Staged, Atomic Updates with Rollback
Upgrades are never performed directly on a live profile directory.

1. **Manifest Comparison**:
   * Cofre compares the installed `server-card.state.json` against the newly fetched `server-card.json`.
   * Computes a diff:
     $$\Delta = \{\text{Files to Add}, \text{Files to Remove}, \text{Files to Update}, \text{Loader Change}\}$$
2. **Staging Directory**:
   * A temporary directory is created: `instances/<id>/.staging_<new_version>/`.
   * New and updated files are downloaded or cloned from CAS into `.staging/`.
   * Integrity verification: All hashes (SHA-512 for mods, SHA-1 for resource packs) are validated.
3. **Atomic Commit**:
   * If validation succeeds, Cofre executes an atomic swap:
     - Existing `instances/<id>/mods` is renamed to `instances/<id>/mods.bak`.
     - Staged mods directory is moved into place.
     - `mods.bak` is purged once verification passes.
4. **Automatic Rollback**:
   * If any network error, hash mismatch, or app crash occurs during staging, `.staging/` is wiped and the current working profile remains 100% untouched.

### 4.3 Preservation Policy
The sync engine strictly preserves user-owned files across all updates:
* **Preserved Configurations**:
  * `options.txt` (controls, graphics, audio, keybinds).
  * `servers.dat` (in-game multiplayer bookmarks).
  * `config/` files: Server pack configs are merged; user-modified values are not overwritten unless explicitly flagged with `force_overwrite = true` in the pack metadata.
* **Preserved Content**:
  * User-added optional mods: Cofre tracks installed files in a local `.cofre-manifest.json`. Files added by the user manually or from the "Browse Mods" screen that do not collide with server-required mod IDs are never deleted.
  * Local worlds (`saves/`), screenshots (`screenshots/`), resource packs not managed by the card.

### 4.4 iOS Background URLSession & Network Constraints
* **Background Tasks**: All downloads use `URLSessionConfiguration.background(withIdentifier:)`. If the user switches apps or locks the screen, iOS continues downloading in the background daemon (`nsurlsessiond`).
* **Cellular Safeguard**: If current network is WWAN (cellular) and the required download exceeds 50 MB, Cofre pauses and displays a prompt: "Download 140 MB over cellular?".
* **Storage Assertion**: Before starting download, Cofre checks free space via `URLResourceValues.volumeAvailableCapacityForImportantUsageKey`. Requires $\ge 1.5 \times \text{total download size}$.

---

## 5. Security Architecture

### 5.1 Cryptographic Signatures (Ed25519) & TOFU
* Every server card MUST be signed by the server administrator using Ed25519; unsigned cards are rejected.
* **Canonical Serialization**: The JSON document is serialized using RFC 8785 (JSON Canonicalization Scheme - JCS) omitting the `signing.signature` field.
* **Trust On First Use (TOFU)**:
  * On first join, Cofre shows the HTTPS origin and key fingerprint, then records the server's Ed25519 `public_key` and `key_id` only after explicit user confirmation. The trust record is bound to that exact HTTPS origin; a key from another origin cannot bootstrap trust.
  * Subsequent updates must be signed by the pinned key.
  * If the key changes without a valid `previous_key_signature`, Cofre blocks the update and displays a high-severity security alert: *"Server signing key has changed! Potential man-in-the-middle attack."*
* **Key Rotation**:
  * Legitimate key rotation is supported by including `previous_key_signature`: the new key pair is signed by the old key pair.

### 5.2 Host Allowlist & Consent Boundaries
To prevent server cards from tricking clients into downloading arbitrary binaries from untrusted origins:
* **Allowed hosts** are explicit exact DNS names in the card's `security.allowed_hosts`; wildcard entries are rejected. The HTTPS origin host and every download host (including the pack URL) MUST appear in this list. No implicit CDN or repository allowlist exists.
* **Third-Party Consent**:
  * Any URL outside the explicit allowlist is rejected before download. The UI displays the origin, key fingerprint, host, and hash during first-use consent.

### 5.3 Zip-Slip & Path Traversal Prevention
* Manifest filenames and `.mrpack` entries are subjected to strict path sanitation:
  1. Reject paths containing `..` or leading `/` or `\`.
  2. Target paths must resolve strictly within the instance sandbox root:
     ```swift
     let destination = instanceURL.appendingPathComponent(entryPath).standardizedFileURL
     guard destination.path.hasPrefix(instanceURL.path) else {
         throw SecurityError.pathTraversalAttempt(entryPath)
     }
     ```
  3. No symlinks are created or followed during archive extraction.

### 5.4 Size Caps & Quotas
* Server Card JSON max size: 512 KB.
* Total Modpack download max size: 2 GB (customizable in advanced settings).
* Single mod jar max size: 250 MB.
* Maximum file count in pack: 2,500 files.

### 5.5 Zero Shell Scripts
* No `.sh`, `.bat`, `.cmd`, `.exe`, or custom shell scripts are ever executed from a pack. Modpacks are purely declarative collections of JARs, assets, and configs.

---

## 6. iOS Platform Constraints & Native Mod Compatibility

### 6.1 Desktop Native Libraries (x86_64 vs ARM64)
* Many desktop mods package native libraries (`.dll`, `.so`, `.dylib`) bundled inside their JAR.
* **The Problem**: Desktop mods typically bundle x86_64 Mach-O or Linux ELF binaries. When executed on an iOS ARM64 device, `System.loadLibrary()` fails with `UnsatisfiedLinkError` or crashes the JVM.
* Examples: Simple Voice Chat (Opus natives), Sound Physics Remastered, Plasmo Voice, Methane.
* **Compatibility Solution**:
  * Cofre maintains a bundled and cloud-updated `ios-mod-compatibility.json` catalog.
  * When a server card is processed:
    1. If a mod ID is in `platform_overrides.ios.exclude_mods`, it is stripped from client installation.
    2. If a replacement exists in `platform_overrides.ios.replace_mods`, Cofre installs the replacement.
    3. If an unverified mod is detected to contain `.dll` or non-ARM64 `.dylib` natives, Cofre disables it and informs the user.

### 6.2 Memory & Jetsam Limits
* iOS kills apps exceeding memory limits aggressively (Jetsam).
* Default memory guidance:
  * 6 GB iOS devices (iPhone 13, 14, 15): Allocate maximum 3,072 MB RAM to Java.
  * 8 GB iOS devices (iPhone 15 Pro, 16 Pro, iPad Pro): Allocate maximum 4,096 MB RAM to Java.
* If a server card requests `recommended_ram_mb: 6144` on a 6 GB device, Cofre clamps the allocation to 3,072 MB and surfaces a performance advisory badge.

### 6.3 JIT Debugger Requirement
* Java Edition on iOS requires JIT (Just-In-Time) compilation.
* Before launching into the server, Cofre checks `JITService.isJITEnabled`. If unmounted, it guides the user through the local loopback VPN / JIT activation process before initiating game launch.

---

## 7. Server-Owner Tooling

To ensure seamless adoption by server owners:
* **`cofre-card` CLI** (Node.js & Python open-source CLI):
  ```bash
  # Generate card from an existing Modrinth modpack
  cofre-card from-mrpack ./myserver.mrpack --host play.myserver.net --sign ./private.key

  # Generate card from a packwiz pack.toml
  cofre-card from-packwiz ./pack.toml --host play.myserver.net --sign ./private.key

  # Generate card by scanning server mods directory
  cofre-card from-server-folder /path/to/server/ --host play.myserver.net
  ```
* **Hosting Options**:
  * GitHub Pages / Cloudflare Pages (Free, static HTTPS).
  * Direct server root (`nginx` or `caddy` reverse proxying port 443).
  * Cloudflare R2 / AWS S3 public bucket.

## 3.1 Detached card envelope (v1)
The served document is a detached envelope. `payload` is base64url of the exact card JSON bytes; `signature` is Ed25519 over those decoded bytes. Cofre verifies the envelope first and decodes the verified payload second. The envelope format is `cofre-card-envelope/1`. `previous_key_signature`, when present, is the old key's signature over the new raw public key and is required for key rotation.
