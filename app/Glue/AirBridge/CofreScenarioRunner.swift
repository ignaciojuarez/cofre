#if DEBUG
import Foundation
import UIKit
import CofreUI
import CofreKit

@MainActor
final class CofreScenarioRunner {
    private enum ScenarioError: LocalizedError {
        case worldDirectory
        case worldJoinTimeout(String)

        var errorDescription: String? {
            switch self {
            case .worldDirectory: "scenario world directory is unavailable"
            case .worldJoinTimeout(let world): "Minecraft did not join scenario world \(world)"
            }
        }
    }

    private let backend: CofreBackendAdapter
    private let instances: InstanceStore?
    private let scenario: CofreScenario
    private var targetID: String?
    private var createdIDs: [String] = []
    private var keepInstances = false

    init(backend: CofreBackendAdapter, instances: InstanceStore?, scenario: CofreScenario) {
        self.backend = backend; self.instances = instances; self.scenario = scenario
    }

    func run() {
        Task { await execute() }
    }

    private func log(_ line: String) {
        NSLog("%@", line)
        guard let data = (line + "\n").data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: LogStore().latestLog)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Air normally captures NSLog through its latestlog pipe. The
            // headless installer can close that pipe, so the direct append is
            // best effort and must never change the scenario result.
        }
    }

    private func step(_ name: String) {
        log("[Cofre] scenario name=\(scenario.name) step=\(name) result=ok")
        NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · \(name)")
    }

    private func fail(_ step: String, _ error: Error) {
        log("[Cofre] scenario name=\(scenario.name) step=\(step) result=fail detail=\(error.localizedDescription)")
        NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · failed")
    }

    private func execute() async {
#if DEBUG
        if scenario.renderer == .metallum {
            RendererPolicy.allowMetalForModdedScenario = true
            UserDefaults.standard.set(true, forKey: "cofre.debug.moddedMetal")
        }
#endif
        guard let store = instances else {
            fail("instance", CofreBackendError.unavailable("instances"))
            return
        }
        defer {
            if !keepInstances {
                for id in createdIDs.reversed() {
                    do {
                        try store.remove(id)
                        log("[Cofre] scenario name=\(scenario.name) cleanup instance=\(id) result=ok")
                    } catch {
                        log("[Cofre] scenario name=\(scenario.name) cleanup instance=\(id) result=fail detail=\(error.localizedDescription)")
                    }
                }
            }
        }
        do {
            try scenario.validate(); step("instance")
            var existing = try store.list().first { $0.name == scenario.name }
            // A loader install ends in an app restart; the relaunch resumes that instance instead of reinstalling
            // the loader (which would need yet another restart).
            let resumeKey = "cofre.scenario.resume.\(scenario.name)"
            let resuming = UserDefaults.standard.bool(forKey: resumeKey)
            UserDefaults.standard.removeObject(forKey: resumeKey)
            if scenario.fresh, !resuming, let old = existing { try store.remove(old.id); existing = nil }
            if existing == nil {
                let loader = scenario.loader
                let made = try store.create(name: scenario.name, version: scenario.version ?? "1.21.1", loader: loader)
                if scenario.fresh {
                    // An older run's folder can outlive its profile; its options.txt would force OpenGL.
                    let fm = FileManager.default
                    for item in (try? fm.contentsOfDirectory(at: made.gameDirectory, includingPropertiesForKeys: nil)) ?? []
                    where item.lastPathComponent != "cofre.json" { try? fm.removeItem(at: item) }
                }
                createdIDs.append(made.id)
                existing = made
            }
            guard let instance = existing else { throw CofreBackendError.unavailable("instance") }
            targetID = instance.id
            var targetVersion = instance.gameVersion

            let scenarioLoader: Loader? = scenario.loader == .unknown ? nil : scenario.loader
            if instance.loader != .vanilla, let loader = scenarioLoader {
                if instance.loader.isInstalled(in: instance.versionID, root: store.root,
                                               minecraftVersion: instance.gameVersion) {
                    log("[Cofre] scenario name=\(scenario.name) step=loader result=ok detail=already-installed")
                } else {
                    let availableLoaderVersions = try await backend.loaderVersions(loader: loader, game: instance.gameVersion)
                    let loaderVersion = scenario.loaderVersion ?? availableLoaderVersions.first
                    guard let loaderVersion else { throw CofreBackendError.unavailable("no loader version") }
                    NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · loader")
                    try await backend.installLoader(instanceID: instance.id, loader: loader, version: loaderVersion)
                    log("[Cofre] scenario name=\(scenario.name) step=loader result=ok")
                }
            }

            if let pack = scenario.pack {
                NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · pack")
                let rows = try await backend.search(ProjectQuery(text: pack, kind: .modpacks, instanceID: instance.id))
                let found = rows.first { $0.id == pack || $0.title.lowercased() == pack.lowercased() } ?? foundPack(pack, from: rows)
                guard let found else { throw CofreBackendError.unavailable("pack \(pack) not found") }
                let versions = try await backend.versions(projectID: found.id, instanceID: instance.id)
                let version = scenario.packVersion ?? versions.first?.id ?? "latest"
                let before = Set(try store.list().map(\.id))
                for try await _ in backend.install(projectID: found.id, versionID: version, instanceID: instance.id) {}
                // A pack makes its own instance; launch that one, not whichever other instance lists first.
                guard let made = try store.list().first(where: { !before.contains($0.id) }) else { throw CofreBackendError.unavailable("pack \(pack) made no instance") }
                targetID = made.id
                targetVersion = made.gameVersion
                createdIDs.append(made.id)
                log("[Cofre] scenario name=\(scenario.name) step=pack result=ok")
            } else {
                for mod in scenario.mods {
                    NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · mods")
                    let results = try await backend.search(ProjectQuery(text: mod, kind: .mods, instanceID: instance.id))
                    guard let project = results.first(where: { $0.id == mod }) ?? results.first else { throw CofreBackendError.unavailable("mod \(mod) not found") }
                    // Let the resolver choose the newest compatible build. The fast version list is normally filtered,
                    // but passing an ID from it would make a stale or cross-loader row an unsafe explicit pin.
                    for try await _ in backend.install(projectID: project.id, versionID: "latest", instanceID: instance.id) {}
                }
                if !scenario.mods.isEmpty { log("[Cofre] scenario name=\(scenario.name) step=mods result=ok") }
            }

            if !scenario.files.isEmpty {
                guard let targetID, let directory = backend.air.gameDirectory(forProfile: targetID) else {
                    throw CofreBackendError.unavailable("instance folder")
                }
                for file in scenario.files {
                    let data: Data
                    if let text = file.text {
                        data = Data(text.utf8)
                    } else if let from = file.from {
                        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                        data = try Data(contentsOf: documents.appendingPathComponent(from))
                    } else {
                        guard let url = URL(string: file.url ?? "") else { throw CofreBackendError.unavailable("scenario file URL") }
                        let (body, response) = try await URLSession.shared.data(from: url)
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                            throw CofreBackendError.unavailable("scenario file download")
                        }
                        data = body
                    }
                    let destination = directory.appendingPathComponent(file.to)
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: destination, options: .atomic)
                    log("[Cofre] scenario name=\(scenario.name) file=\(file.to) bytes=\(data.count) result=ok")
                }
                step("files")
            }

            var prefs = try await backend.preferences(instanceID: targetID)
            prefs.renderer = scenario.renderer; prefs.resolution = scenario.resolution
            if let memory = scenario.memoryMB { prefs.autoRAM = false; prefs.ramMB = memory }
            try await backend.setPreferences(prefs, instanceID: targetID)
            // Every scenario states its engine experiments; without them it runs today's defaults.
            (scenario.engine ?? EngineOptions()).save()
            step("settings")
            if scenario.launch, let targetID {
                var gameArguments: [String] = []
                var worldDirectory: URL?
                var worldLogBaseline = Data()
                if let world = scenario.world {
                    do {
                        guard let directory = backend.air.gameDirectory(forProfile: targetID) else {
                            throw ScenarioError.worldDirectory
                        }
                        try ScenarioWorld.ensure(in: directory, folder: world, seed: scenario.seed,
                                                 gameVersion: targetVersion)
                        gameArguments = MinecraftLaunchArguments.singleplayer(folder: world, gameVersion: targetVersion)
                        guard !gameArguments.isEmpty else { throw ScenarioError.worldDirectory }
                        worldDirectory = directory
                        worldLogBaseline = (try? Data(contentsOf: LogStore().latestLog)) ?? Data()
                    } catch {
                        fail("world", error)
                        return
                    }
                }
                NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · launch")
                for try await _ in backend.launch(instanceID: targetID, accountID: nil, gameArguments: gameArguments) {}
                // The stream ends at the first frame, while the game keeps running from this folder.
                // Deleting it now pulls Fabric's jar-in-jar mods (.fabric/processedMods) out from under
                // the game (blank title) and leaves a profile-less folder whose startup marker forces
                // OpenGL on the next run. `fresh` removes it before the next scenario instead.
                keepInstances = true
                if let world = scenario.world, let worldDirectory {
                    do {
                        try await waitForWorldJoin(in: worldDirectory, baseline: worldLogBaseline, world: world)
                        step("world")
                    } catch {
                        fail("world", error)
                    }
                }
            }
        } catch {
            if let failure = error as? LaunchFailure, failure == .restartRequired {
                keepInstances = true
                UserDefaults.standard.set(true, forKey: "cofre.scenario.resume.\(scenario.name)")
                log("[Cofre] scenario name=\(scenario.name) step=run result=restart")
                NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · restart")
            } else {
                fail("run", error)
            }
        }
    }

    /// Watches Cofre's own log, which carries the game's output as it happens; the game's logs/latest.log is
    /// written too late to see the join.
    private func waitForWorldJoin(in gameDirectory: URL, baseline: Data, world: String) async throws {
        let logURL = LogStore().latestLog
        // A big modpack can spend minutes generating spawn chunks.
        let deadline = ContinuousClock.now + .seconds(600)
        while ContinuousClock.now < deadline {
            if let data = try? Data(contentsOf: logURL) {
                let newData: Data
                if data.starts(with: baseline) {
                    newData = data.dropFirst(baseline.count)
                } else {
                    newData = data
                }
                if String(decoding: newData, as: UTF8.self).contains("joined the game") {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw ScenarioError.worldJoinTimeout(world)
    }

    private func foundPack(_ slug: String, from rows: [ProjectSummary]) -> ProjectSummary? { rows.first }
}

extension Notification.Name { static let cofreScenarioStep = Notification.Name("CofreScenarioStep") }
#endif
