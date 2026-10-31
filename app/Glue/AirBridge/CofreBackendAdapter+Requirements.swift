#if canImport(UIKit)
    import CofreKit
    import CofreUI
    import Foundation

    /// Mods a jar's own mods.toml needs that Modrinth doesn't list (CofreKit's `ModRequirements`): added to installs,
    /// shown on the Installed list as "Needs …", and offered by the crash screen. Forge and NeoForge only.
    extension CofreBackendAdapter {
        /// The adapter Cofre's UI runs on, for the crash screen, which has no store of its own.
        public static weak var current: CofreBackendAdapter?

        struct ResolvedRequirement {
            let requirement: ModRequirement
            let projectID: String, name: String
        }

        /// mods.toml per jar by path, size and date, so the Installed list doesn't reopen every jar.
        private static var tomls: [String: ModsToml?] = [:]

        /// What the instance's enabled jars, plus `staged` ones not moved in yet, need and nothing installed provides.
        /// Only requirements Modrinth knows as a mod come back: a guess never shows up as "Needs".
        func missingRequirements(instanceID: String, staged: [URL] = [], have: [InstalledItem]) async
            -> [ResolvedRequirement]
        {
            guard let instance = try? storedInstance(instanceID), [.forge, .neoforge].contains(instance.loader),
                let directory = air.gameDirectory(forProfile: instanceID)
            else { return [] }
            let store = ContentStore(gameDirectory: directory)
            let jars = ((try? store.list(.mods)) ?? []).filter(\.enabled).map { store.url(of: $0) } + staged
            let read = await readTomls(jars, neoForge: instance.loader == .neoforge)
            let found = ModRequirements.missing(
                in: read.compactMap { file, toml in toml.map { (file, $0) } },
                otherFiles: read.filter { $0.toml == nil }.map(\.file))
            var out: [ResolvedRequirement] = []
            for requirement in found {
                guard let resolved = await resolve(requirement),
                    !have.contains(where: { $0.enabled && $0.matches(resolved.projectID, title: resolved.name) })
                else { continue }
                out.append(resolved)
            }
            return out
        }

        /// Marks each jar that needs something missing (the Installed list's "Needs Kotlin for Forge · Get").
        func markRequirements(_ items: inout [InstalledItem], instanceID: String) async {
            for r in await missingRequirements(instanceID: instanceID, have: items) {
                guard let i = items.firstIndex(where: { $0.id == r.requirement.neededBy }) else { continue }
                items[i].needs.append(ProjectDependency(id: r.projectID, name: r.name, installed: false))
                NSLog("[Cofre] dependency missing project=%@ reason=%@", r.projectID, r.requirement.reason)
            }
        }

        /// Extra files an install needs because a downloaded jar asks for them, planned the way Get plans a project
        /// (this instance's loader and game version). One that can't install is left out; Installed then says so.
        func requiredByJars(_ staged: [URL], plan: ModInstallPlan, instanceID: String) async -> [PlannedMod] {
            let have = (try? await scan(.mods, instanceID: instanceID, online: false)) ?? []
            var planned = Set(plan.files(picking: Set(plan.optional.map(\.id))).map(\.id))
            var out: [PlannedMod] = []
            for r in await missingRequirements(instanceID: instanceID, staged: staged, have: have)
            where !planned.contains(r.projectID) {
                guard
                    let sub = try? await installPlan(
                        projectID: r.projectID, versionID: nil, kind: .mods, instanceID: instanceID)
                else { continue }
                if let reason = sub.blocked {
                    NSLog(
                        "[Cofre] dependency skipped project=%@ reason=%@ %@", r.projectID, r.requirement.reason, reason)
                    continue
                }
                for mod in sub.files() where planned.insert(mod.id).inserted { out.append(mod) }
                NSLog("[Cofre] dependency added project=%@ reason=%@", r.projectID, r.requirement.reason)
            }
            return out
        }

        /// The crash screen's Get: installs what the crash named into `instanceID`, like Get on a mod page.
        func installRequirements(_ requirements: [ModRequirement], instanceID: String) async throws {
            var installed = 0
            for requirement in requirements {
                guard let r = await resolve(requirement) else { continue }
                NSLog("[Cofre] crash fix get project=%@ instance=%@", r.projectID, instanceID)
                let plan = try await installPlan(
                    projectID: r.projectID, versionID: nil, kind: .mods, instanceID: instanceID)
                if let reason = plan.blocked {
                    throw NSError(domain: "CofreMods", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
                }
                for try await _ in install(plan, picking: [], instanceID: instanceID) {}
                installed += 1
            }
            guard installed > 0 else {
                throw NSError(
                    domain: "CofreMods", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Cofre couldn't find \(requirements.map(\.name).formatted()) on Modrinth."
                    ])
            }
        }

        /// The Modrinth project behind a requirement: the known one, else the first slug that is a mod.
        private func resolve(_ r: ModRequirement) async -> ResolvedRequirement? {
            if let id = r.projectID { return ResolvedRequirement(requirement: r, projectID: id, name: r.name) }
            for slug in r.slugs {
                if let p = try? await modCatalog.modrinth.project(id: slug), p.projectType == "mod" {
                    modCatalog.titles[p.id] = p.title
                    return ResolvedRequirement(requirement: r, projectID: p.id, name: p.title)
                }
            }
            return nil
        }

        /// Off the main actor: a big instance has hundreds of jars.
        private func readTomls(_ jars: [URL], neoForge: Bool) async -> [(file: String, toml: ModsToml?)] {
            func key(_ url: URL) -> String {
                let a = try? FileManager.default.attributesOfItem(atPath: url.path)
                return
                    "\(url.path)|\(a?[.size] ?? 0)|\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(neoForge)"
            }
            let keys = jars.map(key)
            let unread = zip(jars, keys).filter { Self.tomls[$0.1] == nil }
            let fresh = await Task.detached(priority: .userInitiated) {
                unread.map { ($0.1, ModsToml.read(jar: $0.0, neoForge: neoForge)) }
            }.value
            for (k, toml) in fresh { Self.tomls[k] = .some(toml) }
            return zip(jars, keys).map { ($0.0.lastPathComponent, Self.tomls[$0.1] ?? nil) }
        }
    }
#endif
