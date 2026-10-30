#if canImport(UIKit)
    import SwiftUI

    // Draft · Worlds (Play → Worlds). A list read straight from saves/: icon, name, mode, last played, size, and
    // Play to jump straight in. The context menu holds the file work: back up, export, copy to an instance, delete
    // with undo. No "New world" and no world settings: the game owns those.
    // States: list · menu · backups · copy · undo · empty.

    struct WorldsDraft: View {
        let state: String
        @Environment(\.widthClass) private var width
        @State private var autoBackup = true

        private var worlds: [DraftData.World] { DraftData.worlds.filter { state != "undo" || $0.id != "w4" } }

        var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Worlds") { BlockButton("Import", size: .small) {}.fixedSize() }
                    .environment(\.columnHeaderAccessory, width == .compact ? AnyView(PlayPanePicker(pane: 1)) : nil)
                if state == "empty" {
                    EmptyState(
                        "No worlds yet", message: "Make a world in the game and it shows up here. Or import one.",
                        icon: .grass
                    ) {
                        BlockButton("Import a world", role: .primary) {}
                    }
                } else {
                    DraftScroll {
                        Text("Survival+ · 4 worlds · 749 MB").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                        ForEach(Array(worlds.enumerated()), id: \.element.id) { i, w in
                            WorldCardRow(world: w) {
                                BlockButton(
                                    "Play", icon: i == 0 ? .play : nil, role: i == 0 ? .primary : .secondary,
                                    size: .small
                                ) {}
                            }
                            .contextMenu {
                                Button("Back up now", systemImage: "clock.arrow.circlepath") {}
                                Button("Export…", systemImage: "square.and.arrow.up") {}
                                Button("Copy to instance…", systemImage: "plus.square.on.square") {}
                                Button("Delete", systemImage: "trash", role: .destructive) {}
                            }
                        }
                        GameOwnsNote(
                            "New worlds, world settings and game rules are in the game. Changes there show up here.")
                        ListSection("Backups", spacing: 4) {
                            ValueRow("All backups", value: "5 · 1.1 GB")
                            ToggleRow("Back up before updates and deletes", isOn: $autoBackup)
                        }
                    }
                }
            }
            .overlay {
                if state == "menu" {
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        VStack(alignment: .leading, spacing: 10) {
                            WorldCardRow(world: DraftData.worlds[1]) { BlockButton("Play", size: .small) {} }
                            NativeMenuMock(items: [
                                ("Play", "play.fill", false), ("Back up now", "clock.arrow.circlepath", false),
                                ("Backups…", "archivebox", false), ("Export…", "square.and.arrow.up", false),
                                ("Copy to instance…", "plus.square.on.square", false),
                                ("Show in Files", "folder", false),
                                ("Delete", "trash", true),
                            ])
                        }
                        .padding(.horizontal, 16).padding(.top, 182)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if state == "undo" {
                    UndoToast(title: "Deleted Hardcore #3", detail: "A backup stays 7 days in Backups")
                }
            }
            .draftSheet(state == "backups") { WorldBackupsSheet() }
            .draftSheet(state == "copy") { CopyWorldSheet() }
        }
    }

    struct WorldBackupsSheet: View {
        @State private var keep = 5

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Ironwood backups") {
                    BlockButton("Back up now", role: .primary, size: .small) {}.fixedSize()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ListSection(spacing: 4) {
                            backup("Today, 14:02", "Before the Lithium update · 410 MB")
                            backup("Yesterday, 21:40", "You · 409 MB")
                            backup("Oct 21", "Before Fabric 0.16.14 · 398 MB")
                        }
                        ListSection("Automatic", spacing: 4) {
                            ControlRow("Keep") {
                                SelectButton(
                                    "Keep", selection: $keep, options: [(3, "Last 3"), (5, "Last 5"), (10, "Last 10")]
                                )
                                .compactStyle()
                            }
                        }
                        GameOwnsNote(
                            "Restore swaps the world for the backup. Cofre backs up the current world first, so nothing is lost."
                        )
                    }
                    .padding(16)
                }
            }
        }

        private func backup(_ when: String, _ detail: String) -> some View {
            Row(
                when, subtitle: detail, leading: { PixelIcon(.chest, size: 20) },
                trailing: { BlockButton("Restore", size: .small) {} })
        }
    }

    /// Copy a world into another instance. The version check runs before anything is copied.
    struct CopyWorldSheet: View {
        @State private var target = "vanilla"

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Copy Ironwood to…")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ListSection(spacing: 4) {
                            option("cobblemon", "Cobblemon", "NeoForge 1.21.1 · same version", .success, "Fits")
                            option(
                                "vanilla", "Vanilla", "26.3 · newer: the world updates and can't go back", .warn,
                                "Newer")
                            option(
                                "create", "Create: Above & Beyond", "1.20.1 · older than the world", .danger, "Older"
                            )
                            .dimmed()
                        }
                        if target == "vanilla" {
                            Banner("Vanilla is newer. The copy updates; your original stays on 1.21.1.", icon: .grass)
                        }
                        Row("Space", trailing: { Meta("410 MB of 18.4 GB free", tone: .success) })
                        BlockButton("Copy world", role: .primary) {}
                    }
                    .padding(16)
                }
            }
        }

        private func option(_ id: String, _ name: String, _ detail: String, _ tone: Tone, _ badge: LocalizedStringKey)
            -> Row<Radio, Badge>
        {
            Row(
                name, subtitle: detail, isSelected: target == id, leading: { Radio(isOn: target == id) },
                trailing: { Badge(badge, tone: tone) })
        }
    }
#endif
