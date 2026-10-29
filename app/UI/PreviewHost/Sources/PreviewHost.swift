import CofreUI
import SwiftUI
import UIKit

// Launch arguments (all optional):
//   -screen play|worlds|instances|mods|modpage|settings|jit|setup|launch|join|gameExit   (default play)
//   -exitReason memory|renderer|missingLibrary|mods|java|unknown|quit   Why the game stopped (-screen gameExit)
//   -exitDetails YES    Open its Details sheet
//   -joinState firstVisit|needsAttention|keyChanged|installing|update|error|ready|resolving|live   Join server sheet state
//   -joinURL cofre://join?server=…   Opens the sheet through the deep-link route instead
//   -setupStep 0…7      Setup step for -screen setup
//   -failVersions YES   Mod versions fail to load (-screen modpage)
//   -instance vanilla   Active instance (mock IDs: survival create cobblemon skyblock vanilla)
//   -instances a,b      Keep only these mock instances
//   -plan YES           Open New instance pre-filled from Mods ("Make a mods instance", "New mods instance")
//   -type xl|ax3        Dynamic Type override
//   -appearance light   Light theme
//   -canvas 1376x1032   Lay the UI out at this point size (scaled to fit) and write a full-size PNG
//                       to Documents/<snapshot>.png, e.g. an iPad 13" window on an 11" simulator.
//   -snapshot name      File name for -canvas output
//   -touch a|b|c|ipad|settings|sheet   Touch-controls design mock (-screen touch)

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let args = UserDefaults.standard
        var theme = CofreTheme.current
        if args.string(forKey: "appearance") == "light" { theme.appearance = .light }
        CofreUI.bootstrap(theme: theme)

        let screen = args.string(forKey: "screen") ?? "play"
        let services = CofreServices.mock(setupComplete: screen != "setup")
        let nav = NavModel()
        switch screen {
        case "instances": nav.section = .instances
        case "mods": nav.section = .mods
        case "modpage":
            nav.section = .mods
            nav.mod = .project("iris")
            (services.backend as? MockBackend)?.failVersions = args.bool(forKey: "failVersions")
        case "settings": nav.section = .settings
        case "jit":
            nav.section = .settings
            nav.settingsPane = .jitJava
        case "launch": nav.showingLaunch = true
        case "worlds": nav.playPane = 1
        case "join":
            nav.playPane = 1
            if let mock = services.backend as? MockBackend {
                // "live" reads the card like the app: resolving, then first visit.
                let state = args.string(forKey: "joinState")
                mock.serverJoinScenario =
                    state == "live" ? nil : state.flatMap(MockServerJoin.Scenario.init(rawValue:)) ?? .firstVisit
                if mock.serverJoinScenario == .resolving { mock.stepDelay = 60 }
            }
            if let link = args.string(forKey: "joinURL").flatMap(URL.init(string:)) {
                nav.open(link)
            } else {
                nav.serverJoin = ServerJoinRequest(server: MockServerJoin.ironwood.address)
            }
        default: break
        }

        if let mock = services.backend as? MockBackend, let keep = args.string(forKey: "instances") {
            let ids = keep.split(separator: ",").map(String.init)
            mock.instanceList.removeAll { !ids.contains($0.id) }
        }

        // Fresh setup progress every launch, so a finished run doesn't hide `-screen setup`.
        let defaults = UserDefaults(suiteName: "app.cofre.ui.previewhost.setup")!
        defaults.removePersistentDomain(forName: "app.cofre.ui.previewhost.setup")
        let store = CofreStore(services: services, defaults: defaults)
        if screen == "launch" { store.play("survival") }
        store.activeInstanceID = args.string(forKey: "instance")
        if args.bool(forKey: "plan") {
            Task { @MainActor in
                while !store.libraryLoaded { try? await Task.sleep(for: .milliseconds(100)) }
                store.newInstancePlan = store.planNewInstance()
                nav.sheet = .newInstance
            }
        }
        let setupStep = args.object(forKey: "setupStep") != nil ? args.integer(forKey: "setupStep") : nil
        let root: UIViewController =
            screen == "touch"
            ? UIHostingController(rootView: TouchControlsMockPage(args.string(forKey: "touch") ?? "sheet"))
            : screen == "gameExit"
            ? UIHostingController(
                rootView: GameExitView(
                    report: MockGameExit.report(
                        args.string(forKey: "exitReason").flatMap(GameExitReport.Reason.init) ?? .memory),
                    showDetails: args.bool(forKey: "exitDetails"), close: {}))
            : UIHostingController(rootView: CofreRootView(store: store, nav: nav, setupStart: setupStep))
        root.view.backgroundColor = .cofre.page
        let window = UIWindow(windowScene: scene)
        // On the window, so presented sheets get it too.
        switch args.string(forKey: "type") {
        case "xl": window.traitOverrides.preferredContentSizeCategory = .extraLarge
        case "ax3": window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraLarge
        default: break
        }
        window.overrideUserInterfaceStyle = theme.interfaceStyle
        if let canvas = args.string(forKey: "canvas").flatMap(Self.size(from:)) {
            window.rootViewController = CanvasController(
                child: root, canvas: canvas, snapshot: args.string(forKey: "snapshot") ?? screen)
        } else {
            window.rootViewController = root
        }
        window.makeKeyAndVisible()
        self.window = window
    }

    static func size(from s: String) -> CGSize? {
        let p = s.split(separator: "x").compactMap { Double($0) }
        return p.count == 2 ? CGSize(width: p[0], height: p[1]) : nil
    }
}

/// Hosts the UI at a fixed point size, scaled to fit the device, then writes a full-resolution PNG.
final class CanvasController: UIViewController {
    let child: UIViewController, canvas: CGSize, snapshot: String

    init(child: UIViewController, canvas: CGSize, snapshot: String) {
        self.child = child
        self.canvas = canvas
        self.snapshot = snapshot
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(child)
        child.view.bounds = CGRect(origin: .zero, size: canvas)
        view.addSubview(child.view)
        child.didMove(toParent: self)
        // Regular width in both directions, like a full-screen iPad window.
        child.traitOverrides.horizontalSizeClass = .regular
        child.traitOverrides.verticalSizeClass = .regular
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = min(view.bounds.width / canvas.width, view.bounds.height / canvas.height)
        child.view.transform = CGAffineTransform(scaleX: scale, y: scale)
        child.view.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                child.view.drawHierarchy(in: CGRect(origin: .zero, size: canvas), afterScreenUpdates: true)
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(
                "\(snapshot).png")
            try? image.pngData()?.write(to: url)
            print("[CofrePreviewHost] wrote \(url.path)")
        }
    }
}
