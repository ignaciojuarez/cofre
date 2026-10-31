import UIKit
import CofreUI
import CofreKit

@objc(CofreCoreEntry)
public final class CofreCoreEntry: NSObject {
    private static var bridge: (any CofreAirBridging)?
    private static var root: UIViewController?
    /// The ObjC engine applies this value; all renderer decisions stay in Swift.
    @objc(rendererForProfile:metadata:globalSetting:)
    @MainActor public static func renderer(forProfile profile: [String: Any], metadata: [String: Any],
                                          globalSetting: String) -> String {
        let fallback = bridge.flatMap { bridge in
            bridge.gameDirectory(forProfile: bridge.selectedProfileName()).flatMap { directory in
                (try? Data(contentsOf: directory.appendingPathComponent("cofre.json")))
                    .flatMap { try? JSONDecoder().decode(Instance.self, from: $0) }?.loader
            }
        }
        return RendererPolicy.resolve(profile: profile, metadata: metadata, globalSetting: globalSetting,
            fallbackLoader: fallback, metalVersions: ModCompatibility.metalVersions)
    }
    @objc(startWithBridge:)
    @MainActor public static func start(withBridge bridge: Any) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CofreVersion") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CofreBuild") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        NSLog("[Cofre] app version=%@ build=%@", version, build)
        guard let bridge = bridge as? any CofreAirBridging else { NSLog("[Cofre] owned UI fallback reason=bridge type"); return }
        self.bridge = bridge
        bridge.ensureAutomaticMemoryDefault()
        CofreUIKitTheme.apply()
        root = CofreRootViewController(bridge: bridge)
    }
    /// Minecraft exited (patch 0004 via CofreHandleGameExit): keep the user in Cofre's recovery view.
    @objc(handleGameExit:)
    @MainActor public static func handleGameExit(_ code: Int32) {
        CofreGameExit.handle(code: Int(code), root: root, bridge: bridge)
    }
    /// The in-game touch overlay. Air's `CofreGameOverlayHost` asks once per game view.
    @objc(touchOverlay)
    @MainActor public static func touchOverlay() -> UIViewController {
        TouchOverlayController(input: CofreGameInput.shared)
    }
    @objc(rootViewController)
    @MainActor public static func rootViewController() -> UIViewController? {
        guard let root else { NSLog("[Cofre] owned UI fallback reason=root missing"); return nil }
        NSLog("[Cofre] UI root installed")
        return root
    }
}
