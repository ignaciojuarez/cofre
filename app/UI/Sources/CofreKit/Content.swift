import Foundation

/// The files Minecraft uses for installed content in one instance.
public final class ContentStore: @unchecked Sendable {
    public enum Kind: String, CaseIterable, Codable, Sendable { case mods, resourcePacks, shaderpacks, datapacks }
    public struct Item: Identifiable, Hashable, Sendable {
        public let id: String, name: String, version: String, world: String?
        public let kind: Kind, enabled: Bool, inUse: Bool
        public var urlName: String { id + (enabled ? "" : ".disabled") }
    }
    public struct TrashToken: Hashable, Sendable { fileprivate let original: URL, trashed: URL }
    public let gameDirectory: URL
    private let fm: FileManager
    public init(gameDirectory: URL, fileManager: FileManager = .default) { self.gameDirectory = gameDirectory; fm = fileManager }

    public func list(_ kind: Kind) throws -> [Item] {
        let folders: [(URL, String?)]
        if kind == .datapacks {
            let saves = gameDirectory.appendingPathComponent("saves")
            folders = (try? fm.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey]))?.compactMap {
                guard (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                return ($0.appendingPathComponent("datapacks"), $0.lastPathComponent)
            } ?? []
        } else { folders = [(gameDirectory.appendingPathComponent(kind.rawValue == "shaderpacks" ? "shaderpacks" : kind.rawValue), nil)] }
        var out: [Item] = []
        for (folder, world) in folders {
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for file in names where !file.hasPrefix(".") && !file.hasSuffix(".disabled") {
                let enabled = true
                out.append(item(file: file, enabled: enabled, kind: kind, world: world, in: folder))
            }
            for file in names where file.hasSuffix(".disabled") {
                out.append(item(file: String(file.dropLast(9)), enabled: false, kind: kind, world: world, in: folder))
            }
        }
        return out.sorted { ($0.world ?? "") + $0.name < ($1.world ?? "") + $1.name }
    }

    public func setEnabled(_ enabled: Bool, _ item: Item) throws {
        let folder = folder(for: item.kind, world: item.world)
        let on = folder.appendingPathComponent(item.id), off = folder.appendingPathComponent(item.id + ".disabled")
        if enabled, fm.fileExists(atPath: off.path) { try fm.moveItem(at: off, to: on) }
        if !enabled, fm.fileExists(atPath: on.path) { try fm.moveItem(at: on, to: off) }
    }
    public func trash(_ item: Item) throws -> TrashToken {
        let source = folder(for: item.kind, world: item.world).appendingPathComponent(item.urlName)
        let bin = gameDirectory.appendingPathComponent(".cofre-trash/content", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let target = bin.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        try fm.moveItem(at: source, to: target); return TrashToken(original: source, trashed: target)
    }
    public func restore(_ token: TrashToken) throws { try fm.moveItem(at: token.trashed, to: token.original) }
    public func delete(_ item: Item) throws { _ = try trash(item) }

    private func folder(for kind: Kind, world: String?) -> URL {
        if kind == .datapacks, let world { return gameDirectory.appendingPathComponent("saves").appendingPathComponent(world).appendingPathComponent("datapacks") }
        return gameDirectory.appendingPathComponent(kind.rawValue)
    }
    private func item(file: String, enabled: Bool, kind: Kind, world: String?, in folder: URL) -> Item {
        let base = (file as NSString).deletingPathExtension
        let version = base.split(separator: "-").last.map(String.init) ?? ""
        let inUse = kind == .resourcePacks ? resourcePacks().contains(file) : kind == .shaderpacks && shaderPack() == file
        return Item(id: file, name: base, version: version, world: world, kind: kind, enabled: enabled, inUse: inUse)
    }
    private func resourcePacks() -> Set<String> {
        guard let text = try? String(contentsOf: gameDirectory.appendingPathComponent("options.txt")) else { return [] }
        guard let raw = text.split(whereSeparator: { $0 == "\n" }).first(where: { $0.hasPrefix("resourcePacks:") }) else { return [] }
        return Set(String(raw.dropFirst("resourcePacks:".count)).split(separator: ",").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "[]\" ")) }.filter { !$0.isEmpty && $0 != "vanilla" }.map { $0.hasPrefix("file/") ? String($0.dropFirst(5)) : $0 })
    }
    private func shaderPack() -> String? {
        for name in ["optionsshaders.txt", "iris.properties"] {
            guard let text = try? String(contentsOf: gameDirectory.appendingPathComponent(name)) else { continue }
            for line in text.split(whereSeparator: { $0 == "\n" }) {
                let s = String(line); if s.hasPrefix("shaderPack:") || s.hasPrefix("shaderPack=") { return s.components(separatedBy: CharacterSet(charactersIn: ":=")).dropFirst().joined().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            }
        }
        return nil
    }
}
private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
