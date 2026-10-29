#if canImport(UIKit)
    import SwiftUI
    import UniformTypeIdentifiers

    // P03 Instances list · I02 Instance detail · P04 New instance. AdaptiveListDetail: push on compact, columns on regular.

    public struct InstancesSection: View {
        @Environment(NavModel.self) private var nav
        @Environment(CofreStore.self) private var store
        @Environment(\.widthClass) private var width
        public init() {}
        public var body: some View {
            @Bindable var nav = nav
            AdaptiveListDetail(
                selection: $nav.instance, defaultSelection: width == .compact ? nil : store.instances.first?.id
            ) {
                InstancesListPane()
            } detail: { id in
                InstanceDetailPane(id: id)
            }
        }
    }

    public struct InstancesListPane: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        @State private var search = ""
        @State private var dropTargeted = false
        @State private var pickingPack = false
        public init() {}

        public var body: some View {
            let shown = store.instances.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader("Instances") {
                    BlockButton("+ New", role: .primary, size: .small) { nav.sheet = .newInstance }
                }
                VStack(spacing: 8) {
                    Field("Search", text: $search, kind: .search)
                    if dropTargeted {
                        // The drop itself is handled by the list's onDrop below.
                        DropZone(
                            "Drop to import", detail: ".mrpack · .zip · new instance", glyph: .chest,
                            types: [.mrpack, .zip],
                            onDrop: { _ in }, onChoose: { pickingPack = true })
                    }
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 4)
                Group {
                    if !store.libraryLoaded {
                        Row("Loading instances…", leading: { Spinner() }).padding(
                            .horizontal, width == .compact ? 16 : 20)
                        Spacer(minLength: 0)
                    } else if store.instances.isEmpty {
                        EmptyState("No instances yet", message: "Make one, or import a modpack.", icon: .grass) {
                            BlockButton("New instance", role: .primary) { nav.sheet = .newInstance }
                        }
                    } else if shown.isEmpty {
                        EmptyState("No matches", message: "Try another name.", icon: .book)
                    } else {
                        list(shown)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .onDrop(of: [.mrpack, .zip], isTargeted: $dropTargeted) { providers in
                    _ = providers.first?.loadFileRepresentation(for: .zip) { url, _, _ in
                        if let url {
                            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(
                                url.lastPathComponent)
                            try? FileManager.default.removeItem(at: copy)
                            try? FileManager.default.copyItem(at: url, to: copy)
                            Task { @MainActor in
                                store.importPack(copy)
                                nav.sheet = .importPack
                            }
                        }
                    }
                    return true
                }
                if !dropTargeted {
                    HStack(spacing: 8) {
                        BlockButton("Import pack", icon: .chest) { nav.sheet = .importPack }
                        BlockButton("Files", fullWidth: false) { pickingPack = true }
                    }
                    .padding(.horizontal, width == .compact ? 16 : 20).padding(.vertical, 10)
                }
            }
            .fileImporter(isPresented: $pickingPack, allowedContentTypes: [.mrpack, .zip]) { r in
                if case .success(let url) = r {
                    store.importPack(url)
                    nav.sheet = .importPack
                }
            }
        }

        private func list(_ shown: [InstanceSummary]) -> some View {
            BlockList {
                ForEach(shown) { inst in
                    let selected = width != .compact && (nav.instance ?? store.instances.first?.id) == inst.id
                    Button {
                        nav.instance = inst.id
                    } label: {
                        Row(inst.name, isSelected: selected) {
                            HStack(spacing: 6) {
                                Badge(loader: inst.loader, version: inst.gameVersion)
                                Text(verbatim: inst.sizeLine).cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                                    .lineLimit(1)
                            }
                        } leading: {
                            InstanceGlyph(icon: inst.icon, size: 30)
                        } trailing: {
                            InstanceMenu(instance: inst) {
                                Meta("⋯").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                            }
                        }
                        .rowStyle(.big)
                    }
                    .buttonStyle(RowButtonStyle())
                    .contextMenu { InstanceMenuItems(instance: inst) }
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.pendingConfirmation = .deleteInstance(inst) }
                    }
                    .blockListRow(horizontal: width == .compact ? 16 : 20)
                }
            }
        }
    }

    /// Instance ⋯ menu: Play, Edit, Duplicate, Export, Delete (native menu).
    struct InstanceMenu<Label: View>: View {
        let instance: InstanceSummary
        @ViewBuilder let label: () -> Label
        var body: some View {
            Menu {
                InstanceMenuItems(instance: instance)
            } label: {
                label()
            }
            .menuStyle(.button).buttonStyle(.plain)
            .accessibilityLabel(Text("More for \(instance.name)"))
        }
    }

    struct InstanceMenuItems: View {
        let instance: InstanceSummary
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        var body: some View {
            Button("Play") { startLaunch(store, nav, instanceID: instance.id) }
            Button("Edit") {
                nav.instance = instance.id
                nav.section = .instances
            }
            Button("Duplicate") { Task { await store.duplicate(instance.id) } }
            Button("Export .mrpack") {
                Task { if let url = await store.export(instance.id) { presentShareSheet(url) } }
            }
            Button("Delete", role: .destructive) { store.pendingConfirmation = .deleteInstance(instance) }
        }
    }

    // MARK: I02 Instance detail

    public struct InstanceDetailPane: View {
        let id: String
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        @State private var tab = 0
        @State private var exported: URL?

        public init(id: String) { self.id = id }

        public var body: some View {
            if let inst = store.instances.first(where: { $0.id == id }) {
                VStack(spacing: 0) {
                    ColumnHeader(inst.name) {
                        InstanceMenu(instance: inst) {
                            Text(verbatim: "⋯").cofreFont(.buttonS).foregroundStyle(Color.cofre.ink)
                                .padding(.horizontal, 10).frame(minHeight: 30).block(.button, lip: 3)
                                .contentShape(Rectangle().inset(by: -7))
                        }
                        BlockButton("Play", icon: .play, role: .primary, size: .small) {
                            startLaunch(store, nav, instanceID: inst.id)
                        }
                    }
                    PaneScroll {
                        PixelScene(seed: inst.stableSeed, pixels: .init(width: 200, height: 70))
                            .frame(height: width == .compact ? 110 : 150).clipped()
                            .overlay(alignment: .bottomLeading) {
                                InstanceGlyph(icon: inst.icon, size: 40).shadow(color: .black, radius: 0, y: 2).padding(
                                    14)
                            }
                            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                        FlowBadges(inst: inst)
                        Segmented(
                            "Instance", selection: $tab,
                            options: [
                                (0, "Overview"), (1, "Mods · \(inst.modCount ?? 0)"),
                                (2, "Worlds · \(store.worlds.count)"), (3, "Options"),
                            ])
                        switch tab {
                        case 1: InstalledRows(items: store.installed[.mods] ?? [])
                        case 2: WorldRows(worlds: store.worlds, playFirst: false)
                        case 3: GameSettingsContent(instanceID: inst.id)
                        default: overview(inst)
                        }
                    }
                }
                .task(id: id) {
                    if store.activeInstanceID != id { await store.selectInstance(id) }
                    await store.loadPreferences(for: id)
                }
            } else {
                DetailPlaceholder()
            }
        }

        @ViewBuilder private func overview(_ inst: InstanceSummary) -> some View {
            let prefs = store.preferences(for: inst.id)
            AdaptiveGrid(minItem: 110) {
                Stat("\(inst.modCount ?? 0)", label: "Mods")
                Stat(Fmt.bytes(inst.sizeBytes) ?? "—", label: "Size")
                Stat("\(inst.updatesAvailable)", label: "Updates", tone: inst.updatesAvailable > 0 ? .warn : .neutral)
                Stat(Fmt.ago(inst.lastPlayed) ?? "—", label: "Played")
            }
            ListSection("Instance", spacing: 4) {
                if inst.loader != .vanilla {
                    Row("Loader version", trailing: { Meta(inst.loaderVersion ?? "—") })
                }
                Button {
                    nav.section = .settings
                    nav.settingsPane = .renderer
                } label: {
                    ValueRow(
                        "Renderer", value: store.renderers.first { $0.id == prefs.renderer }?.name ?? prefs.renderer,
                        accent: true)
                }.buttonStyle(RowButtonStyle())
                Button {
                    tab = 3
                } label: {
                    ValueRow("Memory", value: prefs.autoRAM ? String(localized: "Auto") : Fmt.mb(prefs.ramMB))
                }
                .buttonStyle(RowButtonStyle())
            }
            BlockButton("Export .mrpack") { Task { exported = await store.export(inst.id) } }
            BlockButton("Duplicate") { Task { await store.duplicate(inst.id) } }.keyboardShortcut(
                "d", modifiers: .command)
            BlockButton("Delete instance", role: .ghostDestructive) {
                store.pendingConfirmation = .deleteInstance(inst)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            if let exported {
                ShareLink(item: exported) { Text("Share export").cofreFont(.button) }.buttonStyle(.block())
            }
        }
    }

    private struct FlowBadges: View {
        let inst: InstanceSummary
        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { badges }
                VStack(alignment: .leading, spacing: 4) { badges }
            }
        }
        @ViewBuilder private var badges: some View {
            Badge(loader: inst.loader, version: inst.gameVersion)
            if let v = inst.loaderVersion { Badge("Loader \(v)") }
            if let j = inst.javaVersion { Badge("Java \(j)") }
            if inst.ownFolder { Badge("Own folder") }
        }
    }

    extension InstanceSummary {
        /// Same art on every launch (`hashValue` is seeded per process).
        var stableSeed: UInt32 { id.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31 &+ $1.value) } % 50 }
    }

    // MARK: P04 New instance

    public struct NewInstanceSheet: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.dismiss) private var dismiss
        @State private var name = "Survival+"
        @State private var kind = VersionKind.release
        @State private var versions: [GameVersion] = []
        @State private var versionsFailed = false
        @State private var versionsAttempt = 0
        @State private var version = "1.21.1"
        @State private var loader = Loader.fabric
        @State private var loaderVersions: [String] = []
        @State private var loaderVersion = ""
        @State private var ownFolder = true
        @State private var fabricAPI = true
        @State private var creating = false
        /// From Mods: pre-fills the form, then makes the new instance the one Mods (and Play) works on.
        private let plan: NewInstancePlan?

        public init(plan: NewInstancePlan? = nil) {
            self.plan = plan
            if let plan {
                _name = State(initialValue: plan.name)
                _loader = State(initialValue: plan.loader)
                // Empty: the newest release, once the list loads.
                _version = State(initialValue: plan.version)
            }
        }

        public var body: some View {
            VStack(spacing: 0) {
                SheetHeader("New instance")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Name")
                        Field("Name", text: $name)
                        SectionLabel("Version")
                        if versionsFailed {
                            Banner("Couldn't load versions", icon: .cross, tone: .danger) {
                                BlockButton("Try again", size: .small) { versionsAttempt += 1 }
                            }
                        } else {
                            SelectButton("Version", selection: $version, options: versions.map { ($0.id, $0.id) })
                        }
                        Segmented(
                            "Version type", selection: $kind,
                            options: [(.release, "Release"), (.snapshot, "Snap"), (.old, "Old")], size: .small)
                        SectionLabel("Loader")
                        AdaptiveGrid(minItem: 96, maxColumns: 3) {
                            ForEach(Loader.allCases) { l in
                                tile(l.displayName, glyph: l == .vanilla ? .stone : .ore, tint: l, on: loader == l) {
                                    loader = l
                                }
                            }
                            tile("From pack", glyph: .chest, tint: nil, on: false) { nav.sheet = .importPack }
                        }
                        ListSection(spacing: 4) {
                            if loader != .vanilla {
                                HStack {
                                    Text("Loader version").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                                    Spacer()
                                    SelectButton(
                                        "Loader version", selection: $loaderVersion,
                                        options: loaderVersions.map { ($0, $0) }
                                    ).compactStyle()
                                }
                                .padding(.horizontal, 11).frame(minHeight: 44).block(.panel)
                            }
                            if store.can(.createOptions) {
                                ToggleRow("Own folder", isOn: $ownFolder)
                                if loader == .fabric || loader == .quilt {
                                    ToggleRow("Add Fabric API", isOn: $fabricAPI)
                                }
                            }
                            Row("Java", trailing: { Meta("Auto") })
                        }
                        if creating, loader != .vanilla, !loaderVersion.isEmpty {
                            Row("Installing \(loader.displayName) \(loaderVersion)…", leading: { Spinner() })
                        }
                        BlockButton("Create", role: .primary, isLoading: creating) { create() }
                            .disabled(name.isEmpty || version.isEmpty)
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(16)
                }
            }
            .onDisappear { store.newInstancePlan = nil }
            .task(id: "\(kind.rawValue)-\(versionsAttempt)") {
                do {
                    versions = try await store.backend.gameVersions(kind)
                    versionsFailed = false
                } catch is CancellationError { return } catch {
                    versions = []
                    versionsFailed = true
                }
                if !versions.contains(where: { $0.id == version }) { version = versions.first?.id ?? "" }
            }
            .task(id: "\(loader.rawValue)-\(version)") {
                loaderVersions = (try? await store.backend.loaderVersions(loader: loader, game: version)) ?? []
                loaderVersion = loaderVersions.first ?? ""
            }
        }

        private func tile(_ title: String, glyph: PixelGlyph, tint: Loader?, on: Bool, action: @escaping () -> Void)
            -> some View
        {
            Button(action: action) {
                VStack(spacing: 6) {
                    PixelIcon(glyph, size: 24, tint: tint.map { Color.cofre.tone($0.tone) })
                    Text(verbatim: title).cofreFont(.buttonS).foregroundStyle(Color.cofre.ink)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .block(on ? .raised : .panel, selected: on)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .blockHover()
            .accessibilityAddTraits(on ? .isSelected : [])
        }

        private func create() {
            creating = true
            Task {
                let made = await store.createInstance(
                    name: name, version: version, loader: loader, loaderVersion: loaderVersion,
                    ownFolder: ownFolder, fabricAPI: fabricAPI)
                creating = false
                // On failure the sheet stays open; the error shows in the banner.
                guard let made else { return }
                dismiss()
                if plan != nil {
                    // From Mods: stay there, on the new instance.
                    await store.selectInstance(made.id)
                } else {
                    nav.instance = made.id
                    nav.section = .instances
                }
            }
        }
    }
#endif
