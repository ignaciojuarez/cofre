#if canImport(UIKit)
    import CofreKit
    import Foundation

    extension ProjectPage {
        /// The page previews and the preview host show (no client there). Its body mixes Markdown and raw HTML the way
        /// real Modrinth bodies do: headings, a list, a table, a spoiler, code, an image and a YouTube embed.
        static func sample(id: String) -> ProjectPage {
            let p = MockBackend.projects.first { $0.id == id }
            // Lithium's page is plain text with no images or videos, so its Gallery tab hides.
            if id == "lithium" {
                return ProjectPage(
                    id: id, source: .modrinth, title: p?.title ?? id, summary: p?.summary ?? "", iconURL: p?.iconURL,
                    body: .markdown("Lithium makes game logic faster without changing how the game plays."),
                    license: "LGPL-3.0")
            }
            let shots = "https://cdn.modrinth.com/data/YL57xq9U/images/"
            let gallery = [
                ("f47cea26f135d74c2d69df0a1806751818d705d3", "f47cea26f135d74c2d69df0a1806751818d705d3", "Grand Teton"),
                (
                    "17f09a3d424d6e2005fcecc81838780a6847f8ce", "d382106b9a2b943d06107c31c139c77849f1a0e8",
                    "A nice sunset"
                ),
            ].map { thumb, full, title in
                Image(
                    id: thumb, thumb: URL(string: "\(shots)\(thumb)_350.webp")!,
                    full: URL(string: "\(shots)\(full).png"),
                    title: title, featured: title == "Grand Teton")
            }
            let body = """
                ![Banner](https://cdn.modrinth.com/data/cached_images/e63175a54ed1c0484e07f9e71bd426244220b51b.png)

                ## Features

                * **Faster** chunk rendering, with *no* visual changes
                * Works with [Fabric API](https://modrinth.com/mod/fabric-api) and most mods
                * Settings live in `Video Settings → Performance`

                | Device | Before | After |
                |---|---:|---:|
                | iPhone 15 Pro | 40 fps | 90 fps |
                | iPad Air M2 | 55 fps | 120 fps |

                <iframe width="560" height="315" src="https://www.youtube-nocookie.com/embed/rR8W-f9YhYA" allowfullscreen></iframe>

                <details><summary>Known issues</summary>

                Some shader packs flicker on older GPUs. <script>alert(1)</script>

                </details>

                > Report bugs on the [issue tracker](https://github.com/CaffeineMC/sodium/issues).
                """
            return ProjectPage(
                id: id, source: .modrinth, title: p?.title ?? "Sample mod", summary: p?.summary ?? "",
                iconURL: p?.iconURL, body: .markdown(body), gallery: gallery,
                links: [
                    Link(kind: .source, url: URL(string: "https://github.com/CaffeineMC/sodium")!),
                    Link(kind: .issues, url: URL(string: "https://github.com/CaffeineMC/sodium/issues")!),
                    Link(kind: .donate("Ko-fi"), url: URL(string: "https://ko-fi.com/jellysquid_")!),
                ], license: "Polyform Shield 1.0.0")
        }

        /// A version's notes the way Modrinth writes them, for versions that arrive without one.
        static let sampleChangelog = """
            ## Changes

            * Fixed chunks flickering when the render distance changes
            * Faster startup with large mod lists
            * See the [full list](https://github.com/CaffeineMC/sodium/releases)
            """
    }
#endif
