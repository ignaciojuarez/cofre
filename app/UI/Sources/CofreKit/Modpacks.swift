import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Imports Modrinth and CurseForge packs into complete, isolated game instances.
/// Archives are unpacked and downloaded into a staging directory first; the profile is
/// created only after every file has passed its hash check.
public final class ModpackImport: @unchecked Sendable {
    public struct Result: Sendable {
        public let instance: Instance
        public let addedFiles: [String]
        public init(instance: Instance, addedFiles: [String]) { self.instance = instance; self.addedFiles = addedFiles }
    }

    public enum Failure: LocalizedError, Sendable {
        case invalidPack(String), unsupportedFormat, curseForgeKeyRequired(URL), curseForgeDownloadUnavailable(Int, Int, URL)
        public var errorDescription: String? {
            switch self {
            case .invalidPack(let message): return message
            case .unsupportedFormat: return "This ZIP is not a Modrinth or CurseForge modpack."
            case .curseForgeKeyRequired(let url): return "CurseForge needs an API key to fetch this pack. Open \(url.absoluteString) to download its files, then try again."
            case .curseForgeDownloadUnavailable(let project, let file, let url): return "CurseForge could not provide project \(project), file \(file). Download it from \(url.absoluteString)."
            }
        }
    }

    private struct ModrinthIndex: Decodable {
        struct File: Decodable { let path: String; let hashes: [String: String]; let downloads: [URL]; let fileSize: Int64?; let env: [String: String]? }
        let formatVersion: Int
        let game: String
        let versionId: String?
        let name: String?
        let dependencies: [String: String]
        let files: [File]
    }
    private struct CurseManifest: Decodable {
        struct Minecraft: Decodable { let version: String; let modLoaders: [Loader] }
        struct Loader: Decodable { let id: String; let primary: Bool? }
        struct File: Decodable { let projectID: Int; let fileID: Int; let required: Bool? }
        let name: String?; let minecraft: Minecraft; let files: [File]
    }

    private let instances: InstanceStore
    private let queue: DownloadQueue
    private let fm: FileManager
    private let curseForgeKey: String?

    public init(instances: InstanceStore, queue: DownloadQueue = .shared, fileManager: FileManager = .default, curseForgeKey: String? = nil) {
        self.instances = instances; self.queue = queue; self.fm = fileManager; self.curseForgeKey = curseForgeKey
    }

    public func importPack(_ archive: URL, name: String? = nil) async throws -> Result {
        let staging = fm.temporaryDirectory.appendingPathComponent("cofre-import-(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try Zip.extract(archive, to: staging)
        let indexURL = staging.appendingPathComponent("modrinth.index.json")
        let result: (name: String, version: String, loader: Instance.Loader, loaderVersion: String?, files: [String])
        if fm.fileExists(atPath: indexURL.path) {
            result = try await importModrinth(indexURL: indexURL, root: staging)
        } else if fm.fileExists(atPath: staging.appendingPathComponent("manifest.json").path) {
            result = try await importCurseForge(manifestURL: staging.appendingPathComponent("manifest.json"), root: staging)
        } else { throw Failure.unsupportedFormat }

        let instance = try instances.create(name: name ?? result.name, version: result.version, loader: result.loader, loaderVersion: result.loaderVersion)
        do {
            // The instance directory is empty because all content was staged above.
            for file in result.files {
                let source = staging.appendingPathComponent(file)
                let target = instance.gameDirectory.appendingPathComponent(file)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
            }
            return Result(instance: instance, addedFiles: result.files)
        } catch {
            try? instances.remove(instance.id)
            throw error
        }
    }

    private func importModrinth(indexURL: URL, root: URL) async throws -> (String, String, Instance.Loader, String?, [String]) {
        let index = try JSONDecoder().decode(ModrinthIndex.self, from: Data(contentsOf: indexURL))
        guard index.formatVersion == 1, index.game.lowercased() == "minecraft" else { throw Failure.invalidPack("Unsupported Modrinth index format.") }
        let version = index.dependencies["minecraft"] ?? index.versionId ?? ""
        guard !version.isEmpty else { throw Failure.invalidPack("The pack does not declare a Minecraft version.") }
        let loaderInfo: (Instance.Loader, String?) = if let v = index.dependencies["fabric-loader"] { (.fabric, v) } else if let v = index.dependencies["quilt-loader"] { (.quilt, v) } else if let v = index.dependencies["neoforge"] { (.neoforge, v) } else if let v = index.dependencies["forge"] { (.forge, v) } else { (.vanilla, nil) }
        var added: [String] = []
        for file in index.files {
            try validatePath(file.path)
            if file.env?["client"]?.lowercased() == "unsupported" { continue }
            guard let url = file.downloads.first else { throw Failure.invalidPack("No download URL for \(file.path).") }
            let destination = root.appendingPathComponent(file.path)
            try await queue.download(url: url, destination: destination, title: file.path, totalBytes: file.fileSize, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"])
            added.append(file.path)
        }
        added += try copyOverrides(from: root, names: ["overrides", "client-overrides"])
        return (index.name ?? indexURL.deletingLastPathComponent().lastPathComponent, version, loaderInfo.0, loaderInfo.1, added)
    }

    private func importCurseForge(manifestURL: URL, root: URL) async throws -> (String, String, Instance.Loader, String?, [String]) {
        let manifest = try JSONDecoder().decode(CurseManifest.self, from: Data(contentsOf: manifestURL))
        let selected = manifest.minecraft.modLoaders.first(where: { $0.primary == true }) ?? manifest.minecraft.modLoaders.first
        let loader = selected.flatMap { parseLoader($0.id) } ?? (.vanilla, nil)
        guard let key = curseForgeKey, !key.isEmpty else { throw Failure.curseForgeKeyRequired(URL(string: "https://www.curseforge.com/minecraft/modpacks")!) }
        var added: [String] = []
        for file in manifest.files where file.required ?? true {
            let page = URL(string: "https://api.curseforge.com/v1/mods/(file.projectID)/files/(file.fileID)/download")!
            var request = URLRequest(url: page); request.setValue(key, forHTTPHeaderField: "x-api-key")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode), let url = http.url else { throw Failure.curseForgeDownloadUnavailable(file.projectID, file.fileID, page) }
            // The API normally redirects to the CDN. Use the queue so the staged file gets the same lifecycle.
            let destination = root.appendingPathComponent("mods/(file.projectID)-(file.fileID).jar")
            try data.write(to: destination)
            _ = url; added.append("mods/(file.projectID)-(file.fileID).jar")
        }
        added += try copyOverrides(from: root, names: ["overrides", "client-overrides"])
        return (manifest.name ?? manifestURL.deletingLastPathComponent().lastPathComponent, manifest.minecraft.version, loader.0, loader.1, added)
    }

    private func parseLoader(_ id: String) -> (Instance.Loader, String?) {
        for (prefix, loader) in [("fabric-", Instance.Loader.fabric), ("quilt-", .quilt), ("forge-", .forge), ("neoforge-", .neoforge)] where id.lowercased().hasPrefix(prefix) { return (loader, String(id.dropFirst(prefix.count))) }
        return (.vanilla, nil)
    }

    private func copyOverrides(from root: URL, names: [String]) throws -> [String] {
        var added: [String] = []
        for name in names {
            let source = root.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path) else { continue }
            let base = root
            guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            for case let file as URL in enumerator {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let relative = String(file.standardizedFileURL.path.dropFirst(source.standardizedFileURL.path.count + 1))
                let target = base.appendingPathComponent(relative)
                try validatePath(relative); try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: target); try fm.copyItem(at: file, to: target); added.append(relative)
            }
            try? fm.removeItem(at: source)
        }
        return added
    }

    private func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/")
        guard !path.hasPrefix("/"), !parts.contains(".."), !parts.contains(where: { $0.isEmpty }) else { throw Zip.Failure.unsafePath(path) }
    }
}
