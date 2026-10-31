import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything Cofre decides about a modpack before and after the engine unpacks it: taking a file in from Files or
/// the share sheet, resolving a link to a pack file, reading what the archive is without unpacking it, and rolling
/// back an import that didn't finish. The engine still downloads the pack's mods and installs its loader.
public enum ModpackImport {
    private static let markerName = ".cofre-import-in-progress"
    private static let stagingPrefix = ".cofre-import-"
    /// Refuses archives that would unpack to more than this: real packs are well under it; zip bombs aren't.
    static let maxUnpackedBytes: Int64 = 8 << 30

    // MARK: Rollback

    /// Records the files already in a game directory so an interrupted Air import can be rolled back safely.
    public static func markImportStarted(in gameDirectory: URL, fileManager fm: FileManager = .default) throws {
        let baseline = (fm.enumerator(at: gameDirectory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])?.compactMap { item -> String? in
            guard let url = item as? URL else { return nil }
            return String(url.path.dropFirst(gameDirectory.path.count + 1))
        } ?? [])
        let data = try JSONSerialization.data(withJSONObject: ["baseline": baseline], options: [])
        try data.write(to: gameDirectory.appendingPathComponent(markerName), options: .atomic)
    }

    public static func markImportFinished(in gameDirectory: URL, fileManager fm: FileManager = .default) {
        try? fm.removeItem(at: gameDirectory.appendingPathComponent(markerName))
    }

    /// Removes only files and folders created after a marker was written. Symlinks are removed as links and never traversed.
    public static func cleanupAbandonedImport(in gameDirectory: URL, fileManager fm: FileManager = .default) {
        let marker = gameDirectory.appendingPathComponent(markerName)
        guard let data = try? Data(contentsOf: marker),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let baseline = object["baseline"] as? [String] else { return }
        let keep = Set(baseline)
        let urls = (fm.enumerator(at: gameDirectory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])?.compactMap { $0 as? URL } ?? [])
            .filter { $0.path != marker.path }
            .sorted { $0.path.count > $1.path.count }
        for url in urls where !keep.contains(String(url.path.dropFirst(gameDirectory.path.count + 1))) {
            try? fm.removeItem(at: url)
        }
        try? fm.removeItem(at: marker)
    }

    /// Deletes received and downloaded packs left behind by a crash. Call once at launch, never during an import.
    public static func cleanupAbandonedStaging(in directory: URL, fileManager fm: FileManager = .default) {
        let folders = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        for folder in folders where folder.lastPathComponent.hasPrefix(stagingPrefix) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory) == true,
                  (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
            try? fm.removeItem(at: folder)
        }
    }

    // MARK: Taking a file in

    /// Copies a file from Files, the share sheet or a drop into its own staging folder, so the import never depends
    /// on a security-scoped URL staying valid. Files iOS dropped in `Documents/Inbox` are moved, not copied.
    public static func receive(_ url: URL, in directory: URL? = nil, fileManager fm: FileManager = .default) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = (directory ?? fm.temporaryDirectory).appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = url.lastPathComponent.isEmpty || url.lastPathComponent.hasPrefix(".") ? "pack.zip" : url.lastPathComponent
        let target = folder.appendingPathComponent(name)
        do {
            if url.pathComponents.suffix(2).first == "Inbox" { try fm.moveItem(at: url, to: target) } else { try fm.copyItem(at: url, to: target) }
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
        return target
    }

    /// A new staging file for a pack downloaded from a link.
    public static func stagingFile(named name: String, in directory: URL? = nil, fileManager fm: FileManager = .default) throws -> URL {
        let folder = (directory ?? fm.temporaryDirectory).appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = (name as NSString).lastPathComponent
        return folder.appendingPathComponent(safe.isEmpty || safe.hasPrefix(".") ? "pack.mrpack" : safe)
    }

    /// Deletes a file made by `receive` or `stagingFile`, with its folder. Anything else is left alone.
    public static func discard(_ staged: URL, fileManager fm: FileManager = .default) {
        let folder = staged.deletingLastPathComponent()
        guard folder.lastPathComponent.hasPrefix(stagingPrefix) else { return }
        try? fm.removeItem(at: folder)
    }

    // MARK: What the archive is

    public enum Kind: String, Sendable { case modrinth, curseForge, multiMC, mcbbs, plain, cofreInstance }

    /// Read from the archive's file list and manifest, without unpacking it.
    public struct Summary: Equatable, Sendable {
        public let kind: Kind
        public var name: String?
        public var gameVersion: String?
        public var loader: Instance.Loader = .vanilla
        public var loaderVersion: String?
        /// Files the pack downloads during import (Modrinth and CurseForge manifests).
        public var downloads = 0
        /// Bytes those downloads take, when the manifest says (Modrinth only).
        public var downloadBytes: Int64 = 0
        public var unpackedBytes: Int64 = 0
    }

    public enum Failure: LocalizedError, Sendable, Equatable {
        case notAZip, bedrockWorld, javaWorld, modFile, unsupportedFormat, tooBig, invalidPack(String), invalidLink, curseForgePage
        public var errorDescription: String? {
            switch self {
            case .notAZip: "This file isn't a .mrpack or .zip. It may be damaged or still downloading."
            case .bedrockWorld: "This is a Bedrock world. Cofre plays Java Edition."
            case .javaWorld: "This is a world, not a modpack. Add it from an instance's Worlds."
            case .modFile: "This is a mod, not a modpack. Add it from an instance's Mods."
            case .unsupportedFormat: "This ZIP isn't a Modrinth, CurseForge or MultiMC modpack."
            case .tooBig: "This pack would unpack to more than 8 GB, so Cofre won't open it."
            case .invalidPack(let message): message
            case .invalidLink: "That link isn't a modpack. Use a Modrinth modpack page or a link to a .mrpack or .zip file."
            case .curseForgePage: "CurseForge pages can't be imported directly. Download the pack's ZIP from CurseForge, then open it in Cofre."
            }
        }
    }

    private struct ModrinthIndex: Decodable {
        struct File: Decodable { let path: String; let fileSize: Int64?; let env: [String: String]? }
        let formatVersion: Int
        let game: String
        let name: String?
        let dependencies: [String: String]
        let files: [File]
    }
    private struct CurseManifest: Decodable {
        struct Minecraft: Decodable { let version: String; let modLoaders: [Loader]? }
        struct Loader: Decodable { let id: String; let primary: Bool? }
        struct File: Decodable { let required: Bool? }
        let name: String?; let minecraft: Minecraft; let files: [File]?
    }
    private struct MultiMCPack: Decodable {
        struct Component: Decodable { let uid: String; let version: String? }
        let components: [Component]
    }

    public static func inspect(_ archive: URL) throws -> Summary {
        let data: Data
        let entries: [Zip.Entry]
        do {
            data = try Data(contentsOf: archive, options: .alwaysMapped)
            entries = try Zip.entries(in: data)
        } catch { throw Failure.notAZip }
        let visible = entries.filter { !$0.path.hasPrefix("__MACOSX/") && !($0.path.split(separator: "/").last ?? "").hasPrefix(".") }
        guard !visible.isEmpty else { throw Failure.notAZip }
        let unpacked = visible.reduce(Int64(0)) { $0 + Int64($1.size) }
        guard unpacked <= maxUnpackedBytes else { throw Failure.tooBig }

        // Like Air: a pack zipped together with its folder has every file under that one folder.
        let prefix = wrapperPrefix(visible.map(\.path))
        var byPath: [String: Zip.Entry] = [:]
        for entry in visible where entry.path.hasPrefix(prefix) { byPath[String(entry.path.dropFirst(prefix.count))] = entry }
        func json<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
            guard let entry = byPath[name] else { return nil }
            do { return try JSONDecoder().decode(T.self, from: Zip.data(of: entry, in: data)) }
            catch { throw Failure.invalidPack("The pack's \(name) is damaged.") }
        }

        var summary: Summary
        if byPath["cofre.json"] != nil {
            summary = Summary(kind: .cofreInstance)
        } else if let index = try json("modrinth.index.json", as: ModrinthIndex.self) {
            guard index.formatVersion == 1, index.game.lowercased() == "minecraft" else { throw Failure.invalidPack("This Modrinth pack uses a format Cofre doesn't know.") }
            summary = Summary(kind: .modrinth, name: index.name, gameVersion: index.dependencies["minecraft"])
            for (key, loader) in [("neoforge", Instance.Loader.neoforge), ("forge", .forge), ("fabric-loader", .fabric), ("quilt-loader", .quilt)] {
                if let version = index.dependencies[key] { summary.loader = loader; summary.loaderVersion = version; break }
            }
            let files = index.files.filter { $0.env?["client"]?.lowercased() != "unsupported" }
            summary.downloads = files.count
            summary.downloadBytes = files.reduce(0) { $0 + ($1.fileSize ?? 0) }
        } else if let pack = try json("mmc-pack.json", as: MultiMCPack.self) {
            summary = Summary(kind: .multiMC, gameVersion: pack.components.first { $0.uid == "net.minecraft" }?.version)
            for (uid, loader) in [("net.neoforged", Instance.Loader.neoforge), ("net.minecraftforge", .forge), ("net.fabricmc.fabric-loader", .fabric), ("org.quiltmc.quilt-loader", .quilt)] {
                if let component = pack.components.first(where: { $0.uid == uid }) { summary.loader = loader; summary.loaderVersion = component.version; break }
            }
        } else if byPath["mcbbs.packmeta"] != nil {
            summary = Summary(kind: .mcbbs)
        } else if let entry = byPath["manifest.json"] {
            if let object = try? JSONSerialization.jsonObject(with: Zip.data(of: entry, in: data)) as? [String: Any], object["addons"] is [Any] {
                summary = Summary(kind: .mcbbs, name: object["name"] as? String)
            } else {
                guard let manifest = try json("manifest.json", as: CurseManifest.self) else { throw Failure.unsupportedFormat }
                summary = Summary(kind: .curseForge, name: manifest.name, gameVersion: manifest.minecraft.version)
                let loaders = manifest.minecraft.modLoaders ?? []
                if let id = (loaders.first { $0.primary == true } ?? loaders.first)?.id.lowercased() {
                    // neoforge- before forge-: both prefixes would match "neoforge-…" otherwise.
                    for (prefix, loader) in [("neoforge-", Instance.Loader.neoforge), ("forge-", .forge), ("fabric-", .fabric), ("quilt-", .quilt)] where id.hasPrefix(prefix) {
                        summary.loader = loader; summary.loaderVersion = String(id.dropFirst(prefix.count)); break
                    }
                }
                summary.downloads = (manifest.files ?? []).filter { $0.required ?? true }.count
            }
        } else if byPath["level.dat"] != nil, byPath.keys.contains(where: { $0.hasPrefix("db/") }) {
            throw Failure.bedrockWorld
        } else if byPath["level.dat"] != nil {
            throw Failure.javaWorld
        } else if ["fabric.mod.json", "quilt.mod.json", "META-INF/mods.toml", "META-INF/neoforge.mods.toml"].contains(where: { byPath[$0] != nil }) {
            throw Failure.modFile
        } else if byPath.keys.contains(where: isGameFolderPath) {
            summary = Summary(kind: .plain)
        } else {
            throw Failure.unsupportedFormat
        }
        summary.unpackedBytes = unpacked
        return summary
    }

    /// The single top-level folder everything sits in, or "" when the pack's files are at the top (Air's rule).
    static func wrapperPrefix(_ paths: [String]) -> String {
        let markers = ["modrinth.index.json", "mmc-pack.json", "manifest.json", "mcbbs.packmeta", "instance.cfg", "cofre.json"]
        guard !paths.contains(where: { path in !path.contains("/") || markers.contains(path) || isGameFolderPath(path)
            || ["overrides/", "client-overrides/", ".minecraft/"].contains { path.hasPrefix($0) } }) else { return "" }
        let tops = Set(paths.compactMap { $0.split(separator: "/").first.map(String.init) })
        return tops.count == 1 ? tops.first! + "/" : ""
    }

    /// Air's list of what a plain game-folder ZIP has at its top.
    private static func isGameFolderPath(_ path: String) -> Bool {
        let path = path.hasPrefix(".minecraft/") ? String(path.dropFirst(".minecraft/".count)) : path
        return ["mods/", "config/", "versions/", "saves/", "resourcepacks/", "shaderpacks/", "defaultconfigs/", "kubejs/", "scripts/"]
            .contains { path.hasPrefix($0) } || ["options.txt", "optionsof.txt", "servers.dat"].contains(path)
    }

    // MARK: Links

    public enum Link: Equatable, Sendable {
        /// A direct link to a pack file.
        case file(URL)
        /// A Modrinth modpack page, optionally of one version (its id or version number).
        case modrinth(project: String, version: String?)
    }

    /// What a pasted or shared link points to. Only https is accepted.
    public static func link(_ url: URL) throws -> Link {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { throw Failure.invalidLink }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "modrinth.com" || host == "www.modrinth.com" {
            guard parts.count >= 2, parts[0] == "modpack" else { throw Failure.invalidLink }
            return .modrinth(project: parts[1], version: parts.count >= 4 && parts[2] == "version" ? parts[3] : nil)
        }
        if host.hasSuffix("curseforge.com") { throw Failure.curseForgePage }
        guard ["mrpack", "zip"].contains(url.pathExtension.lowercased()) else { throw Failure.invalidLink }
        return .file(url)
    }

    /// The pack file to download from a Modrinth project's versions (newest first, as the API lists them).
    public static func packFile(in versions: [Modrinth.Version], version: String?) -> Modrinth.File? {
        let candidates = version.map { wanted in versions.filter { $0.id == wanted || $0.versionNumber == wanted } } ?? versions
        for candidate in candidates {
            let packs = candidate.files.filter { $0.filename.lowercased().hasSuffix(".mrpack") && $0.url != nil }
            if let file = packs.first(where: \.primary) ?? packs.first { return file }
        }
        return nil
    }
}
