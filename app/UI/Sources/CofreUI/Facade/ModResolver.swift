#if canImport(UIKit)
    import Foundation
    import CofreKit

    // One dependency resolver for every backend, so the rules are tested once (CofreUITests). A backend hands it each
    // project's versions, newest first; it returns an `ModInstallPlan`. Modrinth and CurseForge differ only in how the
    // backend reads their version rows into `ModCandidate`.

    /// Version numbers as people read them: "mc26.3-0.9.3-beta.1-fabric" → "0.9.3 beta 1". The raw number stays
    /// for Details.
    public enum VersionLabel {
        public static func clean(_ number: String) -> String {
            var s = number.trimmingCharacters(in: .whitespaces)
            func strip(_ pattern: String) {
                s = s.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            }
            strip(#"\s*\([^)]*\)$"#)
            strip(#"\.(jar|zip)$"#)
            // Loader tags anywhere: "-fabric", "neoforge-", "+quilt".
            strip(#"[-+_]?\b(fabric|neoforge|forge|quilt)\b(?=$|[-+_])"#)
            strip(#"^[-+_]+"#)
            // Game version tags: "mc26.3-" in front, "+mc26.3" / "+26.3" / "-mc1.21.1" behind.
            strip(#"^mc[0-9.]+[-+_]"#)
            strip(#"\+(mc)?[0-9][0-9.]*([-+_][0-9a-z.]*)?$"#)
            strip(#"[-_]mc[0-9][0-9.]*$"#)
            // A project name in front of the number ("sodium-0.6.0"), and a leading "v".
            strip(#"^[a-z][a-z0-9 ]*?[-_ ](?=v?[0-9])"#)
            strip(#"^v(?=[0-9])"#)
            // Pre-release suffixes read as words.
            s = s.replacingOccurrences(
                of: #"[-.+_ ]?(beta|alpha|pre|rc)[-._ ]?([0-9]+)?$"#, with: " $1 $2",
                options: [.regularExpression, .caseInsensitive]
            ).trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? number : s
        }
    }

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
        public var gameVersions: [String], loaders: [Loader]
        public var channel: VersionChannel
        public var sizeBytes: Int64?
        public var dependencies: [Dependency]
        /// CurseForge authors can forbid downloads outside their app; those files have no URL.
        public var downloadable: Bool
        public init(
            projectID: String, versionID: String, title: String, version: String, gameVersions: [String],
            loaders: [Loader], channel: VersionChannel = .release, sizeBytes: Int64? = nil, dependencies: [Dependency] = [],
            downloadable: Bool = true
        ) {
            self.projectID = projectID
            self.versionID = versionID
            self.title = title
            self.version = version
            self.gameVersions = gameVersions
            self.loaders = loaders
            self.channel = channel
            self.sizeBytes = sizeBytes
            self.dependencies = dependencies
            self.downloadable = downloadable
        }

        public init(
            projectID: String, versionID: String, title: String, version: String, gameVersions: [String],
            loaders: [String], channel: String, sizeBytes: Int64? = nil, dependencies: [Dependency] = [],
            downloadable: Bool = true
        ) {
            self.init(projectID: projectID, versionID: versionID, title: title, version: version,
                      gameVersions: gameVersions, loaders: loaders.compactMap { Loader(rawValue: $0.lowercased()) }, channel: VersionChannel(channel),
                      sizeBytes: sizeBytes, dependencies: dependencies, downloadable: downloadable)
        }

        /// Exact game version, and the instance's loader. Quilt runs Fabric mods; shaders and packs list no loader
        /// we know, so only the game version counts for them.
        public func fits(game: String, loader: Loader, kind: ContentKind = .mods) -> Bool {
            guard gameVersions.contains(game) else { return false }
            guard kind == .mods else { return true }
            return loaders.isEmpty || loaders.contains(loader)
                || (loader == .quilt && loaders.contains(.fabric))
        }

        var planned: PlannedMod {
            PlannedMod(
                id: projectID, name: title, versionID: versionID, version: VersionLabel.clean(version),
                sizeBytes: sizeBytes, channel: channel)
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
            // A caller may have an ID from an unfiltered catalog (or an old UI state). Never let that pin
            // install a build for another game version or loader.
            let root = pick(all, pinned: versionID)
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
                            // One jar for several loaders lists every loader's dependencies together (e.g.
                            // LambDynamicLights needs Fabric API only on Fabric). A dependency with no build for this
                            // loader at all, made for another loader the mod also supports, isn't needed here.
                            if Set(mod.loaders).count > 1, !options.isEmpty,
                                !options.contains(where: { $0.loaders.contains(loader) }),
                                options.contains(where: { !Set($0.loaders).isDisjoint(with: mod.loaders) })
                            {
                                continue
                            }
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

        /// A pinned version when it fits (authors sometimes pin an old one), else the newest fitting release, then
        /// beta, then alpha.
        func pick(_ all: [ModCandidate], pinned: String?) -> ModCandidate? {
            let fits = all.filter { $0.fits(game: game, loader: loader, kind: kind) }
            if let pinned, let exact = fits.first(where: { $0.versionID == pinned }) { return exact }
            return Self.mostStable(fits, channel: { $0.channel })
        }

        /// The newest of the most stable channel present (lists are newest first).
        public static func mostStable<T>(_ newestFirst: [T], channel: (T) -> VersionChannel) -> T? {
            for c in VersionChannel.allCases {
                if let found = newestFirst.first(where: { channel($0) == c }) { return found }
            }
            return nil
        }

        /// Why nothing fits: no build for this game version at all, or only for another loader.
        func missing(_ name: String, in all: [ModCandidate]) -> String {
            let sameGame = all.filter { $0.gameVersions.contains(game) }
            let label = "\(loader.displayName) \(game)"
            if kind == .mods, let other = sameGame.lazy.flatMap(\.loaders).first {
                return String(localized: "\(name) has no \(label) version, only \(other.displayName).")
            }
            return String(localized: "\(name) has no \(kind == .mods ? label : game) version yet.")
        }
    }
#endif

#if canImport(UIKit)
    /// M02's version filters. The defaults come from the Mods target: its loader, its game version, Release + Beta.
    public struct VersionFilter: Equatable, Sendable {
        /// Empty means any.
        public var loaders: Set<Loader>, games: Set<String>
        public var channels: Set<VersionChannel>
        public init(loaders: Set<Loader> = [], games: Set<String> = [], channels: Set<VersionChannel>) {
            self.loaders = loaders
            self.games = games
            self.channels = channels
        }

        public static func defaults(for instance: InstanceSummary?) -> VersionFilter {
            guard let instance, instance.loader != .vanilla else { return VersionFilter(channels: [.release, .beta]) }
            return VersionFilter(
                loaders: instance.loader == .quilt ? [.quilt, .fabric] : [instance.loader],
                games: instance.gameVersion.isEmpty ? [] : [instance.gameVersion], channels: [.release, .beta])
        }

        /// Versions with no loader we know (shaders, packs) pass the loader filter.
        public func matches(_ v: ProjectVersion) -> Bool {
            (loaders.isEmpty || v.loaders.isEmpty || !loaders.isDisjoint(with: v.loaders))
                && (games.isEmpty || !games.isDisjoint(with: v.games)) && channels.contains(v.versionChannel)
        }

        /// What M02 lists: matching versions that fit, plus the installed one. `all` lists everything.
        public func visible(_ versions: [ProjectVersion], installed: String?, all: Bool) -> [ProjectVersion] {
            all ? versions : versions.filter { ($0.fits && matches($0)) || $0.id == installed }
        }
    }

    extension Array where Element == ProjectVersion {
        /// What Get installs: the newest fitting release, else beta, else alpha.
        public var preferred: ProjectVersion? {
            ModResolver.mostStable(filter(\.fits), channel: \.versionChannel)
        }
    }
#endif
