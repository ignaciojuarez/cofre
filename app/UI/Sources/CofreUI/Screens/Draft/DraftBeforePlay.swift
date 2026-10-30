#if canImport(UIKit)
    import SwiftUI

    // Draft · Before you play: the instance's second tab. Only what has to be set before Minecraft starts (preset,
    // GUI scale, language, renderer, memory, Java, JVM arguments, loader); everything else stays in the game's
    // own Options. The preset writes a few options.txt keys and reads them back, so in-game changes show here.
    // States: main · custom (changed in game) · presetB (segmented variation) · engine · pack · packB · packSheet.

    struct BeforePlayDraft: View {
        let state: String

        var body: some View {
            InstanceDetailDraft(
                tab: 1, state: state,
                anchor: state == "engine" ? "engine" : state == "pack" || state == "packB" ? "pack" : nil,
                instance: state == "engine" || state == "packB" ? DraftData.instances[0] : DraftData.instances[1]
            )
            .environment(\.isPushed, true)
            .draftSheet(state == "packSheet") { PerformancePackSheet() }
        }
    }

    struct BeforePlayContent: View {
        let state: String
        let instance: DraftData.Instance
        @State private var preset = "balanced"
        @State private var heatAware = true
        @State private var memory = "auto"
        @State private var ram = 4096.0
        @State private var gui = "auto"
        @State private var language = "en_us"
        @State private var loaderVersion = "0.16.14"
        @State private var jvm = ""

        private var modded: Bool { instance.loader != .vanilla }

        var body: some View {
            Text("Set before the game starts. Everything else is in the game's own Options.")
                .cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
            ListSection("Performance", spacing: 4) {
                if state == "presetB" {
                    Segmented(
                        "Preset", selection: $preset,
                        options: [("quality", "Quality"), ("balanced", "Balanced"), ("battery", "Battery")])
                } else {
                    PresetTiles(preset: $preset, edited: state == "custom")
                }
                if state == "custom" {
                    Banner("Changed in game: render distance 20. Balanced uses 12.", icon: .grass, tone: .neutral) {
                        BlockButton("Use 12", size: .small, fullWidth: false) {}
                    }
                }
                Toggle(isOn: $heatAware) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Heat-aware").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                        Text("Lowers quality when the phone gets hot or Low Power Mode is on")
                            .cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.block)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .frame(minHeight: 44)
                .block(.panel)
                PresetSummary(edited: state == "custom")
                Button {
                } label: {
                    ValueRow("Renderer", value: modded ? "Auto · MobileGlues" : "Auto (Metal for 26.x)", accent: true)
                }
                .buttonStyle(RowButtonStyle())
            }
            ListSection("Game", spacing: 4) {
                ControlRow("GUI scale") {
                    SelectButton(
                        "GUI scale", selection: $gui, options: [("auto", "Auto"), ("2", "2"), ("3", "3"), ("4", "4")]
                    )
                    .compactStyle()
                }
                ControlRow("Language") {
                    SelectButton(
                        "Language", selection: $language,
                        options: [("en_us", "English (US)"), ("es_es", "Español"), ("pt_br", "Português (BR)")]
                    )
                    .compactStyle()
                }
            }
            GameOwnsNote(
                "More in the game: Options › Video Settings, Controls, Music & Sounds. Cofre reads those and never overwrites them."
            )
            ListSection("Engine", spacing: 4) {
                ControlRow("Memory", subtitle: memory == "auto" ? "Auto: 4 GB on this iPhone" : nil) {
                    Segmented(
                        "Memory", selection: $memory, options: [("auto", "Auto"), ("manual", "Manual")], size: .small
                    )
                    .frame(width: 150)
                }
                if memory == "manual" {
                    BlockSlider(
                        "Memory", value: $ram, in: 1024...6144, step: 256, note: "Closes while loading? Lower this.",
                        accessibilityValue: { "\(Int($0)) megabytes" }
                    ) { "\(Fmt.mb(Int($0))) · safe up to 4,096" }
                }
                ValueRow("Java", value: modded ? "Auto · Java 21" : "Auto · Java 25")
                if modded {
                    ControlRow("Fabric loader", subtitle: "0.17.2 is out") {
                        SelectButton(
                            "Fabric loader", selection: $loaderVersion,
                            options: [("0.17.2", "0.17.2"), ("0.16.14", "0.16.14"), ("0.16.10", "0.16.10")]
                        )
                        .compactStyle()
                    }
                }
                SectionLabel("JVM arguments")
                Field("JVM arguments", text: $jvm, prompt: "None · Cofre's safe defaults", kind: .mono)
                Text("If new arguments stop the game from starting, Cofre goes back to the last ones that worked.")
                    .cofreFont(.caption).foregroundStyle(Color.cofre.muted).padding(.horizontal, 2)
            }
            .id("engine")
            .onAppear { if state == "engine" { memory = "manual" } }
            PerformancePackCard(inPlace: state == "packB", instance: instance).id("pack")
            BlockButton("Reset to Cofre defaults", role: .ghostDestructive) {}
            Text("Puts the preset's values back. Worlds, keys and your other options stay.")
                .cofreFont(.caption).foregroundStyle(Color.cofre.muted).frame(maxWidth: .infinity)
        }
    }

    /// Quality · Balanced · Battery as tiles, like the loader tiles in New instance (variation A).
    struct PresetTiles: View {
        @Binding var preset: String
        var edited = false

        var body: some View {
            HStack(spacing: 6) {
                tile("quality", "Quality", "16 chunks · 100%", .ore)
                tile("balanced", "Balanced", edited ? "Edited in game" : "12 chunks · 85%", .grass)
                tile("battery", "Battery", "8 chunks · 70%", .bolt)
            }
        }

        private func tile(_ id: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey, _ glyph: PixelGlyph)
            -> some View
        {
            let on = preset == id
            return Button {
                preset = id
            } label: {
                VStack(spacing: 4) {
                    PixelIcon(glyph, size: 22)
                    Text(title).cofreFont(.buttonS).foregroundStyle(Color.cofre.ink)
                    Text(detail).cofreFont(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(edited && on ? Color.cofre.warn : Color.cofre.muted)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 78)
                .block(on ? .raised : .panel, selected: on)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    /// The options.txt keys the preset writes, read back from the file.
    struct PresetSummary: View {
        var edited = false

        var body: some View {
            let rows: [(LocalizedStringKey, String, Bool)] = [
                ("Render distance", edited ? "20 · in game" : "12", edited), ("Simulation", "6", false),
                ("Resolution", "85%", false), ("Frame rate", "120 · VSync", false), ("Graphics", "Fast", false),
                ("Clouds", "Off", false), ("Particles", "Fewer", false), ("Entities", "75%", false),
            ]
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Balanced sets")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 4) {
                    ForEach(rows.indices, id: \.self) { i in
                        HStack {
                            Text(rows[i].0).foregroundStyle(Color.cofre.muted)
                            Spacer(minLength: 4)
                            Text(verbatim: rows[i].1).foregroundStyle(rows[i].2 ? Color.cofre.warn : Color.cofre.ink)
                        }
                        .cofreFont(.caption).lineLimit(1)
                    }
                }
            }
            .padding(10)
            .block(.well)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Performance pack (opt-in, pinned mods, undoable)

    struct PerformancePackCard: View {
        let inPlace: Bool
        let instance: DraftData.Instance
        static let mods: [(String, LocalizedStringKey)] = [
            ("Sodium", "Faster rendering"), ("Lithium", "Faster game logic"), ("FerriteCore", "Less memory"),
            ("ImmediatelyFast", "Faster HUD and text"), ("Entity Culling", "Skips hidden mobs"),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    PixelIcon(.fabric, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Performance pack").cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                        Text("Optional · 5 mods · 4.1 MB").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    }
                    Spacer(minLength: 4)
                    Badge("Tested", tone: .success)
                }
                Text(
                    inPlace
                        ? "Smoother frames and less memory. Versions pinned and tested with Fabric 1.21.1."
                        : instance.loader == .vanilla
                            ? "Smoother frames and less memory. Needs Fabric, so it goes into a copy. Pinned and tested for 26.3."
                            : "Smoother frames and less memory. Goes into a copy. Pinned and tested with Fabric 1.21.1."
                )
                .cofreFont(.secondary).foregroundStyle(Color.cofre.inkSoft).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Self.mods, id: \.0) { name, what in
                        HStack(spacing: 8) {
                            PixelIcon(.check, size: 11)
                            Text(verbatim: name).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                            Spacer(minLength: 6)
                            Text(what).cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                        }
                        .frame(minHeight: 26)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .block(.well)
                HStack(alignment: .top, spacing: 8) {
                    PixelIcon(.shield, size: 12).padding(.top, 2)
                    Text(
                        inPlace
                            ? "Backs up \(instance.name) first. Undo any time: Remove pack puts the backup back."
                            : "Makes \"\(instance.name) · Fast\". This one stays as it is. To undo, delete the copy."
                    )
                    .cofreFont(.caption).foregroundStyle(Color.cofre.muted).fixedSize(horizontal: false, vertical: true)
                }
                BlockButton(inPlace ? "Add to \(instance.name)" : "Make a fast copy", role: .primary) {}
            }
            .padding(12)
            .block(.panel)
        }
    }

    /// After "Make a fast copy": what happens, the size and the space check, then go.
    struct PerformancePackSheet: View {
        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Make a fast copy")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Row(
                            "Vanilla · Fast", subtitle: "Fabric 26.3 · 5 mods",
                            leading: { PixelIcon(.fabric, size: 26) })
                        ListSection("Steps", spacing: 4) {
                            step(1, "Copy Vanilla", "Instant")
                            step(2, "Add Fabric 0.17.2", "1.2 MB")
                            step(3, "Add the 5 mods", "4.1 MB")
                            step(4, "Check that it starts", "")
                        }
                        Row("Space", trailing: { Meta("5.3 MB of 18.4 GB free", tone: .success) })
                        GameOwnsNote("Worlds are copied too, so you can try the copy without touching the original.")
                        BlockButton("Make copy", role: .primary) {}
                    }
                    .padding(16)
                }
            }
        }

        private func step(_ n: Int, _ title: LocalizedStringKey, _ meta: String) -> some View {
            Row(title, leading: { RowIndex(n) }, trailing: { Meta(meta) })
        }
    }
#endif
