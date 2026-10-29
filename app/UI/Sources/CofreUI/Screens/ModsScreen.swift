#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    // M01 Browse · M02 Mod page · M03 Import pack · M04 Installed. AdaptiveListDetail: the browser on the left,
    // a mod page or the installed manager on the right (pushed on compact).

    public struct ModsSection: View {
        @Environment(NavModel.self) private var nav
        @Environment(CofreStore.self) private var store
        @Environment(\.widthClass) private var width
        public init() {}
        public var body: some View {
            @Bindable var nav = nav
            if store.libraryLoaded && store.modsInstance == nil {
                // Nothing runs mods yet: only the way to make an instance that does.
                VStack(spacing: 0) {
                    ColumnHeader("Get mods")
                    PaneScroll(readable: true) { ModsHero() }
                }
            } else {
                AdaptiveListDetail(selection: $nav.mod, defaultSelection: width == .compact ? nil : .installed) {
                    ModsBrowserPane()
                } detail: { route in
                    switch route {
                    case .installed: InstalledPane()
                    case .project(let id): ModPagePane(id: id)
                    }
                }
            }
        }
    }

    public struct ModsBrowserPane: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        public init() {}

        public var body: some View {
            @Bindable var store = store
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader("Get mods") {
                    BlockButton(store.updateCount > 0 ? "Installed · \(store.updateCount)" : "Installed", size: .small)
                    { nav.mod = .installed }
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let inst = store.modsInstance { ModsInstanceSwitcher(current: inst) }
                    Segmented(
                        "Source", selection: $store.query.source,
                        options: [(.modrinth, "Modrinth"), (.curseforge, "CurseForge")])
                    Field("Search mods", text: $store.query.text, kind: .search)
                        .keyboardShortcut("f", modifiers: .command)
                    ChipGroup(
                        "Type", selection: $store.query.kind,
                        options: [
                            (.mods, "Mods"), (.modpacks, "Packs"), (.shaders, "Shaders"), (.resourcePacks, "Resource"),
                            (.dataPacks, "Data"),
                        ])
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 4)

                if store.query.source == .curseforge && store.curseForgeKey == nil {
                    EmptyState(
                        "Needs a CurseForge key", message: "Add your own key in Accounts & data. It's never bundled.",
                        icon: .key
                    ) {
                        BlockButton("Add key", role: .primary) {
                            nav.section = .settings
                            nav.settingsPane = .accounts
                        }
                    }
                } else if let err = store.searchError, store.results.isEmpty, !store.searching {
                    EmptyState(
                        "Can't reach \(store.query.source.displayName)",
                        message: "Check your connection, then try again.", icon: .cross
                    ) {
                        BlockButton("Try again", role: .primary) { Task { await store.search() } }
                    }
                    .accessibilityHint(Text(verbatim: err))
                } else if store.results.isEmpty && store.searching {
                    Row("Searching…", leading: { Spinner() }).padding(.horizontal, width == .compact ? 16 : 20)
                    Spacer(minLength: 0)
                } else if store.results.isEmpty {
                    EmptyState("No results", message: "Try another name.", icon: .book)
                } else {
                    BlockList {
                        ForEach(store.results) { p in
                            let selected = width != .compact && nav.mod == .project(p.id)
                            Button {
                                endEditing()
                                nav.mod = .project(p.id)
                            } label: {
                                Row(p.title, subtitle: "\(p.summary) · \(Fmt.count(p.downloads))", isSelected: selected)
                                {
                                    ProjectIcon(project: p, size: 28)
                                } trailing: {
                                    if p.installed {
                                        Badge("✓", tone: .success).accessibilityLabel(Text("Installed"))
                                    } else {
                                        BlockButton(
                                            "Get", role: .primary, size: .small,
                                            isLoading: store.installing.contains(p.id)
                                        ) {
                                            endEditing()
                                            store.install(projectID: p.id)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(RowButtonStyle())
                            .blockListRow(horizontal: width == .compact ? 16 : 20)
                        }
                    }
                }
            }
            // Scrolling the results or tapping outside the field closes the keyboard.
            .scrollDismissesKeyboard(.immediately)
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { endEditing() } }
            .task(id: store.query) {
                try? await Task.sleep(for: .milliseconds(250))
                await store.search()
            }
        }

        private func endEditing() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: M02 Mod page

    public struct ModPagePane: View {
        let id: String
        @Environment(CofreStore.self) private var store
        @Environment(\.widthClass) private var width
        @State private var versionID: String?
        public init(id: String) { self.id = id }

        public var body: some View {
            let p = store.results.first { $0.id == id }
            let versions = store.versions[id] ?? []
            let chosen = versionID ?? versions.first(where: \.fits)?.id
            VStack(spacing: 0) {
                ColumnHeader(p?.title ?? "") {
                    if let url = p.flatMap({ $0.pageURL ?? $0.fallbackPageURL }) {
                        ShareLink(item: url) { Text("Share") }.buttonStyle(.block(size: .small))
                    }
                }
                if let p {
                    PaneScroll(readable: true) {
                        HStack(alignment: .top, spacing: 14) {
                            ProjectIcon(project: p, size: 64)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: p.title).cofreFont(.title).foregroundStyle(Color.cofre.ink)
                                    .accessibilityAddTraits(.isHeader)
                                Text("by \(p.author) · \(p.source.displayName)").cofreFont(.secondary).foregroundStyle(
                                    Color.cofre.muted)
                                HStack(spacing: 4) {
                                    ForEach(p.loaders) { Badge($0.displayName, tone: $0.tone) }
                                    if p.clientSide { Badge("Client") }
                                }
                            }
                        }
                        AdaptiveGrid(minItem: 100, maxColumns: 3) {
                            Stat(Fmt.count(p.downloads), label: "Downloads")
                            Stat(
                                p.fits ? "✓" : "✕", label: "Fits \(store.modsInstance?.gameVersion ?? "")",
                                tone: p.fits ? .success : .danger)
                            Stat(Fmt.ago(p.updated) ?? "—", label: "Updated")
                        }
                        Text(verbatim: p.summary).cofreFont(.body).foregroundStyle(Color.cofre.inkSoft)
                        ListSection("Versions", spacing: 4) {
                            ForEach(versions) { v in
                                Button {
                                    versionID = v.id
                                } label: {
                                    Row("\(v.name) · \(v.gameVersions)", isSelected: chosen == v.id) {
                                        Radio(isOn: chosen == v.id)
                                    } trailing: {
                                        Badge(
                                            v.fits ? LocalizedStringKey(v.channel) : "No fit",
                                            tone: v.fits ? (chosen == v.id ? .success : .neutral) : .danger)
                                    }
                                    .dimmed(!v.fits)
                                }
                                .buttonStyle(RowButtonStyle())
                                .disabled(!v.fits)
                            }
                        }
                        ForEach(chosen.flatMap { store.dependencies[$0] } ?? []) { d in
                            Row(
                                "Needs \(d.name)", subtitle: "Dependency", leading: { PixelIcon(.book, size: 18) },
                                trailing: {
                                    Meta(d.installed ? "Installed" : "Adds", tone: d.installed ? .success : .warn)
                                })
                        }
                        if !p.installed, let err = store.versionsError[id] {
                            Banner(String(localized: "Couldn't load versions"), icon: .cross, tone: .danger) {
                                BlockButton("Try again", size: .small, fullWidth: false) {
                                    Task { await store.loadProject(id) }
                                }
                            }
                            Text(verbatim: err).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                        }
                        if p.installed {
                            Banner("Installed in \(store.modsInstance?.name ?? "")", icon: .check, tone: .success)
                        } else if store.versions[id] == nil {
                            if store.versionsError[id] == nil { Row("Loading versions…", leading: { Spinner() }) }
                        } else {
                            let name = versions.first { $0.id == chosen }?.name
                            BlockButton(
                                name.map { "Install \($0)" } ?? "Get", role: .primary,
                                isLoading: store.installing.contains(id)
                            ) {
                                store.install(projectID: id, versionID: chosen)
                            }
                            .keyboardShortcut(.return, modifiers: .command)
                        }
                        if width > .compact {
                            HStack(spacing: 10) {
                                KeyHint("⌘ ↩", "install")
                                KeyHint("esc", "back to results")
                            }
                        }
                    }
                } else {
                    DetailPlaceholder()
                }
            }
            .task(id: "\(id)-\(store.modsInstance?.id ?? "")") { await store.loadProject(id) }
        }
    }

    /// The project's own icon, drawn blocky. The tinted ore stands in while it loads, or when there's no icon.
    struct ProjectIcon: View {
        let project: ProjectSummary, size: CGFloat
        var body: some View {
            Group {
                if let url = project.iconURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.interpolation(.none).resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .accessibilityHidden(true)
        }
        private var placeholder: some View {
            PixelIcon(.ore, size: size, tint: project.iconTintHex.map { Color(uiColor: UIColor(hex: $0)) })
        }
    }

    // MARK: M04 Installed

    public struct InstalledPane: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        @State private var kind = ContentKind.mods
        @State private var filter = ""
        @State private var updating = false
        public init() {}

        public var body: some View {
            let all = store.installed[kind] ?? []
            let items = all.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
            let updates = all.filter { $0.updateTo != nil }.count
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader("Installed") {
                    if let inst = store.modsInstance { Badge(inst.name, tone: inst.loader.tone) }
                }
                VStack(spacing: 8) {
                    Segmented(
                        "Content", selection: $kind,
                        options: [
                            (.mods, "Mods"), (.shaders, "Shaders"), (.resourcePacks, "Packs"), (.dataPacks, "Data"),
                        ])
                    HStack(spacing: 8) {
                        Field("Filter", text: $filter, kind: .search)
                        if updates > 0 {
                            BlockButton("Update \(updates)", role: .primary, size: .small, isLoading: updating) {
                                Task {
                                    updating = true
                                    await store.updateAll()
                                    updating = false
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 4)
                if all.isEmpty {
                    EmptyState(
                        kind == .mods ? "No mods yet" : "Nothing here yet", message: "Get them in Get mods.",
                        icon: .chest
                    ) {
                        // On wider windows Get mods is already beside this pane.
                        if width == .compact { BlockButton("Get mods", role: .primary) { nav.mod = nil } }
                    }
                } else if items.isEmpty {
                    EmptyState("No matches", message: "Try another name.", icon: .book)
                } else {
                    BlockList {
                        ForEach(items) { item in
                            InstalledRows(items: [item])
                                .swipeActions { Button("Delete", role: .destructive) { store.deleteItem(item) } }
                                .blockListRow(horizontal: width == .compact ? 16 : 20)
                        }
                    }
                    let on = all.filter(\.enabled).count
                    Text("\(on) on · \(all.count - on) off · swipe to delete").cofreFont(.label).foregroundStyle(
                        Color.cofre.muted
                    )
                    .padding(.horizontal, width == .compact ? 16 : 20).padding(.vertical, 8)
                }
            }
            .task(id: "\(kind)-\(store.modsInstance?.id ?? "")") { await store.loadInstalled(kind) }
        }
    }

    // MARK: M03 Import pack

    public struct ImportPackSheet: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.dismiss) private var dismiss
        @State private var picking = false
        public init() {}

        public var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Import pack")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ListSection(spacing: 4) {
                            Button {
                                picking = true
                            } label: {
                                ValueRow("From Files", value: ".mrpack · .zip")
                            }.buttonStyle(RowButtonStyle())
                            Button {
                                browse(.modrinth)
                            } label: {
                                ValueRow("Modrinth packs", value: "Browse")
                            }.buttonStyle(RowButtonStyle())
                            Button {
                                browse(.curseforge)
                            } label: {
                                ValueRow(
                                    "CurseForge packs",
                                    value: store.curseForgeKey == nil ? "Browse · needs key" : "Browse")
                            }.buttonStyle(RowButtonStyle())
                        }
                        DropZone(
                            "Drop a pack here", detail: ".mrpack · .zip", glyph: .chest, types: [.mrpack, .zip],
                            onDrop: { if let u = $0.first { store.importPack(u) } }, onChoose: { picking = true })
                        if let p = store.importProgress {
                            SectionLabel("Importing")
                            Row(
                                p.title, leading: { PixelIcon(.chest, size: 22) },
                                trailing: {
                                    if let inst = store.activeInstance {
                                        Badge(loader: inst.loader, version: inst.gameVersion)
                                    }
                                })
                            ProgressView(value: p.fraction).progressViewStyle(.xp())
                            if let d = p.detail {
                                Text(verbatim: d).cofreFont(.label).foregroundStyle(Color.cofre.muted)
                            }
                            ListSection(spacing: 4) {
                                ForEach(p.stages, id: \.title) { s in
                                    Row(
                                        s.title, leading: { StatusMark(state: s.state).frame(width: 14) },
                                        trailing: {
                                            Meta(
                                                s.state.isReady ? "OK" : (s.detail ?? ""),
                                                tone: s.state.isReady ? .success : nil)
                                        }
                                    )
                                    .dimmed(s.state == .unknown)
                                }
                            }
                            BlockButton(p.fraction >= 1 ? "Done" : "Hide · keep going") { dismiss() }
                        }
                    }
                    .padding(16)
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.mrpack, .zip]) { r in
                if case .success(let url) = r { store.importPack(url) }
            }
        }

        private func browse(_ source: ProjectSource) {
            store.query.source = source
            store.query.kind = .modpacks
            nav.section = .mods
            nav.mod = nil
            dismiss()
        }
    }
#endif
