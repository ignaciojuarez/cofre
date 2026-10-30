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

    public func list() throws -> [Instance] {
        try loadProfiles()
        return profiles.compactMap { id, profile in makeInstance(id: id, profile: profile) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @discardableResult public func create(name: String, version: String, loader: Instance.Loader = .vanilla,
                                          loaderVersion: String? = nil, gameDirectory: URL? = nil) throws -> Instance {
        let id = uniqueID(for: name); let dir = gameDirectory ?? root.appendingPathComponent(id)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var p: [String: Any] = ["name": name, "lastVersionId": profileVersion(version, loader: loader, loaderVersion: loaderVersion), "gameDir": dir.path]
        if let loaderVersion { p["loaderVersion"] = loaderVersion }
        profiles[id] = p; try saveProfiles()
        let i = makeInstance(id: id, profile: p)!; try saveMeta(i); return i
    }

    @discardableResult public func rename(_ id: String, to name: String) throws -> Instance {
        guard var p = profiles[id] else { throw StoreError.missingProfile }; p["name"] = name; profiles[id] = p; try saveProfiles()
        var i = makeInstance(id: id, profile: p)!; i.name = name; try saveMeta(i); return i
    }

    @discardableResult public func duplicate(_ id: String, name: String? = nil, includeWorlds: Bool = true,
                                             includeOptions: Bool = true) throws -> Instance {
        guard let source = makeInstance(id: id, profile: profiles[id] ?? [:]) else { throw StoreError.missingProfile }
        let targetName = name ?? "\(source.name) copy"; guard !(try list()).contains(where: { $0.name == targetName }) else { throw StoreError.duplicateName }
        let copy = try create(name: targetName, version: source.gameVersion, loader: source.loader, loaderVersion: source.loaderVersion)
        // copyItem uses APFS clones where supported. Remove the empty destination first.
        try fm.removeItem(at: copy.gameDirectory)
        try fm.copyItem(at: source.gameDirectory, to: copy.gameDirectory)
        if !includeWorlds { try? fm.removeItem(at: copy.gameDirectory.appendingPathComponent("saves")) }
        if !includeOptions { try? fm.removeItem(at: copy.gameDirectory.appendingPathComponent("options.txt")); try? fm.removeItem(at: copy.gameDirectory.appendingPathComponent("optionsof.txt")) }
        return try refresh(copy.id)
    }

    public func trash(_ id: String) throws -> TrashToken {
        guard let i = makeInstance(id: id, profile: profiles[id] ?? [:]) else { throw StoreError.missingProfile }
        let trash = root.appendingPathComponent(".trash", isDirectory: true); try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = trash.appendingPathComponent(UUID().uuidString + "-" + i.gameDirectory.lastPathComponent)
        try fm.moveItem(at: i.gameDirectory, to: destination); profiles.removeValue(forKey: id); try saveProfiles()
        return TrashToken(id: id, original: i.gameDirectory, trashed: destination)
    }

    @discardableResult public func restore(_ token: TrashToken) throws -> Instance {
        try fm.createDirectory(at: token.original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: token.trashed, to: token.original)
        // Reconstruct the profile from the Cofre metadata and directory name.
        let meta = try readMeta(at: token.original); let p = profileDictionary(meta, gameDirectory: token.original)
        profiles[token.id] = p; try saveProfiles(); return try refresh(token.id)
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
        let meta = try readMeta(at: source); let n = name ?? meta.name; let i = try create(name: n, version: meta.gameVersion, loader: meta.loader, loaderVersion: meta.loaderVersion)
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
    public func setMetadata(_ id: String, notes: String? = nil, group: String?? = nil, favorite: Bool? = nil, icon: String?? = nil) throws -> Instance {
        guard var i = makeInstance(id: id, profile: profiles[id] ?? [:]) else { throw StoreError.missingProfile }; if let notes { i.notes = notes }; if let group { i.group = group }; if let favorite { i.favorite = favorite }; if let icon { i.icon = icon }; try saveMeta(i); return i
    }

    private func loadProfiles() throws { guard fm.fileExists(atPath: profilesURL.path) else { profiles = [:]; document = [:]; return }; let d = try Data(contentsOf: profilesURL); let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]; document = obj; profiles = (obj["profiles"] as? [String: [String: Any]]) ?? [:] }
    private func saveProfiles() throws { document["profiles"] = profiles; let d = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]); try d.write(to: profilesURL, options: .atomic) }
    private func makeInstance(id: String, profile p: [String: Any]) -> Instance? { guard let name = p["name"] as? String, let version = p["lastVersionId"] as? String else { return nil }; let dir = resolveGameDirectory?(id, p) ?? URL(fileURLWithPath: (p["gameDir"] as? String) ?? root.appendingPathComponent(id).path); let parsed = parseVersion(version); let meta = try? readMeta(at: dir); return Instance(id: id, name: name, gameDirectory: dir, gameVersion: meta?.gameVersion ?? parsed.version, loader: meta?.loader ?? parsed.loader, loaderVersion: (p["loaderVersion"] as? String) ?? meta?.loaderVersion, javaPath: p["javaPath"] as? String, javaVersion: p["javaVersion"] as? Int, memoryMB: p["memory"] as? Int, autoMemory: (p["autoMemory"] as? Bool) ?? true, jvmArguments: p["javaArgs"] as? String, lastGoodJVMArguments: p["lastGoodJavaArgs"] as? String, notes: meta?.notes ?? "", group: meta?.group, favorite: meta?.favorite ?? false, icon: meta?.icon) }
    private func refresh(_ id: String) throws -> Instance { try loadProfiles(); guard let i = makeInstance(id: id, profile: profiles[id] ?? [:]) else { throw StoreError.missingProfile }; return i }
    private func saveMeta(_ i: Instance) throws { try JSONEncoder().encode(i).write(to: i.gameDirectory.appendingPathComponent("cofre.json"), options: .atomic) }
    private func readMeta(at dir: URL) throws -> Instance { try JSONDecoder().decode(Instance.self, from: Data(contentsOf: dir.appendingPathComponent("cofre.json"))) }
    private func profileDictionary(_ i: Instance, gameDirectory: URL) -> [String: Any] { ["name": i.name, "lastVersionId": profileVersion(i.gameVersion, loader: i.loader, loaderVersion: i.loaderVersion), "gameDir": gameDirectory.path] }
    private func uniqueID(for name: String) -> String { var id = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-")); if id.isEmpty { id = UUID().uuidString }; while profiles[id] != nil { id += "-copy" }; return id }
    private func profileVersion(_ v: String, loader: Instance.Loader, loaderVersion: String?) -> String { guard loader != .vanilla, let lv = loaderVersion, !lv.isEmpty else { return v }; return "\(loader.rawValue)-loader-\(lv)-\(v)" }
    private func parseVersion(_ s: String) -> (version: String, loader: Instance.Loader) { for l in [Instance.Loader.fabric, .forge, .neoforge, .quilt] { if let r = s.range(of: "\(l.rawValue)-loader-"), let end = s.range(of: "-", range: r.upperBound..<s.endIndex) { return (String(s[end.upperBound...]), l) } }; return (s, .vanilla) }
    private func zip(_ source: URL, to destination: URL) throws { try? fm.removeItem(at: destination); try Zip.write(directory: source, to: destination) }
    private func unzip(_ archive: URL, to destination: URL) throws { try Zip.extract(archive, to: destination) }
}
