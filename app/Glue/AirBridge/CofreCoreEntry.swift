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
    /// Minecraft exited (patch 0004 via CofreHandleGameExit): Cofre's crash screen instead of Air's.
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
        guard let root else { NSLog("[Cofre] UI fallback reason=root missing"); return nil }
        NSLog("[Cofre] UI root installed")
        return root
    }
}
