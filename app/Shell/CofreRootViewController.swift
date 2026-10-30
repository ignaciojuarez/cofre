import CofreKit
import CofreUI
import UIKit

@objc(CofreRootViewController)
public final class CofreRootViewController: UIViewController {
    /// Forward this from the application's UIApplicationDelegate when iOS wakes Cofre for a background session.
    public static func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == "com.cofre.downloads" else { completionHandler(); return }
        DownloadQueue.shared.handleBackgroundEvents(completion: completionHandler)
    }
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
        backend.serverInstances = instances
        let services = CofreServices(backend: backend, instances: instances)
        let root = CofreUI.makeRootViewController(services: services)
        addChild(root); root.view.frame = view.bounds; root.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(root.view); root.didMove(toParent: self)
    }
}
