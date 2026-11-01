#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers
    import CofreKit

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
        @Environment(\.dynamicTypeSize) private var typeSize
        @State private var showFilters = false
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
                    // Large text puts the two buttons on their own row under the field.
                    let row = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 8)) : AnyLayout(HStackLayout(spacing: 6))
                    row {
                        Field("Search mods", text: $store.query.text, kind: .search)
                            .keyboardShortcut("f", modifiers: .command)
                        HStack(spacing: 6) {
                            ModsSourceButton()
                            BlockButton(activeFilters > 0 ? "Filters · \(activeFilters)" : "Filters", size: .small) {
                                showFilters = true
                            }
                            .fixedSize()
                            .accessibilityLabel(Text("Filters"))
                            .accessibilityValue(Text("\(activeFilters) active"))
                        }
                    }
                    ChipGroup(
                        "Type", selection: $store.query.kind,
                        options: [
                            (.mods, "Mods"), (.modpacks, "Packs"), (.shaders, "Shaders"), (.resourcePacks, "Resource"),
                        ])
                    if let summary = ModsFiltersSheet.summary(store) {
                        Button { showFilters = true } label: {
                            Text(verbatim: summary).cofreFont(.secondary).foregroundStyle(Color.cofre.muted).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Opens filters"))
                    }
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
                    EmptyState("No results", message: "Try another name.", icon: .book) {
                        if activeFilters > 0 {
                            BlockButton("Clear filters", role: .primary) { store.query.filters = .cleared }
                        }
                    }
                } else {
                    BlockList {
                        ForEach(store.results) { p in
                            let selected = width != .compact && nav.mod == .project(p.id)
                            Button {
                                endEditing()
                                nav.mod = .project(p.id)
                            } label: {
                                ModRow(
                                    title: p.title, subtitle: "\(p.summary) · \(Fmt.count(p.downloads))",
                                    icon: .remote(p.iconURL, tint: p.iconTintHex), isSelected: selected,
                                    badges: (p.fits ? [] : [ModBadge("Other version", tone: .warn)])
                                        + (store.compatibilityIssue(id: p.id, name: p.title, kind: store.query.kind)
                                            .map { [ModBadge($0.badge, tone: .warn)] } ?? [])
                                ) {
                                    GetButton(project: p) { endEditing() }
                                }
                            }
                            .buttonStyle(RowButtonStyle())
                            .blockListRow(horizontal: width == .compact ? 16 : 20)
                            // Ten rows before the end, fetch the next page so scrolling doesn't stop.
                            .onAppear {
                                if store.hasMoreResults, store.results.suffix(10).contains(where: { $0.id == p.id }) {
                                    Task { await store.loadMoreResults() }
                                }
                            }
                        }
                        if store.loadingMoreResults {
                            Spinner().frame(maxWidth: .infinity).padding(.vertical, 12)
                                .blockListRow()
                                .accessibilityLabel(Text("Loading more"))
                        }
                    }
                }
            }
            // Scrolling the results or tapping outside the field closes the keyboard.
            .scrollDismissesKeyboard(.immediately)
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { endEditing() } }
            .task(id: store.query) {
                // This also runs when the list comes back from a mod page; its results and scroll position stay.
                guard store.searchedQuery != store.query else { return }
                // Debounce: a keystroke cancels the wait, and the old text is never searched.
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                await store.search()
            }
            .onChange(of: store.results.count) { _, count in
                AccessibilityNotification.Announcement(
                    count == 1 ? String(localized: "1 result") : String(localized: "\(count) results")
                ).post()
            }
            .blockSheet(isPresented: $showFilters, hugsContent: true) { ModsFiltersSheet().environment(store) }
        }

        private var activeFilters: Int {
            let inst = store.modsInstance
            return store.query.filters.activeCount(
                store.query.kind, source: store.query.source, game: inst?.gameVersion ?? "", loader: inst?.loader ?? .unknown)
        }

        private func endEditing() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
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

    enum ModIconSource {
        case remote(URL?, tint: UInt32? = nil)
        case local(Data, key: String)
        case placeholder(UInt32? = nil)
    }

    struct ModBadge: Identifiable {
        let id = UUID()
        let title: String, tone: Tone
        init(_ title: String, tone: Tone) { self.title = title; self.tone = tone }
    }

    /// One mod row for search and Installed. The trailing control is supplied by the caller so the row keeps one
    /// visual voice while its action remains a page push or an isolated on/off switch.
    struct ModRow<Trailing: View>: View {
        let title: String, subtitle: String, icon: ModIconSource, isSelected: Bool, badges: [ModBadge]
        let trailing: Trailing
        init(
            title: String, subtitle: String, icon: ModIconSource, isSelected: Bool = false, badges: [ModBadge] = [],
            @ViewBuilder trailing: () -> Trailing
        ) {
            self.title = title; self.subtitle = subtitle; self.icon = icon; self.isSelected = isSelected
            self.badges = badges; self.trailing = trailing()
        }
        var body: some View {
            Row(title, isSelected: isSelected, subtitleView: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: subtitle).cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(1)
                    if !badges.isEmpty {
                        HStack(spacing: 4) { ForEach(badges) { Badge($0.title, tone: $0.tone) } }
                    }
                }
            }, leading: { ModIcon(source: icon, size: 40) }, trailing: { trailing })
        }
    }

    struct ModIcon: View {
        let source: ModIconSource, size: CGFloat
        var body: some View {
            Group {
                switch source {
                case .remote(let url, let tint):
                    if let url { RemoteImage(url: url, maxPoints: size, contentMode: .fill, pixelated: true) { placeholder(tint) } }
                    else { placeholder(tint) }
                case .local(let data, let key): LocalModImage(data: data, key: key, size: size) { placeholder(nil) }
                case .placeholder(let tint): placeholder(tint)
                }
            }
            .frame(width: size, height: size).clipped()
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .accessibilityHidden(true)
        }
        private func placeholder(_ tint: UInt32?) -> some View {
            PixelIcon(.ore, size: size, tint: tint.map { Color(uiColor: UIColor(hex: $0)) })
        }
    }

    /// Compatibility wrapper for project pages and install sheets.
    struct ProjectIcon: View {
        let project: ProjectSummary, size: CGFloat
        var body: some View {
            ModIcon(source: .remote(project.iconURL, tint: project.iconTintHex), size: size)
        }
    }

    private struct LocalModImage<Placeholder: View>: View {
        let data: Data, key: String, size: CGFloat
        @ViewBuilder let placeholder: () -> Placeholder
        @Environment(\.displayScale) private var scale
        @State private var image: UIImage?
        var body: some View {
            Group {
                if let image { Image(uiImage: image).interpolation(.none).resizable().aspectRatio(contentMode: .fill) }
                else { placeholder() }
            }
            .task(id: key) {
                image = await ImagePipeline.shared.image(data, key: key, maxPixels: Int((size * scale).rounded(.up)))
            }
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
        @State private var removal: ModRemovalRequest?
        @State private var localDetails: InstalledItem?
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
                                    await store.updateAll(kind: kind)
                                    updating = false
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 4)
                if all.isEmpty {
                    EmptyState(
                        kind == .mods ? "No mods yet" : "Nothing here yet",
                        message: kind == .dataPacks ? "Data packs live in each world's datapacks folder." : "Get them in Get mods.",
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
                            InstalledRows(items: [item], onRemove: requestRemoval, onOpenLocal: { localDetails = $0 })
                                .swipeActions { Button("Delete", role: .destructive) { requestRemoval(item) } }
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
            .blockSheet(item: $removal, hugsContent: true) { request in
                ModRemovalSheet(request: request).environment(store)
            }
            .blockSheet(item: $localDetails, hugsContent: true) { item in
                InstalledDetailsSheet(item: item)
            }
        }

        private func requestRemoval(_ item: InstalledItem) {
            let options = store.removalOptions(for: item)
            if options.isEmpty { store.deleteItem(item) }
            else { removal = ModRemovalRequest(item: item, options: options) }
        }
    }

    struct ModRemovalRequest: Identifiable {
        let id = UUID()
        let item: InstalledItem
        let options: [InstalledItem]
    }

    struct ModRemovalSheet: View {
        let request: ModRemovalRequest
        @Environment(CofreStore.self) private var store
        @Environment(\.dismiss) private var dismiss
        @State private var selected: Set<String>

        init(request: ModRemovalRequest) {
            self.request = request
            _selected = State(initialValue: Set(request.options.map(\.id)))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader("Remove \(request.item.name)?")
                Text("Also remove \(request.options.count) mods only \(request.item.name) used? · \(request.options.map(\.name).joined(separator: ", "))")
                    .cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                VStack(spacing: 4) {
                    ForEach(request.options) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        } label: {
                            HStack(spacing: 10) {
                                if selected.contains(item.id) { PixelIcon(.check, size: 18) }
                                else { Rectangle().strokeBorder(Color.cofre.muted, lineWidth: 2).frame(width: 16, height: 16) }
                                Text(verbatim: item.name).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                                Spacer()
                            }
                            .padding(10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(item.name))
                        .accessibilityValue(Text(selected.contains(item.id) ? "Selected" : "Not selected"))
                    }
                }
                HStack(spacing: 8) {
                    BlockButton("Keep them") { dismiss() }
                    BlockButton("Remove", role: .destructive) {
                        let chosen = store.removalItems(for: request.item, selectedIDs: selected)
                        store.deleteItems([request.item] + chosen)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    struct InstalledDetailsSheet: View {
        let item: InstalledItem
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader("Mod details")
                ListSection("Details", spacing: 4) {
                    Row("Name", trailing: { Text(verbatim: item.name).cofreFont(.label) })
                    Row("Version", trailing: { Text(verbatim: VersionLabel.clean(item.version)).cofreFont(.label) })
                    Row("File", trailing: { Text(verbatim: item.id).cofreFont(.code).lineLimit(1) })
                    if let loader = item.loader { Row("Loader", trailing: { Text(verbatim: loader).cofreFont(.label) }) }
                    if let modID = item.modID { Row("Mod ID", trailing: { Text(verbatim: modID).cofreFont(.code) }) }
                    let dependencies = item.dependencies.map(\.name) + item.needs.map(\.name)
                    if !dependencies.isEmpty {
                        Row("Needs", trailing: {
                            Text(verbatim: Array(Set(dependencies)).sorted().joined(separator: ", ")).cofreFont(.label)
                        })
                    }
                }
                BlockButton("Done", role: .primary) { dismiss() }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    // MARK: M03 Import pack

    public struct ImportPackSheet: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.dismiss) private var dismiss
        @State private var picking = false
        @State private var link = ""
        public init() {}

        /// A pasted Modrinth page or `.mrpack`/`.zip` link; the backend says what's wrong with any other https link.
        private var linkURL: URL? {
            let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: text.contains("://") ? text : "https://" + text), url.scheme == "https",
                url.host()?.contains(".") == true
            else { return nil }
            return url
        }

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
                        HStack(alignment: .top, spacing: 8) {
                            Field("Link", text: $link, prompt: "Modrinth page or .mrpack link", kind: .mono)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .submitLabel(.go).onSubmit(importLink)
                            BlockButton("Import", role: .primary, fullWidth: false, action: importLink)
                                .disabled(linkURL == nil).padding(.top, 3)
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
            // Keyed by the file, so "Open in Cofre" while this sheet is already up still imports.
            .task(id: nav.pendingFile) { if let url = nav.pendingFile { nav.pendingFile = nil; store.importPack(url) } }
        }

        private func importLink() {
            guard let url = linkURL else { return }
            link = ""
            store.importPack(url)
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
