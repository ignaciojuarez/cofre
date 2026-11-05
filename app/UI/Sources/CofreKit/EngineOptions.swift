import Foundation

/// Launch-only engine settings Cofre adds on top of Air's JVM and game arguments (`plan/ideal-engine.md`, phases 1–2).
/// Every experiment defaults to today's behavior. A device bench (`scripts/bench.sh`) decides which become defaults.
public struct EngineOptions: Codable, Equatable, Sendable {
    public enum Collector: String, Codable, Sendable { case g1, zgc, parallel }

    /// JIT code cache in MB; nil keeps Air's 64 MB. Under iOS 26's JIT the whole cache is prepared at launch.
    public var codeCacheMB: Int?
    /// Java 25: 8-byte object headers, so a smaller heap after GC (needs compressed class pointers, which Cofre's
    /// extended-virtual-addressing entitlement keeps on).
    public var compactHeaders = false
    /// nil keeps Air's choice (G1 on Java 17+).
    public var collector: Collector?
    /// HotSpot log lines for `scripts/perf-summary.sh`: GC pauses and code cache events.
    public var logGC = false
    public var logCodeCache = false
    /// Java Flight Recorder chunks under `<game>/cofre-jfr/`, kept even if iOS kills the app. Open in JDK Mission Control.
    public var flightRecorder = false
    /// Detach the JIT debugger once the code region is ready instead of keeping it attached.
    public var detachJIT = false
    /// Run background Java threads (world workers, IO, downloads, chunk builders) at utility QoS.
    public var threadQoS = false

    public init(
        codeCacheMB: Int? = nil, compactHeaders: Bool = false, collector: Collector? = nil, logGC: Bool = false,
        logCodeCache: Bool = false, flightRecorder: Bool = false, detachJIT: Bool = false, threadQoS: Bool = false
    ) {
        self.codeCacheMB = codeCacheMB
        self.compactHeaders = compactHeaders
        self.collector = collector
        self.logGC = logGC
        self.logCodeCache = logCodeCache
        self.flightRecorder = flightRecorder
        self.detachJIT = detachJIT
        self.threadQoS = threadQoS
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            codeCacheMB: try c.decodeIfPresent(Int.self, forKey: .codeCacheMB),
            compactHeaders: try c.decodeIfPresent(Bool.self, forKey: .compactHeaders) ?? false,
            collector: try c.decodeIfPresent(Collector.self, forKey: .collector),
            logGC: try c.decodeIfPresent(Bool.self, forKey: .logGC) ?? false,
            logCodeCache: try c.decodeIfPresent(Bool.self, forKey: .logCodeCache) ?? false,
            flightRecorder: try c.decodeIfPresent(Bool.self, forKey: .flightRecorder) ?? false,
            detachJIT: try c.decodeIfPresent(Bool.self, forKey: .detachJIT) ?? false,
            threadQoS: try c.decodeIfPresent(Bool.self, forKey: .threadQoS) ?? false)
    }

    public static let defaultsKey = "cofre.engine.options"

    public static func load(from defaults: UserDefaults = .standard) -> EngineOptions {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? .init()
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    /// JVM flags for this launch. Air applies them after its own (`-XX:ReservedCodeCacheSize=64m`, `-XX:+UseG1GC`),
    /// and HotSpot keeps the last value of a flag. Flags a runtime would reject are left out: an unknown `-XX` option
    /// stops the JVM.
    public func jvmFlags(javaMajor: Int, gameDirectory: URL?) -> [String] {
        var flags: [String] = []
        if let codeCacheMB { flags.append("-XX:ReservedCodeCacheSize=\(min(max(codeCacheMB, 48), 512))m") }
        if compactHeaders, javaMajor >= 25 { flags.append("-XX:+UseCompactObjectHeaders") }
        if javaMajor >= 17 {
            // Air turns G1 on; a second collector without turning it off stops the JVM.
            switch collector {
            case .zgc: flags += ["-XX:-UseG1GC", "-XX:+UseZGC"]
            case .parallel: flags += ["-XX:-UseG1GC", "-XX:+UseParallelGC"]
            case .g1, nil: break
            }
        }
        if javaMajor >= 9 {
            if logGC { flags.append("-Xlog:gc") }
            if logCodeCache { flags.append("-Xlog:codecache") }
        }
        if flightRecorder, javaMajor >= 11, let gameDirectory {
            let repository = gameDirectory.appendingPathComponent("cofre-jfr", isDirectory: true).path
            flags += [
                "-XX:FlightRecorderOptions:repository=\(repository)",
                "-XX:StartFlightRecording=settings=profile,disk=true,maxage=30m,dumponexit=true,filename=\(repository)/cofre.jfr",
            ]
        }
        return flags
    }
}

/// Game arguments that pick Minecraft's graphics backend for Cofre's renderer.
public enum GraphicsBackendArguments {
    /// Metal (Air's agent or MetalUniversal) plugs in as the `default` backend; after a startup crash 26.x saves
    /// OpenGL as its choice, and the argument overrides that. Vulkan runs Mojang's own backend through MoltenVK,
    /// the route macOS uses, available from 26.2.
    public static func arguments(renderer: RendererID, gameVersion: String) -> [String] {
        if RendererPolicy.isMetal(renderer) {
            return (Int(gameVersion.prefix(while: \.isNumber)) ?? 0) >= 26 ? ["--graphicsBackend", "default"] : []
        }
        if RendererPolicy.sameRenderer(renderer, .vulkan), VersionManifest.isOptimized(gameVersion) {
            return ["--graphicsBackend", "vulkan"]
        }
        return []
    }
}
