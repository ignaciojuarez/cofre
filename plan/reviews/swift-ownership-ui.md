# Swift ownership / UI layering audit

**Verdict:** yes, the Swift layer is over-layered. The screens are reasonable; the expensive part is the duplicate domain graph between `CofreKit`, `CofreUI/Facade`, `CofreStore`, `MockBackend`, and the Air adapter. Roadmap item 9 is the right direction.

Current baseline: `cd app/UI && swift test` passes **128 tests** on this Mac. Several pure rules are wrapped in `#if canImport(UIKit)`, so the Mac run does not compile or test the resolver, compatibility, server, and most facade tests.

## Top five recommendations

| Rank | Recommendation | Est. lines removed |
|---|---|---:|
| 1 | Make CofreKit the one domain model set. Remove `InstanceSummary`, `WorldSummary`, `InstalledItem`, `Account`, `ServerSummary`, and the mapping code. | 220–350 |
| 2 | Replace the 18-protocol `CofreBackend` composition with one small concrete Air engine handle (a value of closures for Air-only operations). | 300–450 |
| 3 | Turn `CofreStore` into a root of small feature models and remove its optional `InstanceStore`/backend split. | 180–280 |
| 4 | Replace `MockBackend`/`MockServers`/`MockServerJoin` with fixture folders plus focused CofreKit fakes. | 500–800 |
| 5 | Move pure resolver, compatibility, server-card, and typed-preference logic out of UIKit-gated CofreUI code. | 120–220 |

Estimates overlap where a deleted model also deletes a protocol or mock. Combined realistic deletion is **about 1,100–1,700 lines**.

## Findings

| Area | Problem (file:line evidence) | Proposal | Lines removed (est.) | Effort | Risk | Confidence |
|---|---|---|---:|:---:|---|---|
| Duplicate domain models | `CofreUI/Facade/Models.swift:95-141` defines `InstanceSummary` beside `CofreKit/Instances.swift:4-47` `Instance`; `WorldSummary` (`Models.swift:143-159`) duplicates `CofreKit/Worlds.swift:7-17`; `InstalledItem` (`Models.swift:252-292`) duplicates `ContentStore.Item` (`Content.swift:4-13`); `Account` (`Models.swift:295-307`) duplicates `CofreAccount` (`Accounts.swift:3-15`). The Air adapter translates the same values again (`CofreBackendAdapter.swift:135-152, 201-223`; `CofreBackendAdapter+Mods.swift:353-365`; `CofreBackendAdapter+Servers.swift:19-35`). | Make CofreKit values the API consumed by screens. Add only true presentation extensions (glyph, tone, formatted labels). Keep transient ping/progress state in feature models, not a second saved model. Delete the summary mapper and adapter translations domain by domain. | 220–350 | M | Medium: `Instance` needs the current row metadata or a small optional stats field; preserve profile paths and IDs exactly. | **High** |
| Content kind split | `CofreKit/Content.swift:5-8` has `ContentStore.Kind`, while `ProjectFilters.swift:6-8` has a different `ContentKind`; `CofreBackendAdapter+Mods.swift:482-489` manually maps them and treats `.modpacks` as a special nil case. | Use one `ContentKind` with `folderName`/`isInstallable` properties. `ContentStore` rejects `.modpacks` instead of requiring a second enum and switch. | 30–60 | S | Low; existing raw values and folder spelling stay compatible. | **High** |
| Protocol stack with one real conformer | `Services.swift:103-108` composes roughly 18 protocols into `CofreBackend`; production has one conformer (`CofreBackendAdapter.swift:25-29`) and previews have one all-in-one conformer (`MockBackend.swift:4-5`). `Requirements.swift:168-220, 287-319` adds forwarding defaults and “unsupported” throws to keep that shape compiling. | Keep CofreKit concrete. Put Air-only actions behind one concrete `EngineHandle` value (closures for launch, sign-in, JIT, input, loader install, and setup). A missing closure is an unavailable feature; no existential composition or default method forest. | 300–450 | M | Medium: UI construction must remain independent of Glue; test the handle with focused preview closures. | **High** |
| `CofreStore` god object and two sources of truth | The 895-line `CofreStore.swift:14-113` stores setup, library, mods, launch, logs, system, servers, and server-join state. Startup fans out to every concern (`:158-168`); instance methods branch between `instanceStore` and backend (`:170-201, 380-505`). `CofreServices` carries both `backend` and optional `instances` (`Services.swift:110-124`). | Keep a small root `AppModel`; give each feature one `@MainActor` model: `InstancesModel`, `ModsModel`, `ServersModel`, `LaunchModel`, `SettingsModel`, `SetupModel`. Inject concrete CofreKit stores directly. Air is used only by `LaunchModel`/`SetupModel` through `EngineHandle`. | 180–280 | M | Medium: state ownership and navigation bindings must move together; do one feature per PR. | **High** |
| Dead world path and dead forwarding | `CofreStore.worlds` is declared but never used (`CofreStore.swift:34`); `WorldsPane` and `JumpBackIn` use `WorldsModel` and `World` directly (`PlayScreen.swift:165-223`). `WorldSummary` and `MockBackend.worlds` (`MockBackend.swift:129-146`) therefore serve no screen or protocol. `CofreStore.install` is an alias kept “for callers” (`CofreStore.swift:611-612`); `ProjectCatalog.allVersions` and `installPlan` are defaults that forward (`Requirements.swift:168-196`), as are `ServerService` defaults (`Services.swift:79-100`). | Delete the dead `worlds` state, `WorldSummary`, mock world API, and compatibility aliases as each caller is moved. Prefer one real method with a real implementation; capability checks belong at the feature boundary. | 70–130 | S | Low; search all callers before each deletion. | **High** |
| Stringly typed values | `GamePreferences` stores renderer, graphics API, Java, layouts, and multidraw as strings (`Models.swift:309-327`). `ProjectVersion.channel` is a `String` (`Models.swift:445-465`), `ModCandidate` stores loader/channel strings (`ModResolver.swift:75-100`), and `RendererPolicy` accepts/returns renderer strings (`CofreKit/Compatibility.swift:16-55`). `CofreScenario` validates loader with a string list (`Scenario.swift:7-45`). User-default keys are scattered strings (`CofreStore.swift:115-119`, `RejoinIntent.swift:15-29`). | Use Codable raw-value enums: `RendererID`, `GraphicsAPI`, `JavaRuntimeID`, `VersionChannel`, `PreferenceKey`, and a shared `Loader`/`ContentKind`. Keep string conversion only at Air/file/JSON boundaries. Preserve unknown renderer values with `custom(String)` so old profiles load. | 80–140 | M | Medium: migration must decode old strings and retain unknown future values. | **High** |
| Pure logic lives in the UI target | `ModResolver.swift:1-248`, `ModCompatibility.swift:1-51`, `Models.swift:1`, `ServerJoin.swift:1`, and most `Requirements.swift` are UIKit-gated. The current Mac test run therefore cannot exercise those rules. `CofreKit/Servers.swift:1-2` also mixes file/domain code with `Network`. | Move resolver, compatibility, deep-link/card state, and server-card parsing/trust/planning into CofreKit (or a CofreKit target). Keep SwiftUI views and view-only state in CofreUI. Isolate the Network pinger in a small engine-support file if “Foundation-only” must be literal. | 80–140 | M | Low to medium; public wire formats and security tests must stay unchanged. | **High** |
| Mock duplication | `MockBackend.swift` is 676 lines of mutable state, capability flags, delays, launch simulation, catalog data, and server behavior (`:5-28, 101-674`). `MockServers.swift` adds 103 lines and `MockServerJoin.swift` adds 287. This duplicates file behavior instead of exercising CofreKit fixtures. | Use fixture `Documents/` folders for instances, worlds, content, accounts, logs, and servers. Add small fakes only for Air operations (launch stream, JIT, sign-in). Keep scenario data as static builders, not a production-shaped backend. | 500–800 | M | Medium: previews need deterministic data and a few async controls; keep the existing visual snapshots while migrating. | **High** |
| Separate ServerJoin package and duplicate loader enum | `app/ServerJoin/Package.swift:1-9` is a second package with its own tools version. `CofreServerJoin/Card.swift:24-27` defines `CardLoader`, duplicating `Instance.Loader` (`CofreKit/Instances.swift:5-19`). UI state is separately duplicated in `CofreUI/Facade/ServerJoin.swift:18-414`, while Glue maps package values into it (`ServerJoinAdapter.swift:94-110`). | Merge the package into `app/UI/Package.swift` as a `CofreServerJoin` target first (preserves test isolation), then move its Foundation-only card/trust/planner types into CofreKit once the API is stable. Replace `CardLoader` with `Instance.Loader` at the JSON boundary. Keep security tests unchanged. | 40–90 | S → M | Medium: package merge is mechanical; moving the state machine is not. | **High** |
| `@MainActor` / `Sendable` friction | `CofreStore` is `@Observable @MainActor` (`CofreStore.swift:7-8`), production Glue is also `@MainActor` (`CofreBackendAdapter.swift:25-27`), while mutable stores are marked `@unchecked Sendable` (`CofreKit/Instances.swift:117`, `Content.swift:4`, `Worlds.swift:28`, `Logs.swift:14`) and the mutable preview backend is `@unchecked Sendable` (`MockBackend.swift:5`). `WorldsModel` keeps a main-actor model around an optional store (`WorldsModel.swift:6-13`). | Pick one owner per mutable domain: actor for file/network stores, or main-actor-only for UI-owned stores. Remove `@unchecked Sendable` from mutable mocks and stores where possible; make streams return `Sendable` values and update UI on the main actor. Do this after the model moves, not as a package-wide switch. | 30–70 | M | Medium: strict concurrency will expose callback and continuation races in Glue. | **Medium** |

## Target structure

```text
                 ┌──────────────────────────────────────────┐
                 │ CofreUI (SwiftUI, @MainActor)             │
                 │ AppModel + feature models                │
                 │ Instances · Worlds · Content · Servers    │
                 │ Mods · Settings · Setup · Launch          │
                 └───────────────┬──────────────────────────┘
                                 │ concrete stores + one handle
                 ┌───────────────▼──────────────────────────┐
                 │ CofreKit (no UIKit; fixture-tested)       │
                 │ InstanceStore / WorldStore / ContentStore │
                 │ ServerStore / AccountStore / LogStore      │
                 │ Modrinth / resolver / typed preferences   │
                 │ Server-card decode / trust / install plan │
                 └───────────────┬──────────────────────────┘
                                 │ only Air-owned operations
                 ┌───────────────▼──────────────────────────┐
                 │ Air bridge: one concrete EngineHandle     │
                 │ JVM launch · sign-in/refresh · JIT · input│
                 │ renderer/loader install · game surface    │
                 └──────────────────────────────────────────┘
```

`EngineHandle` is a small closure value at the package boundary, not another service protocol or forwarding adapter. Preview code supplies deterministic closures; file data comes from fixtures.

## Ordered migration, one agent-sized PR per step

| Step | Change | Green tests | Delete in the same step |
|---:|---|---|---|
| 1 | Unify `ContentKind`; add typed renderer/version/preference values with Codable compatibility. | `cd app/UI && swift test`; add Mac tests for old raw values and unknown renderer preservation. | `ContentStore.Kind`, `storeKind` switch, raw-string validation branches. |
| 2 | Make `InstanceStore`/`Instance` the instance source. Add fixture row metadata or a small stats value and point `InstancesScreen` at it. | `CofreKitTests/InstancesTests`; existing instance UI tests; `cd app/UI && swift test`. | `InstanceSummary`, `CofreStore.summary`, instance list/create/delete/duplicate facade methods, `LibraryService.instances`. |
| 3 | Wire `AccountStore` directly; keep Microsoft sign-in as an Air engine action returning `CofreAccount`. | `AccountsTests`, setup/account UI tests, `cd app/UI && swift test`. | UI `Account`, account mapping, `AccountService.accounts/removeAccount`; keep the sign-in operation until the engine seam. |
| 4 | Use `WorldsModel` + `WorldStore` and `LogStore` directly. | `WorldsTests`, `LogStoreTests`, game-exit/rejoin UI tests. | `WorldSummary`, `CofreStore.worlds`, `MockBackend.worlds`, UI `LogLine`/`LogSource` where the concrete store replaces it. |
| 5 | Move `ModResolver` and compatibility rules to CofreKit; use `ContentStore.Item` and `Modrinth` values in the Mods model. | Move `ModInstallTests` and `ModCompatibilityTests` to `CofreKitTests`; run `cd app/UI && swift test` on Mac. | UI `InstalledItem`, resolver/compatibility UIKit guards, `ContentService`, `ProjectCatalog`, installed-item mapping. |
| 6 | Make a canonical server value around the existing `CofreServersStore`; merge `app/ServerJoin` as a target, then move Foundation-only card/trust/planning code to CofreKit. | Existing `ServersTests` plus `CofreServerJoinTests`; run both until the target merge, then only `cd app/UI && swift test`. | `ServerSummary`, `ServerService`, `ServerJoinSource`, `CardLoader`, and record-to-summary conversions. |
| 7 | Replace the facade composition with `EngineHandle`; keep only Air operations in the handle. Keep the input bridge as its own narrow seam. | UI tests use preview closures; device build verifies launch, JIT, sign-in, and loader install markers. | `Services.swift`, backend-only parts of `Requirements.swift`, `CofreBackend`, `CofreServices`, capability/default throw plumbing. Move `GameInputService` and its value types to a standalone input file. |
| 8 | Split `CofreStore` into feature models and replace mocks with fixtures/focused Air fakes. Apply strict concurrency to moved owners. | `cd app/UI && swift test`; retain UI snapshot/interaction tests; run device smoke tests after launch/setup moves. | `CofreStore` feature sections, `MockBackend`, `MockServers`, most `MockServerJoin`, `@unchecked Sendable` preview state. |

## What I would not change

- Keep `InstanceStore`, `WorldStore`, `ContentStore`, `DownloadQueue`, `Modrinth`, and `LogStore` as concrete domain owners. Do not add repositories or protocols around them.
- Keep Air’s JVM, renderer ABI/library loading, input transport, game surface, and Forge/NeoForge processor path behind the engine boundary. Rewriting those is a high-risk engine project, not UI cleanup.
- Keep protocols that are real dependency seams: `CardFetcher`, `PackDownloader`, `TrustStore`, and `HashCache` have meaningful test doubles; the input bridge has a production object plus a spy. They should not be composed into `CofreBackend`.
- Keep the server-card wire schema, TOFU/key-rotation behavior, and its security tests. Merge targets and remove mappings, but do not simplify the trust model.
- Keep `RejoinIntent` and `GameExitReport` as value types with Mac tests. They are small, useful state machines, not layers to dissolve.

**Confidence:** high for duplicate models, dead world state, protocol/default indirection, and mock size; medium for the exact final `Instance` shape and the concurrency actor choice. 
