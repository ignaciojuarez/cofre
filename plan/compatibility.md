# Computed compatibility for mods, shaders and renderers

## Decision

Compatibility is a **graded prediction**, not a proof. Cofre should delete the hand-written `ModCompatibility.table` and combine three local, reproducible signals:

1. **Ship-derived renderer manifest (highest confidence):** inspect the exact Metallum agent shipped in the app and emit its versioned class sets and integration packages. This directly explains the known facts: Iris on 26.2, Sodium on 1.21.11 and 26.2, and no Iris/Sodium on 26.3.
2. **Install-time archive scan (medium confidence):** inspect mod and shader archives without executing them. Treat hard declarations (loader dependency, native library, incompatible environment) as actionable; treat code smells (OpenGL calls, mixin targets) as warnings.
3. **Opt-in crash evidence (confidence grows with corroboration):** aggregate redacted crash signatures into a signed, generated feed. Never make a static compatibility list the source of truth.

A cheap preflight then runs the game’s resolver and renderer capability probe before rendering. A failed preflight is stronger than a scan; a successful preflight is still not a guarantee for every world or code path.

## Ranked signals

| Signal | Computed how | Catches | Misses / false positives | iPhone cost | Effort |
|---|---|---|---|---:|---:|
| Metallum manifest | Build/start script lists `metallum_agent.jar` entries under `classes*`, integration/mixin packages, and hashes the jar | Exact shipped MC/version integrations; detects Air updates without editing Cofre | A class set may be present but incomplete; does not prove runtime correctness | Tiny once; cache by SHA-256 | Low |
| Fabric/Forge metadata | Parse `fabric.mod.json`, `quilt.mod.json`, `META-INF/mods.toml`, `neoforge.mods.toml`; resolve `depends`, `breaks`/`incompatible`, `environment`, loader and MC ranges | Missing required dependency, explicit incompatibility, server-only/client-only mismatch | Metadata is optional, stale, or semantically broad; a declared range is not renderer support | <100 ms for normal packs | Low |
| Native/runtime hazards | List `natives/*.{so,dll,dylib}`, inspect `System.loadLibrary`/`System.load`, JNA/JNI symbols, AWT/Swing/JavaFX package refs | iOS cannot load arbitrary desktop natives or desktop UI stacks | Bundled natives may be unused or have an Air-compatible path; string references can be dead code | One ZIP pass + class constant-pool scan | Low |
| OpenGL/Vulkan bytecode | Parse class constant pools and descriptors for `org/lwjgl/opengl/GL*`, `org/lwjgl/opengles`, `org/lwjgl/vulkan`; flag GL 4.3/compute/SSBO/image-load-store constants | Mods that directly require desktop GL/Vulkan features | Any GL reference can be harmless; reflection/ASM/generated names evade scan; capability emulation varies by renderer | Linear in `.class` bytes; usually milliseconds to tens of ms | Medium |
| Mixin targets | Read `mixins*.json`; flag targets in `net.minecraft.client.renderer`, Sodium/Iris renderer packages, or Metallum integration packages | Renderer hooks likely to conflict with a renderer integration | Target may be optional, remapped, or never applied; misses ASM transforms | JSON parse only | Low |
| Shader pack requirements | Read GLSL `#version`, `#extension`, `layout(std430)`, `buffer`, `imageLoad/Store`, compute stages; parse `shaders.properties` feature toggles | Packs needing compute, SSBO/image load-store, high GLSL versions | Preprocessor branches and vendor extensions make static inference incomplete; pack may select a simpler path | ZIP + text scan; normally <50 ms | Low |
| Runtime renderer probe | In a disposable launch, query actual GL/Vulkan capabilities and let Fabric/Forge resolve, then exit before world/render loop | Real loader/dependency errors and per-renderer limits | Some mods initialize only after a screen/world; Forge boot side effects; cannot safely run every pack | Seconds and JVM startup; do on Play, cache result | Medium |
| Crash evidence | Hash `(exception/top frame, mod package, MC, renderer)`; count distinct devices and successful retries | Unknown incompatibilities and regressions | Selection bias, duplicate reports, privacy and version drift | None on device beyond hashing | Medium |

**Interpretation:** only explicit metadata, a missing shipped integration, an unsupported native, or a failed preflight should block. Bytecode/mixin/shader findings should say “may fail” and offer Play anyway. Do not claim a low false-positive rate for OpenGL references: renderer libraries often mention GL while taking a compatible path.

## What Cofre can know from Air

`upstream/air/JavaApp/libs/others/metallum_agent.jar` is an executable capability description. At build time (preferred) or first launch, enumerate entries matching `classes12111_1_21_11`, `classes261`, `classes262`, `classes262iris`, `classes263`, `classes264`; record class counts, package prefixes, mixin JSON names and SHA-256. Map known prefixes to facts (`iris`, `sodium`) only when the matching integration package is present. Store the generated manifest beside build metadata, never hand-edit it.

The manifest should also record renderer identity and source revision. For ANGLE, MobileGlues and NG-GL4ES, derive a conservative feature set from the shipped configuration and queried limits (GLES version, extensions, max SSBO/image units, compute support). For Zink/Vulkan, record Vulkan API/version and extensions from the runtime probe. Search found Air’s `ModDependencyResolver` (dependency types `required`, `optional`, `incompatible`, `embedded`) but no general renderer blocklist that can serve as an authoritative feed. Keep using the resolver for dependency closure; add renderer checks in CofreKit.

## Static scan details

A ZIP reader can stream entries and cap total uncompressed bytes. For each class, parse the JVM constant-pool tags (no bytecode decompiler needed). Stronger evidence is a method invocation or field descriptor in a known renderer package; a UTF-8 string alone is weak. Flag `GL43`, compute shader dispatch, SSBO/image symbols, Vulkan package references, `System.load*`, JNA, and AWT/Swing/JavaFX. Report evidence paths and confidence, not a binary verdict.

Read Fabric metadata’s `depends`, `recommends`, `suggests`, `conflicts`/`breaks`, `environment`, and entrypoints; read Forge/NeoForge `mods.toml` dependency type and ordering. Resolve the complete graph against the selected MC and loader version. A missing required edge is a blocker; optional/embedded edges are informational. Treat server-only metadata as good news for a client renderer, not proof of compatibility.

For mixins, parse all declared configs and distinguish client/common/server. Renderer targets are a warning even when a target class exists: mappings and conditional application matter. A pack containing a desktop native is a blocker only when no iOS arm64/Air-compatible path is present; `.so`/`.dll` alone is enough to explain why it cannot load on iOS.

## Shader packs

Shader scans should produce requirements such as `glslMin`, `compute`, `ssbo`, `imageLoadStore`, and named extensions. Compare them with the selected renderer’s manifest and live limits. Iris is a special case: Metallum’s shipped Iris integration is only for MC 26.2, so an Iris shader on 26.3 gets a clear pre-launch warning even if its GLSL is modest. ANGLE/MobileGlues limits are device- and build-dependent; query them rather than maintaining a device table.

## Learned feed without hand editing

The auto-triage report already contains MC version, loader, enabled mods, shader packs, renderer, device and a redacted crash signature. The Mac routine can aggregate only opted-in reports into `compatibility.json` keyed by exact mod file hash/version, MC, loader, renderer and signature. Publish a generated, signed artifact (for example GitHub Pages or a release asset) from a bot branch; Cofre downloads it with HTTPS, verifies a pinned public key, applies a TTL, and keeps the last known good copy. The feed contains counts, first/last seen, confidence and a short sanitized reason—never logs, names, IPs, UUIDs or account data.

Keep raw reports private (mailbox/private issue repository), deduplicate by signature, require at least two distinct devices for a “likely” label, and expire evidence after a release/renderer change. A single report remains “reported once.” Users can disable upload; no app token is embedded. This is a generated observation feed, not a compatibility authority.

## Runtime self-test

On Play, after dependency resolution and before creating the game surface, launch a disposable JVM with the same classpath and selected renderer. Ask Fabric/Forge to resolve and initialize client entrypoints, then exit before a world is opened. Where Air permits it, create a GL context and query capabilities; otherwise use the first renderer initialization stage and capture the exception. Cache success/failure by `(instance content hash, loader, MC, renderer, device/build)`, invalidate on any content or engine change, and bound the test duration. Forge and mods with global side effects make a fully isolated dry run imperfect, so retain a Play-time check and crash recovery.

## CofreKit sketch

```swift
public struct RendererManifest: Codable, Sendable {
    public let renderer: String, engineRevision: String, artifactSHA256: String
    public let gameVersions: Set<String>, integrations: Set<String>
    public let features: Set<String>, limits: [String: Int]
}

public struct CompatibilityEvidence: Codable, Sendable {
    public enum Level: String, Codable { case info, warning, blocker, verified }
    public let code: String, level: Level, message: String, source: String
}

public struct CompatibilityReport: Codable, Sendable {
    public let itemID: String, version: String, gameVersion: String, loader: String
    public let renderer: RendererManifest, evidence: [CompatibilityEvidence]
    public var canPlay: Bool { !evidence.contains { $0.level == .blocker } }
}

public final class CompatibilityScanner {
    public func scan(contentURL: URL, context: LaunchContext,
                     manifest: RendererManifest) throws -> CompatibilityReport
}
```

`CompatibilityScanner` belongs in CofreKit and uses Foundation ZIP/file primitives already allowed by the architecture. A build tool emits `RendererManifest`; the app can regenerate and compare the hash as a safety check. Keep one object per domain; do not add a protocol with one implementation or another facade.

## UI behavior

- **Installed/Get card:** badges `Verified`, `Warning`, or `Not supported · Metal · 26.3`; show the evidence (“requires Iris integration; shipped only for 26.2”).
- **Get warning:** list hard dependency/native blockers before download; allow continuing for heuristic warnings.
- **Play-time check:** summarize all enabled mods and shaders, with `Turn off`, `Change renderer`, or `Play anyway`.
- **Crash screen:** show the matched signature and “Reported on N devices”; offer disable-last-change and share report.
- **Unknown:** say “No evidence yet,” never “compatible.”

## Open data and sources

No maintained, open, authoritative iOS-mod compatibility list exists. Existing data is useful input, not a substitute:

- [Fabric mod JSON specification](https://fabricmc.net/wiki/documentation:fabric_mod_json_spec) (CC BY-SA wiki): machine-readable dependencies, environment and entrypoints; community-updated, not renderer-tested.
- [Forge `mods.toml` specification](https://docs.minecraftforge.net/en/latest/gettingstarted/modfiles/) (documentation): dependency types and version ranges; versioned with Forge, no iOS signal.
- [Modrinth API](https://docs.modrinth.com/api/) (AGPL-3.0 docs / service terms): project/version loaders, game versions, dependencies and client/server side; API data changes continuously and does not describe this renderer.
- [CurseForge API docs](https://docs.curseforge.com/) (service/API terms): mod files, game versions, loaders and dependency relations; API key and rate limits; no iOS capability field.
- [Iris source and compatibility notes](https://github.com/IrisShaders/Iris) (LGPL-3.0): upstream MC-version support and known mod interactions; release-driven and not an iOS feed.
- [Sodium source](https://github.com/CaffeineMC/sodium) (LGPL-3.0): version-specific renderer integrations and issue history; no launcher capability API.
- [PojavLauncher wiki](https://pojavlauncherteam.github.io/) (GPL-3.0 project; wiki content varies): Android renderer/device advice, useful heuristics, not machine-readable or iOS-specific.
- [Amethyst, Zalith and Fold Craft Launcher repositories](https://github.com/AngelAuraMC/Amethyst), [ZalithLauncher](https://github.com/ZalithLauncher/ZalithLauncher), [FCL-Team/FoldCraftLauncher](https://github.com/FCL-Team/FoldCraftLauncher): open launchers with issue/wiki knowledge, but no stable signed compatibility feed. Their lists change with releases and are not safe to import as facts.
- [JVM class-file specification](https://docs.oracle.com/javase/specs/jvms/se21/html/jvms-4.html): makes constant-pool scanning deterministic and cheap.
- [OpenGL 4.3 compute/SSBO reference](https://registry.khronos.org/OpenGL-Refpages/gl4/): grounds feature flags; extension/version names alone still need a live capability query.
- [Iris shader documentation](https://github.com/IrisShaders/Iris/tree/1.21.1/docs): shader properties and feature expectations; pack authors can use conditional paths.

## Deletion and rollout

Delete the static `ModCompatibility.table` and its known-mod entries once `RendererManifest`, `CompatibilityScanner`, and the report UI are wired. Preserve the issue/badge types, but populate them from evidence. Roll out in this order: manifest generation → metadata/native scan → shader scan → Play-time resolver/probe → private crash aggregation → signed public observation feed.
