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
                    case .controlsEditor: ControlsEditorContent()
                    case .jitJava: JITJavaContent()
                    case .accounts: AccountsDataContent()
                    case .logs: LogsContent()
                    case .look: LookContent()
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
                BlockSlider(
                    "Resolution", value: prefBinding(store, instanceID, \.resolution), in: 0.25...1, step: 0.05,
                    accessibilityValue: { "\(Int($0 * 100)) percent" }
                ) { "\(Int($0 * 100)) %" }
                VStack(alignment: .leading, spacing: 8) {
                    Text("FSR 1.0 upscale").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Segmented(
                        "FSR 1.0 upscale", selection: prefBinding(store, instanceID, \.fsrMode),
                        options: [(.off, "Off"), (.ultra, "Ultra"), (.quality, "Quality"), (.performance, "Perf")],
                        size: .small)
                }
                .padding(12).block(.panel)
                ToggleRow("FPS overlay", isOn: prefBinding(store, instanceID, \.fpsOverlay))
                ToggleRow("VSync", isOn: prefBinding(store, instanceID, \.vsync))
                HStack {
                    Text("FPS cap").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Spacer()
                    SelectButton(
                        "FPS cap", selection: prefBinding(store, instanceID, \.fpsCap),
                        options: [30, 60, 120].map { ($0, "\($0)") }
                    ).compactStyle()
                }
                .padding(.horizontal, 11).frame(minHeight: 44).block(.panel)
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
            BlockButton("Open controls editor", icon: .cmd) { nav.showingAirScreen = .controlsEditor }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(store.services.airScreens == nil)
        }
    }

    struct ControlsEditorContent: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        var body: some View {
            Text("Drag and resize buttons. Opens full screen.").cofreFont(.body).foregroundStyle(Color.cofre.inkSoft)
            if store.services.airScreens == nil {
                Banner("The controls editor isn't available yet.", icon: .cmd, tone: .warn)
            }
            BlockButton("Open controls editor", icon: .cmd, role: .primary) { nav.showingAirScreen = .controlsEditor }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(store.services.airScreens == nil)
            if width > .compact {
                ListSection("Keys") {
                    KeyHint("⌘Z", "Undo")
                    KeyHint("⌫", "Delete")
                    KeyHint("← →", "Nudge 1 pt · with ⇧, 10 pt")
                    KeyHint("⌘D", "Duplicate")
                    KeyHint("tab", "Next button")
                }
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
                        a.name, subtitle: a.isActive ? "\(a.kind) · active" : a.kind,
                        leading: { PixelIcon(.head, size: 26) },
                        trailing: {
                            BlockButton("Remove", role: .ghostDestructive, size: .small) {
                                store.pendingConfirmation = .removeAccount(a)
                            }
                        })
                }
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
        @State private var sharing = false
        var body: some View {
            Segmented(
                "Log", selection: $kind, options: [(.latest, "Latest"), (.crash, "Crash"), (.launcher, "Launcher")])
            LogView(lines: store.logs[kind] ?? []).frame(height: 300)
                .task(id: kind) { await store.streamLog(kind) }
            // Exports on tap: a live log stream never ends, so nothing can wait for it.
            BlockButton("Share log", role: .primary, isLoading: sharing) {
                Task {
                    sharing = true
                    if let url = await store.exportLog(kind) { presentShareSheet(url) }
                    sharing = false
                }
            }
            HStack(spacing: 8) {
                BlockButton("Copy") {
                    UIPasteboard.general.string = (store.logs[kind] ?? []).map { "\($0.time) [\($0.tag)] \($0.text)" }
                        .joined(separator: "\n")
                }
                BlockButton("Crash report") { kind = .crash }
            }
        }
    }

    // MARK: X07 Look & more

    struct LookContent: View {
        @Environment(CofreStore.self) private var store
        @State private var confirmReset = false
        var body: some View {
            ListSection("Look", spacing: 4) {
                HStack {
                    Text("Theme").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Spacer()
                    Segmented(
                        "Theme",
                        selection: Binding(get: { store.theme.appearance }, set: { store.applyTheme(appearance: $0) }),
                        options: [(.dark, "Dark"), (.light, "Light"), (.auto, "Auto")], size: .small
                    )
                    .frame(maxWidth: 220)
                }
                .padding(.horizontal, 11).padding(.vertical, 6).block(.panel)
                HStack(spacing: 8) {
                    Text("Accent").cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                    Spacer()
                    ForEach(AccentFamily.all) { a in
                        let on = store.theme.accent.id == a.id
                        Button {
                            store.applyTheme(accent: a)
                        } label: {
                            Rectangle().fill(Color(uiColor: UIColor(hex: a.face.dark)))
                                .overlay(alignment: .top) {
                                    Color(uiColor: UIColor(hex: a.faceBevel.dark)).frame(height: 3)
                                }
                                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                                .frame(width: 26, height: 26)
                                .overlay {
                                    if on { Rectangle().strokeBorder(Color.cofre.ink, lineWidth: 2).padding(-4) }
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .blockPointer()
                        .accessibilityLabel(Text(verbatim: a.name))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 11).block(.panel)
                // No handlers yet (GAP-13): shown only when the backend supports them.
                if store.can(.appIcon) { Row("App icon · background", trailing: { Meta("Pixel") }) }
                if store.can(.language) { Row("Language", trailing: { Meta("English") }) }
            }
            if store.can(.lanRoom) {
                ListSection("Play together", spacing: 4) {
                    Row("LAN room", trailing: { Meta("Terracotta") })
                }
            }
            ListSection("Extras", spacing: 4) {
                ToggleRow("AirPlay fullscreen", isOn: prefBinding(store, nil, \.airPlayFullscreen))
                ToggleRow("Capes (Cosmetica)", isOn: prefBinding(store, nil, \.capes))
                ToggleRow("Check for updates", isOn: prefBinding(store, nil, \.checkUpdates))
            }
            BlockButton("Reset all settings", role: .ghostDestructive) { confirmReset = true }
                .confirmationDialog("Reset all settings?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset", role: .destructive) {
                        store.save(GamePreferences())
                        store.applyTheme(accent: .purple, appearance: .dark)
                    }
                }
        }
    }

    // MARK: About (X06 second half): expiry, versions, source, licenses

    struct AboutContent: View {
        @Environment(CofreStore.self) private var store
        @State private var showingOFL = false
        var body: some View {
            let info = store.backend.appInfo()
            ListSection(spacing: 4) {
                if let s = store.signing {
                    Row("Works until", trailing: { Meta(s.expires.formatted(date: .abbreviated, time: .omitted)) })
                }
                Row("Version \(info.version) · Air \(info.airVersion)")
                Link(destination: info.sourceURL) { ValueRow("Source code", value: "GitHub") }.buttonStyle(
                    RowButtonStyle())
            }
            ListSection("Licenses", spacing: 4) {
                Row("Air", subtitle: "GPL-3.0")
                Row("Amethyst", subtitle: "GPL-3.0")
                Row("StikJIT", subtitle: "MPL-2.0")
                Row("idevice", subtitle: "MIT")
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
