import Foundation

/// Mojang's list of Minecraft versions (piston-meta `version_manifest_v2.json`), newest first.
public struct VersionManifest: Decodable, Sendable {
    public struct Entry: Decodable, Sendable, Equatable {
        public enum Kind: String, Sendable { case release, snapshot, old }
        public let id: String
        public let type: String
        public let url: URL?
        /// `old_beta` and `old_alpha` are both `.old`.
        public var kind: Kind { type == "release" ? .release : type == "snapshot" ? .snapshot : .old }
    }
    public struct Latest: Decodable, Sendable, Equatable {
        public let release: String
        public let snapshot: String
    }

    public static let url = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
    public let latest: Latest?
    public let versions: [Entry]

    public static func decode(_ data: Data) throws -> VersionManifest {
        try JSONDecoder().decode(Self.self, from: data)
    }
    public func versions(_ kind: Entry.Kind) -> [Entry] { versions.filter { $0.kind == kind } }
    public func entry(_ id: String) -> Entry? { versions.first { $0.id == id } }
}

/// What a Minecraft version still has to download into a `.minecraft` folder: the client jar, its libraries
/// and its assets. Files already there don't count. An estimate for the disk check, not a download plan.
public struct VersionDownloads: Sendable, Equatable {
    public var clientBytes: Int64 = 0, libraryBytes: Int64 = 0, assetBytes: Int64 = 0
    public var totalBytes: Int64 { clientBytes + libraryBytes + assetBytes }

    public init(clientBytes: Int64 = 0, libraryBytes: Int64 = 0, assetBytes: Int64 = 0) {
        self.clientBytes = clientBytes
        self.libraryBytes = libraryBytes
        self.assetBytes = assetBytes
    }

    private struct Sized: Decodable {
        let path: String?
        let size: Int64?
    }
    private struct Library: Decodable {
        struct Downloads: Decodable { let artifact: Sized? }
        let downloads: Downloads?
    }
    private struct AssetIndex: Decodable {
        let id: String
        let totalSize: Int64?
    }
    private struct VersionJSON: Decodable {
        struct Downloads: Decodable { let client: Sized? }
        let downloads: Downloads?
        let libraries: [Library]?
        let assetIndex: AssetIndex?
    }

    /// `json` is the version's own JSON (`versions/<id>/<id>.json`, or the manifest entry's `url`).
    /// Assets count as present once their index is (Air fetches the index first, then the objects).
    public static func missing(json: Data, id: String, root: URL, fileManager fm: FileManager = .default) throws -> Self
    {
        let v = try JSONDecoder().decode(VersionJSON.self, from: json)
        func has(_ path: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(path).path) }
        var d = Self()
        if !has("versions/\(id)/\(id).jar") { d.clientBytes = v.downloads?.client?.size ?? 0 }
        d.libraryBytes = (v.libraries ?? []).compactMap { $0.downloads?.artifact }
            .filter { $0.path.map { !has("libraries/\($0)") } ?? false }
            .reduce(0) { $0 + ($1.size ?? 0) }
        if let index = v.assetIndex, !has("assets/indexes/\(index.id).json") { d.assetBytes = index.totalSize ?? 0 }
        return d
    }

    /// Reads the local version JSON when the game has one, otherwise asks the manifest. `load` fetches a URL.
    public static func estimate(version id: String, root: URL, load: (URL) async throws -> Data) async throws -> Self {
        if let local = try? Data(contentsOf: root.appendingPathComponent("versions/\(id)/\(id).json")) {
            return try missing(json: local, id: id, root: root)
        }
        guard let url = try VersionManifest.decode(await load(VersionManifest.url)).entry(id)?.url else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try missing(json: await load(url), id: id, root: root)
    }
}

/// Room for a download before it starts: the download plus a margin to unpack and run.
public struct DiskPreflight: Sendable, Equatable {
    public static let margin: Int64 = 128 * 1024 * 1024
    public let downloadBytes: Int64
    public let freeBytes: Int64
    public init(downloadBytes: Int64, freeBytes: Int64) {
        self.downloadBytes = downloadBytes
        self.freeBytes = freeBytes
    }
    public var needBytes: Int64 { downloadBytes > 0 ? downloadBytes + Self.margin : 0 }
    public var hasRoom: Bool { freeBytes >= needBytes }

    /// "Downloads 412 MB · 18.4 GB free", or what to free up.
    public var summary: String {
        let f = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        guard hasRoom else {
            return
                "Not enough space: needs \(f(needBytes)), \(f(freeBytes)) free. Free up \(f(needBytes - freeBytes)) and try again."
        }
        return downloadBytes > 0 ? "Downloads \(f(downloadBytes)) · \(f(freeBytes)) free" : "\(f(freeBytes)) free"
    }

    /// Free space for `url`'s volume, as iOS counts it for files the user asked for. `url` needn't exist yet.
    public static func freeBytes(at url: URL) -> Int64? {
        var url = url
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        #if os(Linux)
            return (try? FileManager.default.attributesOfFileSystem(forPath: url.path)[.systemFreeSize] as? NSNumber)?
                .int64Value
        #else
            return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage
        #endif
    }

    public static func check(downloadBytes: Int64, at url: URL) -> Self {
        Self(downloadBytes: downloadBytes, freeBytes: freeBytes(at: url) ?? .max)
    }
}
