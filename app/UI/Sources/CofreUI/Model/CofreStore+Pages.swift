#if canImport(UIKit)
    import CofreKit
    import Foundation

    extension CofreStore {
        /// Pages kept in memory. Each document embeds ~850 KB of fonts, so older pages are dropped and load again.
        static let keptPages = 8

        /// Loads a project's page once, straight from the shared Modrinth client, and renders its About off the main
        /// actor. CurseForge pages come with its own client (plan/rich-mod-pages.md step 7). A failure only fills
        /// `pageErrors`: the summary and Get never wait on the page.
        public func loadPage(_ id: String) async {
            if pages[id] != nil { return keepPage(id) }
            guard results.first(where: { $0.id == id })?.source != .curseforge else { return }
            pageErrors[id] = nil
            do {
                var page = try await services.modrinth?.page(id: id) ?? .sample(id: id)
                let body = page.body
                let style = PageDocument.Style.cofre
                let document = await Task.detached { body.map { PageDocument($0, style: style) } }.value
                page.videos = document?.videos ?? []
                pages[id] = page
                pageDocuments[id] = document
                keepPage(id)
                NSLog(
                    "[Cofre] project page id=%@ body=%ldB images=%ld videos=%ld", id, body?.text.utf8.count ?? 0,
                    page.gallery.count, page.videos.count)
            } catch {
                pageErrors[id] = error.localizedDescription
                NSLog("[Cofre] project page id=%@ failed=%@", id, error.localizedDescription)
            }
        }

        /// Marks `id` as the newest page and drops the oldest beyond `keptPages`.
        private func keepPage(_ id: String) {
            pageOrder.removeAll { $0 == id }
            pageOrder.append(id)
            while pageOrder.count > Self.keptPages {
                let old = pageOrder.removeFirst()
                pages[old] = nil
                pageDocuments[old] = nil
            }
        }

        /// "What's new" for a version from the changelog-free full list. Stores an empty changelog when the version
        /// has none (CurseForge notes come with its own client), so the page says so instead of asking again.
        public func loadChangelog(_ projectID: String, versionID: String) async throws {
            let text: String
            if results.first(where: { $0.id == projectID })?.source == .curseforge {
                text = ""
            } else if let modrinth = services.modrinth {
                text = try await modrinth.version(id: versionID).changelog ?? ""
            } else {
                text = ProjectPage.sampleChangelog
            }
            guard let i = versions[projectID]?.firstIndex(where: { $0.id == versionID }) else { return }
            versions[projectID]?[i].changelog = .markdown(text)
        }
    }

    extension ProjectPage.Body {
        var text: String {
            switch self {
            case .markdown(let text), .html(let text): text
            }
        }
        /// No notes worth a section.
        var isBlank: Bool { text.allSatisfy(\.isWhitespace) }
    }
#endif
