#if canImport(UIKit)
    import SwiftUI

    // P01 Play home + Worlds | Servers. AdaptiveSplit: side by side on regular, one Play · Worlds · Servers picker on
    // compact.

    public struct PlaySection: View {
        @Environment(NavModel.self) private var nav
        public init() {}
        public var body: some View {
            @Bindable var nav = nav
            AdaptiveSplit(primaryMin: 480, secondaryWidth: 380, fallback: .panes(["Play", "Worlds", "Servers"])) {
                PlayHomePane()
            } secondary: {
                PlaySidePane()
            }
            .selection($nav.playPane)
        }
    }

    public struct PlayHomePane: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        public init() {}

        public var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Play") { AccountChip() }
                PaneScroll {
                    if store.setupCompleted, store.setup.pairing.isFailed {
                        // Setup finished once: a live failure is a banner here, never the wizard again.
                        Banner("Your pairing key is missing. Run the Mac step again.", icon: .key, tone: .danger) {
                            BlockButton("Fix", size: .small) {
                                nav.section = .settings
                                nav.settingsPane = .jitJava
                            }
                        }
                    }
                    if !store.libraryLoaded {
                        Row("Loading instances…", leading: { Spinner() })
                    } else if let inst = store.activeInstance {
                        if inst.updatesAvailable > 0 {
                            Banner("\(inst.updatesAvailable) mod updates for \(inst.name)", icon: .book) {
                                BlockButton("Review", size: .small) {
                                    nav.section = .mods
                                    nav.mod = .installed
                                }
                            }
                        }
                        hero(inst)
                        controls(inst)
                        AdaptiveGrid(minItem: 120) {
                            Stat(
                                store.isJITReady ? "OK" : "Off", label: "JIT · auto",
                                tone: store.isJITReady ? .success : .danger)
                            Stat(
                                store.preferences.autoRAM ? "Auto" : "\(store.preferences.ramMB / 1024) GB",
                                label: "Memory")
                            Stat("\(Int(store.preferences.resolution * 100))%", label: "Resolution")
                            Stat(GamePreferences.fpsCapOptions.first { $0.0 == store.preferences.fpsCap }?.1 ?? "\(store.preferences.fpsCap)", label: "FPS cap")
                        }
                        let recent = store.instances.filter { $0.id != inst.id }.prefix(3)
                        if !recent.isEmpty {
                            ListSection("Recent") {
                                ForEach(Array(recent)) { i in
                                    Row(
                                        i.name,
                                        subtitle: [i.loaderLabel, Fmt.agoLong(i.lastPlayed)].compactMap { $0 }.joined(
                                            separator: " · ")
                                    ) {
                                        InstanceGlyph(icon: i.icon, size: 24)
                                    } trailing: {
                                        BlockButton("Play", size: .small) { startLaunch(store, nav, instanceID: i.id) }
                                    }
                                }
                            }
                        }
                        if store.can(.controllerNavigation) { HintStrip() }
                    } else {
                        EmptyState("No instances yet", message: "Make one, or import a modpack.", icon: .grass) {
                            BlockButton("New instance", role: .primary) { nav.sheet = .newInstance }
                        }
                    }
                }
            }
        }

        private func hero(_ inst: InstanceSummary) -> some View {
            PixelScene(seed: 11, pixels: .init(width: 240, height: 110))
                .frame(height: width == .compact ? 170 : 230)
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 14) {
                        InstanceGlyph(icon: inst.icon, size: width == .compact ? 36 : 48).shadow(
                            color: .black, radius: 0, y: 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: inst.name).cofreFont(.display).foregroundStyle(.white).lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .shadow(color: .black, radius: 0, y: 2)
                            HStack(spacing: 4) {
                                Badge(loader: inst.loader, version: inst.gameVersion)
                                if let n = inst.modCount { Badge("\(n) mods") }
                                Badge(
                                    store.isJITReady ? "Ready" : "JIT off", tone: store.isJITReady ? .success : .danger)
                            }
                        }
                    }
                    .padding(width == .compact ? 12 : 18)
                }
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                .accessibilityElement(children: .combine)
        }

        private func instanceBinding(_ inst: InstanceSummary) -> Binding<String> {
            Binding<String>(
                get: { inst.id },
                set: { (id: String) -> Void in
                    Task { @MainActor in await store.selectInstance(id) }
                })
        }

        @ViewBuilder private func controls(_ inst: InstanceSummary) -> some View {
            let picker = SelectButton(
                "Instance", selection: instanceBinding(inst),
                options: store.instances.map { ($0.id, $0.name) }
            )
            .keyboardShortcut("k", modifiers: .command)
            let play = BlockButton("Play", icon: .play, role: .primary, size: .large, fullWidth: true) {
                startLaunch(store, nav)
            }
            .keyboardShortcut(.return, modifiers: .command)
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
        }
    }

    /// Worlds. New worlds are made in game, so there's no "+ New" here. Servers have their own pane.
    public struct WorldsPane: View {
        @Environment(CofreStore.self) private var store
        public init() {}
        public var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Worlds")
                PaneScroll(spacing: 5) {
                    if store.worlds.isEmpty {
                        EmptyState("No worlds yet", message: "Play once and your worlds show up here.", icon: .grass)
                    } else {
                        WorldRows(worlds: store.worlds)
                    }
                }
            }
        }
    }
#endif
