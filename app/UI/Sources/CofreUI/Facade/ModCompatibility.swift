import Foundation
import CofreKit

/// Compatibility is computed by CofreKit. This small value keeps existing UI call sites source-compatible.
public struct ModCompatibility: Hashable, Sendable {
    /// The renderer an instance runs, decided like the launch does (AirBridgeAdapter pickRendererForProfile): Auto is
    /// Metal where the bundled Metallum supports the version and Java 21+, MobileGlues for Forge/NeoForge elsewhere, else Air's GL.
    public static func renderer(instanceSetting: String? = nil, globalSetting: String, gameVersion: String, loader: String, javaVersion: Int = 21) -> String {
        let setting = instanceSetting.flatMap { $0.isEmpty || $0 == "auto" ? nil : $0 } ?? globalSetting
        guard setting.isEmpty || setting == "auto" else { return setting }
        if (javaVersion <= 0 || javaVersion >= 21) && metalVersions.contains(gameVersion) { return "metallum" }
        return loader == "forge" || loader == "neoforge" ? "mobileglues" : "air"
    }
    /// Versions supported by the exact shipped Metallum manifest. No version family is inferred here.
    nonisolated(unsafe) public static var metalVersions: Set<String> =
        ((Bundle.main.url(forResource: "RendererManifest", withExtension: "json")
            .flatMap { try? RendererManifest.load(from: $0) })?.gameVersions ?? [])
    public static var manifest: RendererManifest {
        (Bundle.main.url(forResource: "RendererManifest", withExtension: "json").flatMap { try? RendererManifest.load(from: $0) }) ?? RendererManifest()
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
        let integrations = manifest.integrations
        guard let integration = integrations.keys.first(where: { key.contains($0.filter { $0.isLetter || $0.isNumber }) || $0.contains(key) }) else { return nil }
        let versions = integrations[integration] ?? []
        let label = name ?? id
        let reason = "\(label) has no shipped \(integration.capitalized) integration for this Minecraft version."
        return .init(id: id, name: label, metalVersions: versions, reason: reason, verified: true)
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
