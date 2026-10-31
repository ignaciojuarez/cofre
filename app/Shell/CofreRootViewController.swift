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
    private var scenarioRunner: CofreScenarioRunner?
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
        let services = CofreServices(backend: backend, instances: instances, modrinth: backend.modrinth)
        let root = CofreUI.makeRootViewController(services: services, nav: nav)
        addChild(root); root.view.frame = view.bounds; root.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(root.view); root.didMove(toParent: self)
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-cofreScenario"), index + 1 < ProcessInfo.processInfo.arguments.count {
            let relative = ProcessInfo.processInfo.arguments[index + 1]
            let url = URL(fileURLWithPath: relative, relativeTo: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
            if let scenario = try? CofreScenario.load(Data(contentsOf: url)) {
                let label = UILabel(); label.textColor = .white; label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
                label.font = .systemFont(ofSize: 13, weight: .semibold); label.textAlignment = .center; label.numberOfLines = 2
                label.layer.cornerRadius = 8; label.clipsToBounds = true; label.isHidden = true; label.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(label)
                NSLayoutConstraint.activate([label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), label.centerXAnchor.constraint(equalTo: view.centerXAnchor), label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.9), label.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)])
                urlObservers.append(NotificationCenter.default.addObserver(forName: .cofreScenarioStep, object: nil, queue: .main) { note in label.text = note.object as? String; label.isHidden = false })
                scenarioRunner = CofreScenarioRunner(backend: backend, instances: instances, scenario: scenario); scenarioRunner?.run()
            } else { NSLog("[Cofre] scenario name=? step=parse result=fail detail=invalid file") }
        }
        #endif
        let center = NotificationCenter.default
        urlObservers.append(center.addObserver(forName: Notification.Name("CofreOpenURL"), object: nil, queue: .main) { [weak self] note in
            guard let url = note.object as? URL else { return }
            _ = self?.nav.open(url)
        })
        center.post(name: Notification.Name("CofreRootReady"), object: nil)
    }

    deinit { urlObservers.forEach(NotificationCenter.default.removeObserver) }
}
