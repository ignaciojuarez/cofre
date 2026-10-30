#if canImport(UIKit)
    import SwiftUI

    // Draft · Play home: the hub for jumping in. Shows the active instance, "Jump back in" (recent worlds, quick
    // play), one Performance row (the preset lives in the instance's Before you play) and the phone's state:
    // downloads, heat, Low Power Mode, account problems. States: home · hot · lowPower · downloads · downloadsSheet ·
    // demo · expired · autosave.

    struct PlayHomeDraft: View {
        let state: String
        @Environment(\.widthClass) private var width
        @State private var instance = "survival"

        var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Play") { AccountChip() }
                    .environment(\.columnHeaderAccessory, width == .compact ? AnyView(PlayPanePicker(pane: 0)) : nil)
                DraftScroll {
                    banners
                    if state == "downloads" || state == "downloadsSheet" { DownloadsStrip() }
                    hero
                    if width == .compact {
                        VStack(spacing: 8) {
                            picker
                            play
                        }
                    } else {
                        HStack(spacing: 8) {
                            picker
                            play.frame(width: 220)
                        }
                    }
                    ListSection("Jump back in", spacing: 4) {
                        ForEach(Array(DraftData.worlds.prefix(3).enumerated()), id: \.element.id) { i, w in
                            WorldCardRow(world: w, showSize: false) {
                                if i == 0 {
                                    BlockButton("Play", icon: .play, role: .primary, size: .small) {}
                                } else {
                                    BlockButton("Play", size: .small) {}
                                }
                            }
                        }
                    }
                    ListSection("This instance", spacing: 4) {
                        Button {
                        } label: {
                            ValueRow(
                                "Performance",
                                value: state == "hot" || state == "lowPower"
                                    ? String(localized: "Battery · for now")
                                    : String(localized: "Balanced · Heat-aware"),
                                accent: true)
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
            .draftSheet(state == "downloadsSheet") { DownloadsSheet() }
        }

        @ViewBuilder private var banners: some View {
            switch state {
            case "hot":
                Banner("Your iPhone is hot. Cofre plays on Battery until it cools.", icon: .bolt, tone: .warn) {
                    BlockButton("Details", size: .small, fullWidth: false) {}
                }
            case "lowPower":
                Banner("Low Power Mode is on: Battery quality and 30 FPS.", icon: .bolt, tone: .warn) {
                    BlockButton("Change", size: .small, fullWidth: false) {}
                }
            case "demo":
                Banner("Steve_42 doesn't own Minecraft: Java Edition. You can play the demo.", icon: .head) {
                    BlockButton("Accounts", size: .small, fullWidth: false) {}
                }
            case "expired":
                Banner("Alex_Mines was signed out. Sign in again to play.", icon: .key, tone: .danger) {
                    BlockButton("Sign in", size: .small, fullWidth: false) {}
                }
            case "autosave":
                Banner(
                    "Leaving the game saves your world first. iOS can still close Cofre later.", icon: .check,
                    tone: .neutral
                ) {
                    BlockButton("OK", size: .small, fullWidth: false) {}
                }
            default: EmptyView()
            }
        }

        private var hero: some View {
            PixelScene(seed: 11, pixels: .init(width: 240, height: 110))
                .frame(height: width == .compact ? 150 : 210)
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 12) {
                        PixelIcon(.fabric, size: 36).shadow(color: .black, radius: 0, y: 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: "Survival+").cofreFont(.display).foregroundStyle(.white)
                                .shadow(color: .black, radius: 0, y: 2)
                            HStack(spacing: 4) {
                                Badge(loader: .fabric, version: "1.21.1")
                                Badge("142 mods")
                                if state == "demo" {
                                    Badge("Demo", tone: .warn)
                                } else {
                                    Badge("Ready", tone: .success)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
        }

        private var picker: some View {
            SelectButton(
                "Instance", selection: $instance, options: DraftData.instances.map { ($0.id, $0.name) })
        }

        private var play: some View {
            BlockButton("Play", icon: .play, role: .primary, size: .large, fullWidth: true) {}
        }
    }

    /// The compact Play · Worlds · Servers picker, as `AdaptiveSplit` draws it.
    struct PlayPanePicker: View {
        @State var pane: Int
        var body: some View {
            Segmented("Pane", selection: $pane, options: [(0, "Play"), (1, "Worlds"), (2, "Servers")])
        }
    }

    /// World row: the save's own icon.png (a scene here), name, mode, last played, size. Reads saves/ directly.
    struct WorldCardRow<Trailing: View>: View {
        let world: DraftData.World
        var showSize = true
        @ViewBuilder let trailing: () -> Trailing

        var body: some View {
            Row(world.name) {
                HStack(spacing: 6) {
                    Badge(world.mode, tone: world.modeTone)
                    Text(verbatim: line).cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(1)
                }
            } leading: {
                WorldThumb(seed: world.seed, size: 44)
            } trailing: {
                trailing()
            }
            .rowStyle(.big)
        }

        private var line: String {
            [Fmt.ago(world.lastPlayed).map { "\($0) ago" }, showSize ? Fmt.bytes(world.sizeBytes) : nil]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }

    /// The world's icon.png. A scene stands in for the screenshot the game saves.
    struct WorldThumb: View {
        let seed: UInt32, size: CGFloat
        var body: some View {
            // A different stretch of a wide scene per world: forest, cabin or lake.
            PixelScene(seed: seed, pixels: .init(width: 96, height: 32))
                .frame(width: size * 3, height: size)
                .offset(x: CGFloat(Int(seed % 3) - 1) * size)
                .frame(width: size, height: size)
                .clipped()
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
        }
    }

    // MARK: Downloads (background, resumable)

    struct DownloadsStrip: View {
        var body: some View {
            Button {
            } label: {
                HStack(spacing: 10) {
                    Spinner()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Downloading 2 · 62%").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                            Spacer()
                            Meta("1 stopped", tone: .danger)
                        }
                        ProgressView(value: 0.62).progressViewStyle(.xp(small: true))
                        Text("Keeps going if you leave Cofre").cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                    }
                    Chevron()
                }
                .padding(.horizontal, 11).padding(.vertical, 9)
                .block(.panel)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
        }
    }

    struct DownloadsSheet: View {
        @State private var cellular = false
        @State private var lowPower = true

        var body: some View {
            VStack(spacing: 0) {
                SheetHeader("Downloads") { BlockButton("Pause all", size: .small) {}.fixedSize() }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ListSection(spacing: 4) {
                            DownloadRow(
                                title: "Fabulously Optimized", glyph: .chest, detail: "87 of 142 mods · 212 of 341 MB",
                                fraction: 0.62
                            ) { Meta("62%") }
                            DownloadRow(
                                title: "Minecraft 26.3", glyph: .grass, detail: "Waits for Wi‑Fi · 412 MB",
                                fraction: nil
                            ) { Badge("Wi‑Fi") }
                            DownloadRow(
                                title: "Iris Shaders 1.8.8", glyph: .ore, detail: "Stopped at 61%: connection lost",
                                fraction: 0.61, failed: true
                            ) { BlockButton("Resume", size: .small) {} }
                            DownloadRow(
                                title: "Complementary Reimagined", glyph: .ore,
                                detail: "File didn't match. Downloads it again.", fraction: nil, failed: true
                            ) { BlockButton("Retry", size: .small) {} }
                        }
                        ListSection("While downloading", spacing: 4) {
                            ToggleRow("Use cellular data", subtitle: "Big downloads wait for Wi‑Fi", isOn: $cellular)
                            ToggleRow("Pause in Low Power Mode", isOn: $lowPower)
                        }
                        GameOwnsNote(
                            "iOS can pause downloads in the background. Cofre picks up where they stopped, and checks every file before it's used."
                        )
                    }
                    .padding(16)
                }
            }
        }
    }

    struct DownloadRow<Trailing: View>: View {
        let title: String, glyph: PixelGlyph, detail: String, fraction: Double?
        var failed = false
        @ViewBuilder let trailing: () -> Trailing

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    PixelIcon(glyph, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(1)
                        Text(verbatim: detail).cofreFont(.caption)
                            .foregroundStyle(failed ? Color.cofre.danger : Color.cofre.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailing()
                }
                if let fraction {
                    ProgressView(value: fraction).progressViewStyle(.xp(failed ? .warn : .success, small: true))
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(minHeight: 44)
            .block(.panel)
            .accessibilityElement(children: .combine)
        }
    }
#endif
