import CofreKit
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
    /// Modrinth puts the size on the file, CurseForge on the version (`fileLength`, passed as `size`).
    var sizeBytes: Int64? { ((file["size"] ?? data["size"]) as? NSNumber).map(\.int64Value).flatMap { $0 > 0 ? $0 : nil } }
    var sha1: String? { (file["hashes"] as? [String: Any])?["sha1"] as? String }

    func fits(gameVersion: String, loader: String) -> Bool {
        !gameVersion.isEmpty && gameVersions.contains(gameVersion)
            && (loaders.isEmpty || loaders.contains(loader.lowercased()))
    }

    struct Dependency {
        enum Relation { case required, optional, incompatible }
        let projectID: String
        let versionID: String?
        let relation: Relation
        var required: Bool { relation == .required }
    }

    /// Embedded (bundled in the jar) and tool dependencies need nothing installed.
    var dependencies: [Dependency] {
        (data["dependencies"] as? [[String: Any]] ?? []).compactMap { row in
            if source == 2 {
                // CurseForge relationType: 2 optional, 3 required, 5 incompatible.
                guard let id = row["modId"] as? NSNumber, let type = row["relationType"] as? Int else { return nil }
                let relation: Dependency.Relation? = [2: .optional, 3: .required, 5: .incompatible][type]
                return relation.map { Dependency(projectID: id.stringValue, versionID: nil, relation: $0) }
            }
            let relation: Dependency.Relation? =
                switch row["dependency_type"] as? String {
                case "required": .required
                case "optional": .optional
                case "incompatible": .incompatible
                default: nil
                }
            guard let relation else { return nil }
            return Dependency(
                projectID: row["project_id"] as? String ?? "", versionID: row["version_id"] as? String,
                relation: relation)
        }
    }
}

#if canImport(UIKit)
    import CofreUI
    import CryptoKit

    @MainActor
    final class CofreModCatalog {
        let modrinth = Modrinth()
        // The facade passes IDs, so retain the catalog and download metadata across calls.
        var projects: [String: [String: Any]] = [:]
        var versions: [String: CofreModVersion] = [:]
        /// Project titles for dependencies that never showed up in a search.
        var titles: [String: String] = [:]
        /// File SHA-1s by path, size and date, so listing doesn't re-read every jar.
        var hashes: [String: String] = [:]
        /// Modrinth's answer per SHA-1: "projectID|versionID", or "" when Modrinth doesn't know the file.
        var identities: [String: String] =
            UserDefaults.standard.dictionary(forKey: PreferenceKey.modsIdentities.rawValue) as? [String: String] ?? [:]
        /// Newest fitting version per instance and SHA-1, with when it was asked.
        var updates: [String: (asked: Date, latest: [String: [String: Any]])] = [:]
        /// "instance|sha" → the allowed update found by hand when the newest was less stable ("" for none).
        var allowedUpdates: [String: String] = [:]
    }

    extension CofreModVersion {
        func candidate(title: String) -> ModCandidate {
            ModCandidate(
                projectID: projectID, versionID: id, title: title,
                version: data["version"] as? String ?? name, gameVersions: gameVersions, loaders: loaders,
                channel: data["channel"] as? String ?? "release", sizeBytes: sizeBytes,
                dependencies: dependencies.map {
                    ModCandidate.Dependency(projectID: $0.projectID, versionID: $0.versionID, relation: $0.candidateRelation)
                },
                downloadable: (file["url"] as? String)?.hasPrefix("https://") == true)
        }
    }

    extension CofreModVersion.Dependency {
        var candidateRelation: ModCandidate.Relation {
            switch relation {
            case .required: .required
            case .optional: .optional
            case .incompatible: .incompatible
            }
        }
    }

    extension CofreBackendAdapter {
        public func search(_ query: ProjectQuery, offset: Int) async throws -> [ProjectSummary] {
            let source = query.source == .curseforge ? 2 : 1
            let projectType = Self.projectType(query.kind)
            let target = query.instanceID.map { modTarget($0) } ?? (game: "", loader: Loader.unknown)
            if source == 1 {
                let facets = [["project_type:\(projectType)"]] + query.filters.facets(query.kind, game: target.game, loader: target.loader)
                let hits = try await modCatalog.modrinth.search(
                    query: query.text, facets: facets, index: query.filters.sort.rawValue, offset: offset,
                    limit: ProjectQuery.pageSize)
                // The project_type facet already limits the type (data packs come back labelled "mod").
                return hits.map { hit in
                    let id = hit.projectID
                    modCatalog.projects[id] = ["id": id, "title": hit.title, "description": hit.description, "imageUrl": hit.iconURL?.absoluteString ?? "", "url": hit.pageURL?.absoluteString ?? "", "downloads": hit.downloads, "projectType": projectType, "apiSource": 1]
                    let loaders = hit.categories.compactMap { Loader(rawValue: $0.lowercased()) }
                    let fits = target.game.isEmpty || hit.versions?.contains(target.game) != false
                    return ProjectSummary(id: id, title: hit.title, author: "", summary: hit.description, iconURL: hit.iconURL, downloads: hit.downloads, updated: hit.updated, loaders: loaders, fits: fits, source: query.source, pageURL: hit.pageURL)
                }
            }
            // CurseForge through Air maps only the game version and loader, and has no further pages.
            guard offset == 0 else { return [] }
            var filters = ["query": query.text, "limit": "\(ProjectQuery.pageSize)", "projectType": projectType]
            filters["mcVersion"] = query.filters.gameVersion(target.game)
            filters["loader"] = query.filters.loader(query.kind, target.loader)?.rawValue
            let rows = try await modRows { done in air.searchProjects(filters, source: source, completion: done) }
            return rows.compactMap { row in
                guard let id = row["id"] as? String, !id.isEmpty else { return nil }
                // Modrinth mirrors can answer with other project types (a resource pack on the Packs tab would
                // then be installed as a modpack and fail), so keep only what this tab asked for.
                if source == 1, let actual = row["projectType"] as? String, actual != projectType { return nil }
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
            let target = modTarget(instanceID)
            let kind = Self.kind(modCatalog.projects[projectID]?["projectType"] as? String)
            let source = source(of: projectID)
            let loaders = source == 1 && target.loader != .vanilla && target.loader != .unknown ? [target.loader.rawValue] : []
            let games = source == 1 && !target.game.isEmpty ? [target.game] : []
            let versions = try await loadModVersions(
                projectID: projectID, source: source, loaders: loaders, gameVersions: games, includeChangelog: true)
            return Self.projectVersions(versions, target: target, kind: kind)
        }

        /// Fetches the complete Modrinth catalog after the page's filtered response. Air is not involved in this path.
        public func allVersions(projectID: String, instanceID: String) async throws -> [ProjectVersion] {
            let target = modTarget(instanceID)
            let kind = Self.kind(modCatalog.projects[projectID]?["projectType"] as? String)
            let source = source(of: projectID)
            guard source == 1 else { return try await versions(projectID: projectID, instanceID: instanceID) }
            let versions = try await loadModVersions(projectID: projectID, source: source)
            return Self.projectVersions(versions, target: target, kind: kind)
        }

        private static func projectVersions(
            _ versions: [CofreModVersion], target: (game: String, loader: Loader), kind: ContentKind
        ) -> [ProjectVersion] {
            versions.map { version in
                let number = version.data["version"] as? String ?? version.name
                // CurseForge's "number" is a file ID; its name is the file name, which cleans up better.
                let raw = version.source == 2 ? version.name : number
                var row = ProjectVersion(
                    id: version.id, name: VersionLabel.clean(raw),
                    gameVersions: version.gameVersions.joined(separator: ", "),
                    channel: (version.data["channel"] as? String ?? "release").capitalized,
                    fits: version.candidate(title: "").fits(game: target.game, loader: target.loader, kind: kind),
                    number: raw, games: version.gameVersions, loaders: version.loaders.compactMap(Loader.init(rawValue:)))
                row.changelog = (version.data["changelog"] as? String).flatMap { $0.isEmpty ? nil : .markdown($0) }
                return row
            }
        }

        public func dependencies(versionID: String, instanceID: String) async throws -> [ProjectDependency] {
            guard let version = modCatalog.versions[versionID] else {
                throw modError("Reload this project's versions before checking dependencies.")
            }
            let local = try await scan(.mods, instanceID: instanceID, online: false)
            var out: [ProjectDependency] = []
            for dependency in version.dependencies where dependency.relation != .incompatible {
                let id = dependency.projectID.isEmpty ? dependency.versionID ?? "unknown" : dependency.projectID
                let name = await projectTitle(id, source: version.source)
                out.append(
                    ProjectDependency(
                        id: id, name: name, required: dependency.required,
                        installed: local.contains { $0.enabled && $0.matches(id, title: name) }))
            }
            return out
        }

        // MARK: Plan and install

        public func installPlan(projectID: String, versionID: String?, kind: ContentKind, instanceID: String)
            async throws -> ModInstallPlan
        {
            let source = source(of: projectID)
            let target = modTarget(instanceID)
            let have = kind == .modpacks ? [] : try await scan(kind, instanceID: instanceID, online: false)
            let resolver = ModResolver(
                game: target.game, loader: target.loader, kind: kind, installed: have,
                versions: { [weak self] id in try await self?.candidates(id, source: source) ?? [] })
            var plan = try await resolver.plan(projectID: projectID, versionID: versionID)
            if kind == .dataPacks {
                plan.blocked = "Data packs belong to a world. Cofre can't add them to the whole instance yet."
            }
            return plan
        }

        public func install(projectID: String, versionID: String, instanceID: String)
            -> AsyncThrowingStream<InstallProgress, Error>
        {
            let kind = Self.kind(modCatalog.projects[projectID]?["projectType"] as? String)
            return AsyncThrowingStream { continuation in
                Task { @MainActor in
                    do {
                        let plan = try await installPlan(
                            projectID: projectID, versionID: versionID == "latest" ? nil : versionID, kind: kind,
                            instanceID: instanceID)
                        if let reason = plan.blocked { throw modError(reason) }
                        for try await p in install(plan, picking: [], instanceID: instanceID) { continuation.yield(p) }
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
            }
        }

        /// Downloads every file into a staging folder first, then moves them all in. A failure before the move
        /// leaves the instance untouched; one during it puts back what moved.
        public func install(_ plan: ModInstallPlan, picking optionalIDs: Set<String>, instanceID: String)
            -> AsyncThrowingStream<InstallProgress, Error>
        {
            install(plan, picking: optionalIDs, instanceID: instanceID, world: nil)
        }

        /// `world`: a data pack update goes back into the world it came from.
        private func install(_ plan: ModInstallPlan, picking optionalIDs: Set<String>, instanceID: String, world: String?)
            -> AsyncThrowingStream<InstallProgress, Error>
        {
            AsyncThrowingStream { continuation in
                Task { @MainActor in
                    let fm = FileManager.default
                    let staging = fm.temporaryDirectory.appendingPathComponent("cofre-install-\(UUID().uuidString)")
                    defer { try? fm.removeItem(at: staging) }
                    let files = plan.files(picking: optionalIDs)
                    var stages = files.map { InstallProgress.Stage(title: $0.name, state: .unknown) }
                    let total = max(files.compactMap { $0.turnsOn ? nil : $0.sizeBytes }.reduce(0, +), 1)
                    var done: Int64 = 0
                    func send() {
                        continuation.yield(
                            InstallProgress(
                                title: plan.target.name, fraction: min(Double(done) / Double(total), 0.99),
                                stages: stages))
                    }
                    do {
                        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                        var staged: [(mod: PlannedMod, version: CofreModVersion, file: URL)] = []
                        var dependencyIDs = Set(plan.required.map(\.id))
                        for (i, mod) in files.enumerated() {
                            stages[i].state = .checking
                            stages[i].detail = mod.turnsOn ? "Turning on" : nil
                            send()
                            if !mod.turnsOn {
                                guard let version = modCatalog.versions[mod.versionID] else {
                                    throw modError("\(mod.name) is no longer available. Try again.")
                                }
                                let file = try await download(version, kind: plan.kind, name: mod.name, into: staging)
                                staged.append((mod, version, file))
                                done += mod.sizeBytes ?? 0
                            }
                            stages[i].state = .ready
                        }
                        // A jar's own mods.toml can need more than Modrinth lists (a Kotlin mod needs Kotlin for Forge).
                        var turnOn = files.filter(\.turnsOn)
                        if plan.kind == .mods {
                            for mod in await requiredByJars(staged.map(\.file), plan: plan, instanceID: instanceID) {
                                dependencyIDs.insert(mod.id)
                                stages.append(InstallProgress.Stage(title: mod.name, state: .checking))
                                send()
                                if mod.turnsOn {
                                    turnOn.append(mod)
                                } else if let version = modCatalog.versions[mod.versionID] {
                                    let file = try await download(version, kind: .mods, name: mod.name, into: staging)
                                    staged.append((mod, version, file))
                                }
                                stages[stages.count - 1].state = .ready
                            }
                        }
                        if plan.makesInstance {
                            guard let pack = staged.first?.file else { throw modError("The pack didn't download.") }
                            try await importWithAir(pack) { fraction, _ in
                                continuation.yield(
                                    InstallProgress(title: plan.target.name, fraction: fraction, stages: stages))
                            }
                        } else {
                            try await commit(staged, dependencyIDs: dependencyIDs, turningOn: turnOn, kind: plan.kind,
                                instanceID: instanceID, world: world, backup: staging.appendingPathComponent(".replaced"))
                        }
                        NSLog("[Cofre] mods installed instance=%@ files=%ld", instanceID, files.count)
                        continuation.yield(InstallProgress(title: plan.target.name, fraction: 1, stages: stages))
                        continuation.finish()
                    } catch {
                        NSLog("[Cofre] mods install failed instance=%@ %@", instanceID, error.localizedDescription)
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        private func download(_ version: CofreModVersion, kind: ContentKind, name: String, into folder: URL)
            async throws -> URL
        {
            let filename = version.file["filename"] as? String ?? ""
            let allowed = kind == .mods ? ["jar"] : kind == .modpacks ? ["mrpack", "zip"] : ["zip"]
            guard let url = modURL(version.file["url"]), url.scheme == "https",
                !filename.isEmpty, (filename as NSString).lastPathComponent == filename,
                !filename.hasPrefix("."), allowed.contains((filename as NSString).pathExtension.lowercased())
            else {
                throw modError(
                    version.source == 2 && version.file["url"] == nil
                        ? "\(name) only downloads in CurseForge's app."
                        : "\(name) has no file Cofre can install.")
            }
            let destination = folder.appendingPathComponent(filename)
            do {
                return try await DownloadQueue.shared.download(url: url, destination: destination, title: name,
                    totalBytes: version.sizeBytes, sha1: version.sha1)
            } catch let error as DownloadQueue.QueueError { throw modError(error.localizedDescription) }
        }

        /// Moves staged files in, turns disabled dependencies back on, and drops older files of the same projects.
        private func commit(
            _ staged: [(mod: PlannedMod, version: CofreModVersion, file: URL)], dependencyIDs: Set<String>,
            turningOn: [PlannedMod],
            kind: ContentKind, instanceID: String, world: String?, backup: URL
        ) async throws {
            let fm = FileManager.default
            let folder = try contentFolder(kind, instanceID: instanceID, create: true, world: world)
            try fm.createDirectory(at: backup, withIntermediateDirectories: true)
            let have = try await scan(kind, instanceID: instanceID, online: false).filter { $0.world == world }
            // Data pack IDs are "<world>/<file>"; the file is the last part.
            func file(_ item: InstalledItem) -> String { (item.id as NSString).lastPathComponent }
            var undo: [() -> Void] = []
            func move(_ from: URL, _ to: URL) throws {
                try fm.moveItem(at: from, to: to)
                undo.append { try? fm.moveItem(at: to, to: from) }
            }
            do {
                for mod in turningOn {
                    guard let item = have.first(where: { !$0.enabled && $0.matches(mod.id, title: mod.name) }) else {
                        continue
                    }
                    try move(
                        folder.appendingPathComponent(file(item) + ".disabled"), folder.appendingPathComponent(file(item)))
                }
                var index = modIndex(instanceID)
                for (mod, version, downloaded) in staged {
                    // Older files of this project (an update), and a same-named file, step aside first.
                    let fresh = downloaded.lastPathComponent
                    let old = have.filter { $0.projectID == mod.id || file($0) == fresh }
                    for item in old {
                        let path = folder.appendingPathComponent(item.enabled ? file(item) : file(item) + ".disabled")
                        try move(path, backup.appendingPathComponent(path.lastPathComponent))
                        index[item.id] = nil
                    }
                    // A pack in use keeps its file name, so the game's own choice (options.txt, the shader mod's
                    // config) still finds it; Cofre never writes those.
                    let name = kind == .mods ? fresh : old.first(where: \.inUse).map(file) ?? fresh
                    try move(downloaded, folder.appendingPathComponent(name))
                    let installedAsDependency = dependencyIDs.contains(mod.id)
                    index[world.map { "\($0)/\(name)" } ?? name] =
                        "\(version.source)|\(mod.id)|\(version.id)|\(installedAsDependency ? "dependency" : "direct")"
                }
                UserDefaults.standard.set(index, forKey: Self.indexKey(instanceID))
            } catch {
                undo.reversed().forEach { $0() }
                throw error
            }
        }

        // MARK: Installed content

        public func installed(_ kind: ContentKind, instanceID: String) async throws -> [InstalledItem] {
            var items = try await scan(kind, instanceID: instanceID, online: true)
            if kind == .mods { await markRequirements(&items, instanceID: instanceID) }
            return items
        }

        /// The files in the instance's folder for `kind`. Air reads mod names and versions out of each jar. `online`
        /// asks Modrinth which project each unknown file is, and for updates; offline only what's cached is used.
        func scan(_ kind: ContentKind, instanceID: String, online: Bool, identify: Bool = true) async throws
            -> [InstalledItem]
        {
            guard kind.folderName != nil, let directory = air.gameDirectory(forProfile: instanceID) else { return [] }
            let store = ContentStore(gameDirectory: directory)
            let files = try store.list(kind)
            var items = files.map { file in
                var item = InstalledItem(id: file.id, name: file.name, version: file.version, enabled: file.enabled, kind: kind)
                item.inUse = file.inUse
                item.world = file.world
                return item
            }
            let paths = Dictionary(files.map { ($0.id, store.url(of: $0)) }) { a, _ in a }
            if identify { await self.identify(&items, kind: kind, paths: paths, instanceID: instanceID, online: online) }
            if kind == .mods { await self.enrichInstalledMods(&items, paths: paths, instanceID: instanceID, online: online) }
            return items
        }

        /// Fills `projectID` (and `updateTo` for mods): Cofre's own install index first, then each file's SHA-1
        /// through Modrinth's version_files, which also knows files installed by Air or copied in by hand.
        private func identify(
            _ items: inout [InstalledItem], kind: ContentKind, paths: [String: URL], instanceID: String, online: Bool
        ) async {
            guard !items.isEmpty else { return }
            let index = modIndex(instanceID)
            var hashOf: [String: String] = [:]
            for item in items {
                if let path = paths[item.id], let sha = try? await cachedSHA1(path) { hashOf[item.id] = sha }
            }
            let unknown = Set(hashOf.values).filter { modCatalog.identities[$0] == nil }
            if online, !unknown.isEmpty, let found = try? await modCatalog.modrinth.versionFiles(hashes: Array(unknown)) {
                for sha in unknown {
                    let v = found[sha]
                    modCatalog.identities[sha] = v.map { "\($0.projectID)|\($0.id)|\($0.versionType)" } ?? ""
                }
                UserDefaults.standard.set(
                    modCatalog.identities.filter { !$0.value.isEmpty }, forKey: PreferenceKey.modsIdentities.rawValue)
            }
            for i in items.indices {
                if let entry = index[items[i].id]?.split(separator: "|").map(String.init), entry.count >= 3 {
                    items[i].projectID = entry[1]
                    items[i].versionID = entry[2]
                    items[i].projectSource = entry[0] == "2" ? .curseforge : .modrinth
                    items[i].installedDirectly = entry.count < 4 || entry[3] != "dependency"
                    modCatalog.titles[entry[1]] = modCatalog.titles[entry[1]] ?? items[i].name
                } else if let sha = hashOf[items[i].id], let id = identity(sha) {
                    items[i].projectID = id.project
                    items[i].versionID = id.version
                    items[i].projectSource = .modrinth
                }
            }
            await markUpdates(&items, kind: kind, hashOf: hashOf, instanceID: instanceID, online: online)
        }

        /// Adds jar metadata and the icon URL/data used by Installed. The expensive jar reads happen in detached
        /// tasks; rows remain lazy on the UI side and the scanner cache is keyed by path, size and mtime.
        private func enrichInstalledMods(
            _ items: inout [InstalledItem], paths: [String: URL], instanceID: String, online: Bool
        ) async {
            let target = modTarget(instanceID)
            let results = await withTaskGroup(of: (String, ModJarMetadata?).self, returning: [(String, ModJarMetadata?)].self) { group in
                for item in items {
                    guard let path = paths[item.id] else { continue }
                    group.addTask {
                        let found = await Task.detached(priority: .utility) {
                            ModJarMetadata.read(jar: path, loader: target.loader)
                        }.value
                        return (item.id, found)
                    }
                }
                var out: [(String, ModJarMetadata?)] = []
                for await result in group { out.append(result) }
                return out
            }
            let metadata: [String: ModJarMetadata?] = Dictionary(uniqueKeysWithValues: results)
            for i in items.indices {
                items[i].loader = target.loader.displayName
                guard let jar = metadata[items[i].id] ?? nil else { continue }
                items[i].modID = jar.modIDs.first
                items[i].dependencies = jar.dependencies
                items[i].iconPNG = jar.icon
                items[i].iconCacheKey = jar.cacheKey
                if let name = jar.name, !name.isEmpty, items[i].name.isEmpty { items[i].name = name }
                if let version = jar.version, !version.isEmpty, items[i].version.isEmpty { items[i].version = version }
            }

            var projectIDs = Set<String>()
            for item in items where item.projectID != nil { projectIDs.insert(item.projectID!) }
            if online {
                let modrinthIDs = projectIDs.filter { id in
                    items.first(where: { $0.projectID == id })?.projectSource == .modrinth
                        && (modCatalog.projects[id]?["imageUrl"] as? String)?.isEmpty != false
                }
                if !modrinthIDs.isEmpty, let projects = try? await modCatalog.modrinth.projects(ids: Array(modrinthIDs)) {
                    for project in projects {
                        let id = project.id
                        modCatalog.projects[id] = [
                            "id": id, "title": project.title, "description": project.description ?? "",
                            "imageUrl": project.iconURL?.absoluteString ?? "", "projectType": "mod", "apiSource": 1,
                        ]
                    }
                }
                for id in projectIDs where items.first(where: { $0.projectID == id })?.projectSource == .curseforge {
                    let image = modCatalog.projects[id]?["imageUrl"] as? String
                    if image?.isEmpty != false { _ = await projectTitle(id, source: 2) }
                }
            }
            for i in items.indices {
                if let id = items[i].projectID {
                    items[i].iconURL = modURL(modCatalog.projects[id]?["imageUrl"])
                    if items[i].projectSource == nil { items[i].projectSource = .modrinth }
                    if let versionID = items[i].versionID, let version = modCatalog.versions[versionID] {
                        items[i].dependencies += version.dependencies.filter { $0.required }.map {
                            ModDependency(id: $0.projectID.isEmpty ? ($0.versionID ?? "unknown") : $0.projectID)
                        }
                    }
                }
                items[i].dependencies = items[i].dependencies.reduce(into: []) {
                    let key = $1.id.lowercased().filter { $0.isLetter || $0.isNumber }
                    if !$0.contains(where: { $0.id.lowercased().filter { $0.isLetter || $0.isNumber } == key }) {
                        $0.append($1)
                    }
                }
                let kitEnabled = paths.values.first.map {
                    MetalMod.supports(gameVersion: target.game, loader: target.loader)
                        && MetalMod.isEnabled(in: $0.deletingLastPathComponent().deletingLastPathComponent(), loader: target.loader)
                } == true
                if kitEnabled, let modID = items[i].modID?.lowercased() {
                    let kitIDs = Set([MetalMod.modID, "fabric_api", "fabric-api", "forgified_fabric_api", "forgified-fabric-api", "connector", "launchpad"])
                    items[i].protectedFromRemoval = kitIDs.contains(modID)
                }
            }
        }

        /// What Modrinth said a file is: project, version, channel. Entries saved before channels read as release,
        /// the strictest for updates.
        private func identity(_ sha: String) -> (project: String, version: String, channel: VersionChannel)? {
            guard let parts = modCatalog.identities[sha]?.split(separator: "|").map(String.init), parts.count >= 2,
                !parts[0].isEmpty
            else { return nil }
            return (parts[0], parts[1], VersionChannel(parts.count > 2 ? parts[2] : nil))
        }

        /// Newer builds for this game and loader, never on a less stable channel than the installed one
        /// (`VersionChannel.allowsUpdate`): one request per channel group, then a check of what came back.
        private func markUpdates(
            _ items: inout [InstalledItem], kind: ContentKind, hashOf: [String: String], instanceID: String, online: Bool
        ) async {
            let known = hashOf.compactMapValues { sha in identity(sha).map { (sha, $0) } }
            let cacheKey = "\(instanceID)|\(kind.rawValue)"
            let cached = modCatalog.updates[cacheKey]
            var latest = cached?.latest ?? [:]
            let stale = cached.map { Date().timeIntervalSince($0.asked) > 1800 } ?? true
            let target = modTarget(instanceID)
            if online, !known.isEmpty, stale || known.values.contains(where: { latest[$0.0] == nil }) {
                let loaders = kind.updateLoaders(target.loader)
                var found: [String: [String: Any]] = [:]
                for (channel, group) in Dictionary(grouping: known.values, by: { $0.1.channel }) {
                    if let answer = try? await modrinthJSON(
                        "version_files/update",
                        body: [
                            "hashes": Array(Set(group.map { $0.0 })), "algorithm": "sha1", "loaders": loaders,
                            "game_versions": [target.game], "version_types": channel.updateChannels.map(\.raw),
                        ]) as? [String: [String: Any]]
                    {
                        found.merge(answer) { a, _ in a }
                    }
                }
                latest = found
                modCatalog.updates[cacheKey] = (Date(), found)
                modCatalog.allowedUpdates = modCatalog.allowedUpdates.filter { !$0.key.hasPrefix("\(instanceID)|") }
            }
            for i in items.indices {
                guard let entry = known[items[i].id], let newest = latest[entry.0],
                    let newID = newest["id"] as? String, newID != entry.1.version
                else { continue }
                let (sha, current) = entry
                var pick: CofreModVersion?
                if current.channel.allowsUpdate(to: VersionChannel(newest["version_type"] as? String)) {
                    pick = Self.modrinthVersion(newest, projectID: current.project)
                    modCatalog.versions[newID] = pick
                } else {
                    // The newest is less stable: look for a newer build on an allowed channel, once per refresh.
                    let key = "\(instanceID)|\(sha)"
                    if modCatalog.allowedUpdates[key] == nil, online {
                        let all = (try? await loadModVersions(projectID: current.project, source: 1)) ?? []
                        modCatalog.allowedUpdates[key] =
                            all.prefix { $0.id != current.version }.first {
                                $0.candidate(title: "").fits(game: target.game, loader: target.loader, kind: kind)
                                    && current.channel.allowsUpdate(to: VersionChannel($0.data["channel"] as? String))
                            }?.id ?? ""
                    }
                    pick = modCatalog.allowedUpdates[key].flatMap { modCatalog.versions[$0] }
                }
                guard let pick else { continue }
                items[i].updateTo = VersionLabel.clean(pick.data["version"] as? String ?? pick.name)
                items[i].updateVersionID = pick.id
            }
        }

        /// A Modrinth API version object in Air's row shape, so install can download it.
        private static func modrinthVersion(_ v: [String: Any], projectID: String) -> CofreModVersion {
            let files = v["files"] as? [[String: Any]] ?? []
            return CofreModVersion(data: [
                "id": v["id"] as? String ?? "", "projectID": projectID, "apiSource": 1,
                "name": v["name"] as? String ?? "", "version": v["version_number"] ?? "",
                "gameVersions": v["game_versions"] ?? [], "loaders": v["loaders"] ?? [],
                "channel": v["version_type"] ?? "release", "dependencies": v["dependencies"] ?? [],
                "file": files.first { $0["primary"] as? Bool == true } ?? files.first ?? [:],
            ])
        }

        /// The instance's content folder and the file behind `item`.
        private func contentFile(_ item: InstalledItem, instanceID: String) throws -> (ContentStore, ContentStore.Item)? {
            guard item.kind.folderName != nil, let directory = air.gameDirectory(forProfile: instanceID) else { return nil }
            let store = ContentStore(gameDirectory: directory)
            return try store.list(item.kind).first { $0.id == item.id }.map { (store, $0) }
        }

        public func setEnabled(_ enabled: Bool, item: InstalledItem, instanceID: String) async throws {
            guard let (store, file) = try contentFile(item, instanceID: instanceID) else { return }
            try store.setEnabled(enabled, file)
            NSLog("[Cofre] content %@ kind=%@ inUse=%d", enabled ? "on" : "off", item.kind.rawValue, file.inUse ? 1 : 0)
        }

        public func delete(_ item: InstalledItem, instanceID: String) async throws {
            guard let (store, file) = try contentFile(item, instanceID: instanceID) else { return }
            _ = try store.trash(file)
            NSLog("[Cofre] content deleted kind=%@", item.kind.rawValue)
            var index = modIndex(instanceID)
            index[item.id] = nil
            UserDefaults.standard.set(index, forKey: Self.indexKey(instanceID))
        }

        /// Each update is its own plan and install, so new dependencies come along and a failure stops only it.
        /// Mods, shaders, resource packs and data packs; a data pack goes back into its own world.
        public func updateAll(kind: ContentKind, instanceID: String) async throws {
            var failed: [String] = []
            var updated = 0
            guard kind.folderName != nil else { return }
            for item in try await scan(kind, instanceID: instanceID, online: true) where item.updateTo != nil {
                guard let id = item.projectID, let next = item.updateVersionID else { continue }
                do {
                    var plan = try await installPlan(projectID: id, versionID: next, kind: kind, instanceID: instanceID)
                    if kind == .dataPacks, item.world != nil { plan.blocked = nil }
                    if let reason = plan.blocked { throw modError(reason) }
                    for try await _ in install(plan, picking: [], instanceID: instanceID, world: item.world) {}
                    updated += 1
                } catch { failed.append(item.name) }
            }
            NSLog("[Cofre] content updated instance=%@ updated=%ld failed=%ld", instanceID, updated, failed.count)
            modCatalog.updates = modCatalog.updates.filter { !$0.key.hasPrefix("\(instanceID)|") }
            if !failed.isEmpty {
                throw modError("Couldn't update \(ListFormatter.localizedString(byJoining: failed)).")
            }
        }

        // MARK: Helpers

        private func candidates(_ projectID: String, source: Int) async throws -> [ModCandidate] {
            var versions = try await loadModVersions(projectID: projectID, source: source)
            // CurseForge file IDs only grow, so higher is newer.
            if source == 2 { versions.sort { (Int($0.id) ?? 0) > (Int($1.id) ?? 0) } }
            let title = await projectTitle(projectID, source: source)
            return versions.map { $0.candidate(title: title) }
        }

        private func projectTitle(_ id: String, source: Int) async -> String {
            let cached = modCatalog.projects[id]?["title"] as? String ?? modCatalog.titles[id]
            let image = modCatalog.projects[id]?["imageUrl"] as? String
            if source != 2 || image?.isEmpty == false { return cached ?? id }
            var title: String? = cached
            if source == 2 {
                if let key = curseForgeKey(), let url = URL(string: "https://api.curseforge.com/v1/mods/\(id)") {
                    var request = URLRequest(url: url)
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.timeoutInterval = 15
                    if let (data, _) = try? await URLSession.shared.data(for: request),
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    {
                        if let payload = json["data"] as? [String: Any] {
                            title = payload["name"] as? String ?? title
                            var project = modCatalog.projects[id] ?? [:]
                            project["id"] = id
                            project["title"] = title ?? id
                            project["imageUrl"] = (payload["logo"] as? [String: Any])?["url"] as? String ?? ""
                            project["projectType"] = project["projectType"] ?? "mod"
                            project["apiSource"] = 2
                            modCatalog.projects[id] = project
                        }
                    }
                }
            } else {
                title = try? await modCatalog.modrinth.project(id: id).title
            }
            if let title { modCatalog.titles[id] = title }
            return title ?? id
        }

        private func modrinthJSON(_ path: String, body: [String: Any]?) async throws -> Any {
            guard let url = URL(string: "https://api.modrinth.com/v2/\(path)") else { throw modError("Bad request.") }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            if let body {
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                throw modError("Modrinth answered \((response as? HTTPURLResponse)?.statusCode ?? 0).")
            }
            return try JSONSerialization.jsonObject(with: data)
        }

        private func cachedSHA1(_ url: URL) async throws -> String {
            let a = try FileManager.default.attributesOfItem(atPath: url.path)
            guard a[.type] as? FileAttributeType == .typeRegular else { throw modError("Not a file.") }
            let key = "\(url.path)|\(a[.size] ?? 0)|\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
            if let sha = modCatalog.hashes[key] { return sha }
            let sha = try await Self.sha1(of: url)
            modCatalog.hashes[key] = sha
            return sha
        }

        /// Off the main actor: a big modpack folder is hundreds of megabytes.
        nonisolated private static func sha1(of url: URL) async throws -> String {
            try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }.value
        }

        /// The instance's folder for `kind`: Air's mods folder, and its siblings for shaders and resource packs.
        /// The same folder `scan` lists, so an install sees what is already there.
        private func contentFolder(_ kind: ContentKind, instanceID: String, create: Bool, world: String? = nil) throws -> URL {
            // Data packs live inside each world (saves/<world>/datapacks); there is no instance-wide folder.
            guard kind.isInstallable || (kind == .dataPacks && world != nil) else {
                throw modError("Data packs belong to a world, so Cofre can't add them to the whole instance yet.")
            }
            guard let directory = air.gameDirectory(forProfile: instanceID) else {
                throw modError("This instance's folder is missing.")
            }
            let folder = ContentStore(gameDirectory: directory).folder(for: kind, world: world)
            if create { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            return folder
        }

        /// Files Cofre installed: file name → "source|projectID|versionID".
        private func modIndex(_ instanceID: String) -> [String: String] {
            UserDefaults.standard.dictionary(forKey: PreferenceKey.modsIndex(instanceID).rawValue) as? [String: String] ?? [:]
        }
        private static func indexKey(_ instanceID: String) -> String { PreferenceKey.modsIndex(instanceID).rawValue }
        private static let userAgent = "ignaciojuarez/cofre (github.com/ignaciojuarez/cofre)"

        /// The instance's Minecraft version and loader, read by CofreKit from launcher_profiles.json.
        private func modTarget(_ instanceID: String) -> (game: String, loader: Loader) {
            guard let instance = try? storedInstance(instanceID) else { return ("", .unknown) }
            return (instance.gameVersion, instance.loader)
        }

        private func source(of projectID: String) -> Int {
            modCatalog.projects[projectID]?["apiSource"] as? Int
                ?? modCatalog.versions.values.first { $0.projectID == projectID }?.source ?? 1
        }

        private static func projectType(_ kind: ContentKind) -> String {
            switch kind {
            case .mods: "mod"
            case .shaders: "shader"
            case .resourcePacks: "resourcepack"
            case .dataPacks: "datapack"
            case .modpacks: "modpack"
            }
        }
        private static func kind(_ projectType: String?) -> ContentKind {
            ContentKind.allCases.first { self.projectType($0) == projectType } ?? .mods
        }

        /// Only the page's filtered request needs changelogs; full lists skip them (less than half the size).
        private func loadModVersions(projectID: String, source: Int, loaders: [String] = [], gameVersions: [String] = [], includeChangelog: Bool = false) async throws -> [CofreModVersion] {
            if source == 1 {
                return try await modCatalog.modrinth.versions(projectID: projectID, loaders: loaders, gameVersions: gameVersions, includeChangelog: includeChangelog).map { v in
                    // The same file keys Air's rows carry; `download` needs the URL and the file name.
                    let file: [String: Any] = (v.files.first(where: { $0.primary }) ?? v.files.first).map {
                        ["url": $0.url?.absoluteString ?? "", "filename": $0.filename, "size": $0.size, "hashes": $0.hashes]
                    } ?? [:]
                    let version = CofreModVersion(data: ["id": v.id, "projectID": v.projectID, "apiSource": 1, "name": v.name, "version": v.versionNumber, "gameVersions": v.gameVersions, "loaders": v.loaders, "channel": v.versionType, "dependencies": v.dependencies.map { ["project_id": $0.projectID as Any, "version_id": $0.versionID as Any, "dependency_type": $0.dependencyType] }, "file": file, "changelog": v.changelog ?? ""])
                    modCatalog.versions[version.id] = version
                    return version
                }
            }
            let rows = try await modRows { done in air.projectVersions(projectID, source: source, completion: done) }
            return rows.map { row in let version = CofreModVersion(data: row); modCatalog.versions[version.id] = version; return version }
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
