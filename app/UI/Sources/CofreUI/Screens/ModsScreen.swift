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
            content
                .blockSheet(item: installSheet, hugsContent: true) { route in
                    ModInstallSheet(id: route.id).environment(store).environment(nav)
                }
        }

        /// M05 Get sheet. Closing it tells the store, so finished Gets are forgotten.
        private var installSheet: Binding<ModInstallRoute?> {
            Binding(
                get: { store.modInstallSheet.map(ModInstallRoute.init) },
                set: { if $0 == nil, let open = store.modInstallSheet { store.closeModInstall(open) } })
        }

        @ViewBuilder private var content: some View {
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
                                    HStack(spacing: 5) {
                                        if let issue = ModCompatibility.entry(for: p.id, name: p.title)?.issue(gameVersion: store.modsInstance?.gameVersion ?? "", renderer: store.preferences.renderer == "auto" ? "metallum" : store.preferences.renderer) { Badge(issue.badge, tone: .warn) }
                                        GetButton(project: p) { endEditing() }
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
        /// Session-only. `nil` uses the target's defaults.
        @State private var filter: VersionFilter?
        @State private var showAll = false
        @Environment(\.showsAllVersions) private var startAll
        public init(id: String) { self.id = id }

        public var body: some View {
            let p = store.results.first { $0.id == id }
            let versions = store.versions[id] ?? []
            let have = p.flatMap { store.installedItem(for: $0) }
            let installed = have?.versionID.flatMap { v in versions.contains { $0.id == v } ? v : nil }
            let chosen = versionID ?? installed ?? versions.preferred?.id
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
                            if let issue = ModCompatibility.entry(for: p.id, name: p.title)?.issue(gameVersion: store.modsInstance?.gameVersion ?? "", renderer: store.preferences.renderer == "auto" ? "metallum" : store.preferences.renderer) { Badge(issue.badge, tone: .warn) }
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
                        versionList(versions, chosen: chosen, installed: installed)
                        let state = store.installState(p)
                        ForEach(chosen.flatMap { store.dependencies[$0] } ?? []) { d in
                            Row(
                                "\(d.required ? "Needs" : "Works with") \(d.name)",
                                subtitle: d.required ? "Dependency" : "Optional",
                                leading: { PixelIcon(.book, size: 18) },
                                trailing: {
                                    Meta(
                                        d.installed ? "Installed" : d.required ? "Adds" : "Offered",
                                        tone: d.installed ? .success : d.required ? .warn : nil)
                                })
                        }
                        if state == .notInstalled, let err = store.versionsError[id] {
                            Banner(String(localized: "Couldn't load versions"), icon: .cross, tone: .danger) {
                                BlockButton("Try again", size: .small, fullWidth: false) {
                                    Task { await store.loadProject(id) }
                                }
                            }
                            Text(verbatim: err).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                        }
                        let inst = store.modsInstance?.name ?? ""
                        let busy = store.modInstalls[id]?.isBusy == true
                        let picked = versions.first { $0.id == chosen }
                        switch state {
                        case .installed, .off, .update:
                            if state == .off {
                                Banner("Off in \(inst)", icon: .check, tone: .warn) {
                                    BlockButton("Turn on", size: .small, fullWidth: false) { turnOn(p) }
                                }
                            } else {
                                Banner("Installed in \(inst)", icon: .check, tone: .success)
                            }
                            // Another build picked by hand: switch to it, whatever its channel.
                            if let picked, versionID != nil, picked.id != installed {
                                BlockButton(Self.title("Switch to", picked), role: .primary, isLoading: busy) {
                                    store.get(id, versionID: picked.id)
                                }
                                .keyboardShortcut(.return, modifiers: .command)
                            } else if case .update(let to) = state {
                                BlockButton("Update to \(to)", role: .primary, isLoading: busy) { store.update(p) }
                                    .keyboardShortcut(.return, modifiers: .command)
                            }
                        case .notInstalled:
                            if store.versions[id] == nil {
                                if store.versionsError[id] == nil { Row("Loading versions…", leading: { Spinner() }) }
                            } else if let picked {
                                // Get takes the newest fitting release (else beta, else alpha) and says which.
                                let isDefault = picked.id == versions.preferred?.id
                                BlockButton(
                                    isDefault
                                        ? (picked.versionChannel == .release
                                            ? "Get" : "Get · \(picked.versionChannel.label.lowercased())")
                                        : Self.title("Install", picked),
                                    role: .primary, isLoading: busy
                                ) {
                                    store.get(id, versionID: picked.id)
                                }
                                .keyboardShortcut(.return, modifiers: .command)
                            }
                        }
                        if let issue = ModCompatibility.entry(for: p.id, name: p.title)?.issue(gameVersion: store.modsInstance?.gameVersion ?? "", renderer: store.preferences.renderer == "auto" ? "metallum" : store.preferences.renderer) { Banner(issue.title, icon: .cross, tone: .warn) }
                        if let picked {
                            ListSection("Details", spacing: 4) {
                                Row("Version", trailing: { Self.detail(picked.number) })
                                Row("ID", trailing: { Self.detail(picked.id) })
                            }
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
            .onAppear { if startAll { showAll = true } }
        }
    }

    extension EnvironmentValues {
        /// Previews and screenshots: M02 opens on All versions.
        @Entry public var showsAllVersions = false
    }

    /// M01 row trailing: ✓ when the target has it, Off, Update, or Get (spinning while a Get runs).
    struct GetButton: View {
        let project: ProjectSummary
        var willAct: () -> Void = {}
        @Environment(CofreStore.self) private var store

        var body: some View {
            let busy = store.modInstalls[project.id]?.isBusy == true
            switch busy ? .notInstalled : store.installState(project) {
            case .installed:
                Badge("✓", tone: .success).accessibilityLabel(Text("Installed"))
            case .off:
                Badge("Off").accessibilityLabel(Text("Installed, off"))
            case .update:
                BlockButton("Update", size: .small) {
                    willAct()
                    store.update(project)
                }
            case .notInstalled:
                BlockButton("Get", role: .primary, size: .small, isLoading: busy) { act() }
                    .accessibilityValue(progress.map { Text("\(Int($0 * 100)) percent") } ?? Text(""))
            }
        }

        private var progress: Double? { store.modInstalls[project.id]?.progress?.fraction }

        private func act() {
            willAct()
            store.get(project.id)
        }
    }

    extension ModPagePane {
        /// "Install 0.9.3 beta 1", "Switch to 0.9.2"; the channel is added when the label doesn't say it.
        static func title(_ verb: String, _ v: ProjectVersion) -> String {
            let c = v.versionChannel
            let says = c == .release || v.name.lowercased().contains(c.raw)
            return "\(verb) \(v.name)" + (says ? "" : " · \(c.label.lowercased())")
        }

        /// M02 versions: filtered to the target by default, with a one-tap way to see the rest.
        @ViewBuilder fileprivate func versionList(_ versions: [ProjectVersion], chosen: String?, installed: String?)
            -> some View
        {
            let f = filter ?? .defaults(for: store.modsInstance)
            let shown = f.visible(versions, installed: installed, all: showAll)
            let hidden = versions.count - shown.count
            ListSection("Versions", spacing: 4) {
                if !versions.isEmpty {
                    VersionFilterBar(versions: versions, filter: Binding(get: { f }, set: { filter = $0 }))
                        .disabled(showAll)
                }
                ForEach(shown) { v in
                    Button {
                        versionID = v.id
                    } label: {
                        Row(v.name, subtitle: Self.subtitle(v), isSelected: chosen == v.id) {
                            Radio(isOn: chosen == v.id)
                        } trailing: {
                            HStack(spacing: 4) {
                                if v.id == installed { Badge("Installed", tone: .success) }
                                if !v.fits {
                                    Badge("No fit", tone: .danger)
                                } else if v.versionChannel != .release || v.id != installed {
                                    Badge(v.versionChannel.label, tone: Self.tone(v.versionChannel))
                                }
                            }
                        }
                        .dimmed(!v.fits)
                    }
                    .buttonStyle(RowButtonStyle())
                    .disabled(!v.fits)
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
        }

        static func detail(_ value: String) -> some View {
            Text(verbatim: value).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
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

        fileprivate func turnOn(_ p: ProjectSummary) {
            guard let item = store.installed[store.query.kind]?.first(where: { $0.matches(p.id, title: p.title) })
            else { return }
            store.setEnabled(true, item: item)
        }
    }

    /// M02 filter menus: Loader, Game version, Channel. Native menus; the labels say what's on.
    struct VersionFilterBar: View {
        let versions: [ProjectVersion]
        @Binding var filter: VersionFilter

        var body: some View {
            let loaders = Loader.allCases.filter { l in versions.contains { $0.loaders.contains(l) } }
            let games = Self.gameOrder(Set(versions.flatMap(\.games)))
            HStack(spacing: 6) {
                if !loaders.isEmpty {
                    menu(filter.loaders.isEmpty ? String(localized: "Any loader") : loaderLabel) {
                        Toggle("Any loader", isOn: set(\.loaders, to: []))
                        ForEach(loaders) { l in Toggle(l.displayName, isOn: set(\.loaders, to: [l])) }
                    }
                }
                menu(filter.games.count == 1 ? filter.games.first! : String(localized: "Any version")) {
                    Toggle("Any version", isOn: set(\.games, to: []))
                    ForEach(games, id: \.self) { g in Toggle(g, isOn: set(\.games, to: [g])) }
                }
                menu(channelLabel) {
                    ForEach(VersionChannel.allCases, id: \.self) { c in
                        Toggle(
                            c.label,
                            isOn: Binding(
                                get: { filter.channels.contains(c) },
                                set: { on in
                                    if on { filter.channels.insert(c) } else if filter.channels.count > 1 {
                                        filter.channels.remove(c)
                                    }
                                }))
                    }
                }
                Spacer(minLength: 0)
            }
        }

        private var loaderLabel: String {
            Loader.allCases.filter { filter.loaders.contains($0) }.map(\.displayName).joined(separator: " + ")
        }
        private var channelLabel: String {
            filter.channels.count == VersionChannel.allCases.count
                ? String(localized: "Any channel")
                : filter.channels.sorted().map(\.label).joined(separator: " + ")
        }

        /// A single-choice item: on when the filter is exactly `value`.
        private func set<T: Equatable>(_ key: WritableKeyPath<VersionFilter, T>, to value: T) -> Binding<Bool> {
            Binding(get: { filter[keyPath: key] == value }, set: { if $0 { filter[keyPath: key] = value } })
        }

        private func menu<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
            Menu {
                content()
            } label: {
                Text(verbatim: "\(title) ▾").cofreFont(.label).foregroundStyle(Color.cofre.ink).lineLimit(1)
                    .padding(.horizontal, 10).frame(minHeight: 32)
                    .block(.button, lip: 3)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .blockPointer()
        }

        /// Newest game version first: "26.3", "1.21.1", "1.21", "1.20.4".
        static func gameOrder(_ games: Set<String>) -> [String] {
            games.sorted { a, b in
                let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
                return x.lexicographicallyPrecedes(y) == false && x != y
            }
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
