#if canImport(UIKit)
    import SwiftUI

    // Draft · Instances: groups, favorites, notes and file-level lifecycle (duplicate, export, delete with undo).
    // The detail drops its Worlds and Mods tabs: each thing has one home (worlds in Play, content in Mods), and the
    // detail links there. Its second tab is Before you play (DraftBeforePlay.swift).
    // States: list (A: sections) · chips (B) · menu · detail · duplicate · export · undo. Wide: list + detail.

    struct InstancesDraft: View {
        let state: String, wide: Bool

        var body: some View {
            if wide {
                HStack(spacing: 0) {
                    let before = state == "beforePlay"
                    InstancesListDraft(
                        variant: state == "chips" ? .chips : .sections, selected: before ? "vanilla" : "survival"
                    )
                    .frame(width: 330)
                    .background(Color.cofre.side.opacity(0.55))
                    .overlay(alignment: .trailing) { Color.cofre.outline.frame(width: 2) }
                    InstanceDetailDraft(tab: before ? 1 : 0, instance: DraftData.instances[before ? 1 : 0])
                }
            } else {
                switch state {
                case "detail": InstanceDetailDraft(tab: 0).environment(\.isPushed, true)
                case "duplicate":
                    InstanceDetailDraft(tab: 0).environment(\.isPushed, true).draftSheet(true) { DuplicateSheet() }
                case "export":
                    InstanceDetailDraft(tab: 0).environment(\.isPushed, true).draftSheet(true) { ExportSheet() }
                case "undo":
                    InstancesListDraft(variant: .sections, hidden: "skyblock")
                        .overlay(alignment: .bottom) {
                            UndoToast(title: "Deleted Skyblock", detail: "A backup stays 7 days in Recently deleted")
                        }
                case "menu":
                    InstancesListDraft(variant: .sections)
                        .overlay(alignment: .topTrailing) {
                            NativeMenuMock(items: [
                                ("Play", "play.fill", false), ("Unfavorite", "star.slash", false),
                                ("Duplicate…", "plus.square.on.square", false),
                                ("Export…", "square.and.arrow.up", false), ("Show in Files", "folder", false),
                                ("Delete", "trash", true),
                            ])
                            .padding(.top, 196).padding(.trailing, 22)
                        }
                default: InstancesListDraft(variant: state == "chips" ? .chips : .sections)
                }
            }
        }
    }

    struct InstancesListDraft: View {
        enum Variant { case sections, chips }
        let variant: Variant
        var selected: String?
        var hidden: String?
        @Environment(\.widthClass) private var width
        @State private var search = ""
        @State private var group = "all"

        private var all: [DraftData.Instance] { DraftData.instances.filter { $0.id != hidden } }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader("Instances") { BlockButton("+ New", role: .primary, size: .small) {}.fixedSize() }
                VStack(spacing: 8) {
                    Field("Search", text: $search, kind: .search)
                    if variant == .chips {
                        ChipGroup(
                            "Group", selection: $group,
                            options: [
                                ("all", "All"), ("fav", "★ Favorites"), ("Modpacks", "Modpacks"),
                                ("Testing", "Testing"),
                            ])
                    }
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 4)
                DraftScroll {
                    if variant == .sections {
                        section("★ Favorites", all.filter(\.favorite))
                        section("Modpacks", all.filter { !$0.favorite && $0.group == "Modpacks" })
                        section("Testing", all.filter { !$0.favorite && $0.group == "Testing" })
                    } else {
                        ForEach(all.sorted { $0.favorite && !$1.favorite }) { row($0) }
                    }
                }
                HStack(spacing: 8) {
                    BlockButton("Import pack", icon: .chest) {}
                    BlockButton("Files", fullWidth: false) {}
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.vertical, 10)
            }
        }

        @ViewBuilder private func section(_ title: LocalizedStringKey, _ items: [DraftData.Instance]) -> some View {
            if !items.isEmpty {
                ListSection(title, spacing: 4) { ForEach(items) { row($0) } }
            }
        }

        private func row(_ inst: DraftData.Instance) -> some View {
            Row(inst.name, isSelected: inst.id == selected) {
                HStack(spacing: 6) {
                    Badge(loader: inst.loader, version: inst.game)
                    Text(verbatim: inst.line).cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(1)
                }
            } leading: {
                InstanceGlyph(icon: inst.icon, size: 30)
            } trailing: {
                HStack(spacing: 2) {
                    if inst.favorite && variant == .chips {
                        Text(verbatim: "★").foregroundStyle(Color.cofre.warn).accessibilityLabel(Text("Favorite"))
                    }
                    Meta("⋯").frame(minWidth: 36, minHeight: 44)
                }
            }
            .rowStyle(.big)
        }
    }

    // MARK: Instance detail

    struct InstanceDetailDraft: View {
        @State var tab: Int
        var state = ""
        var anchor: String?
        var instance = DraftData.instances[0]
        @Environment(\.widthClass) private var width
        @State private var notes = "Testing Create 6 here before I update the main world."
        @State private var group = "Modpacks"

        var body: some View {
            VStack(spacing: 0) {
                ColumnHeader(instance.name) {
                    BlockButton("★", size: .small, fullWidth: false) {}.accessibilityLabel(Text("Unfavorite"))
                    BlockButton("Play", icon: .play, role: .primary, size: .small) {}.fixedSize()
                }
                DraftScroll(anchor: anchor) {
                    PixelScene(seed: 4, pixels: .init(width: 200, height: 70))
                        .frame(height: width == .compact ? 96 : 130).clipped()
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: 4) {
                                InstanceGlyph(icon: instance.icon, size: 34).shadow(color: .black, radius: 0, y: 2)
                                Badge(loader: instance.loader, version: instance.game)
                                if instance.loader != .vanilla { Badge("Loader 0.16.14") }
                                Badge(instance.loader == .vanilla ? "Java 25" : "Java 21")
                            }
                            .padding(10)
                        }
                        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                    Segmented("Instance", selection: $tab, options: [(0, "Overview"), (1, "Before you play")])
                    if tab == 0 { overview } else { BeforePlayContent(state: state, instance: instance) }
                }
            }
        }

        @ViewBuilder private var overview: some View {
            AdaptiveGrid(minItem: 76) {
                Stat("142", label: "Mods")
                Stat("4.4 GB", label: "Size")
                Stat("4", label: "Worlds")
                Stat("2 h", label: "Played")
            }
            ListSection("In this instance", spacing: 4) {
                link("Worlds", "4 · Ironwood 2 h ago")
                link("Content", "142 mods · 6 packs")
                link("Servers", "3 saved")
            }
            GameOwnsNote("Each opens its own place: worlds and servers in Play, content in Mods.")
            ListSection("Group and notes", spacing: 4) {
                ControlRow("Group") {
                    SelectButton(
                        "Group", selection: $group,
                        options: [("Modpacks", "Modpacks"), ("Testing", "Testing"), ("", "None"), ("+", "New group…")]
                    )
                    .compactStyle()
                }
                TextField(text: $notes, prompt: Text("Notes for this instance"), axis: .vertical) { Text("Notes") }
                    .cofreFont(.secondary).foregroundStyle(Color.cofre.ink).tint(Color.cofre.accent)
                    .lineLimit(2...5)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .background(Color.cofre.well)
                    .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            }
            ListSection("Version", spacing: 4) {
                link("Minecraft", "1.21.1")
                link("Fabric loader", "0.16.14 · 0.17.2 out", accent: true)
            }
            ListSection("Manage", spacing: 4) {
                HStack(spacing: 8) {
                    BlockButton("Duplicate…") {}
                    BlockButton("Export…") {}
                }
                BlockButton("Delete instance", role: .ghostDestructive) {}
            }
        }

        private func link(_ title: LocalizedStringKey, _ value: String, accent: Bool = false) -> some View {
            Button {
            } label: {
                ValueRow(title, value: value, accent: accent)
            }
            .buttonStyle(RowButtonStyle())
        }
    }

    // MARK: Duplicate · Export (sheets)

    struct DuplicateSheet: View {
        @State private var name = "Survival+ copy"
        @State private var worlds = true
        @State private var options = true

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Duplicate")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Name")
                        Field("Name", text: $name)
                        ListSection("Copy", spacing: 4) {
                            Row("Mods, config and loader", trailing: { Meta("Always") })
                            ToggleRow("Worlds", subtitle: "4 worlds · 749 MB", isOn: $worlds)
                            ToggleRow("Game options", subtitle: "options.txt and controls", isOn: $options)
                        }
                        GameOwnsNote(
                            "Copies share space with the original until either one changes, so they're instant.")
                        Row("Uses now", trailing: { Meta("0 MB · 18.4 GB free", tone: .success) })
                        BlockButton("Duplicate", role: .primary) {}
                    }
                    .padding(16)
                }
            }
        }
    }

    struct ExportSheet: View {
        @State private var format = ExportFormat.mrpack
        @State private var worlds = false

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Export")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Segmented("Format", selection: $format, options: [(.mrpack, ".mrpack"), (.zip, ".zip")])
                        if format == .mrpack {
                            Row(
                                "Modrinth pack", subtitle: "Mod list and config. Others download the mods themselves.",
                                leading: { PixelIcon(.chest, size: 22) }, trailing: { Meta("2.1 MB") })
                            Row(
                                "Works in", subtitle: "Cofre, Modrinth App, Prism",
                                leading: { PixelIcon(.check, size: 14) })
                        } else {
                            Row(
                                "Full copy", subtitle: "Everything in the folder, for a backup or another device.",
                                leading: { PixelIcon(.chest, size: 22) }, trailing: { Meta("3.7 GB") })
                            ToggleRow("Include worlds", subtitle: "+ 749 MB", isOn: $worlds)
                        }
                        GameOwnsNote("Sign-in details and logs are never included.")
                        BlockButton("Export and share", icon: .paper, role: .primary) {}
                    }
                    .padding(16)
                }
            }
        }
    }
#endif
