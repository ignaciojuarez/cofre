import CofreUI
import CofreKit
import SwiftUI
import UIKit

/// Cofre's recovery screen over a stopped game. Patch 0004 asks
/// `CofreHandleGameExit` (CofreStartup.m), which calls `handle` on the main
/// queue while the JVM thread waits for the process to end.
@MainActor enum CofreGameExit {
    private static var window: UIWindow?

    static func handle(code: Int, root: UIViewController?, bridge: (any CofreAirBridging)?) {
        NSLog("[Cofre] launch exit code=%d", code)
        // Shown before the first frame too: the launch screen closes when the game exits, and Java can't start
        // again in this process, so this screen (Play again reopens Cofre) is the only way on.
        guard window == nil,
            let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let instanceURL = bridge.flatMap { bridge in
            let id = bridge.selectedProfileName()
            return id.isEmpty ? nil : bridge.gameDirectory(forProfile: id)
        }
        let logs = LogStore(instance: instanceURL)
        let crashURL = logs.newestCrashReport(since: .distantPast)
        let logText = logs.tail(.game, limit: 512).map(\.text).joined(separator: "\n")
        let crashText = crashURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        // Settings changed in game: logged as breadcrumbs, and named on the screen when they caused the crash.
        let before = bridge.flatMap { UserDefaults.standard.string(forKey: "cofre.options.before.\($0.selectedProfileName())") } ?? ""
        let after = instanceURL.flatMap { try? String(contentsOf: $0.appendingPathComponent("options.txt"), encoding: .utf8) } ?? ""
        let changes = OptionsDiff.changed(before: before, after: after)
        OptionsDiff.changes(before: before, after: after).forEach { NSLog("%@", $0) }
        let report = GameExitReport(code: code, crashReport: crashText, log: logText, instance: bridge.flatMap(instanceLabel), files: [logs.gameLog].compactMap { $0 } + (crashURL.map { [$0] } ?? []), changedSettings: OptionsDiff.reloadingNames(changes))
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString).zip")
        let reportBundle = try? ReportBundle(store: logs, context: .init(exitReason: report.reason.rawValue, clue: report.clue)).make(at: bundleURL)
        let preview = ReportBundle(store: logs, context: .init(exitReason: report.reason.rawValue, clue: report.clue)).preview()
        let intent = bridge.flatMap { makeRejoinIntent($0) }
        if let intent { RejoinIntentStore.save(intent) }
        NSLog("[Cofre] game exit screen reason=%@ crashReport=%d", report.reason.rawValue, report.files.count > 1)
        let host = UIHostingController(rootView: GameExitView(report: report, intent: intent, reportURL: reportBundle, reportPreview: ReportPreviewData(fields: preview.fields.map { "\($0.name): \($0.value)" }, files: preview.files), close: AppExit.close, retry: { AppExit.close() },
            turnShadersOff: instanceURL.flatMap { dir in
                ShaderSwitch.causedCrash((crashText ?? "") + logText, gameDirectory: dir) ? { try ShaderSwitch.turnOff(in: dir) } : nil
            }))
        host.view.backgroundColor = .cofre.page
        host.overrideUserInterfaceStyle = .dark
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
        let instance = ProcessInfo.processInfo.environment["POJAV_GAME_DIR"].flatMap {
            try? InstanceStore(root: URL(fileURLWithPath: $0)).list().first { $0.id == name }
        }
        let loader = instance.map(\.loader).flatMap { $0 == .vanilla ? nil : $0.displayName }
        let version = [loader, instance?.gameVersion].compactMap { $0 }.joined(separator: " ")
        return version.isEmpty ? name : "\(name) · \(version)"
    }

}
