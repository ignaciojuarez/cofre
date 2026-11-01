import CofreUI
import CofreKit
import SwiftUI
import UIKit

extension ReportBundle.Context {
    /// What a shared report says about this app and phone; the bundle redacts anything personal.
    @MainActor static func current(exitReason: String? = nil, clue: String? = nil) -> Self {
        let info = Bundle.main.infoDictionary ?? [:]
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return Self(
            appVersion: (info["CofreVersion"] ?? info["CFBundleShortVersionString"]) as? String,
            build: (info["CofreBuild"] ?? info["CFBundleVersion"]) as? String, device: model,
            iOS: UIDevice.current.systemVersion, exitReason: exitReason, clue: clue)
    }
}

/// Cofre's recovery screen over a stopped game. Patch 0004 asks
/// `CofreHandleGameExit` (CofreStartup.m), which calls `handle` on the main
/// queue while the JVM thread waits for the process to end.
@MainActor enum CofreGameExit {
    private static var window: UIWindow?

    /// `launcherLog`: what the launch saw before the first frame (Forge/NeoForge's "Failed to start FML"), for when the
    /// game log has none of it.
    static func handle(code: Int, root: UIViewController?, bridge: (any CofreAirBridging)?, launcherLog: String? = nil) {
        NSLog("[Cofre] launch exit code=%d", code)
        GameSessionMarker.clear()
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
        let logText = ([logs.tail(.game, limit: 512).map(\.text).joined(separator: "\n")] + [launcherLog].compactMap { $0 })
            .joined(separator: "\n")
        let crashText = crashURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        // Settings changed in game: logged as breadcrumbs, and named on the screen when they caused the crash.
        let before = bridge.flatMap { UserDefaults.standard.string(forKey: PreferenceKey.optionsBefore($0.selectedProfileName()).rawValue) } ?? ""
        let after = instanceURL.flatMap { try? String(contentsOf: $0.appendingPathComponent("options.txt"), encoding: .utf8) } ?? ""
        let changes = OptionsDiff.changed(before: before, after: after)
        OptionsDiff.changes(before: before, after: after).forEach { NSLog("%@", $0) }
        let report = GameExitReport(code: code, crashReport: crashText, log: logText, instance: bridge.flatMap(instanceLabel), files: [logs.gameLog].compactMap { $0 } + (crashURL.map { [$0] } ?? []), changedSettings: OptionsDiff.reloadingNames(changes))
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString).zip")
        let reportBundle = try? ReportBundle(store: logs, context: .current(exitReason: report.reason.rawValue, clue: report.clue)).make(at: bundleURL)
        let preview = ReportBundle(store: logs, context: .current(exitReason: report.reason.rawValue, clue: report.clue)).preview()
        let intent = bridge.flatMap { makeRejoinIntent($0) }
        if let intent { RejoinIntentStore.save(intent) }
        NSLog("[Cofre] game exit screen reason=%@ crashReport=%d", report.reason.rawValue, report.files.count > 1)
        let host = UIHostingController(rootView: GameExitView(report: report, intent: intent, reportURL: reportBundle, reportPreview: ReportPreviewData(fields: preview.fields.map { "\($0.name): \($0.value)" }, files: preview.files), close: AppExit.close, retry: { AppExit.close() },
            turnShadersOff: instanceURL.flatMap { dir in
                ShaderSwitch.causedCrash((crashText ?? "") + logText, gameDirectory: dir) ? { try ShaderSwitch.turnOff(in: dir) } : nil
            }, fix: report.reason == .mods ? bridge.flatMap { missingModFix(crashText: crashText, log: logText, bridge: $0) } : nil,
            turnModOff: report.reason == .mods ? instanceURL.flatMap { glModTurnOff(crashText: crashText, log: logText, gameDirectory: $0) } : nil))
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

    /// "Get Kotlin for Forge" when the crash names a mod that isn't installed; nil when it names none, or before the
    /// UI's backend is up.
    private static func missingModFix(crashText: String?, log: String, bridge: any CofreAirBridging) -> GameExitFix? {
        let id = bridge.selectedProfileName()
        let needs = ModRequirements.fromCrash((crashText ?? "") + "\n" + log)
        guard !id.isEmpty, !needs.isEmpty, let backend = CofreBackendAdapter.current else { return nil }
        NSLog("[Cofre] crash fix offered mods=%@ instance=%@", needs.map(\.modID).joined(separator: ","), id)
        return GameExitFix(name: needs.map(\.name).formatted()) {
            try await backend.installRequirements(needs, instanceID: id)
        }
    }

    /// "Turn off Distant Horizons" when the crash is a mod's OpenGL code getting a Metal object and its jar is on.
    private static func glModTurnOff(crashText: String?, log: String, gameDirectory: URL) -> GameExitTurnOff? {
        let lines = ((crashText ?? "") + "\n" + log).components(separatedBy: .newlines)
        guard let id = GameExitReport.metalGLModID(in: lines) else { return nil }
        let store = ContentStore(gameDirectory: gameDirectory)
        let mods = ((try? store.list(.mods)) ?? []).filter(\.enabled)
        let key = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard
            let jar = mods.first(where: { key($0.name).contains(key(id)) })
                ?? mods.first(where: { m in
                    ModsToml.read(jar: store.url(of: m), neoForge: true)?.modIDs.contains { $0.lowercased() == id } == true
                })
        else { return nil }
        let name = GameExitReport.modName(id)
        NSLog("[Cofre] crash fix offered turnOff=%@ file=%@", id, jar.id)
        return GameExitTurnOff(name: name) {
            try store.setEnabled(false, jar)
            NSLog("[Cofre] crash fix turned off file=%@", jar.id)
        }
    }

    private static func makeRejoinIntent(_ bridge: any CofreAirBridging) -> RejoinIntent? {
        let id = bridge.selectedProfileName()
        guard !id.isEmpty, let dir = bridge.gameDirectory(forProfile: id) else { return nil }
        let defaults = UserDefaults.standard
        let since = Date(timeIntervalSince1970: defaults.double(forKey: PreferenceKey.launchStarted(id).rawValue))
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
