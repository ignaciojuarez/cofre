import Foundation

/// Air's launcher profile plus Cofre-owned metadata for one game directory.
public struct Instance: Identifiable, Codable, Hashable, Sendable {
    public enum Loader: String, Codable, Sendable { case vanilla, fabric, forge, neoforge, quilt, unknown }
    public let id: String
    public var name: String
    public var gameDirectory: URL
    public var gameVersion: String
    public var loader: Loader
    public var loaderVersion: String?
    public var javaPath: String?
    public var javaVersion: Int?
    public var memoryMB: Int?
    public var autoMemory: Bool
    public var jvmArguments: String?
    public var lastGoodJVMArguments: String?
    public var notes: String
    public var group: String?
    public var favorite: Bool
    public var icon: String?
    /// Air's real `lastVersionId` (e.g. `fabric-loader-0.16.9-1.21.1`, `1.20.1-forge-47.2.0`, `neoforge-21.1.77`).
    public var renderer: String?
    public var versionID: String?

    public init(id: String, name: String, gameDirectory: URL, gameVersion: String,
                loader: Loader = .vanilla, loaderVersion: String? = nil,
                javaPath: String? = nil, javaVersion: Int? = nil, memoryMB: Int? = nil,
                autoMemory: Bool = true, jvmArguments: String? = nil,
                lastGoodJVMArguments: String? = nil, notes: String = "", group: String? = nil,
                favorite: Bool = false, icon: String? = nil) {
        self.id = id; self.name = name; self.gameDirectory = gameDirectory; self.gameVersion = gameVersion
        self.loader = loader; self.loaderVersion = loaderVersion; self.javaPath = javaPath
        self.javaVersion = javaVersion; self.memoryMB = memoryMB; self.autoMemory = autoMemory
        self.jvmArguments = jvmArguments; self.lastGoodJVMArguments = lastGoodJVMArguments
        self.notes = notes; self.group = group; self.favorite = favorite; self.icon = icon
    }
}

public final class InstanceStore: @unchecked Sendable {
    public struct TrashToken: Hashable, Sendable { fileprivate let id: String; fileprivate let original: URL; fileprivate let trashed: URL }
    /// An instance in Recently deleted: its trash folder and what it was.
    public struct Deleted: Identifiable, Hashable, Sendable {
        public var id: URL { folder }
        public let folder: URL, name: String, gameVersion: String, loader: Instance.Loader
    }
    /// Called after every write to launcher_profiles.json, so the engine (Air) can reload its in-memory copy.
    public var didWriteProfiles: (() -> Void)?
    public enum StoreError: Error, LocalizedError { case missingProfile, invalidArchive, duplicateName, commandFailed(String)
        public var errorDescription: String? { switch self { case .missingProfile: "Instance profile not found"; case .invalidArchive: "The archive does not contain an instance"; case .duplicateName: "An instance with that name already exists"; case .commandFailed(let s): s } }
    }

    public let root: URL
    public let profilesURL: URL
    private let fm: FileManager
    /// The engine's own rule for where a profile's game folder is (Air: gameDir or per-version isolation).
    private let resolveGameDirectory: ((String, [String: Any]) -> URL?)?
    private var profiles: [String: [String: Any]] = [:]
    private var document: [String: Any] = [:]

    public init(root: URL, fileManager: FileManager = .default, gameDirectory: ((String, [String: Any]) -> URL?)? = nil) throws {
        self.root = root; self.fm = fileManager; self.profilesURL = root.appendingPathComponent("launcher_profiles.json")
        self.resolveGameDirectory = gameDirectory
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try loadProfiles()
    }

    /// The instance played last: Air records it as `selectedProfile` in launcher_profiles.json.
    public var lastPlayedID: String? { (document["selectedProfile"] as? String).flatMap { profiles[$0] == nil ? nil : $0 } }

    public func list() throws -> [Instance] {
        try loadProfiles()
        return profiles.compactMap { id, profile in makeInstance(id: id, profile: profile) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult public func create(name: String, version: String, loader: Instance.Loader = .vanilla,
                                          loaderVersion: String? = nil, gameDirectory: URL? = nil) throws -> Instance {
        try loadProfiles()
        let id = uniqueID(for: name); let dir = gameDirectory ?? root.appendingPathComponent(id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // The plain game version: the engine's loader installer writes the real version id (fabric-loader-…, …-forge-…).
        var p: [String: Any] = ["name": name, "lastVersionId": version, "gameDir": gameDirValue(dir)]
        if let loaderVersion { p["loaderVersion"] = loaderVersion }
        profiles[id] = p; try saveProfiles()
        var i = makeInstance(id: id, profile: p)!
        i.loader = loader; i.loaderVersion = loaderVersion; i.gameVersion = version
        try saveMeta(i); return i
    }

    @discardableResult public func rename(_ id: String, to name: String) throws -> Instance {
        guard var p = profiles[id] else { throw StoreError.missingProfile }; p["name"] = name; profiles[id] = p; try saveProfiles()
        var i = makeInstance(id: id, profile: p)!; i.name = name; try saveMeta(i); return i
    }

    @discardableResult public func duplicate(_ id: String, name: String? = nil, includeWorlds: Bool = true,
                                             includeOptions: Bool = true) throws -> Instance {
        try loadProfiles()
        guard let profile = profiles[id], let source = makeInstance(id: id, profile: profile) else { throw StoreError.missingProfile }
        let targetName = name ?? "\(source.name) copy"
        guard !(try list()).contains(where: { $0.name == targetName }) else { throw StoreError.duplicateName }
        let newID = uniqueID(for: targetName), dir = root.appendingPathComponent(newID)
        try fm.copyItem(at: source.gameDirectory, to: dir)  // APFS clone where supported
        if !includeWorlds { try? fm.removeItem(at: dir.appendingPathComponent("saves")) }
        if !includeOptions { try? fm.removeItem(at: dir.appendingPathComponent("options.txt")); try? fm.removeItem(at: dir.appendingPathComponent("optionsof.txt")) }
        // Same engine profile (version id, Java, args), new name and folder.
        var copy = profile; copy["name"] = targetName; copy["gameDir"] = gameDirValue(dir)
        profiles[newID] = copy; try saveProfiles()
        var i = makeInstance(id: newID, profile: copy)!; i.name = targetName; i.favorite = false
        try saveMeta(i); return i
    }

    public func trash(_ id: String) throws -> TrashToken {
        try loadProfiles()
        guard let profile = profiles[id], let i = makeInstance(id: id, profile: profile) else { throw StoreError.missingProfile }
        let trash = root.appendingPathComponent(".trash", isDirectory: true); try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        // Keep the exact engine profile with the files, so Restore puts it back unchanged, even after Cofre closes.
        var saved = profile; saved["cofreProfileID"] = id
        try JSONSerialization.data(withJSONObject: saved).write(to: i.gameDirectory.appendingPathComponent(".cofre-profile.json"))
        let destination = trash.appendingPathComponent(UUID().uuidString + "-" + i.gameDirectory.lastPathComponent)
        try fm.moveItem(at: i.gameDirectory, to: destination); profiles.removeValue(forKey: id); try saveProfiles()
        return TrashToken(id: id, original: i.gameDirectory, trashed: destination)
    }

    /// Recently deleted instances, newest first. Worlds share the trash folder and are skipped.
    public func recentlyDeleted() -> [Deleted] {
        let trash = root.appendingPathComponent(".trash", isDirectory: true)
        let folders = (try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return folders.compactMap { folder -> (Deleted, Date)? in
            guard !fm.fileExists(atPath: folder.appendingPathComponent("level.dat").path) else { return nil }
            let date = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let profile = savedProfile(in: folder)
            if let meta = try? readMeta(at: folder) {
                return (Deleted(folder: folder, name: meta.name, gameVersion: meta.gameVersion, loader: meta.loader), date)
            }
            // Made by the engine before Cofre kept metadata: name and loader from what's in the folder.
            let version = (profile?["lastVersionId"] as? String) ?? guessedVersionID(folder)
            let parsed = parseVersion(version)
            let name = (profile?["name"] as? String) ?? "Restored \(parsed.loader == .vanilla ? "instance" : parsed.loader.rawValue.capitalized + " instance")"
            return (Deleted(folder: folder, name: name, gameVersion: parsed.version, loader: parsed.loader), date)
        }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Puts a deleted instance back: its files where they were and its engine profile as it was.
    @discardableResult public func restore(_ deleted: Deleted) throws -> Instance {
        try loadProfiles()
        let meta = try? readMeta(at: deleted.folder)
        var profile = savedProfile(in: deleted.folder)
            ?? ["name": deleted.name, "lastVersionId": meta.map { $0.versionID ?? legacyVersionID($0) } ?? guessedVersionID(deleted.folder)]
        var id = profile.removeValue(forKey: "cofreProfileID") as? String ?? meta?.id ?? uniqueID(for: deleted.name)
        if profiles[id] != nil { id = uniqueID(for: deleted.name + " restored") }
        // The trash folder is "<UUID>-<original folder name>".
        let original = String(deleted.folder.lastPathComponent.dropFirst(37))
        var target = (profile["gameDir"] as? String).map(resolveGameDir) ?? root.appendingPathComponent("cofre-instances").appendingPathComponent(original.isEmpty ? id : original)
        if fm.fileExists(atPath: target.path) { target = root.appendingPathComponent(id + "-" + UUID().uuidString.prefix(4)) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: deleted.folder, to: target)
        try? fm.removeItem(at: target.appendingPathComponent(".cofre-profile.json"))
        profile["gameDir"] = gameDirValue(target); profile["name"] = profile["name"] ?? deleted.name
        profiles[id] = profile; try saveProfiles(); return try refresh(id)
    }

    private func savedProfile(in folder: URL) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(".cofre-profile.json")))) as? [String: Any]
    }

    /// For a folder with no saved profile: a Fabric or Quilt folder matches the newest installed loader version.
    private func guessedVersionID(_ folder: URL) -> String {
        let prefix = fm.fileExists(atPath: folder.appendingPathComponent(".fabric").path) ? "fabric-loader-"
            : fm.fileExists(atPath: folder.appendingPathComponent(".quilt").path) ? "quilt-loader-" : nil
        guard let prefix else { return "latest-release" }
        let versions = (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("versions").path)) ?? []
        return versions.filter { $0.hasPrefix(prefix) }.sorted().last ?? "latest-release"
    }

    @discardableResult public func restore(_ token: TrashToken) throws -> Instance {
        guard let meta = try? readMeta(at: token.trashed) else { throw StoreError.missingProfile }
        return try restore(Deleted(folder: token.trashed, name: meta.name, gameVersion: meta.gameVersion, loader: meta.loader))
    }

    public func export(_ id: String, to destination: URL? = nil, includeWorlds: Bool = true) throws -> URL {
        guard let i = makeInstance(id: id, profile: profiles[id] ?? [:]) else { throw StoreError.missingProfile }
        let out = destination ?? root.appendingPathComponent(i.name.replacingOccurrences(of: "/", with: "-") + ".zip")
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.copyItem(at: i.gameDirectory, to: staging)
        if !includeWorlds { try? fm.removeItem(at: staging.appendingPathComponent("saves")) }
        try zip(staging, to: out); try? fm.removeItem(at: staging); return out
    }

    @discardableResult public func `import`(_ archive: URL, name: String? = nil) throws -> Instance {
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }; try unzip(archive, to: staging)
        let candidates = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey])
        // Cofre's exports keep the instance folder's contents at the top; older ones wrapped them in one folder.
        guard let source = fm.fileExists(atPath: staging.appendingPathComponent("cofre.json").path) ? staging : candidates.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) else { throw StoreError.invalidArchive }
        let meta = try readMeta(at: source); let n = name ?? meta.name; let i = try create(name: n, version: meta.versionID ?? legacyVersionID(meta), loader: meta.loader, loaderVersion: meta.loaderVersion)
        try fm.removeItem(at: i.gameDirectory); try fm.copyItem(at: source, to: i.gameDirectory); return try refresh(i.id)
    }

    public func update(_ id: String, javaPath: String? = nil, javaVersion: Int? = nil, memoryMB: Int? = nil,
                       autoMemory: Bool? = nil, jvmArguments: String? = nil, loaderVersion: String? = nil) throws -> Instance {
        guard var p = profiles[id] else { throw StoreError.missingProfile }
        if let javaPath { p["javaPath"] = javaPath }; if let javaVersion { p["javaVersion"] = javaVersion }
        if let memoryMB { p["memory"] = memoryMB }; if let autoMemory { p["autoMemory"] = autoMemory }
        if let jvmArguments { if p["javaArgs"] != nil { p["lastGoodJavaArgs"] = p["javaArgs"] }; p["javaArgs"] = jvmArguments }
        if let loaderVersion { p["loaderVersion"] = loaderVersion }; profiles[id] = p; try saveProfiles(); let i = makeInstance(id: id, profile: p)!; try saveMeta(i); return i
    }

    public func rollbackJVMArguments(_ id: String) throws -> Instance { guard var p = profiles[id], let old = p["lastGoodJavaArgs"] else { throw StoreError.missingProfile }; p["javaArgs"] = old; profiles[id] = p; try saveProfiles(); return try refresh(id) }
    /// Removes an instance and its files. Used to roll back staged imports.
    public func remove(_ id: String) throws {
        guard let instance = makeInstance(id: id, profile: profiles[id] ?? [:]) else { throw StoreError.missingProfile }
        try? fm.removeItem(at: instance.gameDirectory)
        profiles.removeValue(forKey: id)
        try saveProfiles()
    }
    public func setMetadata(_ id: String, notes: String? = nil, group: String?? = nil, favorite: Bool? = nil, icon: String?? = nil) throws -> Instance {
        guard var i = makeInstance(id: id, profile: profiles[id] ?? [:]) else { throw StoreError.missingProfile }; if let notes { i.notes = notes }; if let group { i.group = group }; if let favorite { i.favorite = favorite }; if let icon { i.icon = icon }; try saveMeta(i); return i
    }

    private func loadProfiles() throws { guard fm.fileExists(atPath: profilesURL.path) else { profiles = [:]; document = [:]; return }; let d = try Data(contentsOf: profilesURL); let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]; document = obj; profiles = (obj["profiles"] as? [String: [String: Any]]) ?? [:] }
    private func saveProfiles() throws {
        document["profiles"] = profiles
        let d = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try d.write(to: profilesURL, options: .atomic)
        didWriteProfiles?()
    }
    private func makeInstance(id: String, profile p: [String: Any]) -> Instance? { guard let name = p["name"] as? String, let version = p["lastVersionId"] as? String else { return nil }; let dir = resolveGameDirectory?(id, p) ?? (p["gameDir"] as? String).map(resolveGameDir) ?? root; let parsed = parseVersion(version); let meta = try? readMeta(at: dir); var instance = Instance(id: id, name: name, gameDirectory: dir, gameVersion: meta?.gameVersion ?? parsed.version, loader: meta?.loader ?? parsed.loader, loaderVersion: (p["loaderVersion"] as? String) ?? meta?.loaderVersion, javaPath: p["javaPath"] as? String, javaVersion: p["javaVersion"] as? Int, memoryMB: p["memory"] as? Int, autoMemory: (p["autoMemory"] as? Bool) ?? true, jvmArguments: p["javaArgs"] as? String, lastGoodJVMArguments: p["lastGoodJavaArgs"] as? String, notes: meta?.notes ?? "", group: meta?.group, favorite: meta?.favorite ?? false, icon: meta?.icon); instance.versionID = version; instance.renderer = (p["cofreRendererPicked"] as? Bool) == true ? "auto" : p["renderer"] as? String; return instance }
    private func refresh(_ id: String) throws -> Instance { try loadProfiles(); guard let i = makeInstance(id: id, profile: profiles[id] ?? [:]) else { throw StoreError.missingProfile }; return i }
    private func saveMeta(_ i: Instance) throws { try JSONEncoder().encode(i).write(to: i.gameDirectory.appendingPathComponent("cofre.json"), options: .atomic) }
    private func readMeta(at dir: URL) throws -> Instance { try JSONDecoder().decode(Instance.self, from: Data(contentsOf: dir.appendingPathComponent("cofre.json"))) }
    /// Air's version id for instances saved before Cofre kept it: Fabric and Quilt ids are predictable; others need a reinstall.
    private func legacyVersionID(_ i: Instance) -> String {
        guard [.fabric, .quilt].contains(i.loader), let lv = i.loaderVersion, !lv.isEmpty else { return i.gameVersion }
        return "\(i.loader.rawValue)-loader-\(lv)-\(i.gameVersion)"
    }
    /// Profiles keep folders inside the game folder relative ("./…"), as Air does, so they survive container moves.
    private func gameDirValue(_ dir: URL) -> String {
        let base = root.standardizedFileURL.path + "/", path = dir.standardizedFileURL.path
        return path.hasPrefix(base) ? "./" + path.dropFirst(base.count) : path
    }
    private func resolveGameDir(_ value: String) -> URL {
        value.hasPrefix("/") ? URL(fileURLWithPath: value) : root.appendingPathComponent(value.hasPrefix("./") ? String(value.dropFirst(2)) : value)
    }
    private func uniqueID(for name: String) -> String { var id = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-")); if id.isEmpty { id = UUID().uuidString }; while profiles[id] != nil { id += "-copy" }; return id }

    /// Air's version ids: `fabric-loader-<loader>-<mc>`, `quilt-loader-<loader>-<mc>`, `<mc>-forge-<forge>` (also
    /// NeoForge 47.1 for 1.20.1), `neoforge-<a.b.c>` (Minecraft 1.a.b; 26+ is a.b), or a plain Minecraft version.
    private func parseVersion(_ s: String) -> (version: String, loader: Instance.Loader) {
        if s.hasPrefix("fabric-loader-") { return (s.components(separatedBy: "-").last ?? s, .fabric) }
        if s.hasPrefix("quilt-loader-") { return (s.components(separatedBy: "-").last ?? s, .quilt) }
        if s.hasPrefix("neoforge-") {
            let n = s.dropFirst("neoforge-".count).split(separator: ".").compactMap { Int($0) }
            guard n.count >= 2 else { return (s, .neoforge) }
            return (n[0] >= 26 ? "\(n[0]).\(n[1])" : n[1] == 0 ? "1.\(n[0])" : "1.\(n[0]).\(n[1])", .neoforge)
        }
        if let r = s.range(of: "-forge-") { return (String(s[..<r.lowerBound]), .forge) }
        return (s, .vanilla)
    }
    private func zip(_ source: URL, to destination: URL) throws { try? fm.removeItem(at: destination); try Zip.write(directory: source, to: destination) }
    private func unzip(_ archive: URL, to destination: URL) throws { try Zip.extract(archive, to: destination) }
}
