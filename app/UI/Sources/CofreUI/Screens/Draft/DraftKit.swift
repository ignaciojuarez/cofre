#if canImport(UIKit)
    import SwiftUI

    // Design draft (plan/design-draft.md): the P0/P1 launcher features and the performance presets, drawn with the
    // real components and draft-only data. Preview host only: `-screen draft -draft <area> -draftState <state>`.
    // Nothing here talks to a backend. Rule: the game's own files are the truth; Cofre only adds what the game
    // can't do on a phone (jump in, before-launch settings, file operations, checks).

    public struct DraftPage: View {
        let area: String, state: String
        @State private var store = CofreStore(services: .mock())
        @State private var nav = NavModel()

        public init(_ area: String, state: String = "") {
            self.area = area
            self.state = state
        }

        public var body: some View {
            GeometryReader { geo in
                let wide = geo.size.width >= 700
                Group {
                    ShellLayout(compact: !wide) {
                        DraftScreen(area: area, state: state, wide: wide)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        NavChrome(style: wide ? .rail : .tabBar, nav: nav)
                    }
                }
                .environment(\.widthClass, wide ? .medium : .compact)
                .sizeClasses(SizeClasses(geo.size))
            }
            .environment(store).environment(nav)
            .background { PageBackground() }
            .onAppear { nav.section = DraftScreen.section(area) }
            .task { await store.start() }
        }
    }

    /// One area, one state. Unknown states show the area's main screen.
    struct DraftScreen: View {
        let area: String, state: String, wide: Bool

        static func section(_ area: String) -> NavModel.Section {
            switch area {
            case "instances", "import", "beforePlay", "versions": .instances
            case "content": .mods
            case "logs", "accounts": .settings
            default: .play
            }
        }

        var body: some View {
            switch area {
            case "instances": InstancesDraft(state: state, wide: wide)
            case "import": ImportDraft(state: state)
            case "files": FilesDraft(state: state)
            case "content": ContentDraft(state: state)
            case "worlds": WorldsDraft(state: state)
            case "beforePlay": BeforePlayDraft(state: state)
            case "versions": VersionsDraft(state: state)
            case "accounts": Text("Accounts & data")
            default: PlayHomeDraft(state: state)
            }
        }
    }

    // MARK: Shared draft pieces

    /// Scrolling pane that can open at a section (`anchor` matches an `.id` inside).
    struct DraftScroll<C: View>: View {
        let anchor: String?, content: C
        @Environment(\.widthClass) private var width
        init(anchor: String? = nil, @ViewBuilder content: () -> C) {
            self.anchor = anchor
            self.content = content()
        }
        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) { content }
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, width == .compact ? 16 : 20)
                        .padding(.top, 6).padding(.bottom, 90)
                        .frame(maxWidth: .infinity)
                }
                .task {
                    guard let anchor else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
    }

    /// "Deleted Skyblock · Undo". Sits over the bottom of the pane for a few seconds; the file is only removed
    /// when it goes away (and a backup stays for 7 days).
    struct UndoToast: View {
        let title: String, detail: String
        var body: some View {
            HStack(spacing: 10) {
                PixelIcon(.check, size: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Text(verbatim: detail).cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                }
                Spacer(minLength: 8)
                BlockButton("Undo", size: .small) {}
            }
            .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 8)
            .frame(minHeight: 52)
            .background(BlockBackground(.raised, lip: 4))
            .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
            .padding(.horizontal, 16).padding(.bottom, 12)
            .accessibilityElement(children: .combine)
        }
    }

    /// Stand-in for the system context menu in screenshots (the real one is native, §0 rule 4).
    struct NativeMenuMock: View {
        let items: [(String, String, Bool)]
        var body: some View {
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    HStack {
                        Text(verbatim: items[i].0)
                        Spacer()
                        Image(systemName: items[i].1)
                    }
                    .font(.body)
                    .foregroundStyle(items[i].2 ? Color.red : Color.white)
                    .padding(.horizontal, 16).frame(height: 46)
                    if i < items.count - 1 { Divider().overlay(Color.white.opacity(0.12)) }
                }
            }
            .frame(width: 250)
            .background(Color(white: 0.17).opacity(0.97), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            .environment(\.colorScheme, .dark)
        }
    }

    /// Mono note under a section: where the game owns the rest.
    struct GameOwnsNote: View {
        let text: LocalizedStringKey
        init(_ text: LocalizedStringKey) { self.text = text }
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                PixelIcon(.grass, size: 12).padding(.top, 2)
                Text(text).cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 2).padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    /// A labeled row with a trailing control (menu, segmented). Same chrome as `ToggleRow`.
    struct ControlRow<C: View>: View {
        let title: LocalizedStringKey, subtitle: LocalizedStringKey?, control: C
        init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, @ViewBuilder control: () -> C) {
            self.title = title
            self.subtitle = subtitle
            self.control = control()
        }
        var body: some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    if let subtitle { Text(subtitle).cofreFont(.caption).foregroundStyle(Color.cofre.muted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                control
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .frame(minHeight: 44)
            .block(.panel)
        }
    }

    /// Presents a sheet once the screen is up, so screenshots show it over its parent.
    struct PresentOnAppear<S: View>: ViewModifier {
        let enabled: Bool
        @ViewBuilder let sheet: () -> S
        @State private var shown = false
        func body(content: Content) -> some View {
            content
                .blockSheet(isPresented: $shown) { sheet() }
                .task {
                    guard enabled else { return }
                    try? await Task.sleep(for: .milliseconds(250))
                    shown = true
                }
        }
    }

    extension View {
        func draftSheet<S: View>(_ enabled: Bool, @ViewBuilder _ sheet: @escaping () -> S) -> some View {
            modifier(PresentOnAppear(enabled: enabled, sheet: sheet))
        }
    }

    // MARK: Draft data

    enum DraftData {
        static let now = Date()

        struct World: Identifiable, Hashable {
            let id: String, name: String, mode: String
            let ago: TimeInterval, sizeBytes: Int64, seed: UInt32
            var backups = 0
            var lastPlayed: Date { now.addingTimeInterval(-ago) }
            var modeTone: Tone { mode == "Hardcore" ? .danger : mode == "Creative" ? .accent : .neutral }
        }

        static let worlds: [World] = [
            .init(
                id: "w1", name: "Ironwood", mode: "Survival", ago: 7200, sizeBytes: 412_000_000, seed: 11, backups: 3),
            .init(id: "w2", name: "Skyhaven", mode: "Creative", ago: 86400, sizeBytes: 96_000_000, seed: 23),
            .init(id: "w3", name: "River Base", mode: "Survival", ago: 4 * 86400, sizeBytes: 180_000_000, seed: 5),
            .init(id: "w4", name: "Hardcore #3", mode: "Hardcore", ago: 14 * 86400, sizeBytes: 61_000_000, seed: 37),
        ]

        struct Instance: Identifiable, Hashable {
            let id: String, name: String, loader: Loader, game: String
            var mods = 0, sizeBytes: Int64 = 0, ago: TimeInterval? = nil
            var favorite = false, group = "", glyph: PixelGlyph? = nil
            var icon: InstanceIcon { glyph.map { .init(glyph: $0) } ?? .automatic(id: id, loader: loader) }
            var line: String {
                [
                    mods > 0 ? "\(mods) mods" : nil, Fmt.bytes(sizeBytes),
                    ago.flatMap { Fmt.ago(now.addingTimeInterval(-$0)) },
                ]
                .compactMap { $0 }.joined(separator: " · ")
            }
        }

        static let instances: [Instance] = [
            .init(
                id: "survival", name: "Survival+", loader: .fabric, game: "1.21.1", mods: 142,
                sizeBytes: 4_402_000_000, ago: 7200, favorite: true, group: "Modpacks"),
            .init(
                id: "vanilla", name: "Vanilla", loader: .vanilla, game: "26.3", sizeBytes: 644_000_000, ago: 3 * 3600,
                favorite: true),
            .init(
                id: "create", name: "Create: Above & Beyond", loader: .forge, game: "1.20.1", mods: 189,
                sizeBytes: 6_228_000_000, ago: 86400, group: "Modpacks"),
            .init(
                id: "cobblemon", name: "Cobblemon", loader: .neoforge, game: "1.21.1", mods: 64,
                sizeBytes: 2_362_000_000, ago: 3 * 86400, group: "Modpacks"),
            .init(
                id: "skyblock", name: "Skyblock", loader: .quilt, game: "1.20.4", mods: 23, sizeBytes: 966_000_000,
                ago: 8 * 86400, group: "Testing"),
            .init(
                id: "snap", name: "Snapshot test", loader: .vanilla, game: "26.4-pre1", sizeBytes: 702_000_000,
                ago: 20 * 86400, group: "Testing"),
        ]
    }
#endif
