# Rich mod pages (Modrinth + CurseForge)

Goal (Ignacio): mod pages like CurseForge's site. A rendered **About**, a **Gallery** (very important), **videos**, links and changelogs, for both providers.

Status: plan only (2026-10-30). Nothing is built. Sources are listed at the end; numbers marked 📏 were measured against the live Modrinth API on 2026-10-30.

## 1. Verdict: one `ProjectPage`, two small clients ✅

One provider-neutral value in CofreKit, filled by two clients (no protocol, no adapter layer):

```
 Modrinth.page(id:) ──┐                                   ┌─ About tab   (ProjectBody, WKWebView)
                      ├─► ProjectPage (CofreKit value) ───┼─ Gallery tab (native grid + viewer)
 CurseForge.page(id:)─┘   body · gallery · videos · links  └─ Versions tab (+ changelog of the picked one)
```

Why one model is enough:

| Part | Modrinth | CurseForge | Same shape? |
|---|---|---|---|
| About | GFM Markdown **with raw HTML** (`body`) | HTML (`/description`) | ✅ Both end up as HTML. Markdown converts to HTML in one step |
| Gallery | `gallery[]`: `url` (350 px webp), `raw_url`, `title`, `description`, `featured`, `ordering` | `screenshots[]`: `thumbnailUrl`, `url`, `title`, `description` | ✅ thumb + full + title + caption |
| Videos | None as a field. YouTube `<iframe>` in `body` | None as a field. YouTube `<iframe>` in the description | ✅ Same extraction from the HTML |
| Links | source, issues, wiki, discord, donations[] | website, wiki, issues, source | ✅ a list of `(kind, url)` |
| Changelog | Markdown on each version | HTML per file (`/files/{id}/changelog`) | ✅ `Body` per version |

The only real difference is the transport (key, no caching for CurseForge) and Markdown vs HTML. Both sit inside each client and in a single `Body` enum. Separate pages would duplicate the whole screen for a two-case difference.

```swift
// CofreKit/ProjectPage.swift (sketch)
public struct ProjectPage: Sendable, Hashable {
    public enum Body: Sendable, Hashable { case markdown(String), html(String) }
    public struct Image: Sendable, Hashable, Identifiable { public let id: String; public let thumb, full: URL; public let title, caption: String?; public let featured: Bool }
    public struct Video: Sendable, Hashable, Identifiable { public let id: String /* YouTube ID */; public var watch: URL; public var thumb: URL }
    public struct Link: Sendable, Hashable { public enum Kind: Sendable { case website, source, issues, wiki, discord, donate(String) }; public let kind: Kind; public let url: URL }
    public let id: String, source: ProjectSource
    public let body: Body?, gallery: [Image], videos: [Video], links: [Link], license: String?
}
```

`ProjectVersion` gains `changelog: ProjectPage.Body?` (Modrinth: already in the filtered response; CurseForge: fetched when a version is picked).

## Why the own Modrinth client matters (plainly)

Air asked Modrinth for **every version of a mod, with every changelog**, and parsed it all into ObjC dictionaries before the page could show anything.

| Sodium 📏 | Versions | JSON |
|---|---:|---:|
| Air: everything | 258 | **539 KB** |
| Cofre now: fits the instance (Fabric 1.21.1) | 22 | **55 KB** (10× less) |
| Cofre background full list, with `include_changelog=false` (not yet set, step 1) | 258 | 219 KB |

So the page shows the right versions almost at once. Owning the client also lets us add the page fields (`body`, `gallery`, links) as plain `Codable` without touching Air. One `GET /project/{id}` is all a rich page needs: Sodium's is 5 KB of body.

## 2. What each provider gives vs what we show

| We show | Modrinth | CurseForge | Gap / fallback |
|---|---|---|---|
| Header: icon, title, author, downloads, updated, loaders | ✅ search hit + project | ✅ mod | — |
| About | ✅ `body` | ✅ `/description` (1 extra call) | Empty → summary + "Open on …" |
| Gallery | ✅ `gallery` (thumb = `url`, full = `raw_url`) | ✅ `screenshots` | `raw_url` isn't in the OpenAPI spec but is in live responses 📏: decode optional, fall back to `url`. Empty → tab hidden |
| Videos | From `<iframe>` in body (Modrinth allows YouTube + Discord iframes only) | From `<iframe>` in description | No API field anywhere. YouTube only; others stay plain links |
| Links | ✅ 4 + donations | ✅ 4 (no social links) | Discord only on Modrinth |
| License | ✅ `license.name` | ❌ | Row hidden |
| Changelog | ✅ per version (Markdown) | ✅ per file (HTML, 1 call) | Empty → "No notes for this version" |
| Download | ✅ | ⚠ `downloadUrl` is null when `allowModDistribution=false`; CDN downloads need the key since July 2024 | "Only downloads on CurseForge" + Open page (today's copy) |

Measured examples 📏: Create's body has 44 HTML tags, 6 `<img>` and 1 YouTube iframe, and an empty gallery. Iris has a Markdown image and 4 gallery shots. Fabric API is plain Markdown. **Raw HTML is common, so a renderer that drops HTML is not enough.**

## 3. UI layout

Tabs use the existing `Segmented`. The Get button is pinned so it works from any tab.

**iPhone** (compact)

```
┌───────────────────────────────┐
│ ← Results            Share    │  ColumnHeader
│ [icon] Sodium                 │
│ by jellysquid · Modrinth      │
│ [Fabric][NeoForge] Won't run? │
│ 120M ↓ · ✓ Fits 1.21.1 · 3d   │  Stats row
│ ┌About┬Gallery 4┬Versions┐    │  Segmented
│ │ rendered body …          │  │
│ │ ▶ video card (thumb)     │  │  iframe → tap opens YouTube
│ │ Links: Source · Issues … │  │  native rows under the body
├───────────────────────────────┤
│ [ Get · 0.6.3 ]               │  safeAreaInset(.bottom), ⌘↩
└───────────────────────────────┘
```

**iPad** (regular, detail column of the Mods split view)

```
┌──────────── main (readable width) ────────────┬──── rail 280 pt ────┐
│ [icon] Sodium  by … · Modrinth        Share   │ [ Get · 0.6.3 ]     │
│ ┌About┬Gallery 4┬Versions┐                    │ Banner: installed…  │
│ │ About body / gallery grid (3–4 cols) /     │ Stats               │
│ │ versions list                               │ Needs: Fabric API   │
│                                               │ Links · License     │
│                                               │ Details (version,ID)│
└───────────────────────────────────────────────┴─────────────────────┘
```

| Tab | Content | Notes |
|---|---|---|
| **About** (default) | `ProjectBody` web view, then native link rows and license | Summary shows natively while the body loads |
| **Gallery N** | Featured first, then `ordering`. Grid 2 cols (iPhone) / 3–4 (iPad). Video cards first, with a ▶ badge | Hidden when there are no images and no videos |
| **Versions** | Today's version list + filter bar. The picked version expands "What's new" (its changelog) | **No separate Changelog tab**: a changelog belongs to a version |

**Gallery viewer** (`.fullScreenCover`):
- Paged `TabView` over the images; swipe left/right, swipe down or ✕ to close.
- Pinch and double-tap zoom: a small `UIScrollView` wrapper (SwiftUI on iOS 17 has no reliable zoomable scroll view).
- Thumbnail (350 px) shows at once; the full image (`raw_url`) loads on top.
- Title and caption at the bottom, a "2 / 4" counter, Share.
- Reduce Motion: cross-fade, no zoom spring. VoiceOver: each page reads "title, caption, image 2 of 4".

**Videos**: never played inline. A card with the YouTube thumbnail (`img.youtube.com/vi/ID/hqdefault.jpg`) and ▶. Tap opens the YouTube app or Safari. Reasons: the player needs JavaScript, YouTube's 2025 error 153 rejects embeds without a proper referer, and owners can block embedding (101/150).

## 4. Rendering: sanitized `WKWebView` ✅

| Option | Raw HTML (Create) | CurseForge HTML | Cost | Verdict |
|---|---|---|---|---|
| `AttributedString(markdown:)` in `Text` | ❌ dropped | ❌ | none | ❌ no images, headings, lists or tables |
| MarkdownUI | ❌ dropped | ❌ | dependency, maintenance mode (moved to Textual) | ❌ |
| swift-markdown AST → own SwiftUI views | ❌ unless we parse HTML too | needs an HTML parser (SwiftSoup) | 2 renderers, lots of code | ❌ |
| **Markdown → HTML, then one locked-down `WKWebView`** | ✅ | ✅ | 1 web view per page | ✅ one renderer for both, VoiceOver and links for free |

Pipeline (all string work in CofreKit, Mac-tested; the view in CofreUI):

```
Body.markdown ──swift-markdown (cmark-gfm) → HTML──┐
Body.html ─────────────────────────────────────────┴► PageDocument.html(…)
   1. drop <script>, <iframe> (YouTube ones become linked video cards), <object>, <embed>, <form>, on* attributes
   2. wrap in the template: CSP meta, Cofre colours, fonts
   3. collect videos for the Gallery tab
                                                      ► ProjectBody (WKWebView)
```

Security rules (each one is a test or a config line):

| Rule | How |
|---|---|
| No page JavaScript | `defaultWebpagePreferences.allowsContentJavaScript = false` (the app can still measure height) |
| Nothing but HTTPS images loads | CSP `default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; font-src data:` plus the strip step. Iframes, media, fonts from the web and forms are blocked twice |
| No cookies or tracking state | `websiteDataStore = .nonPersistent()`, `<meta name="referrer" content="no-referrer">` |
| Links never navigate inside | `decidePolicyFor`: allow only the initial load. A tapped `http(s)` link → `openURL` (Safari or the app). Other schemes are dropped. The decision is a pure function, unit-tested |
| No media autoplay | `mediaTypesRequiringUserActionForPlayback = .all`, and no `<video>`/`<audio>` (CSP) |
| Tracking pixels | Accepted risk: a remote image reveals the IP to its host, same as Modrinth's own site. Low Data Mode loads no images in the body (`img-src data:` only, plus a "Show images" button) |

Look and accessibility:
- Cofre's single dark look: the template uses the theme's colours (no `prefers-color-scheme` needed).
- Dynamic Type: `font: -apple-system-body` sets the size; the family is overridden to Geist, embedded as a `data:` `@font-face` (no network). Headings use Pixelify Sans the same way.
- `img { max-width: 100%; height: auto }`, and Modrinth's allowed `image-rendering: pixelated` is kept.
- `<details>` spoilers, tables and `<kbd>` work natively in WebKit.
- Height: the web view doesn't scroll on its own. Its height follows `scrollView.contentSize` (KVO), so the page scrolls as one, and late-loading images and Dynamic Type changes resize it.

Cellular and caching:

| Item | Size 📏 | Rule |
|---|---|---|
| Project JSON (Sodium) | ~13 KB | Modrinth client's 30 s cache, as today |
| Gallery thumb (`url`, 350 px webp) | ~220 KB | Load when the Gallery tab opens, not with the page |
| Gallery full (`raw_url`) | ~430 KB | Only in the viewer, for the image on screen ± 1 |
| Body images | varies | WebKit's own loading; none in Low Data Mode |

Images go through one `URLSession` with a bigger `URLCache` (for example 32 MB memory and 150 MB disk) instead of `AsyncImage`'s default session, so the grid doesn't refetch on every scroll. **CurseForge API JSON is never cached** (their terms §3.1). The CDN images are only in the HTTP cache.

## 5. CurseForge: own Swift client, bring your own key ✅ (🤔 Ignacio)

| Option | For | Against |
|---|---|---|
| Keep Air's bridge | Nothing to write | Unreachable today (the key getter returns nil and the setter throws). It has no description or screenshot calls. It's ObjC dictionaries. **It breaks the terms:** without a key it sends requests to the third-party MCIM mirror, and for files whose authors turned off third-party downloads it rebuilds an `edge.forgecdn.net` link anyway (`.work/air/Natives/installer/modpack/CurseForgeAPI.m`: `baseURL`, `cfFileByResolvingNullDownloadURL:`) |
| Drop CurseForge | Deletes ~110 lines; no terms to follow | Many packs and mods live only there; the Settings field and "needs a key" copy go too |
| **Own `CofreKit/CurseForge.swift` + key in the Keychain** | ~150 lines; the same `ProjectPage`; Mac-tested on fixtures; deletes Air's `searchProjects`/`projectVersions` paths and the `source == 2` branches | We follow the terms ourselves (no caching, key on downloads) |

How a launcher gets a key:
- **Now (personal use):** the user makes a key in the CurseForge for Studios console (`console.curseforge.com`) and pastes it in Settings. This is Prism Launcher's approach for builds without a maintainer key. The Settings field already exists; it only needs storage.
- **Before a public release:** apply with the CurseForge 3rd-party API key form for Cofre. Keep that key out of the repo: inject it at build time from `scripts/run.local.config` or a CI secret, the way Prism keeps its key out of public source. A user key, if set, overrides it.
- Terms to respect: no saving or caching API data (§3.1), no hiding identity through proxies or VPNs (§3), and `allowModDistribution=false` files open the CurseForge page instead of downloading. Ask CurseForge whether the loopback JIT tunnel counts as a VPN for §3: it doesn't route traffic out, but say so in the application.

## 6. Steps (one agent each, in order)

| # | Step | Files | Tests (fixtures, no network) | Done when |
|---|---|---|---|---|
| 1 | `ProjectPage` + `Modrinth.page(id:)`; `changelog` on `Version`; `include_changelog=false` on the full list; `raw_url` optional | `CofreKit/ProjectPage.swift` (new), `CofreKit/Modrinth.swift`, `CofreBackendAdapter+Mods.swift` (pass the changelog through) | New fixtures `modrinth-project-{sodium,create,iris}.json` (trimmed real responses): decode, featured-first order, link kinds, empty icon/gallery. `versionsURL` test for `include_changelog` | `swift test` green |
| 2 | `PageDocument`: Markdown → HTML (add Apple's `swift-markdown`; check its `HTMLFormatter` first, else a cmark-gfm call), strip list, iframe → video card, template with CSP and fonts, video extraction | `CofreKit/PageDocument.swift`, `Package.swift` | Create body → no `<iframe>`/`<script>`, 1 video with the right ID, CSP meta present, `on*` attributes gone. A hand-written CurseForge-style HTML fixture with a script, a form and a Vimeo iframe | `swift test` green |
| 3 | `ProjectBody` web view (hardened config, link decision, contentSize height); `CofreStore.pages[id]` + `loadPage(id)`, calling the CofreKit client directly (no facade protocol, per [swift-ownership-ui](reviews/swift-ownership-ui.md)). One shared `Modrinth` handed in from Glue | `CofreUI/Components/ProjectBody.swift`, `CofreStore.swift`, `CofreBackendAdapter.swift` (hand over the client) | Pure link-decision tests (http → open outside, `javascript:` → drop, initial load → allow). Preview seeded from the fixture | Device: `[Cofre] project page id=… body=…B images=n videos=n` |
| 4 | New page layout: header, `Segmented` tabs, pinned Get (iPhone), right rail (iPad); versions move to their tab with "What's new". Delete the old inline layout in the same change | `Screens/ModsScreen.swift` (`ModPagePane` split into `ModPage{About,Gallery,Versions}`), `MockBackend` sample page | UI tests: tabs switch, the Gallery tab hides when empty, Get works from every tab, iPhone and iPad sizes | Device: open Sodium and Create, both tabs render |
| 5 | Gallery grid + viewer (paging, pinch/double-tap zoom, captions, counter, Share), video cards open outside | `Components/GalleryViewer.swift`, `Components/ZoomableImage.swift` | Order and index tests; VoiceOver labels; Reduce Motion path | Device: pinch and swipe on Iris's gallery; `[Cofre] gallery open id=… index=i` |
| 6 | Image session with a bigger `URLCache`; Low Data Mode (no body images, thumbs only on tap) | `CofreKit/ImageLoading.swift` or extend `Downloads`; `ProjectIcon` uses it too | Cache config test; constrained → CSP without remote `img-src` | Device: Low Data Mode on, body shows "Show images" |
| 7 | CurseForge client: search, mod, description, files, changelog, download with key; no caching; Keychain key; Settings field works; delete Air's CurseForge bridge and the `source == 2` branches | `CofreKit/CurseForge.swift`, `CofreKit/Keychain.swift` (or reuse existing storage), `+Mods.swift`, `AirBridgeAdapter.{h,m}`, `CofreBackendAdapter.swift` | Fixtures written from the docs: mod with screenshots, `allowModDistribution=false`, description HTML, changelog HTML; the request has `x-api-key`; no `URLCache` | Device (with a real key): `[Cofre] curseforge page id=…` and one download |
| 8 | Docs: ROADMAP status, AGENTS "Already Cofre-owned" if CurseForge lands | `plan/ROADMAP.md`, `AGENTS.md` | — | — |

Steps 1–2 are Mac-only and can run in parallel. Steps 3–6 follow in order. Step 7 waits on the decision but doesn't block 1–6.

Notes for agents:
- Project links (source, wiki, …) are user content opened outside. They aren't Cofre site links, so `CofreLinks` and its allowlist test don't change.
- Keep the summary and Get usable when the body or gallery fails; a page fetch failure must never block installing.

## 7. Decisions (Ignacio, 2026-10-30) ✅

1. **CurseForge:** own Swift client now, with the user's own key in the Keychain; Air's CurseForge path goes.
2. **Official key:** apply for Cofre's 3rd-party key before the public release (injected at build time, never in the repo).
3. **Videos:** always open in YouTube.
4. **Changelog:** inside Versions, under the picked version.
5. **Cellular:** body images load automatically except in Low Data Mode.
6. **Dependency:** add Apple's `swift-markdown`.
7. **About font:** Geist body, Pixelify headings.

## Sources

- Modrinth API: [overview, rate limits, User-Agent](https://docs.modrinth.com/api/) · [get project](https://docs.modrinth.com/api/operations/getproject/) · [project versions (`include_changelog`)](https://docs.modrinth.com/api/operations/getprojectversions/) · [OpenAPI](https://docs.modrinth.com/openapi.yaml) · [Markdown and allowed HTML](https://support.modrinth.com/en/articles/8801962-advanced-markdown-formatting)
- CurseForge: [REST API](https://docs.curseforge.com/rest-api/) · [3rd-party API terms](https://support.curseforge.com/support/solutions/articles/9000207405-curse-forge-3rd-party-api-terms-and-conditions) · [API key on CDN downloads (2024)](https://blog.curseforge.com/introducing-api-key-authentication-for-curseforge-file-downloads/)
- Prism Launcher: [blocked downloads](https://github.com/PrismLauncher/PrismLauncher/issues/1044) · [user API key field](https://github.com/PrismLauncher/PrismLauncher/pull/4700)
- Rendering: [MarkdownUI → Textual](https://github.com/gonzalezreal/swift-markdown-ui) · [YouTube IFrame API errors](https://developers.google.com/youtube/iframe_api_reference) · [revision history (error 153)](https://developers.google.com/youtube/iframe_api_revision_history)
- Code: `CofreKit/Modrinth.swift`, `CofreBackendAdapter+Mods.swift`, `ModsScreen.swift` (`ModPagePane`, `ProjectIcon`), [swift-ownership-bridge](reviews/swift-ownership-bridge.md) (CurseForge unreachable), [swift-ownership-ui](reviews/swift-ownership-ui.md)
