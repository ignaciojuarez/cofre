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
        let services = CofreServices(backend: backend, airScreens: AirScreensAdapter(bridge: bridge))
        let root = CofreUI.makeRootViewController(services: services)
        addChild(root); root.view.frame = view.bounds; root.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(root.view); root.didMove(toParent: self)
    }
}

@MainActor private final class AirScreensAdapter: NSObject, AirScreens {
    let bridge: any CofreAirBridging
    init(bridge: any CofreAirBridging) { self.bridge = bridge }
    func controlsEditor() -> UIViewController { bridge.controlsEditor() }
}
