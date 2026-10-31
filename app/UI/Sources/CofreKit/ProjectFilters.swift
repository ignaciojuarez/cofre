import Foundation

// Mods search: what to search for, where, and Modrinth's facets for the filters. Foundation only, so the facet rules
// test on the Mac.

public enum ContentKind: String, CaseIterable, Codable, Sendable {
    case mods, shaders, resourcePacks, dataPacks, modpacks
    /// Minecraft's folder: in the game directory, or in each world for data packs. `nil` for modpacks, which make
    /// an instance. The case matters: iOS disks are case-sensitive.
    public var folderName: String? {
        switch self {
        case .mods: "mods"
        case .shaders: "shaderpacks"
        case .resourcePacks: "resourcepacks"
        case .dataPacks: "datapacks"
        case .modpacks: nil
        }
    }
    /// Get adds it to the whole instance. Data packs belong to one world; modpacks make their own instance.
    public var isInstallable: Bool { self == .mods || self == .shaders || self == .resourcePacks }
}

public enum ProjectSource: String, CaseIterable, Sendable {
    case modrinth, curseforge
    public var displayName: String { self == .modrinth ? "Modrinth" : "CurseForge" }
}

/// Version and loader either follow the instance or allow anything: another version couldn't be installed.
public enum FilterScope: Hashable, Sendable { case instance, any }

/// Modrinth's search `index` values.
public enum ProjectSort: String, CaseIterable, Hashable, Sendable { case relevance, downloads, updated, newest }

public enum ShaderLoader: String, CaseIterable, Hashable, Sendable { case any, iris, optifine }

/// Resource pack resolution; the top one also takes anything bigger.
public enum PackResolution: String, CaseIterable, Hashable, Sendable {
    case x16 = "16x"
    case x32 = "32x"
    case x64 = "64x"
    case x128 = "128x"
    var facets: [String] {
        (self == .x128 ? ["128x", "256x", "512x+"] : [rawValue]).map { "categories:\($0)" }
    }
}

/// Mods search filters. Defaults follow the instance; Modrinth supports every field, CurseForge only version
/// and loader.
public struct ProjectFilters: Hashable, Sendable {
    public var version = FilterScope.instance
    public var loader = FilterScope.instance
    /// `nil` follows the instance: Iris where it runs (Fabric, Quilt, NeoForge), else any.
    public var shaderLoader: ShaderLoader?
    public var clientSide = true
    public var resolution: PackResolution?
    /// Modrinth category IDs from `ProjectFilters.categories(for:)`.
    public var categories: Set<String> = []
    public var sort = ProjectSort.relevance
    public init() {}

    /// Everything Any: what "Clear filters" sets.
    public static let cleared: Self = {
        var f = Self()
        f.version = .any
        f.loader = .any
        f.shaderLoader = .any
        f.clientSide = false
        return f
    }()

    /// A new instance: its version and loader apply again. Categories, resolution and sort stay.
    public mutating func followInstance() {
        version = .instance
        loader = .instance
        shaderLoader = nil
    }

    /// The game version to keep to, `nil` for any. `game` is empty without an instance.
    public func gameVersion(_ game: String) -> String? { version == .instance && !game.isEmpty ? game : nil }

    /// The loader to keep to, for kinds that have one. `nil` for any, Vanilla or no instance.
    public func loader(_ kind: ContentKind, _ instance: Instance.Loader) -> Instance.Loader? {
        guard loader == .instance, kind == .mods || kind == .modpacks else { return nil }
        return instance == .vanilla || instance == .unknown ? nil : instance
    }

    public func shaderLoader(_ instance: Instance.Loader) -> ShaderLoader {
        shaderLoader ?? ([.fabric, .quilt, .neoforge].contains(instance) ? .iris : .any)
    }

    /// Modrinth facets (AND of OR groups) for `kind`, without its project type.
    public func facets(_ kind: ContentKind, game: String, loader instance: Instance.Loader) -> [[String]] {
        var out: [[String]] = []
        if let v = gameVersion(game) { out.append(["versions:\(v)"]) }
        if let l = loader(kind, instance) { out.append(["categories:\(l.rawValue)"]) }
        if clientSide, kind == .mods || kind == .modpacks {
            out.append(["client_side:required", "client_side:optional"])
        }
        let shaders = shaderLoader(instance)
        if kind == .shaders, shaders != .any { out.append(["categories:\(shaders.rawValue)"]) }
        if kind == .resourcePacks, let resolution { out.append(resolution.facets) }
        let known = Set(Self.categories(for: kind).map(\.id))
        return out + categories.filter(known.contains).sorted().map { ["categories:\($0)"] }
    }

    /// What the Filters button counts: every field that isn't Any, the source supports and the kind has.
    public func activeCount(_ kind: ContentKind, source: ProjectSource, game: String, loader instance: Instance.Loader)
        -> Int
    {
        source == .modrinth
            ? facets(kind, game: game, loader: instance).count
            : (gameVersion(game) == nil ? 0 : 1) + (loader(kind, instance) == nil ? 0 : 1)
    }

    /// Modrinth's categories per kind, as (facet ID, label).
    public static func categories(for kind: ContentKind) -> [(id: String, label: String)] {
        let ids: [String]
        switch kind {
        case .mods:
            ids = [
                "adventure", "decoration", "library", "magic", "optimization", "storage", "technology",
                "utility", "worldgen",
            ]
        case .modpacks:
            ids = [
                "adventure", "kitchen-sink", "lightweight", "magic", "multiplayer", "optimization", "quests",
                "technology",
            ]
        case .shaders:
            ids = [
                "realistic", "vanilla-like", "fantasy", "cartoon", "potato", "low", "medium", "high",
                "screenshot",
            ]
        case .resourcePacks:
            ids = ["vanilla-like", "realistic", "simplistic", "themed", "gui", "audio", "models", "tweaks"]
        case .dataPacks: ids = []
        }
        return ids.map { ($0, $0 == "gui" ? "GUI" : $0.prefix(1).uppercased() + $0.dropFirst()) }
    }
}
