#if canImport(UIKit)
    import SwiftUI

    // Draft · Files in and out. Modpack import (Instances → Import pack: file or link, staged progress, what changed,
    // rollback) and "Open in Cofre" (a file from Files or the share sheet: Cofre says what it is and where it goes).
    // Import states: pick · progress · done · failed. Files states: mrpack · jar · world · bedrock.

    struct ImportDraft: View {
        let state: String
        var body: some View {
            InstancesListDraft(variant: .sections).draftSheet(true) { ImportPackDraftSheet(state: state) }
        }
    }

    struct FilesDraft: View {
        let state: String
        var body: some View {
            PlayHomeDraft(state: "home").draftSheet(true) { IncomingFileSheet(kind: state.isEmpty ? "mrpack" : state) }
        }
    }

    // MARK: Modpack import

    struct ImportPackDraftSheet: View {
        let state: String
        @State private var link = ""

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader(state == "done" ? "Pack ready" : "Import pack")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch state {
                        case "progress": progress
                        case "done": done
                        case "failed": failed
                        default: pick
                        }
                    }
                    .padding(16)
                }
                footer.padding(.horizontal, 16).padding(.vertical, 10)
            }
        }

        @ViewBuilder private var pick: some View {
            SectionLabel("From a link")
            HStack(spacing: 8) {
                Field("Link", text: $link, prompt: "Modrinth or CurseForge pack link")
                BlockButton("Get", size: .small) {}.fixedSize()
            }
            SectionLabel("From a file")
            DropZone(
                "Choose a file", detail: ".mrpack · .zip from Modrinth, CurseForge, Prism or ATLauncher", glyph: .chest,
                types: [.mrpack, .zip], onDrop: { _ in }, onChoose: {})
            ListSection("Or browse", spacing: 4) {
                ValueRow("Modrinth packs", value: "Browse")
                ValueRow("CurseForge packs", value: "Browse")
            }
            GameOwnsNote("A pack becomes a new instance. Nothing you already have changes.")
        }

        private var packRow: some View {
            Row(
                "Fabulously Optimized 6.4.0", subtitle: "Modrinth · 142 mods · 341 MB",
                leading: { PixelIcon(.chest, size: 26) },
                trailing: { Badge(loader: .fabric, version: "1.21.1") }
            )
        }

        @ViewBuilder private var progress: some View {
            packRow
            ProgressView(value: 0.62).progressViewStyle(.xp())
            Text("87 of 142 mods · 212 of 341 MB").cofreFont(.label).foregroundStyle(Color.cofre.muted)
            ListSection(spacing: 4) {
                stage("Read the pack", .ready, "OK")
                stage("Minecraft 1.21.1", .ready, "Have it")
                stage("Fabric 0.16.14", .ready, "OK")
                stage("Mods", .checking, "87 / 142")
                stage("Resource packs and config", .unknown, "")
                stage("Check every file", .unknown, "")
            }
            GameOwnsNote("Keeps going if you leave Cofre. Cancel removes everything it added.")
        }

        @ViewBuilder private var done: some View {
            Banner("Fabulously Optimized is ready to play.", icon: .check, tone: .success)
            AdaptiveGrid(minItem: 70) {
                Stat("140", label: "Mods")
                Stat("6", label: "Packs")
                Stat("2", label: "Shaders")
                Stat("341 MB", label: "Size")
            }
            ListSection("What changed", spacing: 4) {
                Row(
                    "New instance", subtitle: "Fabulously Optimized · Fabric 1.21.1",
                    leading: { PixelIcon(.fabric, size: 20) })
                Row(
                    "Added", subtitle: "140 mods, 6 resource packs, 2 shaders, config",
                    leading: { PixelIcon(.check, size: 14) })
                Row(
                    "Skipped 2 mods", subtitle: "They can't run on iPhone", leading: { PixelIcon(.cross, size: 12) },
                    trailing: { Badge("2", tone: .warn) })
            }
            ListSection("Skipped", spacing: 4) {
                Row("Distant Horizons", subtitle: "Needs desktop OpenGL")
                Row("Simple Voice Chat", subtitle: "Needs a desktop audio library")
            }
        }

        @ViewBuilder private var failed: some View {
            Banner("Import stopped. Nothing was changed.", icon: .cross, tone: .danger)
            packRow
            ListSection(spacing: 4) {
                stage("Read the pack", .ready, "OK")
                stage("Minecraft 1.21.1", .ready, "Have it")
                stage("Fabric 0.16.14", .ready, "OK")
                stage("Mods", .failed("404"), "87 / 142")
            }
            Text("Sodium 0.6.13 didn't download. Modrinth no longer has that file.")
                .cofreFont(.secondary).foregroundStyle(Color.cofre.inkSoft)
            ListSection("Undone", spacing: 4) {
                Row("Removed the half-made instance", leading: { PixelIcon(.check, size: 14) })
                Row(
                    "Kept 87 downloads for next time", leading: { PixelIcon(.check, size: 14) },
                    trailing: { Meta("212 MB") })
            }
        }

        @ViewBuilder private var footer: some View {
            switch state {
            case "progress":
                HStack(spacing: 8) {
                    BlockButton("Cancel", role: .ghostDestructive, fullWidth: false) {}
                    BlockButton("Hide · keep going", role: .primary) {}
                }
            case "done":
                HStack(spacing: 8) {
                    BlockButton("Open instance") {}
                    BlockButton("Play", icon: .play, role: .primary) {}
                }
            case "failed":
                HStack(spacing: 8) {
                    BlockButton("Share report") {}
                    BlockButton("Try again", role: .primary) {}
                }
            default: EmptyView()
            }
        }

        private func stage(_ title: LocalizedStringKey, _ state: CheckState, _ meta: String) -> some View {
            let tone: Tone? =
                switch state {
                case .ready: .success
                case .failed, .blocked: .danger
                case .checking, .unknown: nil
                }
            return Row(
                title, leading: { StatusMark(state: state).frame(width: 14) }, trailing: { Meta(meta, tone: tone) }
            )
            .dimmed(state == .unknown)
        }
    }

    // MARK: Open in Cofre

    struct IncomingFileSheet: View {
        let kind: String
        @State private var choice = 0

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Open in Cofre")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        file
                        switch kind {
                        case "jar": jar
                        case "world": world
                        case "bedrock": bedrock
                        default: mrpack
                        }
                    }
                    .padding(16)
                }
                footer.padding(.horizontal, 16).padding(.vertical, 10)
            }
        }

        private var file: some View {
            let (name, what, glyph): (String, LocalizedStringKey, PixelGlyph) =
                switch kind {
                case "jar": ("sodium-fabric-0.6.13+mc1.21.1.jar", "Fabric mod · for 1.21.1 · 1.0 MB", .ore)
                case "world": ("Ironwood-backup.zip", "Java world · made in 1.21.4 · 410 MB", .grass)
                case "bedrock": ("Hardcore.mcworld", "Bedrock world · 61 MB", .grass)
                default: ("Fabulously Optimized-6.4.0.mrpack", "Modrinth pack · 142 mods · 2.1 MB", .chest)
                }
            return HStack(spacing: 12) {
                PixelIcon(glyph, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).cofreFont(.code).foregroundStyle(Color.cofre.ink).lineLimit(2)
                    Text(what).cofreFont(.label).foregroundStyle(Color.cofre.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(12).block(.well)
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder private var mrpack: some View {
            ListSection("What to do", spacing: 4) {
                option(0, "Make a new instance", "Fabulously Optimized · Fabric 1.21.1")
                option(1, "Update Fabulously Optimized", "6.3.2 → 6.4.0 · backs it up first")
            }
            Row("Download", trailing: { Meta("341 MB · 18.4 GB free", tone: .success) })
        }

        @ViewBuilder private var jar: some View {
            ListSection("Add to", spacing: 4) {
                fit(0, "Survival+", "Fabric 1.21.1", .success, "Fits")
                fit(1, "Cobblemon", "NeoForge 1.21.1 · other loader", .danger, "No").dimmed()
                fit(2, "Vanilla", "26.3 · no loader", .danger, "No").dimmed()
            }
            GameOwnsNote("Needs Fabric API. Cofre adds it too.")
        }

        @ViewBuilder private var world: some View {
            ListSection("Add to", spacing: 4) {
                fit(0, "Survival+", "1.21.1 · older than the world", .warn, "Older")
                fit(1, "Vanilla", "26.3 · opens it fine", .success, "Fits")
            }
            if choice == 0 {
                Banner("Made in 1.21.4. Opening it in 1.21.1 can break it.", icon: .grass, tone: .warn)
            }
            Row("Space", trailing: { Meta("410 MB of 18.4 GB free", tone: .success) })
        }

        @ViewBuilder private var bedrock: some View {
            Banner("This is a Bedrock world. Java Edition can't open it.", icon: .cross, tone: .danger)
            Text("Java worlds are folders with a level.dat inside. Zip one and open the .zip here.")
                .cofreFont(.body).foregroundStyle(Color.cofre.inkSoft)
            ListSection("Cofre opens", spacing: 4) {
                Row(".mrpack · .zip", subtitle: "Modpacks from Modrinth, CurseForge, Prism, ATLauncher")
                Row(".jar", subtitle: "A mod for one instance")
                Row(".zip", subtitle: "A world, a resource pack, a shader or a data pack")
            }
        }

        @ViewBuilder private var footer: some View {
            switch kind {
            case "jar": BlockButton("Add to Survival+", role: .primary) {}
            case "world": BlockButton("Add world", role: .primary) {}
            case "bedrock": BlockButton("Choose another file") {}
            default: BlockButton("Import", role: .primary) {}
            }
        }

        private func option(_ i: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
            Button {
                choice = i
            } label: {
                Row(title, subtitle: detail, isSelected: choice == i, leading: { Radio(isOn: choice == i) })
            }
            .buttonStyle(RowButtonStyle())
        }

        private func fit(_ i: Int, _ name: String, _ detail: String, _ tone: Tone, _ badge: LocalizedStringKey)
            -> Row<Radio, Badge>
        {
            Row(
                name, subtitle: detail, isSelected: choice == i, leading: { Radio(isOn: choice == i) },
                trailing: { Badge(badge, tone: tone) })
        }
    }
#endif
