import CofreUI
import SwiftUI

// 5. Data packs: Cofre can't put them in a world yet, so the Data chip (Get mods) and tab (Installed) go until it
// can (ROADMAP #5). No dead-end empty state. Also shows #4's short row badge, "Won't run" (run with -metal YES).
// Get mods is rebuilt here from public parts; the only intended changes are the chips and the badge.

enum DataPacksClean {
    struct Preview<Real: View>: View {
        let real: Real
        let nav: NavModel, store: CofreStore
        var body: some View {
            AdaptiveShell(nav: nav) { _ in GetMods() }
                .measuredSizeClasses()
                .task {
                    nav.section = .mods
                    await store.start()
                }
        }
    }

    private struct GetMods: View {
        @Environment(CofreStore.self) private var store
        @State private var source = ProjectSource.modrinth
        @State private var kind = ContentKind.mods
        @State private var text = ""

        /// The real rule (ModCompatibility), with the short badge.
        private func issue(_ p: ProjectSummary) -> Bool {
            guard let inst = store.modsInstance else { return false }
            let renderer = ModCompatibility.renderer(
                setting: store.preferences.renderer, gameVersion: inst.gameVersion, loader: inst.loader.rawValue)
            return ModCompatibility.entry(for: p.id, name: p.title)?.issue(gameVersion: inst.gameVersion, renderer: renderer) != nil
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader("Get mods") { BlockButton("Installed · 3", size: .small) {}.fixedSize() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let inst = store.modsInstance {
                            HStack(spacing: 10) {
                                Text("For").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                                Text(verbatim: inst.name).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                                Spacer()
                                Meta(inst.loaderLabel)
                                Text(verbatim: "▾").foregroundStyle(Color.cofre.muted)
                            }
                            .padding(.horizontal, 12).frame(minHeight: 44).block(.button)
                        }
                        Segmented(
                            "Source", selection: $source, options: [(.modrinth, "Modrinth"), (.curseforge, "CurseForge")])
                        Field("Search mods", text: $text, kind: .search)
                        ChipGroup(
                            "Type", selection: $kind,
                            options: [(.mods, "Mods"), (.modpacks, "Packs"), (.shaders, "Shaders"), (.resourcePacks, "Resource")])
                        ListSection(spacing: 4) {
                            ForEach(store.results) { p in
                                Row(p.title, subtitle: "\(p.summary) · \(p.downloads / 1_000_000)M") {
                                    AsyncImage(url: p.iconURL) { $0.interpolation(.none).resizable() } placeholder: {
                                        PixelIcon(.book, size: 20)
                                    }
                                    .frame(width: 28, height: 28)
                                    .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                                } trailing: {
                                    HStack(spacing: 5) {
                                        if issue(p) { Badge("Won't run", tone: .warn) }
                                        if p.installed {
                                            Text(verbatim: "✓").foregroundStyle(Color.cofre.ink)
                                                .frame(width: 30, height: 30).block(.tinted(.success))
                                        } else {
                                            BlockButton("Get", size: .small) {}.fixedSize()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
        }
    }
}
