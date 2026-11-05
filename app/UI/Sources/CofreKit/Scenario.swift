import Foundation

/// A small, Codable description of a repeatable debug launch.
public struct CofreScenario: Codable, Equatable, Sendable {
    /// A file written into the instance before launch: downloaded from `url`
    /// (artifacts not in the Modrinth catalog), copied `from` a path in the
    /// app's Documents (pushed by `scripts/scenario.sh`, no network needed) or,
    /// for small configs, `text`.
    public struct File: Codable, Equatable, Sendable {
        public let url: String?
        public let from: String?
        public let text: String?
        public let to: String

        public init(url: String? = nil, from: String? = nil, text: String? = nil, to: String) {
            self.url = url; self.from = from; self.text = text; self.to = to
        }
    }

    public let name: String
    public let version: String?
    public let loader: Instance.Loader
    public let loaderVersion: String?
    public let mods: [String]
    public let files: [File]
    public let pack: String?
    public let packVersion: String?
    public let renderer: RendererID
    public let resolution: Double
    public let memoryMB: Int?
    public let launch: Bool
    public let fresh: Bool
    public let world: String?
    public let seed: Int64?
    /// Engine experiments for this run (`EngineOptions`); absent means today's defaults.
    public let engine: EngineOptions?

    enum CodingKeys: String, CodingKey { case name, version, loader, loaderVersion, mods, files, pack, packVersion, renderer, resolution, memoryMB, launch, fresh, world, seed, engine }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name); version = try c.decodeIfPresent(String.self, forKey: .version)
        loader = Instance.Loader(rawValue: (try c.decodeIfPresent(String.self, forKey: .loader) ?? "vanilla").lowercased()) ?? .unknown
        loaderVersion = try c.decodeIfPresent(String.self, forKey: .loaderVersion)
        mods = try c.decodeIfPresent([String].self, forKey: .mods) ?? []; files = try c.decodeIfPresent([File].self, forKey: .files) ?? []
        pack = try c.decodeIfPresent(String.self, forKey: .pack); packVersion = try c.decodeIfPresent(String.self, forKey: .packVersion)
        renderer = RendererID(rawValue: try c.decodeIfPresent(String.self, forKey: .renderer) ?? "auto")
        resolution = try c.decodeIfPresent(Double.self, forKey: .resolution) ?? 1
        memoryMB = try c.decodeIfPresent(Int.self, forKey: .memoryMB); launch = try c.decodeIfPresent(Bool.self, forKey: .launch) ?? true; fresh = try c.decodeIfPresent(Bool.self, forKey: .fresh) ?? false
        world = try c.decodeIfPresent(String.self, forKey: .world); seed = try c.decodeIfPresent(Int64.self, forKey: .seed)
        engine = try c.decodeIfPresent(EngineOptions.self, forKey: .engine)
    }

    public init(name: String, version: String? = nil, loader: Instance.Loader = .vanilla, loaderVersion: String? = nil,
                mods: [String] = [], files: [File] = [], pack: String? = nil, packVersion: String? = nil, renderer: RendererID = .auto,
                resolution: Double = 1, memoryMB: Int? = nil, launch: Bool = true, fresh: Bool = false,
                world: String? = nil, seed: Int64? = nil, engine: EngineOptions? = nil) {
        self.name = name; self.version = version; self.loader = loader; self.loaderVersion = loaderVersion
        self.mods = mods; self.files = files; self.pack = pack; self.packVersion = packVersion; self.renderer = renderer
        self.resolution = resolution; self.memoryMB = memoryMB; self.launch = launch; self.fresh = fresh
        self.world = world; self.seed = seed; self.engine = engine
    }

    public init(name: String, version: String? = nil, loader: String, loaderVersion: String? = nil,
                mods: [String] = [], files: [File] = [], pack: String? = nil, packVersion: String? = nil, renderer: String = "auto",
                resolution: Double = 1, memoryMB: Int? = nil, launch: Bool = true, fresh: Bool = false,
                world: String? = nil, seed: Int64? = nil) {
        self.init(name: name, version: version, loader: Instance.Loader(rawValue: loader.lowercased()) ?? .unknown,
                  loaderVersion: loaderVersion, mods: mods, files: files, pack: pack, packVersion: packVersion,
                  renderer: RendererID(rawValue: renderer), resolution: resolution, memoryMB: memoryMB,
                  launch: launch, fresh: fresh, world: world, seed: seed)
    }

    public enum ValidationError: Error, LocalizedError, Equatable {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ValidationError.invalid("name is required") }
        guard pack == nil || mods.isEmpty else { throw ValidationError.invalid("pack and mods are mutually exclusive") }
        if pack == nil { guard let version, !version.isEmpty else { throw ValidationError.invalid("version is required") } }
        guard loader != .unknown else { throw ValidationError.invalid("unknown loader") }
        guard (0.1...1.0).contains(resolution) else { throw ValidationError.invalid("resolution must be between 0.1 and 1") }
        guard memoryMB == nil || (memoryMB! >= 512 && memoryMB! <= 16384) else { throw ValidationError.invalid("memoryMB is out of range") }
        guard mods.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") }) else { throw ValidationError.invalid("invalid mod slug") }
        if let world {
            guard !world.isEmpty, world != ".", world != "..", !world.contains("/"), !world.contains("\\"), !world.contains("\0") else {
                throw ValidationError.invalid("invalid world folder")
            }
        } else if seed != nil {
            throw ValidationError.invalid("seed requires world")
        }
        for file in files {
            guard [file.url, file.from, file.text].compactMap({ $0 }).count == 1 else {
                throw ValidationError.invalid("file needs one of url, from or text")
            }
            if let value = file.url {
                guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()) else {
                    throw ValidationError.invalid("file URL must use http or https")
                }
            }
            for path in [file.to, file.from].compactMap({ $0 }) {
                guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
                      !path.split(separator: "\\").contains("..") else { throw ValidationError.invalid("invalid file path") }
            }
        }
    }

    public static func load(_ data: Data) throws -> CofreScenario {
        let value = try JSONDecoder().decode(Self.self, from: data); try value.validate(); return value
    }
}
