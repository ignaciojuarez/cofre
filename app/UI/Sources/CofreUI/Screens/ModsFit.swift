#if canImport(UIKit)
    import SwiftUI

    // Mods on an instance that can't run them. Vanilla leads M01 with "Make a mods instance"; "Get" on a mod the
    // active instance can't run opens the misfit sheet: get it in an instance that runs it, or make one.

    /// M01 on Vanilla: popular mod icons over the one action. Never names a loader; P04 picks one.
    struct ModsHero: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav

        var body: some View {
            VStack(spacing: 14) {
                collage(Array(store.results.prefix(6)))
                VStack(spacing: 6) {
                    Text("This instance can't run mods").cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text("Make a mods instance to play with these.").cofreFont(.secondary)
                        .foregroundStyle(Color.cofre.muted).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                VStack(spacing: 8) {
                    BlockButton("Make a mods instance", role: .primary, size: .large) {
                        store.newInstancePlan = store.planNewInstance()
                        nav.sheet = .newInstance
                    }
                    if let other = store.moddedInstance {
                        BlockButton("Switch to \(other.name)", role: .ghost) {
                            Task { await store.selectInstance(other.id) }
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 14)
            .block(.panel)
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

    /// "Get" on a mod the active instance can't run. One primary: get it in an instance that runs it, or make one.
    struct MisfitSheet: View {
        let misfit: ModMisfit
        @Environment(CofreStore.self) private var store
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            let p = misfit.project
            VStack(spacing: 14) {
                ProjectIcon(project: p, size: 72).padding(.top, 24)
                VStack(spacing: 6) {
                    Text("\(p.title) needs another instance").cofreFont(.title2).foregroundStyle(Color.cofre.ink)
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text(reason).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 8) {
                    if let other = misfit.fitting {
                        BlockButton("Get it in \(other.name)", role: .primary, size: .large) {
                            Task { await store.install(p, in: other) }
                        }
                        BlockButton("Make a new instance") { make() }
                    } else {
                        BlockButton("Make an instance for it", role: .primary, size: .large) { make() }
                    }
                    BlockButton("Cancel", role: .ghost) { dismiss() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }

        private var reason: String {
            misfit.instance.loader == .vanilla
                ? String(localized: "\(misfit.instance.name) can't run mods.")
                : String(localized: "It doesn't work with \(misfit.instance.loaderLabel).")
        }

        /// Opens P04 pre-filled once this sheet is gone (the Mods section's `onDismiss`).
        private func make() {
            store.newInstancePlan = misfit.plan
            store.misfit = nil
        }
    }
#endif
