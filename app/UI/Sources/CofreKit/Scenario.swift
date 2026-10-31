import Foundation

/// A small, Codable description of a repeatable debug launch.
public struct CofreScenario: Codable, Equatable, Sendable {
    public let name: String
    public let version: String?
    public let loader: Instance.Loader
    public let loaderVersion: String?
    public let mods: [String]
    public let pack: String?
    public let packVersion: String?
    public let renderer: RendererID
    public let resolution: Double
    public let memoryMB: Int?
    public let launch: Bool
    public let fresh: Bool

    enum CodingKeys: String, CodingKey { case name, version, loader, loaderVersion, mods, pack, packVersion, renderer, resolution, memoryMB, launch, fresh }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name); version = try c.decodeIfPresent(String.self, forKey: .version)
        loader = Instance.Loader(rawValue: (try c.decodeIfPresent(String.self, forKey: .loader) ?? "vanilla").lowercased()) ?? .unknown
        loaderVersion = try c.decodeIfPresent(String.self, forKey: .loaderVersion)
        mods = try c.decodeIfPresent([String].self, forKey: .mods) ?? []; pack = try c.decodeIfPresent(String.self, forKey: .pack); packVersion = try c.decodeIfPresent(String.self, forKey: .packVersion)
        renderer = RendererID(rawValue: try c.decodeIfPresent(String.self, forKey: .renderer) ?? "auto")
        resolution = try c.decodeIfPresent(Double.self, forKey: .resolution) ?? 1
        memoryMB = try c.decodeIfPresent(Int.self, forKey: .memoryMB); launch = try c.decodeIfPresent(Bool.self, forKey: .launch) ?? true; fresh = try c.decodeIfPresent(Bool.self, forKey: .fresh) ?? false
    }

    public init(name: String, version: String? = nil, loader: Instance.Loader = .vanilla, loaderVersion: String? = nil,
                mods: [String] = [], pack: String? = nil, packVersion: String? = nil, renderer: RendererID = .auto,
                resolution: Double = 1, memoryMB: Int? = nil, launch: Bool = true, fresh: Bool = false) {
        self.name = name; self.version = version; self.loader = loader; self.loaderVersion = loaderVersion
        self.mods = mods; self.pack = pack; self.packVersion = packVersion; self.renderer = renderer
        self.resolution = resolution; self.memoryMB = memoryMB; self.launch = launch; self.fresh = fresh
    }

    public init(name: String, version: String? = nil, loader: String, loaderVersion: String? = nil,
                mods: [String] = [], pack: String? = nil, packVersion: String? = nil, renderer: String = "auto",
                resolution: Double = 1, memoryMB: Int? = nil, launch: Bool = true, fresh: Bool = false) {
        self.init(name: name, version: version, loader: Instance.Loader(rawValue: loader.lowercased()) ?? .unknown,
                  loaderVersion: loaderVersion, mods: mods, pack: pack, packVersion: packVersion,
                  renderer: RendererID(rawValue: renderer), resolution: resolution, memoryMB: memoryMB,
                  launch: launch, fresh: fresh)
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
    }

    public static func load(_ data: Data) throws -> CofreScenario {
        let value = try JSONDecoder().decode(Self.self, from: data); try value.validate(); return value
    }
}
