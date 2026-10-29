import UIKit
import CofreUI

/// Host for Cofre's production SwiftUI shell inside Air's existing UIKit scene.
@objc(CofreRootViewController)
public final class CofreRootViewController: UIViewController {
    private var child: UIViewController?
    public override func viewDidLoad() {
        super.viewDidLoad()
        CofreUIKitTheme.apply()
        let backend = CofreBackendAdapter()
        let services = CofreServices(backend: backend, airScreens: AirScreensAdapter())
        let root = CofreUI.makeRootViewController(services: services)
        addChild(root); root.view.frame = view.bounds; root.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(root.view); root.didMove(toParent: self); child = root
        NSLog("[Cofre] UI root installed")
    }
}

@MainActor
private final class AirScreensAdapter: NSObject, AirScreens {
    func controlsEditor() -> UIViewController { unavailable("controls editor") }
    func forgeInstaller(instanceID: String) -> UIViewController { unavailable("Forge installer") }
    private func unavailable(_ name: String) -> UIViewController {
        let vc = UIViewController(); vc.view.backgroundColor = .systemBackground; vc.title = "Unavailable"; NSLog("[Cofre] %@ unavailable", name); return vc
    }
}
