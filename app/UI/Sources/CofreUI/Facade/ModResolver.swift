#if canImport(UIKit)
    import Foundation

    // One dependency resolver for every backend, so the rules are tested once (CofreUITests). A backend hands it each
    // project's versions, newest first; it returns an `ModInstallPlan`. Modrinth and CurseForge differ only in how the
    // backend reads their version rows into `ModCandidate`.

    /// One downloadable version of a project, as the resolver needs it.
    public struct ModCandidate: Hashable, Sendable {
        public enum Relation: Hashable, Sendable { case required, optional, incompatible }
        public struct Dependency: Hashable, Sendable {
            public var projectID: String, versionID: String?, relation: Relation
            public init(projectID: String, versionID: String? = nil, relation: Relation) {
                self.projectID = projectID
                self.versionID = versionID
                self.relation = relation
            }
        }
        public var projectID: String, versionID: String
        /// The project's title ("Cloth Config"), not the version's.
        public var title: String, version: String
        public var gameVersions: [String], loaders: [String]
        /// "release", "beta" or "alpha".
        public var channel: String
        public var sizeBytes: Int64?
        public var dependencies: [Dependency]
        /// CurseForge authors can forbid downloads outside their app; those files have no URL.
        public var downloadable: Bool
        public init(
            projectID: String, versionID: String, title: String, version: String, gameVersions: [String],
            loaders: [String], channel: String = "release", sizeBytes: Int64? = nil, dependencies: [Dependency] = [],
            downloadable: Bool = true
        ) {
            self.projectID = projectID
            self.versionID = versionID
            self.title = title
            self.version = version
            self.gameVersions = gameVersions
            self.loaders = loaders.map { $0.lowercased() }
            self.channel = channel.lowercased()
            self.sizeBytes = sizeBytes
            self.dependencies = dependencies
            self.downloadable = downloadable
        }

        /// Exact game version, and the instance's loader. Quilt runs Fabric mods; shaders and packs list no loader
        /// we know, so only the game version counts for them.
        public func fits(game: String, loader: Loader, kind: ContentKind = .mods) -> Bool {
            guard gameVersions.contains(game) else { return false }
            guard kind == .mods else { return true }
            return loaders.isEmpty || loaders.contains(loader.rawValue)
                || (loader == .quilt && loaders.contains(Loader.fabric.rawValue))
        }

        var planned: PlannedMod {
            PlannedMod(id: projectID, name: title, versionID: versionID, version: version, sizeBytes: sizeBytes)
        }
    }

    public struct ModResolver {
        public var game: String, loader: Loader, kind: ContentKind
        /// What the Mods target has now, on and off.
        public var installed: [InstalledItem]
        /// A project's versions, newest first. Throws offline or without a CurseForge key.
        public var versions: (String) async throws -> [ModCandidate]

        public init(
            game: String, loader: Loader, kind: ContentKind = .mods, installed: [InstalledItem],
            versions: @escaping (String) async throws -> [ModCandidate]
        ) {
            self.game = game
            self.loader = loader
            self.kind = kind
            self.installed = installed
            self.versions = versions
        }

        /// `versionID == nil` picks the newest fitting release (then beta, then alpha).
        public func plan(projectID: String, versionID: String? = nil) async throws -> ModInstallPlan {
            let all = try await versions(projectID)
            let root =
                versionID.flatMap { id in all.first { $0.versionID == id } }
                ?? pick(all, pinned: nil)
            guard let root else {
                let title = all.first?.title ?? projectID
                return ModInstallPlan(
                    target: PlannedMod(id: projectID, name: title, versionID: ""), kind: kind,
                    blocked: missing(title, in: all))
            }
            var plan = ModInstallPlan(target: root.planned, kind: kind)
            // Shaders, resource packs and modpacks carry no mod dependencies.
            guard kind == .mods else { return plan }
            var seen: Set<String> = [root.projectID]
            var queue = [root]
            while !queue.isEmpty {
                let mod = queue.removeFirst()
                for dep in mod.dependencies where !dep.projectID.isEmpty {
                    let have = installed.first { $0.matches(dep.projectID) }
                    switch dep.relation {
                    case .incompatible:
                        if let have, have.enabled {
                            plan.blocked = String(
                                localized: "\(mod.title) can't run with \(have.name). Turn \(have.name) off first.")
                            return plan
                        }
                        if let clash = (plan.required + [plan.target]).first(where: { $0.id == dep.projectID }) {
                            plan.blocked = String(localized: "\(mod.title) can't run with \(clash.name).")
                            return plan
                        }
                    case .required:
                        // A cycle or a shared dependency: already planned.
                        guard seen.insert(dep.projectID).inserted else { continue }
                        // Installed from the other site, or never identified: the same name counts, so a second
                        // copy of a library never lands next to the first.
                        var options: [ModCandidate] = []
                        var have = have
                        if have == nil {
                            options = try await versions(dep.projectID)
                            let title = options.first?.title
                            have = installed.first { $0.matches(dep.projectID, title: title) }
                        }
                        if let have {
                            if have.enabled {
                                plan.present.append(have.name)
                            } else {
                                plan.required.append(
                                    PlannedMod(
                                        id: dep.projectID, name: have.name, versionID: "", version: have.version,
                                        turnsOn: true))
                            }
                            continue
                        }
                        guard let found = pick(options, pinned: dep.versionID) else {
                            let name = options.first?.title ?? dep.projectID
                            plan.blocked = String(
                                localized: "\(mod.title) needs \(name). \(missing(name, in: options))")
                            return plan
                        }
                        guard found.downloadable else {
                            plan.blocked = String(
                                localized: "\(mod.title) needs \(found.title), which only downloads in CurseForge's app.")
                            return plan
                        }
                        plan.required.append(found.planned)
                        queue.append(found)
                    case .optional:
                        // Offered only for the mod the user picked, never for dependencies of dependencies.
                        guard mod.projectID == root.projectID, have == nil, seen.insert(dep.projectID).inserted,
                            let found = try? await pick(versions(dep.projectID), pinned: dep.versionID),
                            found.downloadable
                        else { continue }
                        plan.optional.append(found.planned)
                    }
                }
            }
            // An optional one that turned out required elsewhere installs anyway.
            plan.optional.removeAll { o in plan.required.contains { $0.id == o.id } }
            if !root.downloadable {
                plan.blocked = String(localized: "\(root.title) only downloads in CurseForge's app.")
            }
            return plan
        }

        /// A pinned version when it fits (authors sometimes pin an old one), else the newest stable fit.
        func pick(_ all: [ModCandidate], pinned: String?) -> ModCandidate? {
            let fits = all.filter { $0.fits(game: game, loader: loader, kind: kind) }
            if let pinned, let exact = fits.first(where: { $0.versionID == pinned }) { return exact }
            return fits.first { $0.channel == "release" } ?? fits.first { $0.channel == "beta" } ?? fits.first
        }

        /// Why nothing fits: no build for this game version at all, or only for another loader.
        func missing(_ name: String, in all: [ModCandidate]) -> String {
            let sameGame = all.filter { $0.gameVersions.contains(game) }
            let label = "\(loader.displayName) \(game)"
            if kind == .mods, let other = sameGame.lazy.flatMap(\.loaders).compactMap(Loader.init(rawValue:)).first {
                return String(localized: "\(name) has no \(label) version, only \(other.displayName).")
            }
            return String(localized: "\(name) has no \(kind == .mods ? label : game) version yet.")
        }
    }
#endif
