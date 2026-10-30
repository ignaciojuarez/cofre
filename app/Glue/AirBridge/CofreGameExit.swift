import CofreUI
import SwiftUI
import UIKit

@_silgen_name("CofreLaunchAwaitingFirstFrame")
private func CofreLaunchAwaitingFirstFrame() -> Bool

/// Cofre's crash screen over a stopped game, in place of Air's PLCrashView. Patch 0004 asks `CofreHandleGameExit`
/// (CofreStartup.m), which calls `handle` on the main queue while the JVM thread waits for the process to end.
@MainActor enum CofreGameExit {
    private static var window: UIWindow?

    static func handle(code: Int, root: UIViewController?, bridge: (any CofreAirBridging)?) {
        NSLog("[Cofre] launch exit code=%d", code)
        // Before the first frame Cofre's launch screen is still up and shows the failure itself (store.launchError).
        if CofreLaunchAwaitingFirstFrame() {
            NSLog("[Cofre] game exit shown on the launch screen")
            return
        }
        guard window == nil,
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let report = CofreLogStore().gameExitReport(code: code, instance: bridge.flatMap(instanceLabel))
        let intent = bridge.flatMap { makeRejoinIntent($0) }
        if let intent { RejoinIntentStore.save(intent) }
        NSLog("[Cofre] game exit screen reason=%@ crashReport=%d", report.reason.rawValue, report.files.count > 1)
        let host = UIHostingController(rootView: GameExitView(report: report, intent: intent, close: AppExit.close, retry: { AppExit.close() }))
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

    private static func makeRejoinIntent(_ bridge: any CofreAirBridging) -> RejoinIntent? {
        let id = bridge.selectedProfileName()
        guard !id.isEmpty, let dir = bridge.gameDirectory(forProfile: id) else { return nil }
        let defaults = UserDefaults.standard
        let since = Date(timeIntervalSince1970: defaults.double(forKey: "cofre.launch.started.\(id)"))
        let logURL = dir.appendingPathComponent("logs/latest.log")
        if let log = try? String(contentsOf: logURL), let server = RejoinDetector.server(in: log) {
            return RejoinIntent(instanceID: id, kind: .server, target: server, displayName: server)
        }
        guard since.timeIntervalSince1970 > 0, let world = RejoinDetector.world(in: dir, since: since) else { return nil }
        return RejoinIntent(instanceID: id, kind: .world, target: world.lastPathComponent, displayName: world.lastPathComponent)
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
