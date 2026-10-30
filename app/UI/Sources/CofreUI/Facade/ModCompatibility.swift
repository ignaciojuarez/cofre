import Foundation

/// Renderer compatibility facts used before installing and launching mods.
public struct ModCompatibility: Hashable, Sendable {
    public let id: String
    public let name: String
    public let metalVersions: Set<String>?
    public let reason: String
    public let verified: Bool

    public init(id: String, name: String, metalVersions: Set<String>?, reason: String, verified: Bool) {
        self.id = id; self.name = name; self.metalVersions = metalVersions; self.reason = reason; self.verified = verified
    }

    public func issue(gameVersion: String, renderer: String) -> ModCompatibilityIssue? {
        let metal = renderer.lowercased().contains("metal") || renderer.lowercased().contains("metallum")
        guard metal, metalVersions != nil, metalVersions?.contains(gameVersion) != true else { return nil }
        return ModCompatibilityIssue(modID: id, modName: name, gameVersion: gameVersion, reason: reason)
    }

    public static let table: [ModCompatibility] = [
        .init(id: "iris", name: "Iris", metalVersions: ["26.2"], reason: "Iris needs OpenGL; Metallum ships Iris support only for Minecraft 26.2.", verified: true),
        .init(id: "sodium", name: "Sodium", metalVersions: ["26.2", "1.21.11"], reason: "Metallum ships Sodium support only for these versions.", verified: true),
        .init(id: "oculus", name: "Oculus", metalVersions: nil, reason: "Oculus is an OpenGL shader renderer and has no verified Metallum support.", verified: false),
        .init(id: "embeddium", name: "Embeddium", metalVersions: nil, reason: "Embeddium is an OpenGL renderer and has no verified Metallum support.", verified: false),
        .init(id: "distant-horizons", name: "Distant Horizons", metalVersions: nil, reason: "Distant Horizons draws with raw OpenGL, which Metal cannot provide.", verified: true),
        .init(id: "immersive-portals", name: "Immersive Portals", metalVersions: nil, reason: "Immersive Portals uses OpenGL paths; Metallum support is unverified.", verified: false),
    ]

    public static func entry(for id: String, name: String? = nil) -> ModCompatibility? {
        let key = id.lowercased()
        let normalized: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        return table.first { $0.id == key } ?? table.first { entry in name.map { normalized($0) == normalized(entry.name) } ?? false }
    }
}

public struct ModCompatibilityIssue: Hashable, Sendable {
    public let modID: String, modName: String, gameVersion: String, reason: String
    public var title: String { "(modName) doesn't run on (gameVersion) with Metal" }
    public var badge: String { "Not on Metal · (gameVersion)" }
}

public enum ModLaunchDecision: Equatable, Sendable { case play, warn([ModCompatibilityIssue]) }

#if canImport(UIKit)
public enum ModCompatibilityChecker {
    public static func decision(items: [InstalledItem], gameVersion: String, renderer: String) -> ModLaunchDecision {
        let issues = items.filter { $0.enabled && $0.kind == .mods }.compactMap { item in
            ModCompatibility.entry(for: item.projectID ?? item.id, name: item.name)?.issue(gameVersion: gameVersion, renderer: renderer)
        }
        return issues.isEmpty ? .play : .warn(issues)
    }
}
#endif
