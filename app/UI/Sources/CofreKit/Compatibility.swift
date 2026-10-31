import Foundation

public struct RendererManifest: Codable, Sendable, Hashable {
    public var renderer: String
    public var engineRevision: String
    public var artifactSHA256: String
    public var gameVersions: Set<String>
    public var integrations: [String: Set<String>]
    public var features: Set<String>
    public var limits: [String: Int]
    public init(renderer: String = "Metal", engineRevision: String = "", artifactSHA256: String = "", gameVersions: Set<String> = [], integrations: [String: Set<String>] = [:], features: Set<String> = [], limits: [String: Int] = [:]) { self.renderer = renderer; self.engineRevision = engineRevision; self.artifactSHA256 = artifactSHA256; self.gameVersions = gameVersions; self.integrations = integrations; self.features = features; self.limits = limits }
    public static func load(from url: URL) throws -> RendererManifest { try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
}
/// One decision for engine launch, compatibility checks, and renderer display.
public enum RendererPolicy {
    public static func resolve(profile: [String: Any], metadata: [String: Any], globalSetting: String,
                               fallbackLoader: Instance.Loader? = nil, metalVersions: Set<String>) -> RendererID {
        let versionID = profile["lastVersionId"] as? String ?? metadata["id"] as? String ?? ""
        let libraries = (metadata["libraries"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let loader = Instance.Loader.resolve(requested: profile[Instance.Loader.requestedProfileKey] as? String,
            legacy: profile["loader"] as? String ?? metadata["loader"] as? String,
            versionID: versionID, libraries: libraries, fallback: fallbackLoader)
        let game = metadata["inheritsFrom"] as? String ?? profile["cofreGameVersion"] as? String ?? metadata["id"] as? String ?? ""
        let picked = profile["cofreRendererPicked"] as? Bool ?? false
        return airIdentifier(resolve(setting: picked ? .auto : RendererID(rawValue: profile["renderer"] as? String ?? "auto"),
            globalSetting: RendererID(rawValue: globalSetting), gameVersion: game, loader: loader,
            metalVersions: metalVersions))
    }

    public static func resolve(setting: RendererID, globalSetting: RendererID = .auto, gameVersion: String,
                               loader: Instance.Loader, metalVersions: Set<String>) -> RendererID {
        let fallback = automatic(gameVersion: gameVersion, loader: loader)
        // Metallum is attached by Air only for a vanilla version id. A loader's
        // version id cannot use it, even when the base Minecraft version is in
        // the Metal manifest.
        if setting != .auto { return isMetal(setting) && loader != .vanilla ? fallback : setting }
        if globalSetting != .auto { return isMetal(globalSetting) && loader != .vanilla ? fallback : globalSetting }
        // Air only attaches the bundled Metallum agent for Minecraft 26+.
        let major = Int(gameVersion.prefix(while: { $0.isNumber })) ?? 0
        if loader == .vanilla && major >= 26 && metalVersions.contains(gameVersion) { return .metallum }
        return fallback
    }

    /// The GL renderer Cofre uses when Metal is unavailable or Auto has no
    /// manifest-backed vanilla Metal choice.
    private static func automatic(gameVersion: String, loader: Instance.Loader) -> RendererID {
        // Air's `auto` path is ANGLE. That is a poor default for current
        // Minecraft on iOS: it is the path that produced
        // GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT on the iPhone 17 Pro. Use the
        // explicit MobileGlues path for modern 1.20.5+ releases (and for
        // Forge/NeoForge), so Auto actually selects the renderer Cofre tests.
        let numbers = gameVersion.split(separator: ".").compactMap { Int($0) }
        let modern = (numbers.first ?? 0) >= 26 ||
            (numbers.count >= 3 && numbers[0] == 1 &&
                (numbers[1] > 20 || (numbers[1] == 20 && numbers[2] >= 5)))
        return modern || loader == .forge || loader == .neoforge ? .mobileglues : .air
    }

    /// Renderer ids from old profiles may be Air library names rather than
    /// the typed `metallum` value.
    public static func isMetal(_ renderer: RendererID) -> Bool {
        switch renderer {
        case .metallum: true
        case .custom(let value): value.lowercased().contains("metallum") || value.lowercased() == "metal"
        default: false
        }
    }

    public static func resolve(setting: String, globalSetting: String = "auto", gameVersion: String,
                               loader: Instance.Loader, metalVersions: Set<String>) -> String {
        resolve(setting: RendererID(rawValue: setting), globalSetting: RendererID(rawValue: globalSetting),
                 gameVersion: gameVersion, loader: loader, metalVersions: metalVersions).rawValue
    }

    public static func airIdentifier(_ renderer: RendererID) -> RendererID {
        switch renderer {
        case .metallum: .custom("libmetallum.dylib")
        case .mobileglues: .custom("libmobileglues.dylib")
        case .air, .auto: .auto
        default: renderer
        }
    }

    public static func airIdentifier(_ renderer: String) -> String {
        airIdentifier(RendererID(rawValue: renderer)).rawValue
    }
}

/// A mod or shader pack that won't run with the renderer an instance uses.
public struct CompatibilityIssue: Hashable, Sendable {
    public let modID: String, modName: String, gameVersion: String, reason: String
    public var kind: ContentKind
    /// The renderer as people know it: "Metal" or "MobileGlues".
    public var renderer: String
    /// The file to turn off, when the issue came from the instance's folder.
    public var file: String?
    public init(modID: String, modName: String, gameVersion: String, reason: String, kind: ContentKind = .mods,
                renderer: String = "Metal", file: String? = nil) {
        self.modID = modID; self.modName = modName; self.gameVersion = gameVersion; self.reason = reason
        self.kind = kind; self.renderer = renderer; self.file = file
    }
    public var title: String { kind == .shaders ? "Shaders don't run here" : "\(modName) doesn't run here" }
    public var badge: String { "Not on \(renderer) · \(gameVersion)" }
}

/// Which mods and shader packs can't run with an instance's renderer. Metal
/// runs vanilla only for now; shader packs on MobileGlues fail at pipeline
/// creation (ES 3.0 via ANGLE: "Draw buffers … Status: 36054"), though
/// MobileGlues reports OpenGL 4.0 so Iris's own check passes.
public enum ContentCompatibility {
    public static func rendererName(_ renderer: String) -> String? {
        let r = renderer.lowercased()
        return r.contains("metal") ? "Metal" : r.contains("mobileglues") ? "MobileGlues" : nil
    }

    /// The Metallum integration a mod needs (`iris`, `sodium`) and the versions it ships for. `mixin` is
    /// Metallum's own package, not a mod.
    public static func integration(for name: String, _ manifest: RendererManifest) -> (name: String, versions: Set<String>)? {
        let key = normalized(name)
        guard !key.isEmpty else { return nil }
        return manifest.integrations.filter { $0.key != "mixin" }.sorted { $0.key < $1.key }
            .first { key.contains(normalized($0.key)) }.map { ($0.key, $0.value) }
    }

    public static func issue(id: String, name: String, kind: ContentKind, gameVersion: String, renderer: String,
                             manifest: RendererManifest) -> CompatibilityIssue? {
        guard let shown = rendererName(renderer) else { return nil }
        let label = name.isEmpty ? id : name
        func make(_ reason: String, as name: String = label) -> CompatibilityIssue {
            CompatibilityIssue(modID: id, modName: name, gameVersion: gameVersion, reason: reason, kind: kind, renderer: shown)
        }
        switch (kind, shown) {
        case (.mods, "Metal"):
            guard let found = integration(for: name, manifest) ?? integration(for: id, manifest) else { return nil }
            // Named after the integration: a file name like "iris-fabric-1.8.0+mc26.3" reads badly in a title.
            return make("Metal runs vanilla only for now.", as: found.name.capitalized)
        case (.shaders, "Metal"):
            return make("Metal runs vanilla only for now.")
        case (.shaders, "MobileGlues"):
            return make("On MobileGlues, shader packs fail to start and Iris turns them off.")
        default: return nil
        }
    }

    /// The Play-time check: enabled mods, and the shader pack the game has on.
    public static func playIssues(gameDirectory: URL, gameVersion: String, renderer: String,
                                  manifest: RendererManifest) -> [CompatibilityIssue] {
        let store = ContentStore(gameDirectory: gameDirectory)
        let mods = ((try? store.list(.mods)) ?? []).filter(\.enabled)
        var out = mods.compactMap { m in
            issue(id: m.id, name: m.name, kind: .mods, gameVersion: gameVersion, renderer: renderer, manifest: manifest)
                .map { var i = $0; i.file = m.id; return i }
        }
        // A pack only runs with a shader mod on; if that mod is already flagged, turning it off covers the pack.
        let shaderMods = (ShaderSwitch.files.map { ($0 as NSString).deletingPathExtension } + ["optifine"])
        let shaderMod = mods.first { m in shaderMods.contains { normalized(m.name).hasPrefix($0) } }
        if let shaderMod, !out.contains(where: { $0.file == shaderMod.id }),
            let pack = ((try? store.list(.shaders)) ?? []).first(where: \.inUse),
            var i = issue(id: pack.id, name: pack.name, kind: .shaders, gameVersion: gameVersion, renderer: renderer, manifest: manifest) {
            i.file = pack.id
            out.append(i)
        }
        return out
    }

    /// "Turn off and play": flagged mods get `.disabled`, flagged shaders go off in the shader mod's own switch.
    public static func turnOff(_ issues: [CompatibilityIssue], gameDirectory: URL) throws {
        let store = ContentStore(gameDirectory: gameDirectory)
        let mods = try store.list(.mods)
        for issue in issues {
            if issue.kind == .shaders { try ShaderSwitch.turnOff(in: gameDirectory); continue }
            if let item = mods.first(where: { $0.enabled && $0.id == issue.file }) { try store.setEnabled(false, item) }
        }
    }

    private static func normalized(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
}
