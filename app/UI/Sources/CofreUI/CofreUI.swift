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
    @MainActor public static func makeRootViewController(services: CofreServices, nav: NavModel? = nil) -> UIViewController {
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

/// Web pages the UI links to. The domain is a placeholder until the site is published.
public enum CofreLinks {
    /// The one Mac command that puts the pairing key into Cofre over the cable, with its steps.
    public static let pairing = URL(string: "https://cofre.site/pair")!

    /// "cofre.site/pair": a URL without its scheme, for display.
    public static func short(_ url: URL) -> String { (url.host() ?? "") + url.path() }
}

#if canImport(UIKit)
/// Root view: setup wizard until every check passes, then the adaptive shell. Launch, sheets and Air's
/// UIKit screens are presented from here so every section shares them.
public struct CofreRootView: View {
    @State private var store: CofreStore
    @State private var nav: NavModel
    private let setupStart: Int?

    @MainActor public init(store: CofreStore, nav: NavModel? = nil, setupStart: Int? = nil) {
        _store = State(initialValue: store); _nav = State(initialValue: nav ?? NavModel()); self.setupStart = setupStart
    }

    public var body: some View {
        Group {
            if store.showsSetup {
                SetupFlow(startAt: setupStart)
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
        .background { commands }
        .fullScreenTakeover(isPresented: $nav.showingLaunch) { LaunchScreen().environment(store).environment(nav) }
        .blockSheet(item: $nav.sheet) { sheet in
            Group {
                switch sheet {
                case .newInstance: NewInstanceSheet()
                case .importPack: ImportPackSheet()
                }
            }
            .environment(store).environment(nav)
        }
        .fullScreenTakeover(item: $nav.showingAirScreen) { route in
            if let air = store.services.airScreens {
                AirScreenHost(make: {
                    switch route {
                    case .controlsEditor: air.controlsEditor()
                    case .forgeInstaller(let id): air.forgeInstaller(instanceID: id)
                    }
                }, onClose: { nav.showingAirScreen = nil })
                .ignoresSafeArea()
            }
        }
        .environment(store)
        .environment(nav)
        .environment(\.cofreTheme, store.theme)
        .preferredColorScheme(store.theme.colorScheme)
        .tint(Color.cofre.accent)
        .task { await store.start() }
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
            Button("Show log") { nav.section = .settings; nav.settingsPane = .logs }.keyboardShortcut("l", modifiers: .command)
        }
        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }
}
#endif
