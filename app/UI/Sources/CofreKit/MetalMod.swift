import Foundation

/// MetalUniversal: the Fabric mod that runs modded Minecraft on Metal. Its jar's Fabric id is `metallum`, and it
/// loads Air's signed `Frameworks/libmetallum.dylib`, so the launch hands Air the Metal renderer.
public enum MetalMod {
    public static let modID = "metallum"
    /// Fabric versions where MetalUniversal + Sodium rendered on an iPad (plan/reviews/renderer-benchmarks.md).
    public static let gameVersions: Set<String> = ["26.2"]
    /// The device-validated stock jar. Shared by the one-tap install and the Fabric preset.
    public static let pin = CofrePreset.Mod(
        project: "EternityQwQ/MetalUniversal", slug: "metaluniversal", version: "1.0.4", file: "metallum-1.0.4.jar",
        sha512:
            "bcc248f19c4e6b5bc4041b38e68425d72595148cc67f7f740d3b2449323ea7fc47d662610d531e0eb847c98d41fcc44ff6f6ff0c64ce435ca80775a52f31340c",
        license: "MIT",
        url: "https://github.com/EternityQwQ/MetalUniversal/releases/download/MetalUniversal_1.0.4/metallum-1.0.4.jar")

    /// Whether this instance can run Metal once the mod is in its mods folder.
    public static func supports(gameVersion: String, loader: Instance.Loader) -> Bool {
        loader == .fabric && gameVersions.contains(gameVersion)
    }

    /// An enabled jar in `mods/` whose `fabric.mod.json` id is `metallum`.
    public static func isEnabled(in gameDirectory: URL) -> Bool {
        let store = ContentStore(gameDirectory: gameDirectory)
        return ((try? store.list(.mods)) ?? []).contains { $0.enabled && isMetalMod(store.url(of: $0)) }
    }

    /// Jars are read once per path, size and date: Settings asks on every redraw.
    nonisolated(unsafe) private static var seen: [String: Bool] = [:]
    private static let lock = NSLock()

    static func isMetalMod(_ jar: URL) -> Bool {
        guard jar.pathExtension.lowercased() == "jar",
            let values = try? jar.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return false }
        let key = "\(jar.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        if let known = lock.withLock({ seen[key] }) { return known }
        let found =
            (try? Data(contentsOf: jar, options: .alwaysMapped)).flatMap { data in
                (try? Zip.entries(in: data))?.first { $0.path == "fabric.mod.json" }
                    .flatMap { try? Zip.data(of: $0, in: data) }
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            }?["id"] as? String == modID
        lock.withLock { seen[key] = found }
        return found
    }
}
