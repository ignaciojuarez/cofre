import CofreUI
import SwiftUI
import UIKit

// Launch arguments (all optional):
//   -screen play|worlds|servers|serversMock|instances|mods|modpage|settings|jit|about|controls|setup|launch|join|gameExit
//                       (default play)
//   -servers mine|loading|pinging|offline|empty|version|newInstance|joining
//                       Servers pane state (-screen servers, plan/servers.md)
//   (-screen serversMock) Layout B for comparison: worlds and servers as two sections of one list
//   -exitReason memory|renderer|missingLibrary|mods|java|unknown|quit   Why the game stopped (-screen gameExit)
//   -exitDetails YES    Open its Details sheet
//   -joinState firstVisit|needsAttention|keyChanged|installing|update|error|ready|resolving|live   Join server sheet state
//   -joinURL cofre://join?server=…   Opens the sheet through the deep-link route instead
//   -setupStep 0…7      Setup step for -screen setup
//   -failVersions YES   Mod versions fail to load (-screen modpage)
//   -instance vanilla   Active instance (mock IDs: survival create cobblemon skyblock vanilla)
//   -instances a,b      Keep only these mock instances
//   -plan YES           Open New instance pre-filled from Mods ("Make a mods instance", "New mods instance")
//   -mod sodium         Project for -screen modpage (default iris). -allVersions YES opens All versions
//   -fabric26 YES       Add "Fabric Mods" (Fabric 26.3, Sodium 0.9.2 installed) and make it the target
//   -get culling        Tap Get on that mock mod (-screen mods). With -getConfirm YES, also tap Install;
//                       -getFail fabric-api fails that download; -getSlow YES holds each download for a while
//   -type xl|ax3        Dynamic Type override
//   -canvas 1376x1032   Lay the UI out at this point size (scaled to fit) and write a full-size PNG
//                       to Documents/<snapshot>.png, e.g. an iPad 13" window on an 11" simulator.
//   -snapshot name      File name for -canvas output
//   -touch a|b|c|ipad|settings|sheet   Touch-controls design mock (-screen touch)
//   -draft play|instances|import|files|content|worlds|beforePlay|logs|crash|versions|accounts   Design draft
//   -draftState <state>  That area's state (plan/design-draft.md), e.g. -draft worlds -draftState undo

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let args = UserDefaults.standard
        CofreUI.bootstrap()

        let screen = args.string(forKey: "screen") ?? "play"
        let services = CofreServices.mock(setupComplete: screen != "setup")
        let nav = NavModel()
        switch screen {
        case "instances": nav.section = .instances
        case "mods": nav.section = .mods
        case "modpage":
            nav.section = .mods
            nav.mod = .project(args.string(forKey: "mod") ?? "iris")
        case "installed":
            nav.section = .mods
            nav.mod = .installed
            (services.backend as? MockBackend)?.failVersions = args.bool(forKey: "failVersions")
        case "settings": nav.section = .settings
        case "jit":
            nav.section = .settings
            nav.settingsPane = .jitJava
        case "about", "controls":
            nav.section = .settings
            nav.settingsPane = screen == "about" ? .about : .touch
        case "launch": nav.showingLaunch = true
        case "worlds": nav.playPane = 1
        case "servers":
            nav.playPane = 2
            if let mock = services.backend as? MockBackend {
                switch args.string(forKey: "servers") {
                case "loading": mock.serverDelay = 600
                case "pinging": mock.pingDelay = 600
                case "offline":
                    mock.serversOffline = true
                    mock.offline = true
                case "empty": mock.serverLists = [:]
                default: break
                }
            }
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
        if args.bool(forKey: "fabric26"), let mock = services.backend as? MockBackend {
            mock.instanceList.insert(
                InstanceSummary(
                    id: "fabric26", name: "Fabric Mods", loader: .fabric, gameVersion: "26.3", loaderVersion: "0.17.2",
                    icon: .init(glyph: .grass)), at: 0)
            if let i = mock.mods.firstIndex(where: { $0.id == "sodium" }) {
                mock.mods[i].version = "0.9.2+mc26.3"
                mock.mods[i].versionID = "sodium-092"
            }
        }
        if let id = args.string(forKey: "get"), let mock = services.backend as? MockBackend {
            mock.failDownload = args.string(forKey: "getFail")
            mock.stepDelay = args.bool(forKey: "getSlow") ? 30 : 0
            Task { @MainActor in
                while store.results.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
                store.get(id)
                guard args.bool(forKey: "getConfirm") else { return }
                while store.modInstalls[id]?.phase != .confirm { try? await Task.sleep(for: .milliseconds(100)) }
                store.confirmInstall(id)
            }
        }
        if screen == "servers", args.string(forKey: "servers") == "joining" {
            // Join on Emberfall Network: straight into the server.
            Task { @MainActor in
                while store.serversLoading || store.servers.count < 3 { try? await Task.sleep(for: .milliseconds(100)) }
                store.play("survival", server: store.live(store.servers[2]))
                nav.showingLaunch = true
            }
        }
        if screen == "servers", ["version", "newInstance"].contains(args.string(forKey: "servers")) {
            // Play on Oakridge Towny (1.20.4) from Survival+ (1.21.1).
            Task { @MainActor in
                while store.serversLoading || store.servers.count < 4 { try? await Task.sleep(for: .milliseconds(100)) }
                try? await Task.sleep(for: .milliseconds(300))
                guard case .otherVersion(let choice)? = store.route(store.servers[3]) else { return }
                if args.string(forKey: "servers") == "newInstance" {
                    store.planInstance(for: choice)
                    nav.sheet = .newInstance
                } else {
                    nav.serverVersion = choice
                }
            }
        }
        let setupStep = args.object(forKey: "setupStep") != nil ? args.integer(forKey: "setupStep") : nil
        let root: UIViewController =
            screen == "draft"
            ? UIHostingController(
                rootView: DraftPage(
                    args.string(forKey: "draft") ?? "play", state: args.string(forKey: "draftState") ?? ""))
            : screen == "touch"
            ? UIHostingController(rootView: TouchControlsMockPage(args.string(forKey: "touch") ?? "sheet"))
            : screen == "serversMock"
            ? UIHostingController(rootView: ServersVariationsMock())
            : screen == "gameExit"
            ? UIHostingController(
                rootView: GameExitView(
                    report: MockGameExit.report(
                        args.string(forKey: "exitReason").flatMap(GameExitReport.Reason.init) ?? .memory),
                    showDetails: args.bool(forKey: "exitDetails"), close: {}))
            : UIHostingController(
                rootView: CofreRootView(store: store, nav: nav, setupStart: setupStep)
                    .environment(\.showsAllVersions, args.bool(forKey: "allVersions")))
        root.view.backgroundColor = .cofre.page
        let window = UIWindow(windowScene: scene)
        // On the window, so presented sheets get it too.
        switch args.string(forKey: "type") {
        case "xl": window.traitOverrides.preferredContentSizeCategory = .extraLarge
        case "ax3": window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraLarge
        default: break
        }
        window.overrideUserInterfaceStyle = .dark
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
