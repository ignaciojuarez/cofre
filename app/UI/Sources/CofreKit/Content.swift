import Foundation

/// The files Minecraft uses for installed content in one instance. "In use" is read from the game's own settings
/// (options.txt, the shader mod's config); Cofre never writes them.
public final class ContentStore: @unchecked Sendable {
    public struct Item: Identifiable, Hashable, Sendable {
        /// The file name, or "<world>/<file>" for a data pack, so the same pack in two worlds stays two rows.
        public let id: String
        public let name: String, version: String, world: String?
        public let kind: ContentKind, enabled: Bool, inUse: Bool
        public var file: String { (id as NSString).lastPathComponent }
        public var urlName: String { file + (enabled ? "" : ".disabled") }
    }
    public struct TrashToken: Hashable, Sendable { fileprivate let original: URL, trashed: URL }
    public enum Failure: LocalizedError {
        case notFiles(ContentKind)
        public var errorDescription: String? { "Modpacks make their own instance, so they have no files here." }
    }
    public let gameDirectory: URL
    private let fm: FileManager
    public init(gameDirectory: URL, fileManager: FileManager = .default) { self.gameDirectory = gameDirectory; fm = fileManager }

    /// Throws for modpacks: they aren't files in an instance.
    public func list(_ kind: ContentKind) throws -> [Item] {
        guard let folderName = kind.folderName else { throw Failure.notFiles(kind) }
        let folders: [(URL, String?)]
        if kind == .dataPacks {
            let saves = gameDirectory.appendingPathComponent("saves")
            folders = (try? fm.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey]))?.compactMap {
                guard (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                return ($0.appendingPathComponent(folderName), $0.lastPathComponent)
            } ?? []
        } else { folders = [(gameDirectory.appendingPathComponent(folderName), nil)] }
        let inUse = kind == .resourcePacks ? resourcePacks() : kind == .shaders ? Set([activeShaderPack()].compactMap { $0 }) : []
        var out: [Item] = []
        for (folder, world) in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for file in names where !file.hasPrefix(".") {
                let enabled = !file.hasSuffix(".disabled")
                let name = enabled ? file : String(file.dropLast(9))
                let base = (name as NSString).deletingPathExtension
                out.append(Item(id: world.map { "\($0)/\(name)" } ?? name, name: base,
                    version: base.split(separator: "-").last.map(String.init) ?? "", world: world, kind: kind,
                    enabled: enabled, inUse: enabled && inUse.contains(name)))
            }
        }
        return out.sorted { ($0.world ?? "") + $0.name < ($1.world ?? "") + $1.name }
    }

    /// Where the item's file is now: its `.disabled` name when off.
    public func url(of item: Item) -> URL { folder(for: item.kind, world: item.world).appendingPathComponent(item.urlName) }

    public func folder(for kind: ContentKind, world: String?) -> URL {
        let name = kind.folderName ?? kind.rawValue
        if kind == .dataPacks, let world { return gameDirectory.appendingPathComponent("saves").appendingPathComponent(world).appendingPathComponent(name) }
        return gameDirectory.appendingPathComponent(name)
    }

    public func setEnabled(_ enabled: Bool, _ item: Item) throws {
        let folder = folder(for: item.kind, world: item.world)
        let on = folder.appendingPathComponent(item.file), off = folder.appendingPathComponent(item.file + ".disabled")
        if enabled, fm.fileExists(atPath: off.path) { try fm.moveItem(at: off, to: on) }
        if !enabled, fm.fileExists(atPath: on.path) { try fm.moveItem(at: on, to: off) }
    }
    public func trash(_ item: Item) throws -> TrashToken {
        let source = url(of: item)
        let bin = gameDirectory.appendingPathComponent(".cofre-trash/content", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let target = bin.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        try fm.moveItem(at: source, to: target); return TrashToken(original: source, trashed: target)
    }
    public func restore(_ token: TrashToken) throws { try fm.moveItem(at: token.trashed, to: token.original) }
    public func delete(_ item: Item) throws { _ = try trash(item) }

    /// The shader pack the game has on: Iris or Oculus (`config/<mod>.properties`), else OptiFine's
    /// `optionsshaders.txt`. `nil` when shaders are off.
    public func activeShaderPack() -> String? {
        for name in ShaderSwitch.files {
            guard let text = try? String(contentsOf: gameDirectory.appendingPathComponent("config").appendingPathComponent(name), encoding: .utf8) else { continue }
            let p = Self.properties(text)
            if p["enableShaders"] == "false" { return nil }
            if let pack = p["shaderPack"], !pack.isEmpty { return pack }
        }
        guard let text = try? String(contentsOf: gameDirectory.appendingPathComponent("optionsshaders.txt"), encoding: .utf8),
            let pack = Self.properties(text)["shaderPack"], !pack.isEmpty, pack != "OFF", pack != "(internal)"
        else { return nil }
        return pack
    }

    private func resourcePacks() -> Set<String> {
        guard let text = try? String(contentsOf: gameDirectory.appendingPathComponent("options.txt"), encoding: .utf8),
            let raw = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("resourcePacks:") })
        else { return [] }
        let value = String(raw.dropFirst("resourcePacks:".count))
        let names = (try? JSONDecoder().decode([String].self, from: Data(value.utf8)))
            ?? value.split(separator: ",").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "[]\" ")) }
        return Set(names.filter { $0.hasPrefix("file/") }.map { String($0.dropFirst(5)) })
    }

    /// Java `.properties` lines: `key=value` or `key:value`, with `\` escapes.
    static func properties(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("#"), !s.hasPrefix("!"), let i = s.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            var value = "", escaped = false
            for c in s[s.index(after: i)...] {
                if escaped || c != "\\" { value.append(c); escaped = false } else { escaped = true }
            }
            out[s[..<i].trimmingCharacters(in: .whitespaces)] = value.trimmingCharacters(in: .whitespaces)
        }
        return out
    }
}

public extension ContentKind {
    /// Modrinth's loaders for update checks: the instance's for mods (Quilt also runs Fabric's), and the fixed ones
    /// Modrinth files packs under.
    func updateLoaders(_ instance: Instance.Loader) -> [String] {
        switch self {
        case .mods: instance == .quilt ? ["quilt", "fabric"] : [instance.rawValue]
        case .shaders: ["iris", "optifine", "canvas", "vanilla"]
        case .resourcePacks: ["minecraft"]
        case .dataPacks: ["datapack"]
        case .modpacks: []
        }
    }
}
