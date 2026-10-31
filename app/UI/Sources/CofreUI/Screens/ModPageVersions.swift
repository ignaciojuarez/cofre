#if canImport(UIKit)
    import SwiftUI
    import CofreKit

    /// M02 Versions: filtered to the target by default, with a one-tap way to see the rest. The picked version opens
    /// "What's new" under its row. On iPhone, Needs and Details follow; the iPad rail has them instead.
    struct ModPageVersions: View {
        let state: ModPageState
        @Binding var versionID: String?
        @Binding var filter: VersionFilter?
        @Binding var showAll: Bool
        let showsDetails: Bool
        @Environment(CofreStore.self) private var store

        var body: some View {
            let s = state
            let versions = s.versions
            let f = filter ?? .defaults(for: store.modsInstance)
            let shown = f.visible(versions, installed: s.installed, all: showAll)
            let hidden = versions.count - shown.count
            ListSection("Versions", spacing: 4) {
                // Big projects list hundreds of versions, which can take a few seconds.
                if s.loading {
                    Row(
                        "Loading versions…", subtitle: "Big mods have hundreds; this can take a few seconds",
                        leading: { Spinner() })
                    ForEach(0..<3, id: \.self) { _ in
                        Row("0.0.0", subtitle: "26.3 · Fabric", leading: { Radio(isOn: false) })
                            .redacted(reason: .placeholder).opacity(0.5)
                    }
                }
                if !versions.isEmpty {
                    VersionFilterBar(versions: versions, filter: Binding(get: { f }, set: { filter = $0 }))
                        .disabled(showAll)
                }
                ForEach(shown) { v in
                    Button {
                        versionID = v.id
                    } label: {
                        Row(v.name, subtitle: Self.subtitle(v), isSelected: s.chosen == v.id) {
                            Radio(isOn: s.chosen == v.id)
                        } trailing: {
                            HStack(spacing: 4) {
                                if v.id == s.installed { Badge("Installed", tone: .success) }
                                if !v.fits {
                                    Badge("No fit", tone: .danger)
                                } else if v.versionChannel != .release || v.id != s.installed {
                                    Badge(v.versionChannel.label, tone: Self.tone(v.versionChannel))
                                }
                            }
                        }
                        .dimmed(!v.fits)
                    }
                    .buttonStyle(RowButtonStyle())
                    .disabled(!v.fits)
                    if s.chosen == v.id { ModPageChangelog(projectID: s.id, version: v) }
                }
                if shown.isEmpty, !versions.isEmpty {
                    Row("No versions match these filters", leading: { PixelIcon(.book, size: 18) })
                }
                if hidden > 0 || showAll {
                    Button {
                        showAll.toggle()
                    } label: {
                        ValueRow(
                            showAll ? "Only versions for this instance" : "Show \(hidden) hidden",
                            value: showAll ? "" : String(localized: "All versions"), accent: true)
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            if showsDetails {
                ModPageNeeds(state: s)
                ModPageDetails(state: s)
            }
        }

        static func subtitle(_ v: ProjectVersion) -> String {
            let games = v.games.prefix(3).joined(separator: ", ") + (v.games.count > 3 ? " +\(v.games.count - 3)" : "")
            return ([games] + [v.loaders.map(\.displayName).joined(separator: ", ")]).filter { !$0.isEmpty }
                .joined(separator: " · ")
        }

        static func tone(_ c: VersionChannel) -> Tone {
            switch c {
            case .release: .neutral
            case .beta: .warn
            case .alpha: .danger
            }
        }
    }

    /// "What's new" for the picked version, rendered like the About (sanitized, no JavaScript, links open outside).
    /// Versions from the changelog-free full list fetch theirs first.
    struct ModPageChangelog: View {
        let projectID: String, version: ProjectVersion
        @Environment(CofreStore.self) private var store
        @State private var document: PageDocument?
        @State private var failed = false
        @State private var attempt = 0

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("What's new")
                if let changelog = version.changelog {
                    if changelog.isBlank {
                        Text("No notes for this version").cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                    } else if let document {
                        ProjectBody(document: document)
                    } else {
                        Spinner()
                    }
                } else if failed {
                    Banner(String(localized: "Couldn't load the notes"), icon: .cross, tone: .warn) {
                        BlockButton("Try again", size: .small, fullWidth: false) {
                            failed = false
                            attempt += 1
                        }
                    }
                } else {
                    Row("Loading notes…", leading: { Spinner() })
                }
            }
            .padding(.leading, 12).padding(.vertical, 4)
            .task(id: "\(version.id)-\(version.changelog == nil)-\(attempt)") {
                guard let changelog = version.changelog else {
                    do { try await store.loadChangelog(projectID, versionID: version.id) } catch { failed = true }
                    return
                }
                guard !changelog.isBlank else { return }
                let style = PageDocument.Style.cofre
                document = await Task.detached { PageDocument(changelog, style: style) }.value
            }
        }
    }
#endif
