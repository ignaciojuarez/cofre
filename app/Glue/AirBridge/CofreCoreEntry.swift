import UIKit
import CofreUI
import CofreKit

@objc(CofreCoreEntry)
public final class CofreCoreEntry: NSObject {
    private static var bridge: (any CofreAirBridging)?
    private static var root: UIViewController?

    private static func javaMajor(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue > 0 ? value.intValue : nil }
        if let value = value as? String, let major = Int(value), major > 0 { return major }
        if let value = value as? [String: Any] { return javaMajor(value["majorVersion"]) }
        return nil
    }

    private static func requiredJava(from metadata: [String: Any]) -> Int {
        let java = metadata["javaVersion"] as? [String: Any]
        return javaMajor(java?["majorVersion"] ?? java?["version"]) ?? 8
    }

    /// ObjC launch glue uses this without importing CofreKit's Swift types.
    @objc(javaRuntimeDecisionForProfile:metadata:renderer:availableJavaMajors:)
    @MainActor public static func javaRuntimeDecision(profile: [String: Any], metadata: [String: Any],
                                                      renderer: String, availableJavaMajors: [NSNumber]) -> NSDictionary {
        let required = requiredJava(from: metadata)
        let selected = javaMajor(profile["javaVersion"])
        let decision = JavaRuntimePolicy.decision(
            requiredJava: required, selectedJava: selected,
            renderer: RendererID(rawValue: renderer), bundledMajors: availableJavaMajors.map(\.intValue))
        switch decision {
        case .keep:
            return ["action": "keep"]
        case .use(let major):
            return ["action": "use", "major": major, "required": required, "selected": selected ?? 0]
        case .unsupportedSelection:
            return ["action": "unsupportedSelection", "selected": selected ?? 0,
                    "minimum": JavaRuntimePolicy.metalMinimumMajor]
        case .unavailable:
            return ["action": "unavailable", "required": required,
                    "minimum": JavaRuntimePolicy.metalMinimumMajor]
        }
    }
    /// Launch-only additions on top of Air's arguments: engine experiments as JVM flags (Air applies them after its
    /// own) and the game argument that picks Minecraft's graphics backend for this renderer.
    @objc(launchAdditionsForMetadata:renderer:gameDirectory:)
    @MainActor public static func launchAdditions(metadata: [String: Any], renderer: String,
                                                  gameDirectory: URL?) -> NSDictionary {
        let base = metadata["inheritsFrom"] as? String ?? metadata["id"] as? String ?? ""
        let options = EngineOptions.load()
        let jvm = options.jvmFlags(javaMajor: requiredJava(from: metadata), gameDirectory: gameDirectory)
            + MetalMod.agentJVMFlags(metadata: metadata, gameDirectory: gameDirectory)
        let game = GraphicsBackendArguments.arguments(renderer: RendererID(rawValue: renderer), gameVersion: base)
        return ["jvm": jvm, "game": game, "threadQoS": options.threadQoS]
    }
    /// The ObjC engine applies this value; all renderer decisions stay in Swift.
    @objc(rendererForProfile:metadata:globalSetting:)
    @MainActor public static func renderer(forProfile profile: [String: Any], metadata: [String: Any],
                                          globalSetting: String) -> String {
        let directory = bridge.flatMap { $0.gameDirectory(forProfile: $0.selectedProfileName()) }
        let fallback = directory.flatMap { directory in
            (try? Data(contentsOf: directory.appendingPathComponent("cofre.json")))
                .flatMap { try? JSONDecoder().decode(Instance.self, from: $0) }?.loader
        }
        // A Fabric instance with MetalUniversal in its mods folder runs Metal (RendererPolicy).
        let renderer = RendererPolicy.resolve(profile: profile, metadata: metadata, globalSetting: globalSetting,
            fallbackLoader: fallback, gameDirectory: directory, metalVersions: ModCompatibility.metalVersions)
        if RendererPolicy.isMetal(renderer), let directory, (try? GameOptions.clearForcedOpenGL(in: directory)) == true {
            NSLog("[Cofre] options: cleared forced OpenGL for a Metal launch")
        }
        return renderer.rawValue
    }
    @objc(startWithBridge:)
    @MainActor public static func start(withBridge bridge: Any) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CofreVersion") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CofreBuild") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        NSLog("[Cofre] app version=%@ build=%@", version, build)
        guard let bridge = bridge as? any CofreAirBridging else { NSLog("[Cofre] owned UI fallback reason=bridge type"); return }
        self.bridge = bridge
        bridge.ensureAutomaticMemoryDefault()
        CofreUIKitTheme.apply()
        root = CofreRootViewController(bridge: bridge)
        Task { await CofreVPN.startIfInstalled() }
    }
    @objc(handleOpenURL:)
    @MainActor public static func handleOpenURL(_ url: URL) {
        if url.isFileURL, url.pathExtension.lowercased() == "plist" {
            do {
                try PairingFileStore.importFile(at: url)
                NSLog("[Cofre] pairing imported")
            } catch {
                NSLog("[Cofre] pairing import rejected: %@", error.localizedDescription)
            }
            return
        }
        NotificationCenter.default.post(name: Notification.Name("CofreOpenURL"), object: url)
    }
    /// Minecraft exited (patch 0004 via CofreHandleGameExit): keep the user in Cofre's recovery view.
    @objc(handleGameExit:)
    @MainActor public static func handleGameExit(_ code: Int32) {
        CofreGameExit.handle(code: Int(code), root: root, bridge: bridge)
    }
    /// The in-game touch overlay. Air's `CofreGameOverlayHost` asks once per game view.
    @objc(touchOverlay)
    @MainActor public static func touchOverlay() -> UIViewController {
        TouchOverlayController(input: CofreGameInput.shared)
    }
    @objc(rootViewController)
    @MainActor public static func rootViewController() -> UIViewController? {
        guard let root else { NSLog("[Cofre] owned UI fallback reason=root missing"); return nil }
        NSLog("[Cofre] UI root installed")
        return root
    }
}
