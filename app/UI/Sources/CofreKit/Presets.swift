import Foundation

/// A ready-made instance definition bundled with Cofre.
public struct CofrePreset: Codable, Hashable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case recommended, experimental }

    public enum RAMTier: String, Codable, Hashable, Sendable {
        case fourGB = "4GB"
        case twelveGB = "12GB"
    }

    public struct Mod: Codable, Hashable, Sendable {
        public let project: String
        public let slug: String
        public let version: String
        public let file: String
        public let sha512: String
        public let license: String

        public init(project: String, slug: String, version: String, file: String, sha512: String, license: String) {
            self.project = project
            self.slug = slug
            self.version = version
            self.file = file
            self.sha512 = sha512
            self.license = license
        }
    }

    public struct FirstCreateOptions: Codable, Hashable, Sendable {
        public let renderDistance: Int
        public let simulationDistance: Int
        public let entityDistanceScaling: Double
        public let mipmapLevels: Int
        public let menuBackgroundBlurriness: Int
        public let touchscreen: Bool
        public let maxFps: Int
        public let enableVsync: Bool

        public init(
            renderDistance: Int, simulationDistance: Int, entityDistanceScaling: Double, mipmapLevels: Int,
            menuBackgroundBlurriness: Int, touchscreen: Bool, maxFps: Int, enableVsync: Bool = true
        ) {
            self.renderDistance = renderDistance
            self.simulationDistance = simulationDistance
            self.entityDistanceScaling = entityDistanceScaling
            self.mipmapLevels = mipmapLevels
            self.menuBackgroundBlurriness = menuBackgroundBlurriness
            self.touchscreen = touchscreen
            self.maxFps = maxFps
            self.enableVsync = enableVsync
        }
    }

    public let id: String
    public let name: String
    public let pitch: String
    public let gameVersion: String
    public let loader: Instance.Loader
    public let loaderVersion: String?
    public let renderer: String
    public let status: Status
    public let pinnedMods: [Mod]
    public let optionalMods: [Mod]
    /// The reviewed native Metal renderer artifact is deliberately not bundled yet.
    public let metalRendererModPlaceholder: String?
    public let firstCreateOptions: [RAMTier: FirstCreateOptions]
    public let sourceDate: String?

    /// Compatibility alias for the `mods` name used by the plan's draft manifest.
    public var mods: [Mod] { pinnedMods }

    public init(
        id: String, name: String, pitch: String, gameVersion: String, loader: Instance.Loader,
        loaderVersion: String?, renderer: String, status: Status, pinnedMods: [Mod], optionalMods: [Mod] = [],
        metalRendererModPlaceholder: String? = nil, firstCreateOptions: [RAMTier: FirstCreateOptions],
        sourceDate: String? = nil
    ) {
        self.id = id
        self.name = name
        self.pitch = pitch
        self.gameVersion = gameVersion
        self.loader = loader
        self.loaderVersion = loaderVersion
        self.renderer = renderer
        self.status = status
        self.pinnedMods = pinnedMods
        self.optionalMods = optionalMods
        self.metalRendererModPlaceholder = metalRendererModPlaceholder
        self.firstCreateOptions = firstCreateOptions
        self.sourceDate = sourceDate
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, pitch, gameVersion, loader, loaderVersion, renderer, status, pinnedMods, mods, optionalMods
        case metalRendererModPlaceholder, firstCreateOptions, sourceDate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        pitch = try c.decode(String.self, forKey: .pitch)
        gameVersion = try c.decode(String.self, forKey: .gameVersion)
        loader = try c.decode(Instance.Loader.self, forKey: .loader)
        loaderVersion = try c.decodeIfPresent(String.self, forKey: .loaderVersion)
        renderer = try c.decode(String.self, forKey: .renderer)
        status = try c.decode(Status.self, forKey: .status)
        pinnedMods =
            try c.decodeIfPresent([Mod].self, forKey: .pinnedMods)
            ?? c.decode([Mod].self, forKey: .mods)
        optionalMods = try c.decodeIfPresent([Mod].self, forKey: .optionalMods) ?? []
        metalRendererModPlaceholder = try c.decodeIfPresent(String.self, forKey: .metalRendererModPlaceholder)
        let raw = try c.decode([String: FirstCreateOptions].self, forKey: .firstCreateOptions)
        firstCreateOptions = Dictionary(
            uniqueKeysWithValues: raw.compactMap { key, value in
                CofrePreset.RAMTier(rawValue: key).map { ($0, value) }
            })
        sourceDate = try c.decodeIfPresent(String.self, forKey: .sourceDate)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(pitch, forKey: .pitch)
        try c.encode(gameVersion, forKey: .gameVersion)
        try c.encode(loader, forKey: .loader)
        try c.encodeIfPresent(loaderVersion, forKey: .loaderVersion)
        try c.encode(renderer, forKey: .renderer)
        try c.encode(status, forKey: .status)
        try c.encode(pinnedMods, forKey: .pinnedMods)
        try c.encode(optionalMods, forKey: .optionalMods)
        try c.encodeIfPresent(metalRendererModPlaceholder, forKey: .metalRendererModPlaceholder)
        let raw = Dictionary(uniqueKeysWithValues: firstCreateOptions.map { ($0.key.rawValue, $0.value) })
        try c.encode(raw, forKey: .firstCreateOptions)
        try c.encodeIfPresent(sourceDate, forKey: .sourceDate)
    }

    /// The low-memory tier is used below the same 6 GB cutoff as GameOptions.distances.
    public func options(forPhysicalMemoryMB physicalMemoryMB: Int) -> FirstCreateOptions {
        firstCreateOptions[physicalMemoryMB >= 6000 ? .twelveGB : .fourGB]!
    }

    public func validate() throws {
        guard !id.isEmpty, !name.isEmpty, !gameVersion.isEmpty, !pitch.isEmpty else {
            throw PresetValidationError.missingIdentity(id)
        }
        guard firstCreateOptions[.fourGB] != nil, firstCreateOptions[.twelveGB] != nil else {
            throw PresetValidationError.missingRAMTier(id)
        }
        let allMods = pinnedMods + optionalMods
        var projects = Set<String>()
        for mod in allMods {
            guard !mod.project.isEmpty, !mod.version.isEmpty, !mod.file.isEmpty,
                mod.sha512.range(of: "^[0-9a-fA-F]{128}$", options: .regularExpression) != nil
            else { throw PresetValidationError.invalidMod(id, mod.slug) }
            guard projects.insert(mod.project).inserted else {
                throw PresetValidationError.duplicateMod(id, mod.project)
            }
        }
    }

    public enum PresetValidationError: Error, Equatable, Sendable {
        case missingIdentity(String)
        case missingRAMTier(String)
        case invalidMod(String, String)
        case duplicateMod(String, String)
    }
}

public enum PresetCatalog {
    public struct Manifest: Codable, Sendable {
        public let schema: Int
        public let presets: [CofrePreset]

        public init(schema: Int, presets: [CofrePreset]) {
            self.schema = schema
            self.presets = presets
        }
    }

    public static let presets: [CofrePreset] = load().presets

    public static func decode(_ data: Data) throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: data)
    }

    public static func validate(_ manifest: Manifest) throws {
        guard manifest.schema == 1 else { throw CatalogValidationError.unsupportedSchema(manifest.schema) }
        var ids = Set<String>()
        for preset in manifest.presets {
            guard ids.insert(preset.id).inserted else { throw CatalogValidationError.duplicatePreset(preset.id) }
            try preset.validate()
        }
    }

    private static func load() -> Manifest {
        guard let url = Bundle.module.url(forResource: "presets", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return Manifest(schema: 1, presets: []) }
        guard let manifest = try? decode(data), (try? validate(manifest)) != nil else {
            return Manifest(schema: 1, presets: [])
        }
        return manifest
    }

    public enum CatalogValidationError: Error, Equatable, Sendable {
        case unsupportedSchema(Int)
        case duplicatePreset(String)
    }
}
