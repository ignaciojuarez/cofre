import Foundation
import CofreKit

/// Compatibility is computed by CofreKit. This small value keeps existing UI call sites source-compatible.
public struct ModCompatibility: Hashable, Sendable {
    public static func renderer(setting: String, gameVersion: String, loader: String) -> String {
        guard setting.lowercased() == "auto" else { return setting }
        if loader == "forge" || loader == "neoforge" { return "mobileglues" }
        return gameVersion == "1.21.11" || gameVersion.hasPrefix("26.") ? "metallum" : "air"
    }
    public let id: String, name: String
    private let supportedMetalVersions: Set<String>?
    private let reason: String
    private let isWarning: Bool
    public init(id: String, name: String, metalVersions: Set<String>?, reason: String, verified: Bool) { self.id=id; self.name=name; supportedMetalVersions=metalVersions; self.reason=reason; isWarning = !verified }
    public func issue(gameVersion: String, renderer: String) -> ModCompatibilityIssue? {
        guard renderer.lowercased().contains("metal") || renderer.lowercased().contains("metallum") else { return nil }
        if let versions = supportedMetalVersions, versions.contains(gameVersion) { return nil }
        return ModCompatibilityIssue(modID:id, modName:name, gameVersion:gameVersion, reason:reason)
    }
    public static func entry(for id: String, name: String? = nil) -> ModCompatibility? {
        let key = (name ?? id).lowercased().filter { $0.isLetter || $0.isNumber }
        if key.contains("iris") { return .init(id:id, name:name ?? "Iris", metalVersions:["26.2"], reason:"requires Iris integration; shipped only for Minecraft 26.2.", verified:true) }
        if key.contains("sodium") { return .init(id:id, name:name ?? "Sodium", metalVersions:["26.2","1.21.11"], reason:"requires Sodium integration unavailable for this Minecraft version.", verified:true) }
        if ["oculus","embeddium","distanthorizons","immersiveportals"].contains(key) { return .init(id:id,name:name ?? id,metalVersions:[],reason:"renderer integration is not present in the shipped manifest.",verified:false) }
        return nil
    }
}
public struct ModCompatibilityIssue: Hashable, Sendable {
    public let modID: String, modName: String, gameVersion: String, reason: String
    public var title: String { "\(modName) won't run on \(gameVersion) with Metal" }
    public var badge: String { "Not supported · Metal · \(gameVersion)" }
}
public enum ModLaunchDecision: Equatable, Sendable { case play, warn([ModCompatibilityIssue]) }
#if canImport(UIKit)
public enum ModCompatibilityChecker {
    public static func decision(items: [InstalledItem], gameVersion: String, renderer: String) -> ModLaunchDecision {
        let issues = items.filter { $0.enabled && $0.kind == .mods }.compactMap { item in ModCompatibility.entry(for:item.projectID ?? item.id,name:item.name)?.issue(gameVersion:gameVersion,renderer:renderer) }
        return issues.isEmpty ? .play : .warn(issues)
    }
}
#endif
