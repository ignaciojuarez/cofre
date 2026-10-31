import Foundation

/// How a quick-tray chord behaves while its tile is touched.
public enum QuickTrayMode: String, CaseIterable, Codable, Hashable, Sendable {
    case tap, hold, toggle
}

/// A user-facing key chord. IDs are stable so saved trays survive catalog changes.
public struct QuickTrayAction: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var keys: [CofreInputKey]
    public var mode: QuickTrayMode

    public init(id: String = UUID().uuidString, label: String, keys: [CofreInputKey], mode: QuickTrayMode = .tap) {
        self.id = id
        self.label = String(label.prefix(8))
        self.keys = Array(keys.prefix(3))
        self.mode = mode
    }

    var keyHint: String { keys.map(\.rawValue).joined(separator: "+") }
    var glyph: OverlayGlyph {
        switch id {
        case "view": .eye
        case "players": .players
        case "swap": .swap
        case "hud": .hide
        case "keyboard": .keyboard
        case "drop": .drop
        case "pause": .pause
        default: .keyboard
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.keys == rhs.keys && lhs.mode == rhs.mode
    }
}

public enum QuickTrayCatalog {
    public static let common: [QuickTrayAction] = [
        QuickTrayAction(id: "drop", label: "Drop", keys: [.drop]),
        QuickTrayAction(id: "screenshot", label: "Shot", keys: [.f2]),
        QuickTrayAction(id: "swap", label: "Swap", keys: [.swapHands]),
        QuickTrayAction(id: "view", label: "View", keys: [.f5]),
        QuickTrayAction(id: "players", label: "Players", keys: [.tab], mode: .hold),
        QuickTrayAction(id: "hud", label: "Hide HUD", keys: [.f1]),
        QuickTrayAction(id: "keyboard", label: "Keys", keys: []),
    ]
    public static let debug: [QuickTrayAction] = [
        QuickTrayAction(id: "debug", label: "Debug F3", keys: [.f3]),
        QuickTrayAction(id: "chunks", label: "Chunks", keys: [.f3, .g]),
    ]
    public static let all: [QuickTrayAction] = common + debug

    public static func action(id: String) -> QuickTrayAction? { all.first { $0.id == id } }

    public static var defaults: [QuickTrayAction?] {
        [
            action(id: "view"), action(id: "players"), action(id: "swap"), action(id: "hud"), action(id: "debug"),
            action(id: "keyboard"),
        ]
    }
}

/// Global quick-tray configuration. The two fixed tiles (Pause and Edit) are not stored here.
public struct QuickTraySettings: Codable, Equatable, Sendable {
    public var slots: [QuickTrayAction?]
    public var custom: [QuickTrayAction]
    static let key = "cofre.touch.quick-tray"

    public init(slots: [QuickTrayAction?] = QuickTrayCatalog.defaults, custom: [QuickTrayAction] = []) {
        self.slots = Array(slots.prefix(6)) + Array(repeating: nil, count: max(0, 6 - slots.count))
        self.custom = custom
    }

    private enum CodingKeys: String, CodingKey { case slots, custom }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            slots: try c.decodeIfPresent([QuickTrayAction?].self, forKey: .slots) ?? QuickTrayCatalog.defaults,
            custom: try c.decodeIfPresent([QuickTrayAction].self, forKey: .custom) ?? [])
    }

    public static func load(_ defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key) else { return Self() }
        if let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        // Early previews stored only an array of catalog IDs. Keep those slots when possible.
        if let ids = try? JSONDecoder().decode([String].self, from: data) {
            return Self(slots: ids.prefix(6).map { QuickTrayCatalog.action(id: $0) })
        }
        return Self()
    }

    public func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    public mutating func reset() {
        slots = QuickTrayCatalog.defaults
        if slots.count < 6 { slots += Array(repeating: nil, count: 6 - slots.count) }
    }

    public mutating func remove(at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = nil
    }

    public mutating func move(from index: Int, by offset: Int) {
        let target = index + offset
        guard slots.indices.contains(index), slots.indices.contains(target), index != target else { return }
        slots.swapAt(index, target)
    }
}
