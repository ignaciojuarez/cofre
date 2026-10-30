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

    init(backend: CofreBackendAdapter, instances: InstanceStore?, scenario: CofreScenario) {
        self.backend = backend; self.instances = instances; self.scenario = scenario
    }

    func run() {
        Task { await execute() }
    }

    private func step(_ name: String) {
        NSLog("[Cofre] scenario name=%@ step=%@ result=ok", scenario.name, name)
        NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · \(name)")
    }

    private func fail(_ step: String, _ error: Error) {
        NSLog("[Cofre] scenario name=%@ step=%@ result=fail detail=%@", scenario.name, step, error.localizedDescription)
        NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · failed")
    }

    private func execute() async {
        do {
            try scenario.validate(); step("instance")
            var existing = try await backend.instances().first { $0.name == scenario.name }
            if scenario.fresh, let old = existing { try await backend.delete(instanceID: old.id); existing = nil }
            if existing == nil {
                let loader = Loader(rawValue: scenario.loader.lowercased()) ?? .vanilla
                existing = try await backend.createInstance(name: scenario.name, version: scenario.version ?? "1.21.1", loader: loader)
            }
            guard let instance = existing else { throw CofreBackendError.unavailable("instance") }
            targetID = instance.id

            if instance.loader != .vanilla, let loader = Loader(rawValue: scenario.loader.lowercased()) {
                let availableLoaderVersions = try await backend.loaderVersions(loader: loader, game: instance.gameVersion)
                let loaderVersion = scenario.loaderVersion ?? availableLoaderVersions.first
                guard let loaderVersion else { throw CofreBackendError.unavailable("no loader version") }
                NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · loader")
                try await backend.installLoader(instanceID: instance.id, loader: loader, version: loaderVersion)
                NSLog("[Cofre] scenario name=%@ step=loader result=ok", scenario.name)
            }

            if let pack = scenario.pack {
                NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · pack")
                let rows = try await backend.search(ProjectQuery(text: pack, kind: .modpacks, instanceID: instance.id))
                let found = rows.first { $0.id == pack || $0.title.lowercased() == pack.lowercased() } ?? foundPack(pack, from: rows)
                guard let found else { throw CofreBackendError.unavailable("pack \(pack) not found") }
                let versions = try await backend.versions(projectID: found.id, instanceID: instance.id)
                let version = scenario.packVersion ?? versions.first?.id ?? "latest"
                let before = Set(try await backend.instances().map(\.id))
                for try await _ in backend.install(projectID: found.id, versionID: version, instanceID: instance.id) {}
                // A pack makes its own instance; launch that one, not whichever other instance lists first.
                guard let made = try await backend.instances().first(where: { !before.contains($0.id) }) else { throw CofreBackendError.unavailable("pack \(pack) made no instance") }
                targetID = made.id
                NSLog("[Cofre] scenario name=%@ step=pack result=ok", scenario.name)
            } else {
                for mod in scenario.mods {
                    NotificationCenter.default.post(name: .cofreScenarioStep, object: "Scenario: \(scenario.name) · mods")
                    let results = try await backend.search(ProjectQuery(text: mod, kind: .mods, instanceID: instance.id))
                    guard let project = results.first(where: { $0.id == mod }) ?? results.first else { throw CofreBackendError.unavailable("mod \(mod) not found") }
                    let versions = try await backend.versions(projectID: project.id, instanceID: instance.id)
                    for try await _ in backend.install(projectID: project.id, versionID: versions.first?.id ?? "latest", instanceID: instance.id) {}
                }
                if !scenario.mods.isEmpty { NSLog("[Cofre] scenario name=%@ step=mods result=ok", scenario.name) }
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
        } catch { fail("run", error) }
    }

    private func foundPack(_ slug: String, from rows: [ProjectSummary]) -> ProjectSummary? { rows.first }
}

extension Notification.Name { static let cofreScenarioStep = Notification.Name("CofreScenarioStep") }
#endif
