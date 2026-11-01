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
#if DEBUG
    /// Device scenarios may exercise Metal on a loader instance without changing normal policy.
    public static var allowMetalForModdedScenario = false
#endif

    /// The production picker. Other IDs remain valid for old profiles, but are
    /// only shown when one of them is already selected.
    public static let normalPickerRenderers: [RendererID] = [
        .auto, .metallum, .mobileglues, .zink, .gl4es, .simpleFPEWrapper, .angle,
    ]

    /// `gameDirectory` lets a validated Fabric or NeoForge kit run Metal.
    public static func resolve(profile: [String: Any], metadata: [String: Any], globalSetting: String,
                               fallbackLoader: Instance.Loader? = nil, gameDirectory: URL? = nil,
                               metalVersions: Set<String>) -> RendererID {
        let versionID = profile["lastVersionId"] as? String ?? metadata["id"] as? String ?? ""
        let libraries = (metadata["libraries"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let loader = Instance.Loader.resolve(requested: profile[Instance.Loader.requestedProfileKey] as? String,
            legacy: profile["loader"] as? String ?? metadata["loader"] as? String,
            versionID: versionID, libraries: libraries, fallback: fallbackLoader)
        let game = metadata["inheritsFrom"] as? String ?? profile["cofreGameVersion"] as? String ?? metadata["id"] as? String ?? ""
        let picked = profile["cofreRendererPicked"] as? Bool ?? false
        let metalMod = MetalMod.supports(gameVersion: game, loader: loader)
            && gameDirectory.map { MetalMod.isEnabled(in: $0, loader: loader) } == true
        return airIdentifier(resolve(setting: picked ? .auto : RendererID(rawValue: profile["renderer"] as? String ?? "auto"),
            globalSetting: RendererID(rawValue: globalSetting), gameVersion: game, loader: loader,
            metalVersions: metalVersions, metalMod: metalMod))
    }

    /// `metalMod`: the instance has MetalUniversal enabled in its mods folder.
    public static func resolve(setting: RendererID, globalSetting: RendererID = .auto, gameVersion: String,
                               loader: Instance.Loader, metalVersions: Set<String>, metalMod: Bool = false) -> RendererID {
        let fallback = automatic(gameVersion: gameVersion, loader: loader)
        // Air attaches its Metallum agent only for a vanilla version id. A loader
        // runs Metal only through MetalUniversal, on the versions it was validated on.
        let modMetal = metalMod && MetalMod.supports(gameVersion: gameVersion, loader: loader)
        func allowed(_ choice: RendererID) -> RendererID {
#if DEBUG
            if allowMetalForModdedScenario && isMetal(choice) && loader != .vanilla { return choice }
#endif
            return isMetal(choice) && loader != .vanilla && !modMetal ? fallback : choice
        }
        if setting != .auto { return allowed(setting) }
        if globalSetting != .auto { return allowed(globalSetting) }
        if metalAvailable(gameVersion: gameVersion, loader: loader, metalVersions: metalVersions, metalMod: metalMod) {
            return .metallum
        }
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
        if isLegacy(gameVersion) { return .gl4es }
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

    /// Vanilla: Air's agent on manifest versions. Fabric: MetalUniversal on its validated versions.
    public static func metalAvailable(gameVersion: String, loader: Instance.Loader,
                                      metalVersions: Set<String>, metalMod: Bool = false) -> Bool {
        loader == .vanilla ? metalVersions.contains(gameVersion)
            : metalMod && MetalMod.supports(gameVersion: gameVersion, loader: loader)
    }

    public static func isLegacy(_ gameVersion: String) -> Bool {
        let numbers = gameVersion.split(separator: ".").compactMap { Int($0) }
        guard numbers.count >= 2, numbers[0] == 1 else { return false }
        let patch = numbers.count > 2 ? numbers[2] : 0
        return numbers[1] < 16 || (numbers[1] == 16 && patch <= 5)
    }

    /// IDs to render in Settings for this instance. `current` is retained so
    /// a saved debug/legacy choice is visible instead of being changed.
    public static func pickerRenderers(gameVersion: String? = nil, loader: Instance.Loader? = nil,
                                       metalVersions: Set<String> = [], metalMod: Bool = false,
                                       current: RendererID? = nil) -> [RendererID] {
        var ids = normalPickerRenderers
        if let gameVersion {
            if !isLegacy(gameVersion) { ids.removeAll { $0 == .gl4es || $0 == .simpleFPEWrapper } }
            if let loader, !metalAvailable(gameVersion: gameVersion, loader: loader, metalVersions: metalVersions,
                                           metalMod: metalMod) {
                ids.removeAll { $0 == .metallum }
            } else if loader == .vanilla {
                // Air attaches its Metal agent to every manifest vanilla version whatever the choice,
                // so only MobileGlues stays as the fallback for a Metal driver crash.
                ids.removeAll { $0 == .zink || $0 == .angle }
            }
        }
        if let current, !ids.contains(where: { sameRenderer($0, current) }) { ids.append(current) }
        return ids
    }

    public static func recommendedRenderer(gameVersion: String, loader: Instance.Loader,
                                           metalVersions: Set<String>, metalMod: Bool = false) -> RendererID {
        let resolved = resolve(setting: .auto, gameVersion: gameVersion, loader: loader, metalVersions: metalVersions,
                               metalMod: metalMod)
        return resolved == .air ? .angle : canonical(resolved)
    }

    /// Compare canonical IDs so old profiles containing dylib names still
    /// match the typed picker IDs.
    public static func sameRenderer(_ lhs: RendererID, _ rhs: RendererID) -> Bool {
        key(lhs) == key(rhs)
    }

    public static func canonical(_ renderer: RendererID) -> RendererID {
        RendererID(rawValue: key(renderer))
    }

    public static func displayName(_ renderer: RendererID) -> String {
        switch key(renderer) {
        case "auto": "Auto"
        case "metallum": "Metal"
        case "mobileglues": "MobileGlues"
        case "zink": "Zink"
        case "gl4es": "GL4ES"
        case "simplefpewrapper": "SimpleFPEWrapper"
        case "angle": "ANGLE (fallback)"
        case "ltw": "LTW"
        case "mobilegl": "MobileGL"
        case "mobilegles": "MobileGL GLES"
        case "krypton": "Krypton"
        case "vulkan": "Vulkan"
        case "vgpu": "VGPU"
        case "virgl": "VirGL"
        case "nggl4es": "NG-GL4ES"
        default: renderer.rawValue
        }
    }

    public static func detail(_ renderer: RendererID) -> String {
        switch key(renderer) {
        case "auto": "Chooses a tested renderer for this version and loader."
        case "metallum": "Native Metal; fastest. Vanilla, or the validated 26.2 Metal kit."
        case "mobileglues": "OpenGL translated on the CPU; slow for mods."
        case "zink": "Slower: OpenGL is translated through Vulkan; for advanced compatibility."
        case "gl4es": "Legacy OpenGL path for Minecraft 1.16.5 and older."
        case "simplefpewrapper": "Fixed-function compatibility for very old clients."
        case "angle": "Fallback OpenGL translated on the CPU; use for debugging."
        case "ltw": "Debug OpenGL wrapper; hidden until an iOS result is validated."
        case "mobilegl": "Direct Vulkan OpenGL path; hidden until an iOS result is validated."
        case "mobilegles": "Direct GLES OpenGL path; hidden until an iOS result is validated."
        case "krypton": "Legacy shader translation; hidden until an iOS result is validated."
        case "vulkan": "Direct Vulkan/MoltenVK path; hidden from the production picker."
        case "vgpu": "Legacy shader path; hidden until an iOS result is validated."
        case "virgl": "Mesa compatibility path; hidden until an iOS result is validated."
        case "nggl4es": "Shader translation path; hidden until an iOS result is validated."
        default: "Saved renderer; hidden from the normal picker."
        }
    }

    /// Whether a version and loader have a validated Metal route for modded play.
    /// Vanilla routes come from Air's shipped manifest; the modded routes are the
    /// Cofre-supported kits documented in `plan/recommended-versions.md`.
    public static func isRecommendedForMods(gameVersion: String, loader: Instance.Loader,
                                            metalVersions: Set<String>) -> Bool {
        switch loader {
        case .vanilla:
            metalVersions.contains(gameVersion)
        case .fabric:
            gameVersion == "26.2" || gameVersion == "1.21.11"
        case .neoforge:
            gameVersion == "26.2"
        case .forge, .quilt, .unknown:
            false
        }
    }

    public static func isHidden(_ renderer: RendererID) -> Bool {
        !normalPickerRenderers.contains(where: { sameRenderer($0, renderer) })
    }

    private static func key(_ renderer: RendererID) -> String {
        let raw = renderer.rawValue.lowercased()
        switch raw {
        case "", "auto": return "auto"
        case "metal", "metallum", "libmetallum.dylib": return "metallum"
        case "mobileglues", "libmobileglues.dylib": return "mobileglues"
        case "zink", "libosmesa.8.dylib": return "zink"
        case "ltw", "libltw.dylib": return "ltw"
        case "krypton", "libgl4eszl2.dylib": return "krypton"
        case "angle", "libtinygl4angle.dylib": return "angle"
        case "gl4es", "libgl4es_114.dylib": return "gl4es"
        case "simplefpewrapper", "libsimplefpewrapper.dylib": return "simplefpewrapper"
        case "mobilegl", "libmobilegl.dylib": return "mobilegl"
        case "mobilegles", "libmobilegl-gles.dylib": return "mobilegles"
        case "vulkan", "moltenvk", "libmoltenvk.dylib": return "vulkan"
        case "vgpu", "libvgpu.dylib": return "vgpu"
        case "virgl", "libosmesavirgl.dylib": return "virgl"
        case "nggl4es", "libnggl4es.dylib": return "nggl4es"
        case "air": return "air"
        default: return raw
        }
    }

    public static func resolve(setting: String, globalSetting: String = "auto", gameVersion: String,
                               loader: Instance.Loader, metalVersions: Set<String>, metalMod: Bool = false) -> String {
        resolve(setting: RendererID(rawValue: setting), globalSetting: RendererID(rawValue: globalSetting),
                 gameVersion: gameVersion, loader: loader, metalVersions: metalVersions, metalMod: metalMod).rawValue
    }

    public static func airIdentifier(_ renderer: RendererID) -> RendererID {
        switch key(renderer) {
        case "auto", "air": .auto
        case "metallum": .custom("libmetallum.dylib")
        case "mobileglues": .custom("libmobileglues.dylib")
        case "zink": .custom("libOSMesa.8.dylib")
        case "ltw": .custom("libltw.dylib")
        case "krypton": .custom("libgl4eszl2.dylib")
        case "angle": .custom("libtinygl4angle.dylib")
        case "gl4es": .custom("libgl4es_114.dylib")
        case "simplefpewrapper": .custom("libSimpleFPEWrapper.dylib")
        case "mobilegl": .custom("libMobileGL.dylib")
        case "mobilegles": .custom("libMobileGL-gles.dylib")
        case "vulkan": .custom("libMoltenVK.dylib")
        case "vgpu": .custom("libvgpu.dylib")
        case "virgl": .custom("libOSMesaVirgl.dylib")
        case "nggl4es": .custom("libnggl4es.dylib")
        default: renderer
        }
    }

    public static func airIdentifier(_ renderer: String) -> String {
        airIdentifier(RendererID(rawValue: renderer)).rawValue
    }
}

/// A mod or shader pack that won't run with the renderer an instance uses.
public struct CompatibilityIssue: Hashable, Sendable {
    public let severity: KnownMod.Severity
    public let modID: String, modName: String, gameVersion: String, reason: String
    public var kind: ContentKind
    /// The renderer as people know it: "Metal" or "MobileGlues".
    public var renderer: String
    /// The file to turn off, when the issue came from the instance's folder.
    public var file: String?
    public init(modID: String, modName: String, gameVersion: String, reason: String, kind: ContentKind = .mods,
                renderer: String = "Metal", file: String? = nil, severity: KnownMod.Severity = .broken) {
        self.modID = modID; self.modName = modName; self.gameVersion = gameVersion; self.reason = reason; self.severity = severity
        self.kind = kind; self.renderer = renderer; self.file = file
    }
    public var title: String { kind == .shaders ? "Shaders don't run here" : "\(modName) doesn't run here" }
    public var badge: String {
        renderer == ContentCompatibility.pcOnlyRenderer ? "PC-only" : "Not on \(renderer) · \(gameVersion)"
    }
}

/// Which mods and shader packs can't run with an instance's renderer. Metal
/// runs mods only through the validated MetalUniversal 26.2 kits, with Sodium
/// only on Fabric; NeoForge's OpenGL renderer mods stay flagged. Shader packs
/// on MobileGlues fail at pipeline
/// creation (ES 3.0 via ANGLE: "Draw buffers … Status: 36054"), though
/// MobileGlues reports OpenGL 4.0 so Iris's own check passes.
public enum ContentCompatibility {
    public static func rendererName(_ renderer: String) -> String? {
        let r = renderer.lowercased()
        return r.contains("metal") ? "Metal" : r.contains("mobileglues") ? "MobileGlues" : r.contains("angle") ? "ANGLE" : nil
    }

    /// The Metallum integration a mod needs (`iris`, `sodium`) and the versions it ships for. `mixin` is
    /// Metallum's own package, not a mod.
    public static func integration(for name: String, _ manifest: RendererManifest) -> (name: String, versions: Set<String>)? {
        let key = KnownMod.normalized(name)
        guard !key.isEmpty else { return nil }
        return manifest.integrations.filter { $0.key != "mixin" }.sorted { $0.key < $1.key }
            .first { key.contains(KnownMod.normalized($0.key)) }.map { ($0.key, $0.value) }
    }

    public static func issue(id: String, name: String, kind: ContentKind, gameVersion: String, renderer: String,
                             manifest: RendererManifest, loader: Instance.Loader = .unknown) -> CompatibilityIssue? {
        let label = name.isEmpty ? id : name
        if kind == .mods, let known = KnownModsCatalog.match(
            id: id, name: name, fileName: name, gameVersion: gameVersion, renderer: renderer, loader: loader) {
            let shown = known.scope == .anyRenderer ? pcOnlyRenderer : (rendererName(renderer) ?? renderer)
            return CompatibilityIssue(
                modID: id, modName: known.name, gameVersion: gameVersion,
                reason: known.renderedReason(renderer: shown, gameVersion: gameVersion), kind: kind,
                renderer: shown, severity: known.severity)
        }
        guard let shown = rendererName(renderer) else { return nil }
        func make(_ reason: String, as name: String = label) -> CompatibilityIssue {
            CompatibilityIssue(modID: id, modName: name, gameVersion: gameVersion, reason: reason, kind: kind, renderer: shown)
        }
        switch (kind, shown) {
        case (.shaders, "Metal"):
            return make(irisOnMetal)
        case (.shaders, "MobileGlues"):
            return make("On MobileGlues, shader packs fail to start and Iris turns them off.")
        default: return nil
        }
    }

    /// The Play-time check: enabled mods, and the shader pack the game has on.
    public static func playIssues(gameDirectory: URL, gameVersion: String, renderer: String,
                                  manifest: RendererManifest, loader: Instance.Loader = .unknown) -> [CompatibilityIssue] {
        let store = ContentStore(gameDirectory: gameDirectory)
        let mods = ((try? store.list(.mods)) ?? []).filter(\.enabled)
        var out = mods.compactMap { m in
            issue(id: m.id, name: m.name, kind: .mods, gameVersion: gameVersion, renderer: renderer, manifest: manifest,
                  loader: loader)
                .map { var i = $0; i.file = m.id; return i }
        }
        // A pack only runs with a shader mod on; if that mod is already flagged, turning it off covers the pack.
        let shaderMods = (ShaderSwitch.files.map { ($0 as NSString).deletingPathExtension } + ["optifine"])
        let shaderMod = mods.first { m in shaderMods.contains { KnownMod.normalized(m.name).hasPrefix(KnownMod.normalized($0)) } }
        if let shaderMod, !out.contains(where: { $0.file == shaderMod.id }),
            let pack = ((try? store.list(.shaders)) ?? []).first(where: \.inUse),
            var i = issue(id: pack.id, name: pack.name, kind: .shaders, gameVersion: gameVersion, renderer: renderer,
                          manifest: manifest, loader: loader) {
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

    /// Stock Iris fails on Metal with "No GLCapabilities instance set".
    public static var irisOnMetal: String { reason(for: "Iris", scope: .metal) }
    public static var neoForgeMetalGL: String { reason(for: "Sodium", scope: .metal, loader: .neoforge) }
    public static var distantHorizonsOnMetal: String { reason(for: "Distant Horizons", scope: .metal) }
    public static var pcOnlyReason: String { reason(for: "Simple Voice Chat", scope: .anyRenderer) }
    /// `CompatibilityIssue.renderer` for a mod that runs on no renderer here; its badge reads "PC-only".
    public static let pcOnlyRenderer = "PC"

    private static func reason(for name: String, scope: KnownMod.Scope, loader: Instance.Loader? = nil) -> String {
        KnownModsCatalog.entries.first {
            $0.name == name && $0.scope == scope && (loader == nil || $0.loaders?.contains(loader!) == true)
        }?.reason ?? ""
    }
}
