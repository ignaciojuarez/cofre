import Foundation

/// Values that cross the launcher/Air boundary. Their string form is the
/// existing profile, preference, or JSON spelling.
public enum RendererID: Hashable, Codable, RawRepresentable, Sendable, Identifiable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    case auto, metallum, mobileglues, zink, ltw, krypton, angle, gl4es, simpleFPEWrapper, air
    case custom(String)

    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "", "auto": self = .auto
        case "metallum", "metal": self = .metallum
        case "mobileglues": self = .mobileglues
        case "zink": self = .zink
        case "ltw": self = .ltw
        case "krypton": self = .krypton
        case "angle": self = .angle
        case "gl4es": self = .gl4es
        case "simplefpewrapper": self = .simpleFPEWrapper
        case "air": self = .air
        default: self = .custom(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .auto: "auto"
        case .metallum: "metallum"
        case .mobileglues: "mobileglues"
        case .zink: "zink"
        case .ltw: "ltw"
        case .krypton: "krypton"
        case .angle: "angle"
        case .gl4es: "gl4es"
        case .simpleFPEWrapper: "simplefpewrapper"
        case .air: "air"
        case .custom(let value): value
        }
    }
    public var id: String { rawValue }
    public var description: String { rawValue }
    /// Mojang's Vulkan backend through MoltenVK (Air's `libMoltenVK.dylib`).
    public static let vulkan = Self.custom("vulkan")
    public static var allCases: [Self] {
        [.auto, .metallum, .mobileglues, .zink, .ltw, .krypton, .angle, .gl4es, .simpleFPEWrapper, .air]
    }
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum GraphicsAPI: Hashable, Codable, RawRepresentable, Sendable, Identifiable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    case auto, metal, opengl, vulkan
    case custom(String)

    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "", "auto": self = .auto
        case "metal": self = .metal
        case "opengl", "gles": self = .opengl
        case "vulkan": self = .vulkan
        default: self = .custom(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .auto: "auto"
        case .metal: "metal"
        case .opengl: "opengl"
        case .vulkan: "vulkan"
        case .custom(let value): value
        }
    }
    public var id: String { rawValue }
    public var description: String { rawValue }
    public static var allCases: [Self] { [.auto, .metal, .opengl, .vulkan] }
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum JavaRuntimeID: Hashable, Codable, RawRepresentable, Sendable, Identifiable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    case auto, java8, java17, java21, java25
    case custom(String)

    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "", "auto": self = .auto
        case "8", "java8", "java-8": self = .java8
        case "17", "java17", "java-17": self = .java17
        case "21", "java21", "java-21": self = .java21
        case "25", "java25", "java-25": self = .java25
        default: self = .custom(rawValue)
        }
    }
    public var rawValue: String {
        switch self {
        case .auto: "auto"
        case .java8: "8"
        case .java17: "17"
        case .java21: "21"
        case .java25: "25"
        case .custom(let value): value
        }
    }
    public var id: String { rawValue }
    public var description: String { rawValue }
    public var major: Int? {
        switch self {
        case .auto: nil
        case .java8: 8
        case .java17: 17
        case .java21: 21
        case .java25: 25
        case .custom: Int(rawValue)
        }
    }
    public static var allCases: [Self] { [.auto, .java8, .java17, .java21, .java25] }
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Release stability from Modrinth/CurseForge. Unknown labels keep the old
/// fail-safe behavior and are treated as releases.
public enum VersionChannel: String, Codable, CaseIterable, Comparable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
{
    case release, beta, alpha
    public init(stringLiteral value: String) { self.init(value) }
    public init(_ raw: String?) {
        switch raw?.lowercased() {
        case "beta": self = .beta
        case "alpha": self = .alpha
        default: self = .release
        }
    }
    public var raw: String { rawValue }
    public var description: String { rawValue }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue == rhs.rawValue ? false : order(lhs) < order(rhs)
    }
    private static func order(_ value: Self) -> Int {
        switch value {
        case .release: 0
        case .beta: 1
        case .alpha: 2
        }
    }
    public func allowsUpdate(to newer: Self) -> Bool { newer <= self }
    public var updateChannels: [Self] { Self.allCases.filter { allowsUpdate(to: $0) } }
    public var label: String {
        switch self {
        case .release: String(localized: "Release")
        case .beta: String(localized: "Beta")
        case .alpha: String(localized: "Alpha")
        }
    }
}

/// Keys owned by Cofre's UserDefaults store. Dynamic keys keep their exact
/// legacy spelling through `rawValue`.
public enum PreferenceKey: Hashable, Sendable {
    case setupCompleted, setupStep, modsInstance, inputMode, rejoinIntent
    case renderScale, resolutionDefaulted, memoryDefaultApplied, downloadSourceDefaulted
    case optionsBefore(String)
    case slowModsNotice(String)
    case launchStarted(String)
    case gameSession
    case distancesSeeded(String)
    case serverCard(String)
    case modsIdentities
    case modsIndex(String)
    case updateETag, dismissedUpdate, quickTray, touchSettings, downloadsCellular
    case setupJIT

    public var rawValue: String {
        switch self {
        case .setupCompleted: "cofre.setup.completed"
        case .setupStep: "cofre.setup.step"
        case .modsInstance: "cofre.mods.instance"
        case .inputMode: "cofre.input.mode"
        case .rejoinIntent: "cofre.rejoin.intent"
        case .renderScale: "cofre.render.scale"
        case .resolutionDefaulted: "cofre.resolution.defaulted"
        case .memoryDefaultApplied: "cofre.memory_default_applied"
        case .downloadSourceDefaulted: "cofre.download_source_defaulted"
        case .optionsBefore(let id): "cofre.options.before.\(id)"
        case .slowModsNotice(let id): "cofre.slow-mods-notice.\(id)"
        case .launchStarted(let id): "cofre.launch.started.\(id)"
        case .gameSession: "cofre.game.session"
        case .distancesSeeded(let id): "cofre.options.distances-seeded.\(id)"
        case .serverCard(let host): "cofre.server-card.\(host)"
        case .modsIdentities: "cofre.mods.identities"
        case .modsIndex(let id): "cofre.mods.index.\(id)"
        case .updateETag: "cofre.update.etag"
        case .dismissedUpdate: "cofre.dismissedUpdate"
        case .quickTray: "cofre.touch.quick-tray"
        case .touchSettings: "cofre.touch.settings"
        case .downloadsCellular: "cofre.downloads.cellular"
        case .setupJIT: "cofre.setup.jit"
        }
    }
}
