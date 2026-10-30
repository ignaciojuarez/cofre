#if canImport(UIKit)
    import SwiftUI

    // Draft · Content parity in Mods → Installed. One row pattern for mods, resource packs, shaders and data packs:
    // icon, name, version or problem, Update badge, and a trailing control that says who owns on/off.
    //   · Mods: a switch. The game has no mod manager, so Cofre owns it (renames .jar ↔ .jar.disabled).
    //   · Packs, shaders: a read-only "In use" badge from options.txt / iris.properties. On/off and order stay in game
    //     (variation B, recommended). Variation A (packsA) gives them switches that write options.txt.
    //   · Data packs: grouped by world, since they live in saves/<world>/datapacks.
    // Update and Delete (swipe, context menu) work the same for all four. States: mods · packs · packsA · shaders ·
    // data · empty.

    struct ContentDraft: View {
        let state: String
        @Environment(\.widthClass) private var width
        @State private var kind = ContentKind.mods
        @State private var filter = ""

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader("Installed") { Badge("Survival+", tone: .fabric) }
                    .environment(\.isPushed, true)
                VStack(spacing: 8) {
                    Segmented(
                        "Content", selection: $kind,
                        options: [
                            (.mods, "Mods"), (.resourcePacks, "Packs"), (.shaders, "Shaders"), (.dataPacks, "Data"),
                        ])
                    HStack(spacing: 8) {
                        Field("Filter", text: $filter, kind: .search)
                        if updates > 0 {
                            BlockButton("Update \(updates)", role: .primary, size: .small) {}.fixedSize()
                        }
                    }
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 4)
                if state == "empty" {
                    EmptyState(
                        "No shaders yet", message: "Shaders need Iris, a mod. Get mods adds both in one step.",
                        icon: .ore
                    ) {
                        BlockButton("Get shaders", role: .primary) {}
                    }
                } else {
                    DraftScroll { list }
                }
            }
            .onAppear {
                kind =
                    switch state {
                    case "packs", "packsA": .resourcePacks
                    case "shaders", "empty": .shaders
                    case "data": .dataPacks
                    default: .mods
                    }
            }
        }

        private var updates: Int {
            switch kind {
            case .mods: 2
            case .resourcePacks, .shaders, .dataPacks: 1
            case .modpacks: 0
            }
        }

        @ViewBuilder private var list: some View {
            switch kind {
            case .resourcePacks:
                ForEach(Self.packs) { item in
                    if state == "packsA" { SwitchContentRow(item: item) } else { StatusContentRow(item: item) }
                }
                if state == "packsA" {
                    GameOwnsNote(
                        "Variation A: Cofre turns packs on and off by writing options.txt. Order still changes in game."
                    )
                } else {
                    GameOwnsNote(
                        "Turn packs on and set their order in game: Options › Resource Packs. This list shows what the game uses."
                    )
                }
            case .shaders:
                Row(
                    "Iris Shaders 1.8.8", subtitle: "Loads shaders · a mod", leading: { PixelIcon(.ore, size: 22) },
                    trailing: { Badge("On", tone: .success) })
                ForEach(Self.shaders) { StatusContentRow(item: $0) }
                GameOwnsNote("Pick and tune a shader in game: Options › Video Settings › Shader Packs.")
            case .dataPacks:
                ListSection("Ironwood", spacing: 4) { ForEach(Self.data.prefix(2)) { StatusContentRow(item: $0) } }
                ListSection("Skyhaven", spacing: 4) { ForEach(Self.data.suffix(1)) { StatusContentRow(item: $0) } }
                GameOwnsNote(
                    "Data packs belong to one world. The game loads them with the world; /datapack turns one off.")
            default:
                ForEach(Self.mods) { SwitchContentRow(item: $0) }
                Text("6 on · 2 off · swipe to delete").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    .padding(.top, 4)
            }
        }

        // MARK: Data

        struct Item: Identifiable {
            let id: String, name: String, version: String
            var on = true
            var update: String?
            var issue: String?
            var status: String?
            var glyph: PixelGlyph = .book
            var tint: UInt32?
        }

        static let mods: [Item] = [
            .init(id: "sodium", name: "Sodium", version: "0.6.13", glyph: .ore, tint: 0x45c27a),
            .init(id: "iris", name: "Iris Shaders", version: "1.8.8", glyph: .ore, tint: 0xb07bff),
            .init(id: "lithium", name: "Lithium", version: "0.14.3", update: "0.14.4", glyph: .ore, tint: 0x9a86ff),
            .init(id: "xaero", name: "Xaero's Minimap", version: "25.2.0", on: false, glyph: .paper),
            .init(id: "jei", name: "JEI", version: "19.21.0", update: "19.21.2"),
            .init(id: "glass", name: "Better Glass", version: "1.4", issue: "Needs Fabric API", glyph: .sand),
            .init(id: "modmenu", name: "Mod Menu", version: "11.0.3"),
            .init(id: "cloth", name: "Cloth Config", version: "15.0.140", on: false, glyph: .gear),
        ]
        static let packs: [Item] = [
            .init(id: "faithful", name: "Faithful 32x", version: "1.21", status: "In use · 1", glyph: .planks),
            .init(
                id: "fresh", name: "Fresh Animations", version: "1.9.2", update: "1.9.3", status: "In use · 2",
                glyph: .head),
            .init(id: "staytrue", name: "Stay True", version: "1.21.1", on: false, status: "Not used", glyph: .grass),
            .init(
                id: "mizuno", name: "Mizuno's 16 Craft", version: "1.21", on: false, status: "Not used", glyph: .bricks),
        ]
        static let shaders: [Item] = [
            .init(
                id: "comp", name: "Complementary", version: "r5.4", update: "r5.5", status: "In use",
                glyph: .ore, tint: 0xf0b84f),
            .init(
                id: "bsl", name: "BSL Shaders", version: "8.2.09", on: false, status: "Not used", glyph: .ore,
                tint: 0x5ad1e8),
        ]
        static let data: [Item] = [
            .init(
                id: "terralith", name: "Terralith", version: "2.5.4", update: "2.5.5", status: "Loaded", glyph: .gravel),
            .init(id: "incendium", name: "Incendium", version: "5.4.4", status: "Loaded", glyph: .bricks),
            .init(id: "vt", name: "VanillaTweaks Crafting", version: "1.21", status: "Loaded", glyph: .planks),
        ]
    }

    /// Icon, name, then the problem, the update or the version.
    private struct ContentLabel: View {
        let item: ContentDraft.Item
        var body: some View {
            HStack(spacing: 10) {
                PixelIcon(item.glyph, size: 24, tint: item.tint.map { Color(hex: $0) })
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.name).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(1)
                    Group {
                        if let issue = item.issue {
                            Text(verbatim: issue).foregroundStyle(Color.cofre.danger)
                        } else if let to = item.update {
                            Text(verbatim: "\(item.version) → \(to)").foregroundStyle(Color.cofre.warn)
                        } else {
                            Text(verbatim: item.version).foregroundStyle(Color.cofre.muted)
                        }
                    }
                    .cofreFont(.caption).lineLimit(1)
                }
                Spacer(minLength: 4)
                if item.issue != nil {
                    Badge("Fix", tone: .danger)
                } else if item.update != nil {
                    Badge("Update", tone: .warn)
                }
            }
        }
    }

    /// Cofre owns on/off: a switch.
    private struct SwitchContentRow: View {
        let item: ContentDraft.Item
        @State private var on: Bool
        init(item: ContentDraft.Item) {
            self.item = item
            _on = State(initialValue: item.on)
        }
        var body: some View {
            Toggle(isOn: $on) { ContentLabel(item: item) }
                .toggleStyle(.block)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .frame(minHeight: 44)
                .block(.panel)
                .opacity(on ? 1 : 0.6)
        }
    }

    /// The game owns on/off: what it uses, read from its files.
    private struct StatusContentRow: View {
        let item: ContentDraft.Item
        var body: some View {
            HStack(spacing: 8) {
                ContentLabel(item: item)
                if let s = item.status { Badge(s, tone: item.on ? .success : .neutral) }
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(minHeight: 44)
            .block(.panel)
            .accessibilityElement(children: .combine)
        }
    }
#endif
