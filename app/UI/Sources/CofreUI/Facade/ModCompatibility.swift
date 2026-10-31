import Foundation
import CofreKit

public typealias ModCompatibilityIssue = CompatibilityIssue

/// Compatibility is computed by CofreKit (`ContentCompatibility`). This small value keeps existing UI call sites
/// source-compatible.
public struct ModCompatibility: Hashable, Sendable {
    /// The renderer an instance runs, using the same policy as the launch path.
    public static func renderer(
        instanceSetting: RendererID? = nil, globalSetting: RendererID = .auto, gameVersion: String,
        loader: Instance.Loader, javaVersion: Int = 21, metalMod: Bool = false
    ) -> RendererID {
        let metal = javaVersion >= 21 ? metalVersions : []
        return RendererPolicy.resolve(setting: instanceSetting ?? .auto, globalSetting: globalSetting, gameVersion: gameVersion,
            loader: loader, metalVersions: metal, metalMod: metalMod)
    }

    public static func renderer(
        instanceSetting: String? = nil, globalSetting: String, gameVersion: String, loader: String,
        javaVersion: Int = 21, metalMod: Bool = false
    ) -> String {
        renderer(
            instanceSetting: instanceSetting.map(RendererID.init(rawValue:)), globalSetting: RendererID(rawValue: globalSetting),
            gameVersion: gameVersion, loader: Instance.Loader(rawValue: loader.lowercased()) ?? .unknown,
            javaVersion: javaVersion, metalMod: metalMod
        ).rawValue
    }
    /// Compatibility overload for callers that only have one setting.
    public static func renderer(setting: String, gameVersion: String, loader: String) -> String {
        renderer(instanceSetting: setting, globalSetting: "auto", gameVersion: gameVersion, loader: loader)
    }
    public static func renderer(setting: RendererID, gameVersion: String, loader: Instance.Loader) -> RendererID {
        renderer(instanceSetting: setting, globalSetting: .auto, gameVersion: gameVersion, loader: loader)
    }
    /// The exact shipped Metallum manifest, read once. Previews and tests may replace it.
    nonisolated(unsafe) public static var manifest: RendererManifest =
        (Bundle.main.url(forResource: "RendererManifest", withExtension: "json").flatMap { try? RendererManifest.load(from: $0) }) ?? RendererManifest()
    /// Versions supported by the exact shipped Metallum manifest. No version family is inferred here.
    nonisolated(unsafe) public static var metalVersions: Set<String> = manifest.gameVersions
    /// A project or installed file with the renderer an instance runs.
    public static func issue(id: String, name: String, kind: ContentKind, gameVersion: String, renderer: String) -> ModCompatibilityIssue? {
        ContentCompatibility.issue(id: id, name: name, kind: kind, gameVersion: gameVersion, renderer: renderer, manifest: manifest)
    }
    public static func issue(id: String, name: String, kind: ContentKind, gameVersion: String, renderer: RendererID) -> ModCompatibilityIssue? {
        issue(id: id, name: name, kind: kind, gameVersion: gameVersion, renderer: renderer.rawValue)
    }
    public let id: String, name: String
    private let supportedMetalVersions: Set<String>?
    private let reason: String
    private let isWarning: Bool
    public init(id: String, name: String, metalVersions: Set<String>?, reason: String, verified: Bool) { self.id=id; self.name=name; supportedMetalVersions=metalVersions; self.reason=reason; isWarning = !verified }
    public func issue(gameVersion: String, renderer: String) -> ModCompatibilityIssue? {
        guard ContentCompatibility.rendererName(renderer) == "Metal" else { return nil }
        return ModCompatibilityIssue(modID:id, modName:name, gameVersion:gameVersion, reason:reason)
    }
    public func issue(gameVersion: String, renderer: RendererID) -> ModCompatibilityIssue? {
        issue(gameVersion: gameVersion, renderer: renderer.rawValue)
    }
    public static func entry(for id: String, name: String? = nil) -> ModCompatibility? {
        guard let found = ContentCompatibility.integration(for: name ?? id, manifest) else { return nil }
        let label = name ?? id
        return .init(id: id, name: label, metalVersions: found.versions,
                     reason: found.name == "iris" ? ContentCompatibility.irisOnMetal
                        : "Metal runs this mod only on Fabric 26.2 for now.", verified: true)
    }
}
public enum ModLaunchDecision: Equatable, Sendable { case play, warn([ModCompatibilityIssue]) }
#if canImport(UIKit)
public enum ModCompatibilityChecker {
    public static func decision(items: [InstalledItem], gameVersion: String, renderer: String) -> ModLaunchDecision {
        let issues = items.filter { $0.enabled && ($0.kind == .mods || ($0.kind == .shaders && $0.inUse)) }.compactMap { item in
            ModCompatibility.issue(id: item.projectID ?? item.id, name: item.name, kind: item.kind, gameVersion: gameVersion, renderer: renderer)
        }
        return issues.isEmpty ? .play : .warn(issues)
    }
    public static func decision(items: [InstalledItem], gameVersion: String, renderer: RendererID) -> ModLaunchDecision {
        decision(items: items, gameVersion: gameVersion, renderer: renderer.rawValue)
    }
}
#endif
