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
        AdaptiveListDetail(selection: $nav.instance, defaultSelection: width == .compact ? nil : store.instances.first?.id) {
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
                    DropZone("Drop to import", detail: ".mrpack · .zip · new instance", glyph: .chest, types: [.mrpack, .zip], onDrop: { _ in }, onChoose: {})
                }
            }
            .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 4)
            BlockList {
                ForEach(shown) { inst in
                    let selected = width != .compact && (nav.instance ?? store.instances.first?.id) == inst.id
                    Button { nav.instance = inst.id } label: {
                        Row(inst.name, isSelected: selected) {
                            HStack(spacing: 6) {
                                Badge(loader: inst.loader, version: inst.gameVersion)
                                Text(verbatim: inst.sizeLine).cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(1)
                            }
                        } leading: {
                            InstanceGlyph(icon: inst.icon, size: 30)
                        } trailing: {
                            InstanceMenu(instance: inst) { Meta("⋯").frame(minWidth: 30, minHeight: 44) }
                        }
                        .rowStyle(.big)
                    }
                    .buttonStyle(RowButtonStyle())
                    .contextMenu { InstanceMenuItems(instance: inst) }
                    .swipeActions { Button("Delete", role: .destructive) { Task { await store.delete(inst.id) } } }
                    .blockListRow(horizontal: width == .compact ? 16 : 20)
                }
            }
            .onDrop(of: [.mrpack, .zip], isTargeted: $dropTargeted) { providers in
                _ = providers.first?.loadFileRepresentation(for: .zip) { url, _, _ in
                    if let url { let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.removeItem(at: copy); try? FileManager.default.copyItem(at: url, to: copy)
                        Task { @MainActor in store.importPack(copy); nav.sheet = .importPack } }
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
            if case .success(let url) = r { store.importPack(url); nav.sheet = .importPack }
        }
    }
}

/// Instance ⋯ menu: Play, Edit, Duplicate, Export, Delete (native menu).
struct InstanceMenu<Label: View>: View {
    let instance: InstanceSummary
    @ViewBuilder let label: () -> Label
    var body: some View {
        Menu { InstanceMenuItems(instance: instance) } label: { label() }
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
        Button("Edit") { nav.instance = instance.id; nav.section = .instances }
        Button("Duplicate") { Task { await store.duplicate(instance.id) } }
        Button("Export .mrpack") { Task { _ = await store.export(instance.id) } }
        Button("Delete", role: .destructive) { Task { await store.delete(instance.id) } }
    }
}

// MARK: I02 Instance detail

public struct InstanceDetailPane: View {
    let id: String
    @Environment(CofreStore.self) private var store
    @Environment(NavModel.self) private var nav
    @Environment(\.widthClass) private var width
    @State private var tab = 0
    @State private var confirmDelete = false
    @State private var exported: URL?

    public init(id: String) { self.id = id }

    public var body: some View {
        if let inst = store.instances.first(where: { $0.id == id }) {
            VStack(spacing: 0) {
                ColumnHeader(inst.name) {
                    InstanceMenu(instance: inst) {
                        Text(verbatim: "⋯").cofreFont(.buttonS).foregroundStyle(Color.cofre.ink)
                            .padding(.horizontal, 10).frame(minHeight: 30).block(.button, lip: 3)
                    }
                    BlockButton("Play", icon: .play, role: .primary, size: .small) { startLaunch(store, nav, instanceID: inst.id) }
                }
                PaneScroll {
                    PixelScene(seed: UInt32(abs(inst.id.hashValue) % 50), pixels: .init(width: 200, height: 70))
                        .frame(height: width == .compact ? 110 : 150).clipped()
                        .overlay(alignment: .bottomLeading) { InstanceGlyph(icon: inst.icon, size: 40).shadow(color: .black, radius: 0, y: 2).padding(14) }
                        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                    FlowBadges(inst: inst)
                    Segmented("Instance", selection: $tab, options: [
                        (0, "Overview"), (1, "Mods · \(inst.modCount ?? 0)"), (2, "Worlds · \(store.worlds.count)"), (3, "Options"),
                    ])
                    switch tab {
                    case 1: InstalledRows(items: store.installed[.mods] ?? [])
                    case 2: WorldRows(worlds: store.worlds, playFirst: false)
                    case 3: GameSettingsContent(instanceID: inst.id)
                    default: overview(inst)
                    }
                }
            }
            .task(id: id) { if store.activeInstanceID != id { await store.selectInstance(id) }; await store.loadPreferences(for: id) }
            .confirmationDialog("Delete \(inst.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete instance", role: .destructive) { Task { await store.delete(inst.id); nav.instance = nil } }
            } message: { Text("Worlds and mods in its folder are removed too.") }
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
            Button { nav.section = .settings; nav.settingsPane = .renderer } label: {
                ValueRow("Renderer", value: store.renderers.first { $0.id == prefs.renderer }?.name ?? prefs.renderer, accent: true)
            }.buttonStyle(RowButtonStyle())
            Button { tab = 3 } label: { ValueRow("Memory", value: Fmt.mb(prefs.ramMB)) }.buttonStyle(RowButtonStyle())
            ToggleRow("Own folder", isOn: .constant(inst.ownFolder))
        }
        BlockButton("Export .mrpack") { Task { exported = await store.export(inst.id) } }
        BlockButton("Duplicate") { Task { await store.duplicate(inst.id) } }.keyboardShortcut("d", modifiers: .command)
        BlockButton("Delete instance", role: .ghostDestructive) { confirmDelete = true }.keyboardShortcut(.delete, modifiers: .command)
        if let exported { ShareLink(item: exported) { Text("Share export").cofreFont(.button) }.buttonStyle(.block()) }
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

// MARK: P04 New instance

public struct NewInstanceSheet: View {
    @Environment(CofreStore.self) private var store
    @Environment(NavModel.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Survival+"
    @State private var kind = VersionKind.release
    @State private var versions: [GameVersion] = []
    @State private var version = "1.21.1"
    @State private var loader = Loader.fabric
    @State private var loaderVersions: [String] = []
    @State private var loaderVersion = ""
    @State private var ownFolder = true
    @State private var fabricAPI = true
    @State private var creating = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SheetHeader("New instance")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Name")
                    Field("Name", text: $name)
                    SectionLabel("Version")
                    SelectButton("Version", selection: $version, options: versions.map { ($0.id, $0.id) })
                    Segmented("Version type", selection: $kind, options: [(.release, "Release"), (.snapshot, "Snap"), (.old, "Old")], size: .small)
                    SectionLabel("Loader")
                    AdaptiveGrid(minItem: 96, maxColumns: 3) {
                        ForEach(Loader.allCases) { l in tile(l.displayName, glyph: l == .vanilla ? .stone : .ore, tint: l, on: loader == l) { loader = l } }
                        tile("From pack", glyph: .chest, tint: nil, on: false) { nav.sheet = .importPack }
                    }
                    ListSection(spacing: 4) {
                        if loader != .vanilla {
                            HStack {
                                Text("Loader version").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                                Spacer()
                                SelectButton("Loader version", selection: $loaderVersion, options: loaderVersions.map { ($0, $0) }).compactStyle()
                            }
                            .padding(.horizontal, 11).frame(minHeight: 44).block(.panel)
                        }
                        ToggleRow("Own folder", isOn: $ownFolder)
                        if loader == .fabric || loader == .quilt { ToggleRow("Add Fabric API", isOn: $fabricAPI) }
                        Row("Java", trailing: { Meta("Auto · 21") })
                    }
                    if loader.usesAirInstaller {
                        Banner("\(loader.displayName) installs with Air's installer next.", icon: .book, tone: .accent)
                    }
                    BlockButton("Create", role: .primary, isLoading: creating) { create() }
                        .disabled(name.isEmpty || version.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
        }
        .task(id: kind) {
            versions = (try? await store.backend.gameVersions(kind)) ?? []
            if !versions.contains(where: { $0.id == version }) { version = versions.first?.id ?? "" }
        }
        .task(id: "\(loader.rawValue)-\(version)") {
            loaderVersions = (try? await store.backend.loaderVersions(loader: loader, game: version)) ?? []
            loaderVersion = loaderVersions.first ?? ""
        }
    }

    private func tile(_ title: String, glyph: PixelGlyph, tint: Loader?, on: Bool, action: @escaping () -> Void) -> some View {
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
            let made = await store.createInstance(name: name, version: version, loader: loader, loaderVersion: loaderVersion)
            creating = false
            dismiss()
            if let made {
                nav.instance = made.id; nav.section = .instances
                if loader.usesAirInstaller, store.services.airScreens != nil { nav.showingAirScreen = .forgeInstaller(made.id) }
            }
        }
    }
}
#endif
