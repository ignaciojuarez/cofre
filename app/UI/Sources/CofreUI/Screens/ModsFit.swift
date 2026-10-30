#if canImport(UIKit)
    import SwiftUI

    // Mods works on one instance that runs mods (`store.modsInstance`). The header's switcher picks it, or makes a new
    // one; with none at all, M01 is only the hero.

    /// M01 header: "For Survival+ · Fabric 1.21.1 ▾". A native menu of the modded instances, then New mods instance.
    /// Picking one also selects it in Play.
    struct ModsInstanceSwitcher: View {
        let current: InstanceSummary
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav

        var body: some View {
            Menu {
                // An inline picker checks the current one and keeps each row's loader icon.
                Picker(
                    "Mods for",
                    selection: Binding(
                        get: { current.id }, set: { id in Task { await store.selectInstance(id) } })
                ) {
                    ForEach(store.moddedInstances) { i in
                        Label {
                            Text(verbatim: i.name)
                            Text(verbatim: i.loaderLabel)
                        } icon: {
                            i.loader.glyph.menuImage
                        }
                        .tag(i.id)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("New mods instance", systemImage: "plus") { nav.newModsInstance(store) }
            } label: {
                HStack(spacing: 8) {
                    Text("For").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    Text(verbatim: current.name).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    PixelIcon(current.loader.glyph, size: 16)
                    Text(verbatim: "\(current.loaderLabel) ▾").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                        .lineLimit(1).layoutPriority(1)
                }
                .padding(.horizontal, 12).padding(.bottom, 2)
                .frame(minHeight: 44)
                .block(.button, lip: 4)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .blockPointer()
            .blockFocusRing()
            .accessibilityLabel(Text("Mods for"))
            .accessibilityValue(Text(verbatim: "\(current.name), \(current.loaderLabel)"))
        }
    }

    /// M01 with no instance that runs mods: popular mod icons over the one action. Never names a loader; P04 picks one.
    struct ModsHero: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @State private var popular: [ProjectSummary] = []

        var body: some View {
            VStack(spacing: 14) {
                // Real popular mods only; while loading or offline, a plain icon instead of sample mods.
                if popular.isEmpty { PixelIcon(.chest, size: 64) } else { collage(Array(popular.prefix(6))) }
                VStack(spacing: 6) {
                    Text("Play with mods").cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text("Mods run in their own instance. Make one to start.").cofreFont(.secondary)
                        .foregroundStyle(Color.cofre.muted).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                BlockButton("Make a mods instance", role: .primary, size: .large) { nav.newModsInstance(store) }
                    .padding(.horizontal, 14)
            }
            .padding(.bottom, 14)
            .block(.panel)
            // Popular mods for any instance. Offline, the sample set stands in (tinted ores until icons load).
            .task { popular = (try? await store.backend.search(ProjectQuery())) ?? [] }
        }

        /// Mod icons floating over a dusk scene, tilted like stickers.
        private func collage(_ icons: [ProjectSummary]) -> some View {
            // x, y (0…1 of the scene), size, degrees.
            let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [
                (0.50, 0.50, 64, 0), (0.20, 0.36, 46, -9), (0.80, 0.34, 48, 8),
                (0.33, 0.78, 38, 6), (0.68, 0.80, 40, -6), (0.08, 0.80, 30, 12),
            ]
            return GeometryReader { g in
                ZStack {
                    PixelScene(seed: 11, pixels: .init(width: 160, height: 60))
                    ForEach(Array(icons.enumerated()), id: \.element.id) { i, p in
                        let s = spots[i % spots.count]
                        ProjectIcon(project: p, size: s.2)
                            .shadow(color: .black.opacity(0.5), radius: 0, x: 3, y: 3)
                            .rotationEffect(.degrees(s.3))
                            .position(x: g.size.width * s.0, y: g.size.height * s.1)
                    }
                }
            }
            .frame(height: 150)
            .clipped()
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .accessibilityHidden(true)
        }
    }

    extension NavModel {
        /// P04 pre-filled for mods, from the hero or the switcher. It stays in Mods on the new instance.
        func newModsInstance(_ store: CofreStore) {
            store.newInstancePlan = store.planNewInstance()
            sheet = .newInstance
        }
    }
#endif
