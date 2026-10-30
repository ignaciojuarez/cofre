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
    private let nav = NavModel()
    private var urlObservers: [NSObjectProtocol] = []
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
        instances?.didWriteProfiles = { bridge.reloadProfiles() }
        backend.instances = instances
        let services = CofreServices(backend: backend, instances: instances)
        let root = CofreUI.makeRootViewController(services: services, nav: nav)
        addChild(root); root.view.frame = view.bounds; root.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(root.view); root.didMove(toParent: self)
        let center = NotificationCenter.default
        urlObservers.append(center.addObserver(forName: Notification.Name("UISceneOpenURLContextsNotification"), object: nil, queue: .main) { [weak self] note in
            for context in note.userInfo?["UISceneOpenURLContextsKey"] as? Set<UIOpenURLContext> ?? [] { _ = self?.nav.open(context.url) }
        })
        urlObservers.append(center.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { [weak self] note in
            let options = note.userInfo?["UISceneConnectionOptionsKey"] as? UIScene.ConnectionOptions
            for context in options?.urlContexts ?? [] { _ = self?.nav.open(context.url) }
        })
    }

    deinit { urlObservers.forEach(NotificationCenter.default.removeObserver) }
}
