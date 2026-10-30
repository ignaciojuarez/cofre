import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Entry points for the shell. See README.md.
    public enum CofreUI {
        /// Registers fonts and applies the UIKit theme for Air's leftover screens. Safe to call more than once.
        @MainActor public static func bootstrap(theme: CofreTheme = .current) {
            CofreFonts.register()
            CofreTheme.current = theme
            CofreUIKitTheme.apply(theme)
        }

        /// The whole Cofre UI in one hosting controller. `CofreRootViewController` embeds this as its child.
        @MainActor public static func makeRootViewController(services: CofreServices, nav: NavModel? = nil)
            -> UIViewController
        {
            bootstrap()
            let store = CofreStore(services: services)
            let host = UIHostingController(rootView: CofreRootView(store: store, nav: nav ?? NavModel()))
            host.view.backgroundColor = .cofre.page
            host.overrideUserInterfaceStyle = CofreTheme.current.interfaceStyle
            store.onThemeChange = { [weak host] t in
                host?.overrideUserInterfaceStyle = t.interfaceStyle
                CofreUIKitTheme.applyInterfaceStyle(t, to: host?.view.window)
            }
            return host
        }
    }
#endif

/// Web pages the UI links to: the setup site on GitHub Pages (`docs/` in the Cofre repo).
/// Only hosts in `allowedHosts`; a unit test fails otherwise, because users paste what these pages show into Terminal.
public enum CofreLinks {
    public static let allowedHosts: Set<String> = ["ignaciojuarez.github.io", "github.com"]
    /// The setup site. Step 1 is how to get Cofre.
    public static let site = URL(string: "https://ignaciojuarez.github.io/cofre/")!
    /// The steps for the one Mac command that puts the pairing key into Cofre over the cable.
    public static let pairing = URL(string: "https://ignaciojuarez.github.io/cofre/pair/")!
    /// The script that command runs (Cofre's GitHub release; same as `docs/app.js`).
    public static let pairScript = URL(
        string: "https://github.com/ignaciojuarez/cofre/releases/latest/download/pair.sh")!
    /// What the user pastes into Terminal. Copy and Share hand over exactly this.
    public static let pairCommand = "curl -fsSL \(pairScript.absoluteString) | sh"
    public static let all = [site, pairing, pairScript]
    /// Settings → About: the repo and the author's X profile.
    public static let source = URL(string: "https://github.com/ignaciojuarez/cofre")!
    public static let author = URL(string: "https://x.com/ignaciojb")!

    /// "ignaciojuarez.github.io/cofre/pair": host and path without the scheme or trailing slash, for display.
    public static func short(_ url: URL) -> String {
        var s = (url.host() ?? "") + url.path()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}

#if canImport(UIKit)
    /// Root view: a neutral splash until setup state loads, the wizard for users who never finished it, then the
    /// adaptive shell. Users who finished once go straight to the shell on the first frame. Launch, sheets,
    /// confirmations and Air's UIKit screens are presented from here so every section shares them.
    public struct CofreRootView: View {
        @State private var store: CofreStore
        @State private var nav: NavModel
        @State private var rejoin: RejoinIntent?
        private let setupStart: Int?

        /// `setupStart` forces the wizard at that step (preview host); `nil` resumes where the user left off.
        @MainActor public init(store: CofreStore, nav: NavModel? = nil, setupStart: Int? = nil) {
            _store = State(initialValue: store)
            _nav = State(initialValue: nav ?? NavModel())
            _rejoin = State(initialValue: RejoinIntentStore.load())
            self.setupStart = setupStart
        }

        public var body: some View {
            // Size classes come from the window, not UIKit (see `SizeClasses`).
            GeometryReader { root(SizeClasses($0.size)) }
        }

        private func root(_ classes: SizeClasses) -> some View {
            let regular = classes.horizontal == .regular
            return Group {
                if !store.setupCompleted, let setupStart {
                    SetupFlow(startAt: setupStart)
                } else if !store.setupCompleted && !store.setupLoaded {
                    SplashView()
                } else if store.showsSetup {
                    SetupFlow(startAt: store.resumeStep)
                } else {
                    AdaptiveShell(nav: nav) { section in
                        switch section {
                        case .play: PlaySection()
                        case .instances: InstancesSection()
                        case .mods: ModsSection()
                        case .settings: SettingsSection()
                        }
                    }
                }
            }
            .id(store.theme.accent.id)
            .overlay(alignment: .top) { errorBanner }
            .alert(
                store.pendingConfirmation?.title ?? Text(verbatim: ""), isPresented: confirming,
                presenting: store.pendingConfirmation
            ) { c in
                Button(c.actionTitle, role: .destructive) {
                    Task {
                        await store.confirm(c)
                        if case .deleteInstance(let i) = c, nav.instance == i.id { nav.instance = nil }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { c in
                c.message
            }
            .alert(
                store.pendingModCompatibility?.first?.title ?? "Mod compatibility", isPresented: Binding(
                    get: { store.pendingModCompatibility != nil }, set: { if !$0 { store.pendingModCompatibility = nil } }))
            {
                Button("Turn off and play") { store.playAnywayAfterModWarning(turnOff: true); nav.showingLaunch = true }
                Button("Play anyway") { store.playAnywayAfterModWarning(turnOff: false); nav.showingLaunch = true }
                Button("Cancel", role: .cancel) { store.pendingModCompatibility = nil }
            } message: {
                Text(store.pendingModCompatibility?.map { "\($0.modName): \($0.reason)" }.joined(separator: "\n") ?? "")
            }
            .background { commands }
            .fullScreenTakeover(isPresented: $nav.showingLaunch) { LaunchScreen().environment(store).environment(nav) }
            .blockSheet(item: $nav.sheet) { sheet in
                Group {
                    switch sheet {
                    case .newInstance: NewInstanceSheet(plan: store.newInstancePlan)
                    case .importPack: ImportPackSheet()
                    }
                }
                .environment(store).environment(nav)
            }
            // Servers: Join on a server the instance can't join.
            .blockSheet(item: $nav.serverVersion, hugsContent: true, onDismiss: afterServerSheet) { choice in
                ServerVersionSheet(choice: choice).environment(store).environment(nav)
            }
            // Join server (GAP-14): a bottom sheet on compact, a centered card overlay on regular.
            .sheet(item: serverJoinRequest(card: false, regular: regular), onDismiss: startPendingJoinLaunch) {
                request in
                JoinServerSheet(request: request, style: .bottomSheet).environment(store).environment(nav)
                    .sizeClasses(nil)
            }
            .overlay {
                if let request = serverJoinRequest(card: true, regular: regular).wrappedValue {
                    JoinServerCard(request: request) {
                        nav.serverJoin = nil
                        startPendingJoinLaunch()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: serverJoinRequest(card: true, regular: regular).wrappedValue)
            .onOpenURL { nav.open($0) }
            .environment(store)
            .environment(nav)
            .environment(\.cofreTheme, store.theme)
            .preferredColorScheme(store.theme.colorScheme)
            .tint(Color.cofre.accent)
            .task {
                await store.start()
                if let intent = rejoin, store.setupCompleted {
                    rejoin = nil
                    RejoinIntentStore.clear()
                    try? await Task.sleep(for: .milliseconds(300))
                    startLaunch(store, nav, instanceID: intent.instanceID, rejoin: intent)
                }
            }
            .sizeClasses(classes)
        }

        /// GAP-14. Deep links can arrive any time; the sheet waits for the `.serverJoin` capability and finished setup.
        private func serverJoinRequest(card: Bool, regular: Bool) -> Binding<ServerJoinRequest?> {
            Binding(
                get: {
                    store.can(.serverJoin) && store.setupCompleted && regular == card
                        ? nav.serverJoin : nil
                },
                set: { nav.serverJoin = $0 })
        }

        /// A launch or P04 started from the server sheet waits until it has closed.
        private func afterServerSheet() {
            let next = nav.afterServerSheet
            nav.afterServerSheet = nil
            next?()
        }

        /// "Launch & Join" waits for the sheet to finish closing, so the launch takeover can present.
        private func startPendingJoinLaunch() {
            guard let id = store.pendingJoinLaunch else { return }
            store.pendingJoinLaunch = nil
            // The install made or changed a profile, so reload instances first.
            Task {
                await store.refreshLibrary()
                startLaunch(store, nav, instanceID: id)
            }
        }

        private var confirming: Binding<Bool> {
            Binding(get: { store.pendingConfirmation != nil }, set: { if !$0 { store.pendingConfirmation = nil } })
        }

        @ViewBuilder private var errorBanner: some View {
            if let err = store.lastError {
                Banner(err, icon: .cross, tone: .danger) { BlockButton("OK", size: .small) { store.lastError = nil } }
                    .padding(.horizontal, 16).padding(.top, 8)
                    .frame(maxWidth: 560)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }

        /// App-wide shortcuts (§3.4). Section shortcuts live on NavChrome; pane shortcuts on their buttons.
        private var commands: some View {
            ZStack {
                Button("New instance") { nav.sheet = .newInstance }.keyboardShortcut("n", modifiers: .command)
                Button("Import pack") { nav.sheet = .importPack }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Settings") { nav.section = .settings }.keyboardShortcut(",", modifiers: .command)
                Button("Show log") {
                    nav.section = .settings
                    nav.settingsPane = .logs
                }.keyboardShortcut("l", modifiers: .command)
            }
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    /// First frame for users who haven't finished setup, while their saved state loads. No wizard flash.
    private struct SplashView: View {
        var body: some View {
            AppIcon(size: 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PageBackground())
                .accessibilityLabel(Text(verbatim: "Cofre"))
        }
    }
#endif
