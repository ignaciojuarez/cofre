#if DEBUG
import Foundation
import UIKit
import CofreUI
import CofreKit

@MainActor
final class CofreScenarioRunner {
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
        RendererPolicy.allowMetalForModdedScenario = scenario.renderer == .metallum
        defer { RendererPolicy.allowMetalForModdedScenario = false }
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
            if scenario.fresh, let old = existing { try store.remove(old.id); existing = nil }
            if existing == nil {
                let loader = scenario.loader
                let made = try store.create(name: scenario.name, version: scenario.version ?? "1.21.1", loader: loader)
                createdIDs.append(made.id)
                existing = made
            }
            guard let instance = existing else { throw CofreBackendError.unavailable("instance") }
            targetID = instance.id

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
                createdIDs.append(made.id)
                log("[Cofre] scenario name=\(scenario.name) step=pack result=ok")
            } else {
                for mod in scenario.mods {
                    NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · mods")
                    let results = try await backend.search(ProjectQuery(text: mod, kind: .mods, instanceID: instance.id))
                    guard let project = results.first(where: { $0.id == mod }) ?? results.first else { throw CofreBackendError.unavailable("mod \(mod) not found") }
                    let versions = try await backend.versions(projectID: project.id, instanceID: instance.id)
                    for try await _ in backend.install(projectID: project.id, versionID: versions.first?.id ?? "latest", instanceID: instance.id) {}
                }
                if !scenario.mods.isEmpty { log("[Cofre] scenario name=\(scenario.name) step=mods result=ok") }
            }

            if !scenario.files.isEmpty {
                guard let targetID, let directory = backend.air.gameDirectory(forProfile: targetID) else {
                    throw CofreBackendError.unavailable("instance folder")
                }
                for file in scenario.files {
                    guard let url = URL(string: file.url) else { throw CofreBackendError.unavailable("scenario file URL") }
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw CofreBackendError.unavailable("scenario file download")
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
            step("settings")
            if scenario.launch, let targetID {
                NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · launch")
                for try await _ in backend.launch(instanceID: targetID, accountID: nil) {}
            }
        } catch {
            if let failure = error as? LaunchFailure, failure == .restartRequired {
                keepInstances = true
                log("[Cofre] scenario name=\(scenario.name) step=run result=restart")
                NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · restart")
            } else {
                fail("run", error)
            }
        }
    }

    private func foundPack(_ slug: String, from rows: [ProjectSummary]) -> ProjectSummary? { rows.first }
}

extension Notification.Name { static let cofreScenarioStep = Notification.Name("CofreScenarioStep") }
#endif
