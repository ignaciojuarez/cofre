import CofreKit
import CofreUI
import UIKit

@objc(CofreRootViewController)
public final class CofreRootViewController: UIViewController {
    private let bridge: any CofreAirBridging
    public init(bridge: any CofreAirBridging) { self.bridge = bridge; super.init(nibName: nil, bundle: nil) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("CofreRootViewController requires bridge") }
    public override func viewDidLoad() {
        super.viewDidLoad()
        CofreUIKitTheme.apply()
        let backend = CofreBackendAdapter(bridge: bridge)
        // Air keeps launcher_profiles.json in its game folder and decides each profile's own folder.
        let bridge = self.bridge
        let instances = ProcessInfo.processInfo.environment["POJAV_GAME_DIR"].flatMap { path in
            try? InstanceStore(root: URL(fileURLWithPath: path)) { id, _ in bridge.gameDirectory(forProfile: id) }
        }
        let services = CofreServices(backend: backend, instances: instances)
        let root = CofreUI.makeRootViewController(services: services)
        addChild(root); root.view.frame = view.bounds; root.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(root.view); root.didMove(toParent: self)
    }
}
