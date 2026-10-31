#if canImport(UIKit)
    import SwiftUI
    import CofreKit

    /// M02 About: the rendered body. The summary shows natively while the page loads, when it fails, or when the
    /// project has no body. Links and license follow on iPhone; the iPad rail has them instead.
    struct ModPageAbout: View {
        let project: ProjectSummary
        let showsLinks: Bool
        @Environment(CofreStore.self) private var store

        var body: some View {
            let id = project.id
            if let document = store.pageDocuments[id] {
                ProjectBody(document: document)
            } else {
                Text(verbatim: project.summary).cofreFont(.body).foregroundStyle(Color.cofre.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if store.pageErrors[id] != nil {
                    Banner(String(localized: "Couldn't load the full page"), icon: .cross, tone: .warn) {
                        BlockButton("Try again", size: .small, fullWidth: false) {
                            Task { await store.loadPage(id) }
                        }
                    }
                } else if store.pages[id] == nil, project.source == .modrinth {
                    Row("Loading page…", leading: { Spinner() })
                }
            }
            if showsLinks { ModPageLinks(project: project, page: store.pages[id]) }
        }
    }

    /// M02 Gallery: video cards first, then the images; an image opens the full-screen viewer.
    struct ModPageGallery: View {
        let id: String
        @Environment(CofreStore.self) private var store

        var body: some View {
            if let page = store.pages[id] { GalleryGrid(page: page) }
        }
    }

    /// The provider's page, the project's own links (user content, opened outside the app) and its license. Without
    /// a page (CurseForge, or it failed) the provider's page still opens.
    struct ModPageLinks: View {
        let project: ProjectSummary, page: ProjectPage?

        var body: some View {
            ListSection("Links", spacing: 4) {
                if let url = project.pageURL ?? project.fallbackPageURL {
                    Self.row("Open on \(project.source.displayName)", url)
                }
                ForEach(page?.links ?? [], id: \.self) { link in Self.row(Self.title(link.kind), link.url) }
            }
            if let license = page?.license {
                ListSection("License", spacing: 4) {
                    Row(license, leading: { PixelIcon(.paper, size: 18) })
                }
            }
        }

        static func row(_ title: LocalizedStringKey, _ url: URL) -> some View {
            Link(destination: url) { ValueRow(title, value: url.host() ?? "") }
                .buttonStyle(RowButtonStyle())
                .accessibilityHint(Text("Opens outside Cofre"))
        }

        static func title(_ kind: ProjectPage.Link.Kind) -> LocalizedStringKey {
            switch kind {
            case .website: "Website"
            case .source: "Source code"
            case .issues: "Issues"
            case .wiki: "Wiki"
            case .discord: "Discord"
            case .donate(let platform): platform.isEmpty ? "Donate" : "Donate on \(platform)"
            }
        }
    }
#endif
