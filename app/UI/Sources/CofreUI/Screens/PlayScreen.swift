#if canImport(UIKit)
    import SwiftUI
    import UniformTypeIdentifiers
    import CofreKit

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
        @State private var availableUpdate: Update?
        @AppStorage("cofre.dismissedUpdate") private var dismissedUpdate = ""
        public init() {}

        public var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Play") { AccountChip() }
                PaneScroll {
                    if let update = availableUpdate, update.version != dismissedUpdate {
                        UpdateBanner(update: update, dismiss: { dismissedUpdate = update.version })
                    }
                    if store.libraryLoaded { CofreDownloadsStrip().environment(nav) }
                    if store.libraryLoaded && !store.accounts.contains(where: { $0.state == .ready }) { Banner("Sign in to play Java Edition", icon: .head, tone: .warn) { BlockButton("Accounts", size: .small) { nav.section = .settings; nav.settingsPane = .accounts } } }
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
                        }
                        JumpBackIn(store: store, nav: nav)
                        if store.can(.controllerNavigation) { HintStrip() }
                    } else {
                        EmptyState("No instances yet", message: "Make one, or import a modpack.", icon: .grass) {
                            BlockButton("New instance", role: .primary) { nav.sheet = .newInstance }
                        }
                    }
                }
            }
            .task {
                let number = Int(Bundle.main.object(forInfoDictionaryKey: "CofreBuildNumber") as? String ?? "0") ?? 0
                availableUpdate = await UpdateChecker(installedBuildNumber: number).check()
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
                                if inst.restartRequired { Badge("Reopen Cofre", tone: .warn) }
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

    private struct UpdateBanner: View {
        let update: CofreKit.Update
        let dismiss: () -> Void
        var body: some View {
            HStack(spacing: 10) {
                PixelIcon(.bolt, size: 18)
                Text("Update available · \(update.version) · What's new")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Update") { UIApplication.shared.open(update.installURL) }
                Button("Dismiss") { dismiss() }
            }
        }

    }

    /// Worlds. New worlds are made in game, so there's no "+ New" here. Servers have their own pane.
    public struct WorldsPane: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @State private var model = WorldsModel()
        @State private var showingImport = false
        public init() {}
        public var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Worlds") {
                    Button { showingImport = true } label: { PixelIcon(.paper, size: 16) }
                        .buttonStyle(.plain).accessibilityLabel("Import world")
                }
                PaneScroll(spacing: 5) {
                    if let error = model.error { Banner(error, icon: .cross, tone: .danger) }
                    if let undo = model.undoLabel {
                        Banner(undo, icon: .check, tone: .success) { BlockButton("Undo", size: .small) { model.undoDelete() } }
                    }
                    if model.worlds.isEmpty {
                        EmptyState("No worlds yet", message: "Play once and your worlds show up here.", icon: .grass)
                    } else {
                        ForEach(model.worlds) { world in
                            WorldFileRow(world: world, model: model, store: store, nav: nav)
                        }
                    }
                }
            }
            .task(id: store.activeInstance?.id) { model.load(instanceID: store.activeInstance?.id, from: store.instanceStore) }
            .refreshable { model.refresh() }
            .fileImporter(isPresented: $showingImport, allowedContentTypes: [.zip]) { result in
                if case .success(let url) = result { _ = url.startAccessingSecurityScopedResource(); model.import(url); url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private struct JumpBackIn: View {
        let store: CofreStore
        let nav: NavModel
        @State private var model = WorldsModel()
        var body: some View {
            Group {
                if !model.worlds.isEmpty {
                    ListSection("Jump back in") {
                    ForEach(model.worlds.prefix(3)) { world in
                        Row(world.displayName, subtitle: [world.gameMode, Fmt.ago(world.lastPlayed), Fmt.bytes(world.sizeBytes)].compactMap { $0 }.joined(separator: " · ")) {
                            WorldGlyph(data: world.iconPNG)
                        } trailing: {
                            BlockButton("Play", icon: .play, size: .small) {
                                guard let instance = model.instance else { return }
                                startLaunch(store, nav, instanceID: instance.id, rejoin: RejoinIntent(instanceID: instance.id, kind: .world, target: world.folder, displayName: world.displayName))
                            }
                        }
                    }
                    }
                }
            }
            .task(id: store.activeInstance?.id) { model.load(instanceID: store.activeInstance?.id, from: store.instanceStore) }
        }
    }

    private struct WorldFileRow: View {
        let world: World
        let model: WorldsModel
        let store: CofreStore
        let nav: NavModel
        var body: some View {
            Row(world.displayName, subtitle: [world.gameMode, Fmt.ago(world.lastPlayed), Fmt.bytes(world.sizeBytes)].compactMap { $0 }.joined(separator: " · ")) {
                WorldGlyph(data: world.iconPNG)
            } trailing: {
                BlockButton("Play", icon: .play, role: .primary, size: .small) {
                    guard let instance = model.instance else { return }
                    startLaunch(store, nav, instanceID: instance.id, rejoin: RejoinIntent(instanceID: instance.id, kind: .world, target: world.folder, displayName: world.displayName))
                }
            }
            .contextMenu {
                Button("Play") { guard let instance = model.instance else { return }; startLaunch(store, nav, instanceID: instance.id, rejoin: RejoinIntent(instanceID: instance.id, kind: .world, target: world.folder, displayName: world.displayName)) }
                Button("Back up") { if let url = model.backUp(world) { presentShareSheet(url) } }
                Button("Export") { if let url = model.export(world) { presentShareSheet(url) } }
                if let target = store.instanceStore.flatMap({ try? $0.list().first(where: { $0.id != model.instance?.id }) }) {
                    Button("Copy to instance") { model.copy(world, to: target) }
                }
                Button("Delete", role: .destructive) { model.delete(world) }
            }
        }
    }

    private struct WorldGlyph: View {
        let data: Data?
        var body: some View {
            if let data, let image = UIImage(data: data) { Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 28, height: 28) }
            else { InstanceGlyph(icon: .init(glyph: .grass), size: 28) }
        }
    }
#endif
