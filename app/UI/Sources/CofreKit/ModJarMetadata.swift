import Foundation

/// The small part of a mod jar Cofre needs for Installed: IDs, dependencies and its own icon. Reads are cached by
/// path, size and modification time so scrolling or refreshing does not reopen unchanged jars.
public struct ModJarMetadata: Hashable, Sendable {
    public var modIDs: [String]
    public var name: String?
    public var version: String?
    public var dependencies: [ModDependency]
    public var icon: Data?
    public var cacheKey: String

    public init(
        modIDs: [String] = [], name: String? = nil, version: String? = nil, dependencies: [ModDependency] = [],
        icon: Data? = nil, cacheKey: String = ""
    ) {
        self.modIDs = modIDs
        self.name = name
        self.version = version
        self.dependencies = dependencies
        self.icon = icon
        self.cacheKey = cacheKey
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: ModJarMetadata] = [:]

    public static func read(jar: URL, loader: Instance.Loader = .unknown) -> ModJarMetadata? {
        guard let values = try? jar.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let size = values.fileSize, let date = values.contentModificationDate
        else { return nil }
        let cacheKey = jar.path + "|" + String(size) + "|" + String(date.timeIntervalSince1970) + "|" + loader.rawValue
        if let hit = lock.withLock({ cache[cacheKey] }) { return hit }
        guard let data = try? Data(contentsOf: jar, options: .alwaysMapped),
            let found = parse(data, loader: loader, cacheKey: cacheKey)
        else { return nil }
        lock.withLock { cache[cacheKey] = found }
        return found
    }

    private static func parse(_ data: Data, loader: Instance.Loader, cacheKey: String) -> ModJarMetadata? {
        guard let entries = try? Zip.entries(in: data) else { return nil }
        func bytes(_ path: String, max: Int = 1_000_000) -> Data? {
            guard let entry = entries.first(where: { $0.path == path }), entry.size <= max else { return nil }
            return try? Zip.data(of: entry, in: data)
        }
        func object(_ path: String) -> [String: Any]? {
            bytes(path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }

        var result = ModJarMetadata(cacheKey: cacheKey)
        if let json = object("fabric.mod.json") {
            result.modIDs = (json["id"] as? String).map { [$0] } ?? []
            result.name = json["name"] as? String
            result.version = json["version"] as? String
            result.dependencies = dependencyMap(json["depends"] as? [String: Any])
            result.icon = iconData(json["icon"], entries: entries, data: data)
        } else if let json = object("quilt.mod.json"), let quilt = json["quilt_loader"] as? [String: Any] {
            result.modIDs = (quilt["id"] as? String).map { [$0] } ?? []
            result.name = (quilt["metadata"] as? [String: Any])?["name"] as? String
            result.version = quilt["version"] as? String
            result.dependencies = quiltDependencies(quilt["depends"] as? [[String: Any]])
            result.icon = iconData((quilt["metadata"] as? [String: Any])?["icon"], entries: entries, data: data)
        }

        let tomlNames: [String] =
            loader == .neoforge
            ? ["META-INF/neoforge.mods.toml", "META-INF/mods.toml"]
            : ["META-INF/mods.toml", "META-INF/neoforge.mods.toml"]
        if let tomlPath = tomlNames.first(where: { bytes($0) != nil }),
            let tomlData = bytes(tomlPath)
        {
            let text = String(decoding: tomlData, as: UTF8.self)
            let toml = ModsToml(text: text)
            result.modIDs += toml.modIDs
            result.dependencies += toml.dependencies.filter(\.required).map {
                ModDependency(id: $0.modID, required: true)
            }
            if let loader = toml.modLoader?.lowercased(), let provider = ModRequirements.providers[loader] {
                result.dependencies.append(ModDependency(id: loader, name: provider.name))
            }
            if result.name == nil { result.name = toml.modIDs.first }
            if let logo = rootValue("logoFile", in: text) {
                result.icon = iconData(logo, entries: entries, data: data) ?? result.icon
            }
        }
        result.modIDs = result.modIDs.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        result.dependencies = result.dependencies.reduce(into: []) { result, dependency in
            if !result.contains(where: { $0.id == dependency.id }) { result.append(dependency) }
        }
        return result.modIDs.isEmpty && result.name == nil && result.icon == nil ? nil : result
    }

    private static func dependencyMap(_ values: [String: Any]?) -> [ModDependency] {
        (values ?? [:]).map { key, _ in
            ModDependency(id: key, name: key)
        }.sorted { $0.id < $1.id }
    }

    private static func quiltDependencies(_ values: [[String: Any]]?) -> [ModDependency] {
        (values ?? []).compactMap { row in (row["id"] as? String).map { ModDependency(id: $0) } }
    }

    private static func iconData(_ value: Any?, entries: [Zip.Entry], data: Data) -> Data? {
        let path: String?
        if let string = value as? String {
            path = string
        } else if let map = value as? [String: Any] {
            path = (map["64"] as? String) ?? map.values.compactMap { $0 as? String }.first
        } else {
            path = nil
        }
        guard let path, !path.isEmpty else { return nil }
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let entry = entries.first(where: { $0.path == normalized }), entry.size <= 2_000_000 else { return nil }
        return try? Zip.data(of: entry, in: data)
    }

    private static func rootValue(_ key: String, in text: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), line.firstIndex(of: "[") == nil,
                let eq = line.firstIndex(of: "="), line[..<eq].trimmingCharacters(in: .whitespaces) == key
            else { continue }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'",
                let end = value.dropFirst().firstIndex(of: quote)
            {
                return String(value[value.index(after: value.startIndex)..<end])
            }
            return value.split(separator: "#", maxSplits: 1).first.map(String.init)
        }
        return nil
    }
}
