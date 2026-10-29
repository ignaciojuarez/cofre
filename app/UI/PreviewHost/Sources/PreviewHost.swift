import CofreUI
import SwiftUI
import UIKit

// Launch arguments (all optional):
//   -screen play|instances|mods|modpage|settings|setup|launch   (default play)
//   -setupStep 0…7      Setup step for -screen setup
//   -type xl|ax3        Dynamic Type override
//   -appearance light   Light theme
//   -canvas 1376x1032   Lay the UI out at this point size (scaled to fit) and write a full-size PNG
//                       to Documents/<snapshot>.png, e.g. an iPad 13" window on an 11" simulator.
//   -snapshot name      File name for -canvas output

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
        case "modpage": nav.section = .mods; nav.mod = .project("iris")
        case "settings": nav.section = .settings
        case "launch": nav.showingLaunch = true
        default: break
        }

        let store = CofreStore(services: services)
        if screen == "launch" { store.play("survival") }
        let setupStep = args.object(forKey: "setupStep") != nil ? args.integer(forKey: "setupStep") : nil
        let root = UIHostingController(rootView: CofreRootView(store: store, nav: nav, setupStart: setupStep))
        root.view.backgroundColor = .cofre.page
        switch args.string(forKey: "type") {
        case "xl": root.traitOverrides.preferredContentSizeCategory = .extraLarge
        case "ax3": root.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraLarge
        default: break
        }

        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = theme.interfaceStyle
        if let canvas = args.string(forKey: "canvas").flatMap(Self.size(from:)) {
            window.rootViewController = CanvasController(child: root, canvas: canvas, snapshot: args.string(forKey: "snapshot") ?? screen)
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
        self.child = child; self.canvas = canvas; self.snapshot = snapshot
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
            let format = UIGraphicsImageRendererFormat(); format.scale = 2
            let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                child.view.drawHierarchy(in: CGRect(origin: .zero, size: canvas), afterScreenUpdates: true)
            }
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("\(snapshot).png")
            try? image.pngData()?.write(to: url)
            print("[CofrePreviewHost] wrote \(url.path)")
        }
    }
}
