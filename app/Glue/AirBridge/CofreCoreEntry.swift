import UIKit
import CofreUI

@objc(CofreCoreEntry)
public final class CofreCoreEntry: NSObject {
    private static var bridge: (any CofreAirBridging)?
    private static var root: UIViewController?
    @objc(startWithBridge:)
    @MainActor public static func start(withBridge bridge: Any) {
        guard let bridge = bridge as? any CofreAirBridging else { NSLog("[Cofre] UI fallback reason=bridge type"); return }
        self.bridge = bridge
        bridge.ensureAutomaticMemoryDefault()
        CofreUIKitTheme.apply()
        root = CofreRootViewController(bridge: bridge)
    }
    @objc(rootViewController)
    @MainActor public static func rootViewController() -> UIViewController? {
        guard let root else { NSLog("[Cofre] UI fallback reason=root missing"); return nil }
        NSLog("[Cofre] UI root installed")
        return root
    }
}
