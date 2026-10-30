#if canImport(UIKit)
    import SwiftUI

    // Draft · Versions. One picker for New instance and "Change version": releases or snapshots, sizes, what's
    // installed, and a check before anything downloads (size, space, Java). The loader list sits beside it.
    // Resume and retry live in Downloads (DraftPlay.swift). States: picker · snapshots · loader · noSpace.

    struct VersionsDraft: View {
        let state: String
        var body: some View {
            InstancesListDraft(variant: .sections).draftSheet(true) {
                if state == "loader" { LoaderVersionSheet() } else { GameVersionSheet(state: state) }
            }
        }
    }

    struct GameVersionSheet: View {
        let state: String
        @State private var kind = VersionKind.release
        @State private var picked = "26.3"

        private var versions: [(String, String, String, Bool)] {
            kind == .snapshot
                ? [
                    ("26.4-pre1", "2 days ago", "430 MB", false), ("26.4-snapshot-6", "Oct 22", "428 MB", false),
                    ("26.4-snapshot-5", "Oct 15", "428 MB", false),
                ]
                : [
                    ("26.3", "Latest · Metal renderer", "412 MB", false), ("26.2", "Sep 2026", "409 MB", false),
                    ("1.21.1", "Most mods", "", true), ("1.20.4", "Dec 2023", "380 MB", false),
                    ("1.20.1", "Forge packs", "", true),
                ]
        }

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Minecraft version")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Segmented(
                            "Kind", selection: $kind,
                            options: [(.release, "Releases"), (.snapshot, "Snapshots"), (.old, "Old")])
                        if kind == .snapshot {
                            Banner(
                                "Snapshots can break worlds. Cofre backs a world up before a snapshot opens it.",
                                icon: .grass)
                        }
                        ListSection(spacing: 4) {
                            ForEach(versions, id: \.0) { id, note, size, have in
                                Button {
                                    picked = id
                                } label: {
                                    Row(
                                        id, subtitle: note, isSelected: picked == id,
                                        leading: { Radio(isOn: picked == id) },
                                        trailing: { Meta(have ? "Installed" : size, tone: have ? .success : nil) }
                                    )
                                }
                                .buttonStyle(RowButtonStyle())
                            }
                        }
                    }
                    .padding(16)
                }
                VStack(spacing: 8) {
                    if state == "noSpace" { NoSpaceCheck() } else { PreflightCheck() }
                    BlockButton(state == "noSpace" ? "Create" : "Create · 412 MB", role: .primary) {}
                        .disabled(state == "noSpace")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.cofre.panel)
                .overlay(alignment: .top) { Color.cofre.outline.frame(height: 2) }
            }
            .onAppear {
                if state == "snapshots" {
                    kind = .snapshot
                    picked = "26.4-pre1"
                }
            }
        }
    }

    /// Before it downloads: size, space after, Java. One line when everything's fine.
    struct PreflightCheck: View {
        var body: some View {
            HStack(spacing: 10) {
                PixelIcon(.check, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Downloads 412 MB · needs 1.1 GB").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Text("18.4 GB free · Java 25 already here · Wi‑Fi").cofreFont(.caption).foregroundStyle(
                        Color.cofre.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .block(.panel)
            .accessibilityElement(children: .combine)
        }
    }

    struct NoSpaceCheck: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Banner("Not enough space. Needs 3.1 GB; 1.2 GB free.", icon: .cross, tone: .danger)
                HStack(spacing: 8) {
                    BlockButton("Clear cache · 860 MB", size: .small) {}
                    BlockButton("See storage", size: .small) {}
                }
            }
        }
    }

    struct LoaderVersionSheet: View {
        @State private var betas = false
        @State private var picked = "0.17.2"

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Fabric loader")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("For Survival+ · Minecraft 1.21.1").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                        ToggleRow("Show betas", isOn: $betas)
                        ListSection(spacing: 4) {
                            if betas { row("0.17.3-beta.1", "Beta · Oct 27", badge: ("Beta", .warn)) }
                            row("0.17.2", "Newest stable · Oct 12", badge: ("Best", .success))
                            row("0.17.1", "Sep 30")
                            row("0.16.14", "In use now", badge: ("Installed", .neutral))
                            row("0.16.10", "Aug 2")
                        }
                        GameOwnsNote(
                            "Cofre backs up the instance before it changes the loader. If the game doesn't start, it puts the old one back."
                        )
                    }
                    .padding(16)
                }
                BlockButton("Switch to 0.17.2", role: .primary) {}
                    .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }

        private func row(_ v: String, _ note: String, badge: (LocalizedStringKey, Tone)? = nil) -> some View {
            Button {
                picked = v
            } label: {
                Row(
                    v, subtitle: note, isSelected: picked == v, leading: { Radio(isOn: picked == v) },
                    trailing: { if let badge { Badge(badge.0, tone: badge.1) } })
            }
            .buttonStyle(RowButtonStyle())
        }
    }
#endif
