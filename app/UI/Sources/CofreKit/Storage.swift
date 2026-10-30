import Foundation

/// An allowlist of disposable files. Game content and shader/pipeline caches are never candidates.
public struct StorageCleanup: Sendable {
    public let home: URL
    public let gameDirectories: [URL]
    public let temporaryDirectory: URL
    public init(home: URL, gameDirectories: [URL], temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.home = home.standardizedFileURL
        self.gameDirectories = gameDirectories.map(\.standardizedFileURL)
        self.temporaryDirectory = temporaryDirectory.standardizedFileURL
    }

    private func files() -> [URL] {
        let fm = FileManager.default
        var result = Set<URL>()
        func collect(_ directory: URL, olderThan: Date? = nil) {
            guard safe(directory), let items = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey], options: []) else { return }
            for case let file as URL in items {
                guard safe(file), let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]), values.isSymbolicLink != true else { items.skipDescendants(); continue }
                // The launcher keeps stdout open and Minecraft owns its current log.
                guard !["latestlog.txt", "latest.log"].contains(file.lastPathComponent) else { continue }
                let oldEnough = olderThan.map { (values.contentModificationDate ?? .distantFuture) < $0 } ?? true
                if values.isRegularFile == true, oldEnough { result.insert(file) }
            }
        }
        for root in Set([home] + gameDirectories) {
            for name in ["logs", "crash-reports", "ame_shaderc_dump"] { collect(root.appendingPathComponent(name)) }
            collect(root.appendingPathComponent(".temp/forge_installer_cache"), olderThan: Date().addingTimeInterval(-86400))
            for name in ["latestlog.old.txt"] {
                let file = root.appendingPathComponent(name)
                if safe(file), (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { result.insert(file) }
            }
        }
        // iOS owns this disposable directory. Leave recent downloads/imports alone.
        collect(temporaryDirectory, olderThan: Date().addingTimeInterval(-86400))
        return Array(result)
    }

    /// Reject symlinks beneath the trusted filesystem locations supplied by the launcher.
    private func safe(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        let boundaries = Set(([home, temporaryDirectory] + gameDirectories).map { $0.deletingLastPathComponent().path })
        while current.path != "/", !boundaries.contains(current.path) {
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return false }
            current.deleteLastPathComponent()
        }
        return true
    }
    public var reclaimableBytes: Int64 { files().reduce(0) { $0 + Self.bytes($1) } }
    @discardableResult public func clear() throws -> Int64 {
        var removed: Int64 = 0
        for file in files() where safe(file) {
            let size = Self.bytes(file)
            try FileManager.default.removeItem(at: file)
            removed += size
        }
        return removed
    }
    public static func bytes(_ root: URL) -> Int64 {
        let fm = FileManager.default
        guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return 0 }
        if (try? root.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            return Int64((try? root.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard let items = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]) else { return 0 }
        var size: Int64 = 0
        for case let file as URL in items {
            guard let v = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey]), v.isSymbolicLink != true else { items.skipDescendants(); continue }
            if v.isRegularFile == true { size += Int64(v.fileSize ?? 0) }
        }
        return size
    }
}
