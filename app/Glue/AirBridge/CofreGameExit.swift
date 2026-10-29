import CofreUI
import SwiftUI
import UIKit

/// Cofre's crash screen over a stopped game, in place of Air's PLCrashView. Patch 0004 asks `CofreHandleGameExit`
/// (CofreStartup.m), which calls `handle` on the main queue while the JVM thread waits for the process to end.
@MainActor enum CofreGameExit {
    private static var window: UIWindow?

    static func handle(code: Int, root: UIViewController?, bridge: (any CofreAirBridging)?) {
        NSLog("[Cofre] launch exit code=%d", code)
        // Before the first frame Cofre's launch screen is still up and shows the failure itself (store.launchError).
        if let w = root?.viewIfLoaded?.window, !w.isHidden, w.alpha > 0 {
            NSLog("[Cofre] game exit shown on the launch screen")
            return
        }
        guard window == nil,
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let report = CofreLogStore().gameExitReport(code: code, instance: bridge.flatMap(instanceLabel))
        NSLog("[Cofre] game exit screen reason=%@ crashReport=%d", report.reason.rawValue, report.files.count > 1)
        let host = UIHostingController(rootView: GameExitView(report: report, close: AppExit.close))
        host.view.backgroundColor = .cofre.page
        host.overrideUserInterfaceStyle = CofreTheme.current.interfaceStyle
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .normal + 2  // over the game and Cofre's launch overlay
        w.rootViewController = host
        w.alpha = 0
        w.makeKeyAndVisible()
        UIView.animate(withDuration: 0.25) { w.alpha = 1 }
        window = w
    }

    /// "Survival+ · Fabric 1.21.1".
    private static func instanceLabel(_ bridge: any CofreAirBridging) -> String? {
        let name = bridge.selectedProfileName()
        guard !name.isEmpty else { return nil }
        let context = bridge.modContext(forProfile: name)
        let loader = (context["loader"] as? String).flatMap { $0 == "vanilla" || $0.isEmpty ? nil : $0.capitalized }
        let version = [loader, context["minecraft"] as? String].compactMap { $0 }.joined(separator: " ")
        return version.isEmpty ? name : "\(name) · \(version)"
    }

}
