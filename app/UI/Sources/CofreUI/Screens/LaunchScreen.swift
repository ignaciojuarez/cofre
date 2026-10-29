#if canImport(UIKit)
    import SwiftUI

    // P02 Launch. FullScreenTakeover + AdaptiveSplit(.stack): scene and XP bar beside the stages and live log;
    // stacked on compact with the log behind a button.

    public struct LaunchScreen: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        public init() {}

        public var body: some View {
            AdaptiveSplit(primaryMin: 420, secondaryWidth: 440, fallback: .stack) {
                LaunchHero()
            } secondary: {
                LaunchStages()
            }
            .background(Color.cofre.page.ignoresSafeArea())
            .background {
                // Esc: a hidden cancel button works even when nothing has focus.
                Button("Cancel launch") {
                    Task { await store.cancelLaunch() }
                    nav.showingLaunch = false
                }
                .keyboardShortcut(.cancelAction).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            }
            .onChange(of: store.launch?.stage) { _, stage in
                // VoiceOver hears progress at most every 2 s (spec §2 #13).
                guard let p = store.launch, let stage, Date.now.timeIntervalSince(lastAnnouncement) >= 2 || p.finished
                else { return }
                lastAnnouncement = .now
                AccessibilityNotification.Announcement(
                    p.finished
                        ? String(localized: "In game")
                        : String(localized: "Step \(stage) of \(p.of), \(p.title)")
                ).post()
            }
        }
        @State private var lastAnnouncement = Date.distantPast
    }

    private struct LaunchHero: View {
        @Environment(CofreStore.self) private var store
        @Environment(\.widthClass) private var width

        var body: some View {
            let p = store.launch
            let inst = store.activeInstance
            ZStack(alignment: .bottomLeading) {
                PixelScene(seed: 7, pixels: .init(width: 200, height: 140)).ignoresSafeArea()
                LinearGradient(
                    colors: [.black.opacity(0.1), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    if let inst {
                        Text(verbatim: "\(inst.name) · \(inst.loaderLabel)").cofreFont(.label).foregroundStyle(
                            .white.opacity(0.85))
                    }
                    Text(title(p)).cofreFont(.display).foregroundStyle(.white).shadow(color: .black, radius: 0, y: 2)
                        .accessibilityAddTraits(.isHeader)
                    ProgressView(value: p?.fraction ?? 0).progressViewStyle(.xp())
                    if let p {
                        Text(verbatim: "Step \(p.stage) of \(p.of)" + (p.detail.map { " · \($0)" } ?? ""))
                            .cofreFont(.label).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(width == .compact ? 20 : 32)
                .padding(.bottom, width == .compact ? 0 : 4)
            }
            .frame(minHeight: width == .compact ? 300 : nil)
            .clipped()
            .accessibilityElement(children: .combine)
        }

        private func title(_ p: LaunchProgress?) -> LocalizedStringKey {
            if store.launchError != nil { return "Launch failed" }
            return p?.finished == true ? "In game" : "Launching…"
        }
    }

    private struct LaunchStages: View {
        @Environment(CofreStore.self) private var store
        @Environment(NavModel.self) private var nav
        @Environment(\.widthClass) private var width
        @State private var showLog = false

        private var stageNames: [String] {
            let java = store.activeInstance?.javaVersion.map { "Java \($0)" } ?? "Java"
            return ["JIT", java, "Libraries", "Assets", "Mods", "Renderer", "First frame", "In game"]
        }

        var body: some View {
            let p = store.launch
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ListSection("Stages", spacing: 4) {
                            ForEach(Array(stageNames.enumerated()), id: \.offset) { i, name in
                                let n = i + 1
                                let cur = p?.stage ?? 0
                                let state: CheckState =
                                    n < cur || p?.finished == true
                                    ? .ready
                                    : n == cur ? (store.launchError != nil ? .failed("") : .checking) : .unknown
                                Row(
                                    name, leading: { StatusMark(state: state).frame(width: 14) },
                                    trailing: {
                                        if n == cur, let f = p?.fraction, p?.finished != true {
                                            Meta("\(Int(f * 100))%")
                                        }
                                    }
                                )
                                .dimmed(state == .unknown)
                            }
                        }
                        if let err = store.launchError {
                            Banner(err, icon: .cross, tone: .danger)
                            // A next step, not just the message: JIT first, memory second.
                            HStack(spacing: 8) {
                                BlockButton("Test JIT", icon: .bolt) {
                                    close()
                                    nav.section = .settings
                                    nav.settingsPane = .jitJava
                                    Task { await store.testJIT() }
                                }
                                BlockButton("Lower memory") {
                                    close()
                                    nav.section = .settings
                                    nav.settingsPane = .game
                                }
                            }
                        }
                        if width != .compact {
                            ListSection("Log") { LogView(lines: store.launchLog).frame(minHeight: 180) }
                        }
                    }
                    .padding(.horizontal, width == .compact ? 16 : 20).padding(.top, 20)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep Cofre open while it loads.").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    HStack(spacing: 8) {
                        if width == .compact {
                            BlockButton("Log") { showLog = true }.keyboardShortcut("l", modifiers: .command)
                        } else {
                            BlockButton("Copy log") {
                                UIPasteboard.general.string = store.launchLog.map {
                                    "\($0.time) [\($0.tag)] \($0.text)"
                                }.joined(separator: "\n")
                            }
                        }
                        if p?.finished == true || store.launchError != nil {
                            BlockButton("Close", role: .primary) { close() }
                        } else {
                            BlockButton("Cancel") {
                                Task {
                                    await store.cancelLaunch()
                                    nav.showingLaunch = false
                                }
                            }
                            .keyboardShortcut(".", modifiers: .command)
                        }
                    }
                }
                .padding(.horizontal, width == .compact ? 16 : 20).padding(.bottom, 16)
            }
            .blockSheet(isPresented: $showLog) {
                VStack(spacing: 10) {
                    SheetHeader("Log")
                    LogView(lines: store.launchLog).padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
        }

        private func close() {
            store.launch = nil
            nav.showingLaunch = false
        }
    }
#endif
