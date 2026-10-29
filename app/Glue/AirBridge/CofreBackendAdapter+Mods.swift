import Foundation

/// Air's normalized version payload; kept independent of UIKit for regression checks.
struct CofreModVersion {
    let data: [String: Any]
    var id: String { data["id"] as? String ?? "" }
    var projectID: String { data["projectID"] as? String ?? "" }
    var source: Int { data["apiSource"] as? Int ?? 1 }
    var name: String { data["name"] as? String ?? id }
    var gameVersions: [String] { data["gameVersions"] as? [String] ?? [] }
    var loaders: [String] { (data["loaders"] as? [String] ?? []).map { $0.lowercased() } }
    var file: [String: Any] { data["file"] as? [String: Any] ?? [:] }

    func fits(gameVersion: String, loader: String) -> Bool {
        !gameVersion.isEmpty && gameVersions.contains(gameVersion)
            && (loaders.isEmpty || loaders.contains(loader.lowercased()))
    }

    struct Dependency {
        let projectID: String
        let versionID: String?
        let required: Bool
    }

    var dependencies: [Dependency] {
        (data["dependencies"] as? [[String: Any]] ?? []).compactMap { row in
            if source == 2 {
                guard let id = row["modId"] as? NSNumber,
                    let relation = row["relationType"] as? Int, [2, 3].contains(relation)
                else { return nil }
                return Dependency(projectID: id.stringValue, versionID: nil, required: relation == 3)
            }
            guard let type = row["dependency_type"] as? String, ["required", "optional"].contains(type)
            else { return nil }
            return Dependency(
                projectID: row["project_id"] as? String ?? "", versionID: row["version_id"] as? String,
                required: type == "required")
        }
    }
}

#if canImport(UIKit)
    import CofreUI

    @MainActor
    final class CofreModCatalog {
        // The facade passes IDs, so retain the catalog and download metadata across calls.
        var projects: [String: [String: Any]] = [:]
        var versions: [String: CofreModVersion] = [:]
    }

    extension CofreBackendAdapter {
        public func search(_ query: ProjectQuery) async throws -> [ProjectSummary] {
            let source = query.source == .curseforge ? 2 : 1
            let projectType: String =
                switch query.kind {
                case .mods: "mod"
                case .shaders: "shader"
                case .resourcePacks: "resourcepack"
                case .dataPacks: "datapack"
                case .modpacks: "modpack"
                }
            var filters = ["query": query.text, "limit": "50", "projectType": projectType]
            if let instanceID = query.instanceID {
                let context = air.modContext(forProfile: instanceID)
                filters["mcVersion"] = context["minecraft"] as? String
                if query.kind == .mods, let loader = context["loader"] as? String, loader != "vanilla" {
                    filters["loader"] = loader
                }
            }
            let rows = try await modRows { done in
                air.searchProjects(filters, source: source, completion: done)
            }
            return rows.compactMap { row in
                guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                var project = row
                project["apiSource"] = source
                project["projectType"] = projectType
                modCatalog.projects[id] = project
                let loaders = (row["categories"] as? [String] ?? []).compactMap { Loader(rawValue: $0.lowercased()) }
                return ProjectSummary(
                    id: id, title: row["title"] as? String ?? id, author: row["author"] as? String ?? "",
                    summary: row["description"] as? String ?? "", iconURL: modURL(row["imageUrl"]),
                    downloads: (row["downloads"] as? NSNumber)?.intValue ?? 0,
                    loaders: loaders, fits: true, source: query.source, pageURL: modURL(row["url"]))
            }
        }

        public func versions(projectID: String, instanceID: String) async throws -> [ProjectVersion] {
            let source = modCatalog.projects[projectID]?["apiSource"] as? Int ?? 1
            let versions = try await loadModVersions(projectID: projectID, source: source)
            let context = air.modContext(forProfile: instanceID)
            return versions.map { version in
                ProjectVersion(
                    id: version.id, name: version.name, gameVersions: version.gameVersions.joined(separator: ", "),
                    channel: (version.data["channel"] as? String ?? "release").capitalized,
                    fits: modFits(version, context: context))
            }
        }

        public func dependencies(versionID: String, instanceID: String) async throws -> [ProjectDependency] {
            guard let version = modCatalog.versions[versionID] else {
                throw modError("Reload this project's versions before checking dependencies.")
            }
            let local = try await installed(.mods, instanceID: instanceID)
            return version.dependencies.map { dependency in
                let installed = local.contains { $0.enabled && $0.id == dependency.projectID }
                let id = dependency.projectID.isEmpty ? dependency.versionID ?? "unknown" : dependency.projectID
                return ProjectDependency(
                    id: id, name: modCatalog.projects[id]?["title"] as? String ?? id,
                    required: dependency.required, installed: installed)
            }
        }

        public func install(projectID: String, versionID: String, instanceID: String)
            -> AsyncThrowingStream<InstallProgress, Error>
        {
            AsyncThrowingStream { continuation in
                Task { @MainActor in
                    do {
                        let project = modCatalog.projects[projectID] ?? [:]
                        guard (project["projectType"] as? String ?? "mod") == "mod" else {
                            throw modError("This installer supports mods. Use pack import for modpacks.")
                        }
                        let source = project["apiSource"] as? Int ?? 1
                        let context = air.modContext(forProfile: instanceID)
                        continuation.yield(InstallProgress(title: "Resolving mod dependencies", fraction: 0))
                        let available = try await loadModVersions(projectID: projectID, source: source)
                        guard
                            let selected = available.first(where: {
                                versionID == "latest" ? modFits($0, context: context) : $0.id == versionID
                            })
                        else { throw modError("This mod version is no longer available for the instance.") }
                        var plan: [CofreModVersion] = []
                        var visited: [String: String] = [:]
                        try await planModInstall(selected, context: context, visited: &visited, plan: &plan)
                        for (index, version) in plan.enumerated() {
                            var payload =
                                modCatalog.projects[version.projectID] ?? [
                                    "id": version.projectID, "title": version.name,
                                ]
                            payload["apiSource"] = version.source
                            payload["downloadURL"] = version.file["url"]
                            payload["filename"] = version.file["filename"]
                            payload["sha1"] = (version.file["hashes"] as? [String: Any])?["sha1"]
                            payload["version"] = version.data["version"]
                            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                                air.installProject(
                                    payload, profile: instanceID,
                                    progress: { fraction, stage in
                                        continuation.yield(
                                            InstallProgress(
                                                title: "\(stage) \(version.name)",
                                                fraction: (Double(index) + min(max(fraction, 0), 1))
                                                    / Double(plan.count)))
                                    },
                                    completion: { error in
                                        if let error { done.resume(throwing: error) } else { done.resume() }
                                    })
                            }
                        }
                        continuation.yield(InstallProgress(title: "Installed", fraction: 1))
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
            }
        }

        /// Resolve required dependencies before writing files; pinned versions must match exactly.
        private func planModInstall(
            _ version: CofreModVersion, context: [AnyHashable: Any],
            visited: inout [String: String], plan: inout [CofreModVersion]
        ) async throws {
            let key = "\(version.source):\(version.projectID)"
            if let existing = visited[key] {
                guard existing == version.id else {
                    throw modError("These mods require conflicting dependency versions.")
                }
                return
            }
            guard visited.count < 100 else { throw modError("This mod has too many dependencies to install safely.") }
            guard modFits(version, context: context) else {
                throw modError("\(version.name) does not support this instance's Minecraft version and loader.")
            }
            visited[key] = version.id
            for dependency in version.dependencies where dependency.required {
                guard !dependency.projectID.isEmpty else {
                    throw modError("A required dependency has no project ID. Install it manually before retrying.")
                }
                let versions = try await loadModVersions(projectID: dependency.projectID, source: version.source)
                guard
                    let selected = versions.first(where: {
                        (dependency.versionID == nil || $0.id == dependency.versionID) && modFits($0, context: context)
                    })
                else {
                    throw modError("No compatible version of required dependency \(dependency.projectID) was found.")
                }
                try await planModInstall(selected, context: context, visited: &visited, plan: &plan)
            }
            plan.append(version)
        }

        private func loadModVersions(projectID: String, source: Int) async throws -> [CofreModVersion] {
            let rows = try await modRows { done in
                air.projectVersions(projectID, source: source, completion: done)
            }
            return rows.map { row in
                let version = CofreModVersion(data: row)
                modCatalog.versions[version.id] = version
                return version
            }
        }

        private func modFits(_ version: CofreModVersion, context: [AnyHashable: Any]) -> Bool {
            version.fits(
                gameVersion: context["minecraft"] as? String ?? "", loader: context["loader"] as? String ?? "vanilla")
        }

        private func modRows(_ body: (@escaping ([Any], Error?) -> Void) -> Void) async throws -> [[String: Any]] {
            let rows: [Any] = try await withCheckedThrowingContinuation { done in
                body { rows, error in
                    if let error { done.resume(throwing: error) } else { done.resume(returning: rows) }
                }
            }
            return rows.compactMap { $0 as? [String: Any] }
        }

        private func modURL(_ value: Any?) -> URL? {
            guard let string = value as? String, !string.isEmpty else { return nil }
            return URL(string: string)
        }

        private func modError(_ message: String) -> NSError {
            NSError(domain: "CofreMods", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
#endif
