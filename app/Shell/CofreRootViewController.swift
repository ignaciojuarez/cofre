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
        let instancesRoot = bridge.instances().compactMap { profile in
            guard let id = profile["id"] as? String,
                  let directory = bridge.gameDirectory(forProfile: id) else { return nil }
            return directory.deletingLastPathComponent()
        }.first
        let services = CofreServices(backend: backend, instancesRoot: instancesRoot)
        let root = CofreUI.makeRootViewController(services: services)
        addChild(root); root.view.frame = view.bounds; root.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(root.view); root.didMove(toParent: self)
    }
}
