import Foundation
import Compression
#if canImport(Darwin)
import Darwin
#endif

public struct World: Identifiable, Sendable, Hashable {
    public let id: String
    public let folder: String
    public let displayName: String
    public let gameMode: String
    public let lastPlayed: Date?
    public let sizeBytes: Int64
    public let iconPNG: Data?
    public let gameVersion: String?
    public init(id: String, folder: String, displayName: String, gameMode: String, lastPlayed: Date?, sizeBytes: Int64, iconPNG: Data?, gameVersion: String? = nil) {
        self.id=id; self.folder=folder; self.displayName=displayName; self.gameMode=gameMode; self.lastPlayed=lastPlayed; self.sizeBytes=sizeBytes; self.iconPNG=iconPNG; self.gameVersion=gameVersion
    }
}

public struct WorldBackup: Identifiable, Sendable, Hashable {
    public let id: String
    public let url: URL
    public let date: Date
    public let sizeBytes: Int64
}

public final class WorldStore: @unchecked Sendable {
    public struct TrashToken: Hashable, Sendable { fileprivate let original: URL; fileprivate let trashed: URL }
    public enum Failure: Error, LocalizedError { case gameRunning, missingWorld, bedrockWorld, invalidArchive
        public var errorDescription: String? { switch self { case .gameRunning: "Stop the game before changing worlds"; case .missingWorld: "World not found"; case .bedrockWorld: "Bedrock world files (.mcworld) are not supported"; case .invalidArchive: "The archive does not contain a world" } }
    }
    public let instance: Instance
    private let fm: FileManager
    private let running: () -> Bool
    private var deleted: [TrashToken] = []
    private var saves: URL { instance.gameDirectory.appendingPathComponent("saves", isDirectory: true) }
    private var backups: URL { instance.gameDirectory.appendingPathComponent("backups", isDirectory: true) }

    public init(instance: Instance, fileManager: FileManager = .default, isGameRunning: @escaping () -> Bool = { false }) { self.instance=instance; self.fm=fileManager; self.running=isGameRunning }
    /// Like the game, only folders with a `level.dat` (or the game's `level.dat_old` backup) are worlds.
    public func list() throws -> [World] {
        guard let dirs = try? fm.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) as [URL]? else { return [] }
        return dirs.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  Self.levelFiles.contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).path) }) else { return nil }
            return try? read(url)
        }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }
    public func backups(for world: String) throws -> [WorldBackup] {
        guard fm.fileExists(atPath: try folder(world).path) else { throw Failure.missingWorld }
        guard let files = try? fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        return files.filter { $0.lastPathComponent.hasPrefix(world + "-") && $0.pathExtension == "zip" }.compactMap { u in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]); return WorldBackup(id:u.lastPathComponent,url:u,date:v?.contentModificationDate ?? .distantPast,sizeBytes:Int64(v?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }
    @discardableResult public func backUp(_ world: String, date: Date = Date()) throws -> URL { try ensureWritable(); let source=try folder(world); guard fm.fileExists(atPath: source.path) else { throw Failure.missingWorld }; try fm.createDirectory(at: backups, withIntermediateDirectories: true); let stamp=ISO8601DateFormatter(); stamp.formatOptions=[.withInternetDateTime,.withDashSeparatorInDate,.withColonSeparatorInTime]; let target=backups.appendingPathComponent("\(world)-\(stamp.string(from: date)).zip"); try Zip.write(directory: source, to: target); return target }
    public func restore(_ backup: URL, world: String) throws { try ensureWritable(); _ = try folder(world); guard fm.fileExists(atPath: backup.path) else { throw Failure.invalidArchive }; if fm.fileExists(atPath:saves.appendingPathComponent(world).path) { _=try backUp(world) }; let temp=saves.appendingPathComponent(".restore-\(UUID().uuidString)"); try fm.createDirectory(at: temp, withIntermediateDirectories: true); defer { try? fm.removeItem(at: temp) }; try Zip.extract(backup,to:temp); let source = temp.appendingPathComponent(world).path == (temp.appendingPathComponent(world).path) && fm.fileExists(atPath:temp.appendingPathComponent(world).path) ? temp.appendingPathComponent(world) : temp; try fm.createDirectory(at:saves,withIntermediateDirectories:true); try? fm.removeItem(at:saves.appendingPathComponent(world)); try fm.moveItem(at:source,to:saves.appendingPathComponent(world)) }
    @discardableResult public func export(_ world: String, to destination: URL? = nil) throws -> URL { let source=try folder(world); guard fm.fileExists(atPath:source.path) else { throw Failure.missingWorld }; let target=destination ?? fm.temporaryDirectory.appendingPathComponent("\(world).zip"); try Zip.write(directory:source,to:target); return target }
    @discardableResult public func `import`(_ archive: URL, as name: String? = nil) throws -> World { try ensureWritable(); if archive.pathExtension.lowercased() == "mcworld" { throw Failure.bedrockWorld }; let temp=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); try fm.createDirectory(at:temp,withIntermediateDirectories:true); defer { try? fm.removeItem(at:temp) }; try Zip.extract(archive,to:temp); let candidates=(try? fm.contentsOfDirectory(at:temp,includingPropertiesForKeys:[.isDirectoryKey],options:[.skipsHiddenFiles]))?.filter { (try? $0.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true } ?? []; let source = candidates.count == 1 ? candidates[0] : temp; guard fm.fileExists(atPath:source.appendingPathComponent("level.dat").path) else { throw Failure.invalidArchive }; let target=try folder(name ?? source.lastPathComponent); guard !fm.fileExists(atPath:target.path) else { throw Failure.invalidArchive }; try fm.createDirectory(at:saves,withIntermediateDirectories:true); try fm.copyItem(at:source,to:target); return try read(target) }
    public func copy(_ world: String, to targetInstance: Instance) throws { try ensureWritable(); let source=try folder(world); guard fm.fileExists(atPath:source.path) else { throw Failure.missingWorld }; let target=targetInstance.gameDirectory.appendingPathComponent("saves",isDirectory:true).appendingPathComponent(world); try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true); try? fm.removeItem(at:target); #if canImport(Darwin)
        if clonefile(source.path,target.path,0) != 0 { try fm.copyItem(at:source,to:target) }
        #else
        try fm.copyItem(at:source,to:target)
        #endif
    }
    @discardableResult public func delete(_ world: String) throws -> TrashToken { try ensureWritable(); let source=try folder(world); guard fm.fileExists(atPath:source.path) else { throw Failure.missingWorld }; let trash=instance.gameDirectory.appendingPathComponent(".trash",isDirectory:true); try fm.createDirectory(at:trash,withIntermediateDirectories:true); let dest=trash.appendingPathComponent("world-\(UUID().uuidString)"); try fm.moveItem(at:source,to:dest); let token=TrashToken(original:source,trashed:dest); deleted.append(token); return token }
    public func undo(_ token: TrashToken) throws { try ensureWritable(); guard fm.fileExists(atPath:token.trashed.path) else { throw Failure.missingWorld }; try fm.createDirectory(at:token.original.deletingLastPathComponent(),withIntermediateDirectories:true); try? fm.removeItem(at:token.original); try fm.moveItem(at:token.trashed,to:token.original); deleted.removeAll { $0 == token } }
    private func ensureWritable() throws { if running() { throw Failure.gameRunning } }
    private static let levelFiles = ["level.dat", "level.dat_old"]
    /// A world's folder, directly in saves/. An empty, `.`, `..` or nested name would reach outside it.
    private func folder(_ name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw Failure.missingWorld }
        return saves.appendingPathComponent(name, isDirectory: true)
    }
    /// A world always lists, even when its level.dat can't be read (it then shows its folder name).
    private func read(_ url: URL) throws -> World {
        let root = Self.levelFiles.lazy.compactMap { try? NBT.read(Data(contentsOf: url.appendingPathComponent($0))) }.first.map { $0["Data"] ?? $0 }
        let mode = Int(root?["GameType"]?.integer ?? 0)
        let modes = ["Survival", "Creative", "Adventure", "Spectator"]
        let size = (fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL }.reduce(Int64(0)) {
            $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }) ?? 0
        return World(
            id: url.lastPathComponent, folder: url.lastPathComponent,
            displayName: root?["LevelName"]?.string ?? url.lastPathComponent,
            gameMode: modes.indices.contains(mode) ? modes[mode] : "Unknown",
            lastPlayed: root?["LastPlayed"]?.integer.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            sizeBytes: size, iconPNG: try? Data(contentsOf: url.appendingPathComponent("icon.png")),
            gameVersion: root?["Version"]?["Name"]?.string)
    }
}

