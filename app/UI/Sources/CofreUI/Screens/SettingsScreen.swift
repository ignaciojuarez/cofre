#if canImport(UIKit)
    import SwiftUI

    // X00 index (Game · Controls · System) + panes X01–X07. On compact the index is the root list and each pane is
    // pushed (§3.5 #1); on regular the pane opens beside it in a readable column.

    public struct SettingsSection: View {
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        public init() {}
        public var body: some View {
            @Bindable var nav = nav
            AdaptiveListDetail(selection: $nav.settingsPane, defaultSelection: width == .compact ? nil : .game) {
                SettingsIndexPane()
            } detail: { pane in
                SettingsPaneView(pane: pane)
            }
        }
    }

    public struct SettingsIndexPane: View {
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        public init() {}
        public var body: some View {
            VStack(spacing: 0) {
                ColumnHeader("Settings")
                PaneScroll {
                    ForEach(SettingsPane.groups, id: \.1) { group in
                        ListSection(group.0, spacing: 4) {
                            ForEach(group.1) { pane in
                                let selected = width != .compact && (nav.settingsPane ?? .game) == pane
                                Button {
                                    nav.settingsPane = pane
                                } label: {
                                    Row(pane.title, isSelected: selected) {
                                        PixelIcon(
                                            pane.glyph, size: 18,
                                            tint: pane == .renderer ? Color.cofre.tone(.quilt) : nil)
                                    } trailing: {
                                        Chevron()
                                    }
                                }
                                .buttonStyle(RowButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    public struct SettingsPaneView: View {
        let pane: SettingsPane
        public init(pane: SettingsPane) { self.pane = pane }
        public var body: some View {
            VStack(spacing: 0) {
                ColumnHeader(pane.title)
                PaneScroll(readable: true) {
                    switch pane {
                    case .game: GameSettingsContent(instanceID: nil)
                    case .renderer: RendererContent()
                    case .touch: ControlsPane()
                    case .controller: ControllerContent()
                    case .jitJava: JITJavaContent()
                    case .accounts: AccountsDataContent()
                    case .logs: LogsContent()
                    case .about: AboutContent()
                    }
                }
            }
        }
    }

    /// Binding into the store's preferences that saves on change. `instanceID` scopes to one instance.
    @MainActor private func prefBinding<T>(
        _ store: CofreStore, _ instanceID: String?, _ key: WritableKeyPath<GamePreferences, T>
    ) -> Binding<T> {
        Binding(
            get: { (instanceID.map { store.preferences(for: $0) } ?? store.preferences)[keyPath: key] },
            set: { v in
                var p = instanceID.map { store.preferences(for: $0) } ?? store.preferences
                p[keyPath: key] = v
                store.save(p, instanceID: instanceID)
            }
        )
    }

    // MARK: X01 Game (also the instance detail "Options" tab)

    struct GameSettingsContent: View {
        let instanceID: String?
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav

        var body: some View {
            let p = instanceID.map { store.preferences(for: $0) } ?? store.preferences
            let ram = prefBinding(store, instanceID, \.ramMB)
            ListSection("Memory", spacing: 4) {
                ToggleRow("Auto RAM", isOn: prefBinding(store, instanceID, \.autoRAM))
                Text("Cofre picks a safe amount automatically.").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    .padding(.horizontal, 2)
                BlockSlider(
                    "Memory", value: Binding(get: { Double(ram.wrappedValue) }, set: { ram.wrappedValue = Int($0) }),
                    in: 1024...Double(p.deviceRAMMB), step: 256, note: "Closes while loading? Lower this.",
                    accessibilityValue: { "\(Int($0)) megabytes" }
                ) { "\(Fmt.mb(Int($0))) of \(p.deviceRAMMB / 1024) GB" }
                .disabled(p.autoRAM)
            }
            ListSection("Graphics", spacing: 4) {
                Button {
                    nav.section = .settings
                    nav.settingsPane = .renderer
                } label: {
                    ValueRow(
                        "Renderer", value: store.renderers.first { $0.id == p.renderer }?.name ?? p.renderer,
                        accent: true)
                }.buttonStyle(RowButtonStyle())
                ResolutionRow(scale: prefBinding(store, instanceID, \.resolution))
                ToggleRow("FPS overlay", isOn: prefBinding(store, instanceID, \.fpsOverlay))
                Text("VSync and Max Framerate are in the game: Options › Video Settings.")
                    .cofreFont(.caption).foregroundStyle(Color.cofre.muted).padding(.horizontal, 2)
            }
            ListSection("Audio", spacing: 4) {
                ToggleRow("Mute with switch", isOn: prefBinding(store, instanceID, \.muteWithSwitch))
                ToggleRow("Microphone", isOn: prefBinding(store, instanceID, \.microphone))
            }
        }
    }

    // MARK: X02 Renderer

    struct RendererContent: View {
        @Environment(CofreStore.self) private var store
        var body: some View {
            let current = prefBinding(store, nil, \.renderer)
            ListSection(spacing: 4) {
                ForEach(store.renderers) { r in
                    Button {
                        current.wrappedValue = r.id
                    } label: {
                        Row(r.name, subtitle: r.detail, isSelected: current.wrappedValue == r.id) {
                            Radio(isOn: current.wrappedValue == r.id)
                        } trailing: {
                            if r.recommended { Badge("Best", tone: .success) }
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            if store.can(.rendererTuning) {
                ListSection("MobileGlues", spacing: 4) {
                    HStack {
                        Text("Shader cache").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                        Spacer()
                        SelectButton(
                            "Shader cache", selection: prefBinding(store, nil, \.shaderCacheMB),
                            options: [256, 512, 1024].map { ($0, "\($0) MB") }
                        ).compactStyle()
                    }.padding(.horizontal, 11).frame(minHeight: 44).block(.panel)
                    HStack {
                        Text("Multidraw").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                        Spacer()
                        SelectButton(
                            "Multidraw", selection: prefBinding(store, nil, \.multidraw),
                            options: ["Auto", "Indirect", "Off"].map { ($0, $0) }
                        ).compactStyle()
                    }.padding(.horizontal, 11).frame(minHeight: 44).block(.panel)
                    ToggleRow("Compute shaders", isOn: prefBinding(store, nil, \.computeShaders))
                }
            }
        }
    }

    // MARK: X03 Controls (touch, controller, editor)

    /// Touch, input mode and look live in `ControlsPane` (Screens/Game).
    struct ControllerContent: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        var body: some View {
            ListSection(spacing: 4) {
                HStack {
                    Text("Layout").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Spacer()
                    SelectButton(
                        "Layout", selection: prefBinding(store, nil, \.controllerLayout),
                        options: ["Default", "Compact", "Builder"].map { ($0, $0) }
                    ).compactStyle()
                }.padding(.horizontal, 11).frame(minHeight: 44).block(.panel)
                ToggleRow("Gyro aim", isOn: prefBinding(store, nil, \.gyroAim))
                if store.can(.controllerNavigation) { HintStrip() }
            }
        }
    }

    // MARK: X04 JIT & Java

    struct JITJavaContent: View {
        @Environment(CofreStore.self) private var store
        var body: some View {
            let s = store.setup
            if s.jit.isReady {
                Banner("JIT ready · Attaches at each launch", icon: .bolt, tone: .success) {
                    Badge("On", tone: .success)
                }
            } else {
                Banner("JIT isn't ready. Run the test to see which step fails.", icon: .bolt, tone: .danger) {
                    Badge("Off", tone: .danger)
                }
            }
            JITFailure()
            ListSection(spacing: 4) {
                if let d = store.device { Row("Device", trailing: { Meta("\(d.jitMode) · \(d.model)") }) }
                Row(
                    "Local VPN",
                    trailing: { Badge(s.vpn.isReady ? "On" : "Off", tone: s.vpn.isReady ? .success : .danger) })
                Row(
                    "Pairing file",
                    trailing: {
                        Badge(s.pairing.isReady ? "Valid" : "Missing", tone: s.pairing.isReady ? .success : .danger)
                    })
                Row(
                    "Disk image",
                    trailing: { Badge(s.jit.isReady ? "Mounted" : "—", tone: s.jit.isReady ? .success : .neutral) })
            }
            if store.jitTesting || !store.jitSteps.isEmpty { JITStepRows() }
            if !s.pairing.isReady { PairingGuide() } else if store.pairingFromFile { DeleteCopyNote() }
            BlockButton("Test JIT", isLoading: store.jitTesting) { Task { await store.testJIT() } }
                .keyboardShortcut("j", modifiers: [.command, .option])
            if s.pairing.isReady { KeyFileCard(title: "Replace the key file") }
            ListSection("Java", spacing: 4) {
                Row(
                    "Runtime",
                    trailing: { Meta(store.preferences.java == "auto" ? "Auto per version" : store.preferences.java) })
                Row(
                    "Installed",
                    trailing: {
                        HStack(spacing: 4) {
                            ForEach(store.javaRuntimes) { Badge("\($0.major)", tone: $0.installed ? .neutral : .warn) }
                        }
                    })
                Field("JVM arguments", text: prefBinding(store, nil, \.jvmArgs), prompt: "-XX:+UseG1GC", kind: .mono)
                if store.can(.envVariables) {
                    let n = store.preferences.envVariables.count
                    Row(
                        "Env variables",
                        trailing: { Meta(n == 0 ? String(localized: "None") : String(localized: "\(n) set")) })
                }
            }
        }
    }

    // MARK: X05 Accounts & data

    struct AccountsDataContent: View {
        @Environment(CofreStore.self) private var store
        @State private var key = ""
        var body: some View {
            ListSection(spacing: 4) {
                ForEach(store.accounts) { a in
                    Row(
                        a.name, subtitle: accountSubtitle(a),
                        leading: { PixelIcon(.head, size: 26) },
                        trailing: {
                            HStack(spacing: 6) {
                                if a.state == .expired { BlockButton("Sign in again", role: .primary, size: .small) { Task { await store.signIn() } } }
                                Badge(a.state == .demo ? "Demo" : (a.isActive ? "Active" : a.state == .expired ? "Expired" : "Ready"), tone: a.state == .expired ? .danger : a.state == .demo ? .warn : .success)
                                BlockButton("Remove", role: .ghostDestructive, size: .small) { store.pendingConfirmation = .removeAccount(a) }
                            }
                        })
                }
                if store.accounts.contains(where: { $0.state == .demo }) { Banner("This account doesn't own Java Edition · demo only", icon: .head, tone: .warn) }
                BlockButton("Add account", icon: .head) { Task { await store.signIn() } }
            }
            ListSection("Downloads", spacing: 4) {
                HStack {
                    Text("Source").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Spacer()
                    Segmented(
                        "Source", selection: prefBinding(store, nil, \.downloadSource),
                        options: [(.official, "Official"), (.mirror, "Mirror")], size: .small
                    )
                    .frame(maxWidth: 200)
                }
                .padding(.horizontal, 11).padding(.vertical, 6).block(.panel)
                ToggleRow("Verify files", isOn: prefBinding(store, nil, \.verifyFiles))
            }
            ListSection("CurseForge key", spacing: 4) {
                Field("CurseForge key", text: $key, prompt: "Paste your key", kind: .secure, trailingNote: "Keychain")
                    .onSubmit { store.setCurseForgeKey(key) }
                HStack(spacing: 8) {
                    Text("Your own key. Never bundled.").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    Spacer()
                    BlockButton("Save", size: .small) { store.setCurseForgeKey(key) }.disabled(
                        key == (store.curseForgeKey ?? ""))
                }
            }
            .onAppear { key = store.curseForgeKey ?? "" }
            if let s = store.storage {
                ListSection("Storage · \(Fmt.bytes(s.total) ?? "")", spacing: 8) {
                    StorageBar(usage: s)
                    HStack(spacing: 12) {
                        legend("Game", .accent)
                        legend("Java", .warn)
                        legend("Cache", .success)
                        Spacer()
                        BlockButton("Clear cache", size: .small) { Task { await store.clearCache() } }
                    }
                }
            }
        }

        private func accountSubtitle(_ a: Account) -> String {
            if a.state == .expired { return "Signed out · sign in again" }
            if a.state == .demo { return "Doesn't own Java Edition · demo only" }
            return a.isActive ? "\(a.kind) · active" : a.kind
        }

        private func legend(_ t: LocalizedStringKey, _ tone: Tone) -> some View {
            HStack(spacing: 5) {
                Rectangle().fill(Color.cofre.tone(tone)).frame(width: 10, height: 10)
                Text(t)
            }
            .cofreFont(.label).foregroundStyle(Color.cofre.muted)
        }
    }

    private struct StorageBar: View {
        let usage: StorageUsage
        var body: some View {
            GeometryReader { g in
                let w = g.size.width - 4
                let t = Double(max(usage.total, 1))
                HStack(spacing: 0) {
                    Color.cofre.tone(.accent).frame(width: w * Double(usage.gameBytes) / t)
                    Color.cofre.tone(.warn).frame(width: w * Double(usage.javaBytes) / t)
                    Color.cofre.tone(.success).frame(width: w * Double(usage.cacheBytes) / t)
                }
                .padding(2)
            }
            .frame(height: 18)
            .background(Color.cofre.well)
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .accessibilityElement()
            .accessibilityLabel(Text("Storage"))
            .accessibilityValue(
                Text(
                    "Game \(Fmt.bytes(usage.gameBytes) ?? ""), Java \(Fmt.bytes(usage.javaBytes) ?? ""), cache \(Fmt.bytes(usage.cacheBytes) ?? "")"
                ))
        }
    }

    // MARK: X06 Logs

    struct LogsContent: View {
        @Environment(CofreStore.self) private var store
        @State private var kind = LogKind.latest
        @State private var search = ""
        @State private var level = "all"
        @State private var reportURL: URL?
        @State private var reportPreview: ReportPreviewData?
        @State private var sharing = false
        private var shown: [LogLine] {
            (store.logs[kind] ?? []).filter { line in
                let levelOK = level == "all" || (level == "problems" && (line.level == .warning || line.level == .error)) || (level == "errors" && line.level == .error)
                return levelOK && (search.isEmpty || line.text.localizedCaseInsensitiveContains(search))
            }
        }
        var body: some View {
            Segmented("Log", selection: $kind, options: [(.latest, "Game"), (.crash, "Crash"), (.launcher, "Cofre")])
            Field("Search log", text: $search, kind: .search, trailingNote: search.isEmpty ? nil : "\(shown.count) found")
            ChipGroup("Show", selection: $level, options: [("all", "All"), ("problems", "Warnings"), ("errors", "Errors")])
            LogView(lines: shown, follow: true).frame(minHeight: 260)
                .task(id: kind) { await store.streamLog(kind) }
            HStack(spacing: 8) {
                BlockButton("Share report…", icon: .paper, role: .primary, isLoading: sharing) {
                    Task {
                        sharing = true
                        async let url = store.exportReport()
                        async let preview = store.reportPreview()
                        reportURL = await url; reportPreview = await preview; sharing = false
                    }
                }
            }
            GameOwnsNote("Reads the game's latest.log as it writes. Nothing leaves this iPhone unless you share it.")
                .blockSheet(item: Binding(get: { reportURL.map { ReportSheetItem(url: $0, preview: reportPreview) } }, set: { _ in reportURL = nil })) { item in
                    if let preview = item.preview { ReportPreviewSheet(preview: preview, url: item.url) }
                }
        }
    }
    private struct ReportSheetItem: Identifiable { let id = UUID(); let url: URL; let preview: ReportPreviewData? }

    // MARK: About (X06 second half): Cofre, its maker, expiry, credits

    struct AboutContent: View {
        @Environment(CofreStore.self) private var store
        @State private var showingOFL = false
        /// Open-source projects Cofre is built on: name, role · license, repo.
        private static let credits: [(String, String, URL)] = [
            ("Air", "Game engine · GPL-3.0", URL(string: "https://github.com/herbrine8403/Amethyst-iOS-MyRemastered")!),
            ("Amethyst", "Launcher Air grew from · GPL-3.0", URL(string: "https://github.com/AngelAuraMC/Amethyst-iOS")!),
            ("StikJIT", "JIT · MPL-2.0", URL(string: "https://github.com/StikDebug/StikJIT")!),
            ("idevice", "Pairing · MIT", URL(string: "https://github.com/jkcoxson/idevice")!),
        ]
        var body: some View {
            let info = store.backend.appInfo()
            VStack(spacing: 6) {
                AppIcon(size: 64)
                Text(verbatim: "Cofre").cofreFont(.title).foregroundStyle(Color.cofre.ink)
                Text(verbatim: "Version \(info.version)").cofreFont(.label).foregroundStyle(Color.cofre.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            ListSection(spacing: 4) {
                Link(destination: CofreLinks.author) { ValueRow("Made by Ignacio", value: "@ignaciojb") }
                    .buttonStyle(RowButtonStyle())
                Link(destination: info.sourceURL) { ValueRow("Source code", value: "GitHub") }
                    .buttonStyle(RowButtonStyle())
                if let s = store.signing {
                    Row("Works until", trailing: { Meta(s.expires.formatted(date: .abbreviated, time: .omitted)) })
                }
            }
            ListSection("Credits", spacing: 4) {
                ForEach(Self.credits, id: \.0) { name, role, url in
                    // Air's own version helps when reporting engine bugs upstream.
                    let detail = name == "Air" && !info.airVersion.isEmpty ? "\(role) · \(info.airVersion)" : role
                    Link(destination: url) { Row(name, subtitle: detail, trailing: { Chevron() }) }
                        .buttonStyle(RowButtonStyle())
                }
                Button {
                    showingOFL = true
                } label: {
                    ValueRow("Pixelify Sans · Geist · Geist Mono", value: "OFL 1.1")
                }.buttonStyle(RowButtonStyle())
            }
            Text(
                "Unofficial. Not an official Minecraft product, and not approved by or associated with Mojang or Microsoft."
            )
            .cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
            .blockSheet(isPresented: $showingOFL) {
                VStack(spacing: 10) {
                    SheetHeader("Font licenses")
                    ScrollView {
                        Text(
                            verbatim: CofreFonts.licenseURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                                ?? "OFL.txt missing"
                        )
                        .cofreFont(.code).foregroundStyle(Color.cofre.inkSoft).padding(16).textSelection(.enabled)
                    }
                }
            }
        }
    }
#endif
