import Foundation

/// MetalUniversal: the mod kit that runs validated 26.2 instances on Metal. Its jar's Fabric id is `metallum`, and it
/// loads Air's signed `Frameworks/libmetallum.dylib`, so the launch hands Air the Metal renderer.
public enum MetalMod {
    public static let modID = "metallum"
    public static let neoForgeKitIDs: Set<String> = ["connector", "fabric_api", "launchpad"]
    /// Versions where the MetalUniversal kit rendered on an iPad (plan/reviews/renderer-benchmarks.md).
    public static let gameVersions: Set<String> = ["26.2"]
    /// The device-validated stock jar. Shared by the one-tap install and both Metal presets.
    public static let pin = CofrePreset.Mod(
        project: "EternityQwQ/MetalUniversal", slug: "metaluniversal", version: "1.0.4", file: "metallum-1.0.4.jar",
        sha512:
            "bcc248f19c4e6b5bc4041b38e68425d72595148cc67f7f740d3b2449323ea7fc47d662610d531e0eb847c98d41fcc44ff6f6ff0c64ce435ca80775a52f31340c",
        license: "MIT",
        url: "https://github.com/EternityQwQ/MetalUniversal/releases/download/MetalUniversal_1.0.4/metallum-1.0.4.jar")

    /// The NeoForge bridge jars used by the device-validated Connector kit.
    public static let neoForgePins: [CofrePreset.Mod] = [
        CofrePreset.Mod(
            project: "u58R1TMW", slug: "connector", version: "UTJVNLyr",
            file: "connector-3.1.0-beta.4+26.2-full.jar",
            sha512:
                "7377d33a588f2e0df22a3e2fd4bcbca778aa6aff3fa79cbe6f3d455e206da20b395c02259e41208869c73ff6625f1de9ff5eac365875c2d98735d9782ed1e2e3",
            license: "MIT",
            url: "https://cdn.modrinth.com/data/u58R1TMW/versions/UTJVNLyr/connector-3.1.0-beta.4%2B26.2-full.jar"),
        CofrePreset.Mod(
            project: "voWgQoWV", slug: "launchpad", version: "QMTIAZjK",
            file: "launchpad-1.10.2+26.2-full.jar",
            sha512:
                "a15969ad4c4dd4ceba2346ac49352cf46d8d07c1a14525eca45c8dfa6f1553762176440eb80827a9cdece028cf71b4756aef06f78b94bed527af9ff1ab5e1c58",
            license: "GPL-3.0-only WITH Classpath-exception-2.0",
            url: "https://cdn.modrinth.com/data/voWgQoWV/versions/QMTIAZjK/launchpad-1.10.2%2B26.2-full.jar"),
        CofrePreset.Mod(
            project: "Aqlf1Shp", slug: "forgified-fabric-api", version: "LfyblCbV",
            file: "forgified-fabric-api-0.161.0+26.2+4.0.2.jar",
            sha512:
                "0bdb87556418929aa88a1322c04e8993727580414b95b0410e58c358cb05697bde2a30840043f5a9922e7c751dbdaf1c20a0d7b44c0832ad9655aab5977c3672",
            license: "Apache-2.0",
            url:
                "https://cdn.modrinth.com/data/Aqlf1Shp/versions/LfyblCbV/forgified-fabric-api-0.161.0%2B26.2%2B4.0.2.jar"
        ),
    ]

    public static func pins(for loader: Instance.Loader) -> [CofrePreset.Mod] {
        loader == .neoforge ? [pin] + neoForgePins : [pin]
    }

    /// Whether this instance can run Metal once the mod is in its mods folder.
    public static func supports(gameVersion: String, loader: Instance.Loader) -> Bool {
        (loader == .fabric || loader == .neoforge) && gameVersions.contains(gameVersion)
    }

    /// An enabled MetalUniversal jar in `mods/`.
    public static func isEnabled(in gameDirectory: URL) -> Bool {
        enabledIDs(in: gameDirectory, loader: .fabric).contains(modID)
    }

    /// The Fabric kit needs MetalUniversal. NeoForge additionally needs its Connector/Forgified API/Launchpad bridge.
    public static func isEnabled(in gameDirectory: URL, loader: Instance.Loader) -> Bool {
        let ids = enabledIDs(in: gameDirectory, loader: loader)
        let required = loader == .neoforge ? neoForgeKitIDs.union([modID]) : [modID]
        return required.allSatisfy(ids.contains)
    }

    public static func enabledIDs(in gameDirectory: URL, loader: Instance.Loader) -> Set<String> {
        let store = ContentStore(gameDirectory: gameDirectory)
        return Set(
            ((try? store.list(.mods)) ?? []).filter(\.enabled).flatMap { modIDs(in: store.url(of: $0), loader: loader) }
        )
    }

    /// Jars are read once per path, size and date: Settings asks on every redraw.
    nonisolated(unsafe) private static var seen: [String: Set<String>] = [:]
    private static let lock = NSLock()

    private static func modIDs(in jar: URL, loader: Instance.Loader) -> Set<String> {
        guard jar.pathExtension.lowercased() == "jar",
            let values = try? jar.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return [] }
        let key =
            "\(loader.rawValue)|\(jar.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        if let known = lock.withLock({ seen[key] }) { return known }
        let found =
            (try? Data(contentsOf: jar, options: .alwaysMapped)).map { data -> Set<String> in
                var ids = Set<String>()
                if let toml = ModsToml.read(data, neoForge: loader == .neoforge, nested: true) {
                    ids.formUnion(toml.modIDs)
                }
                if let entry = (try? Zip.entries(in: data))?.first(where: { $0.path == "fabric.mod.json" }),
                    let json = try? Zip.data(of: entry, in: data),
                    let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                    let id = object["id"] as? String
                {
                    ids.insert(id)
                }
                return ids
            } ?? []
        lock.withLock { seen[key] = found }
        return found
    }
}
