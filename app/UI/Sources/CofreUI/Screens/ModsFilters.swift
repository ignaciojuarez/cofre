#if canImport(UIKit)
    import CofreKit
    import SwiftUI

    // M01 filters: one sheet for every kind, each with its own fields. Defaults follow the Mods instance; changes
    // search live through M01's debounce, so there's no Apply.

    /// "Modrinth ⇄": one tap switches the source.
    struct ModsSourceButton: View {
        @Environment(CofreStore.self) private var store

        var body: some View {
            let source = store.query.source
            let other: ProjectSource = source == .modrinth ? .curseforge : .modrinth
            BlockButton("\(source.displayName) ⇄", size: .small) { store.query.source = other }
                .fixedSize()
                .accessibilityLabel(Text("Source, \(source.displayName)"))
                .accessibilityHint(Text("Switches to \(other.displayName)"))
        }
    }

    struct ModsFiltersSheet: View {
        @Environment(CofreStore.self) private var store
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            @Bindable var store = store
            let kind = store.query.kind
            let inst = store.modsInstance
            let loader = inst?.loader ?? .unknown
            let hasLoader = kind == .mods || kind == .modpacks
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader("Filters · \(Self.name(kind))")
                VStack(alignment: .leading, spacing: 10) {
                    // Only this instance or any: another version couldn't be installed here.
                    if let inst {
                        field("Version", modrinthOnly: false) {
                            ChipGroup(
                                "Version", selection: $store.query.filters.version,
                                options: [(.instance, "\(inst.gameVersion)"), (.any, "Any")]
                            )
                            .accessibilityRepresentation {
                                Picker("Version", selection: $store.query.filters.version) {
                                    Text("\(inst.gameVersion), from this instance").tag(FilterScope.instance)
                                    Text("Any").tag(FilterScope.any)
                                }
                            }
                        }
                        if hasLoader, loader != .vanilla, loader != .unknown {
                            field("Loader", modrinthOnly: false) {
                                ChipGroup(
                                    "Loader", selection: $store.query.filters.loader,
                                    options: [(.instance, "\(loader.displayName)"), (.any, "Any")]
                                )
                                .accessibilityRepresentation {
                                    Picker("Loader", selection: $store.query.filters.loader) {
                                        Text("\(loader.displayName), from this instance").tag(FilterScope.instance)
                                        Text("Any").tag(FilterScope.any)
                                    }
                                }
                            }
                        }
                    }
                    if kind == .shaders {
                        field("Shader loader") {
                            ChipGroup(
                                "Shader loader",
                                selection: Binding(
                                    get: { store.query.filters.shaderLoader(loader) },
                                    set: { store.query.filters.shaderLoader = $0 }),
                                options: [(.iris, "Iris"), (.optifine, "OptiFine"), (.any, "Any")])
                        }
                    }
                    if hasLoader {
                        field("Side") {
                            ChipGroup(
                                "Side", selection: $store.query.filters.clientSide,
                                options: [(true, "Runs on client"), (false, "Any")])
                        }
                    }
                    if kind == .resourcePacks {
                        field("Resolution") {
                            ChipGroup(
                                "Resolution", selection: $store.query.filters.resolution,
                                options: [(nil, "Any"), (.x16, "16x"), (.x32, "32x"), (.x64, "64x"), (.x128, "128x+")])
                        }
                    }
                    let categories = ProjectFilters.categories(for: kind)
                    if !categories.isEmpty {
                        field("Category") {
                            AdaptiveGrid(minItem: 96, maxColumns: 4) {
                                ForEach(categories, id: \.id) { c in
                                    Chip(
                                        "\(c.label)",
                                        isOn: Binding(
                                            get: { store.query.filters.categories.contains(c.id) },
                                            set: { on in
                                                if on {
                                                    store.query.filters.categories.insert(c.id)
                                                } else {
                                                    store.query.filters.categories.remove(c.id)
                                                }
                                            }))
                                }
                            }
                        }
                    }
                    field("Sort") {
                        ChipGroup(
                            "Sort", selection: $store.query.filters.sort,
                            options: [
                                (.relevance, "Relevance"), (.downloads, "Downloads"), (.updated, "Updated"),
                                (.newest, "Newest"),
                            ])
                    }
                    HStack(spacing: 8) {
                        BlockButton("Reset to instance") { store.query.filters = ProjectFilters() }
                        BlockButton("Done", role: .primary) { dismiss() }
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            }
        }

        /// A labelled field. CurseForge (through Air) only filters by version and loader, so the rest is off there.
        @ViewBuilder private func field<C: View>(
            _ title: LocalizedStringKey, modrinthOnly: Bool = true, @ViewBuilder _ content: () -> C
        ) -> some View {
            let off = modrinthOnly && store.query.source != .modrinth
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SectionLabel(title)
                    if off { Badge("Modrinth only") }
                }
                content().disabled(off).opacity(off ? 0.5 : 1)
            }
        }

        static func name(_ kind: ContentKind) -> String {
            switch kind {
            case .mods: String(localized: "Mods")
            case .modpacks: String(localized: "Modpacks")
            case .shaders: String(localized: "Shaders")
            case .resourcePacks: String(localized: "Resource packs")
            case .dataPacks: String(localized: "Data packs")
            }
        }

        /// M01's muted line under the type chips: "For 1.21.1 · Fabric · Client". `nil` with nothing applied.
        static func summary(_ store: CofreStore) -> String? {
            let f = store.query.filters
            let kind = store.query.kind
            let game = store.modsInstance?.gameVersion ?? ""
            let loader = store.modsInstance?.loader ?? .unknown
            var parts = [f.gameVersion(game), f.loader(kind, loader)?.displayName].compactMap { $0 }
            if store.query.source == .modrinth {
                if f.clientSide, kind == .mods || kind == .modpacks { parts.append(String(localized: "Client")) }
                if kind == .shaders {
                    switch f.shaderLoader(loader) {
                    case .iris: parts.append("Iris")
                    case .optifine: parts.append("OptiFine")
                    case .any: break
                    }
                }
                if kind == .resourcePacks, let r = f.resolution { parts.append(r == .x128 ? "128x+" : r.rawValue) }
                parts += ProjectFilters.categories(for: kind).filter { f.categories.contains($0.id) }.map(\.label)
            }
            return parts.isEmpty ? nil : String(localized: "For \(parts.joined(separator: " · "))")
        }
    }
#endif
