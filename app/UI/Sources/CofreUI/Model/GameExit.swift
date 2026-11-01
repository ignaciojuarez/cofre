import Foundation
import CofreKit

// Why Minecraft stopped, in plain words. Diagnosed from the exit code, the newest crash report and the log tail;
// the glue reads the files, this only reads text, so it's tested on the Mac too.

public struct GameExitReport: Hashable, Sendable {
    public enum Reason: String, CaseIterable, Sendable {
        case memory, renderer, missingLibrary, mods, java, unknown, quit
    }

    public var code: Int
    public var reason: Reason
    /// The line that gave the reason away, e.g. `java.lang.OutOfMemoryError: Java heap space`.
    public var clue: String?
    /// "Survival+ · Fabric 1.21.1".
    public var instance: String?
    /// Source files used to build the redacted report bundle.
    public var files: [URL]
    /// Last lines of the log, for Details.
    public var logTail: [String]
    /// Settings changed in game that reload every texture, by menu name ("Mipmap levels").
    public var changedSettings: [String] = []

    public init(
        code: Int, reason: Reason, clue: String? = nil, instance: String? = nil, files: [URL] = [],
        logTail: [String] = []
    ) {
        self.code = code
        self.reason = reason
        self.clue = clue
        self.instance = instance
        self.files = files
        self.logTail = logTail
    }

    /// Diagnoses from text. The crash report decides first; the log only counts on lines that read like errors,
    /// so a normal "Loaded shader pack" line can't make a mod crash look like a renderer one.
    public init(
        code: Int, crashReport: String?, log: String?, instance: String? = nil, files: [URL] = [], tail: Int = 60,
        changedSettings: [String] = [], installedModsURL: URL? = nil
    ) {
        let logLines = (log ?? "").split(whereSeparator: \.isNewline).map(String.init)
        let (reason, clue) = Self.diagnose(
            code: code, crashReport: crashReport, logLines: logLines, settingsChanged: !changedSettings.isEmpty,
            installedModsURL: installedModsURL)
        self.init(
            code: code, reason: reason, clue: clue, instance: instance, files: files,
            logTail: Array(logLines.suffix(tail)))
        self.changedSettings = changedSettings
    }

    /// Checked in order: the first reason with a matching line wins.
    static let signs: [(Reason, [String])] = [
        (.memory, ["outofmemoryerror", "out of memory", "gc overhead limit", "cannot allocate memory"]),
        (
            .mods,
            [
                "incompatible mods found", "incompatible mod set", "mod resolution", "modresolutionexception",
                "missing or unsupported mandatory dependencies", "requires version", "requires any version",
                "duplicate mod", "duplicatemods", "mixin apply", "mixinapplyerror", "invalidinjectionexception",
                "modloadingexception", "nosuchmethoderror", "nosuchfielderror",
            ]
        ),
        (
            .missingLibrary,
            [
                "unsatisfiedlinkerror", "noclassdeffounderror", "classnotfoundexception", "library not loaded",
                "failed to load library", "image not found",
            ]
        ),
        (
            .renderer,
            [
                "glfw error", "no opengl context", "opengl error", "egl_bad", "gl_invalid", "shader",
                "failed to create window", "vk_error",
            ]
        ),
    ]

    /// Log lines that read like errors. Only these count, and Details marks them red.
    static func isError(_ line: String) -> Bool {
        let l = line.lowercased()
        return ["error", "exception", "fatal", "caused by", "failed"].contains { l.contains($0) }
    }

    static func diagnose(code: Int, crashReport: String?, logLines: [String], settingsChanged: Bool = false,
                         installedModsURL: URL? = nil) -> (Reason, String?)
    {
        // System Details lists every mod and the shader pack, which would match anything.
        let report = (crashReport ?? "").split(whereSeparator: \.isNewline).map(String.init)
            .prefix { !$0.hasPrefix("-- System Details --") }.map { $0 }
        let errors = logLines.filter(isError)
        // On Metal, Air's GLFW shutdown (pojavTerminate → gl_terminate) crashes after Minecraft has saved and stopped.
        // The player quit; nothing was lost. The JVM can also die before Air logs anything after "Stopping!".
        if let stop = logLines.lastIndex(where: { $0.contains("]: Stopping!") }),
            logLines[stop...].contains(where: { $0.contains("gl_terminate") || $0.contains("pojavTerminate") })
                || (crashReport == nil && !logLines[stop...].dropFirst().contains(where: isError))
        {
            return (.quit, nil)
        }
        // OpenGL-only mods find no GL context on the Metal renderer; name the one at the top of the stack.
        if (report + logLines).contains(where: { $0.contains("No GLCapabilities instance set") }),
            let name = (report + logLines).lazy.compactMap({ line in
                Self.modAttribution(for: line, modsURL: installedModsURL)
            }).first
        {
            return (.mods, "\(name) \(needsGL)")
        }
        // A mod's OpenGL code handed Metallum's objects ("MetalGpuTexture cannot be cast to … opengl.GlTexture").
        if let id = metalGLModID(in: report + logLines) { return (.mods, "\(modName(id)) \(needsGL)") }
        // NeoForge stops loading mods, then refuses every later event ("…RegisterShadersEvent to a broken mod state"),
        // so the client report reads like a shader crash. The loader's own failure line names the real cause.
        let loaderFailures = ["Failure message: ", "Error during pre-loading phase: "]
        for line in report + logLines {
            if let marker = loaderFailures.first(where: { line.contains($0) }),
                let range = line.range(of: marker)
            {
                return (.mods, clean(String(line[range.upperBound...])))
            }
        }
        // Keep memory, mod, and missing-library diagnoses ahead of a native renderer trace. A generic renderer sign
        // is allowed to be refined by the fatal trace below.
        let signed = diagnoseSigns(report: report, errors: errors)
        if let signed, [.memory, .mods, .missingLibrary].contains(signed.0) { return signed }
        // A JVM fatal signal plus a renderer library in the following frame/trace is a native renderer crash. The
        // renderer marker must follow the signal so an ordinary startup line cannot trigger this diagnosis.
        if let renderer = nativeRenderer(in: report + logLines) {
            let reloading = renderer == "Metal"
                && (settingsChanged || logLines.contains { $0.localizedCaseInsensitiveContains("Reloading ResourceManager") })
            return (.renderer, reloading ? metalReload : nativeRendererCrash(renderer))
        }
        if let signed { return signed }
        // A crash report or a Java stack trace without a known sign.
        let java =
            (report + errors).first { $0.contains("Exception") || $0.contains("java.lang.") }
            ?? report.first { $0.hasPrefix("Description:") }.map { String($0.dropFirst(12)) }
        if let java { return (.java, clean(java)) }
        if !report.isEmpty { return (.java, nil) }
        return (code == 0 ? .quit : .unknown, errors.last.map(clean))
    }

    private static func diagnoseSigns(report: [String], errors: [String]) -> (Reason, String?)? {
        for source in [report, errors] {
            for (reason, keys) in signs {
                if let line = source.last(where: { line in keys.contains { line.lowercased().contains($0) } }) {
                    return (reason, clean(line))
                }
            }
        }
        return nil
    }

    private static let nativeRendererMarkers: [(marker: String, name: String)] = [
        ("agxmetal", "Metal"),
        ("libmetallum", "Metal"),
        ("metaluniversal", "Metal"),
        ("libspvc", "Metal"),
        ("libmobileglues", "MobileGlues"),
        ("libtinygl4angle", "ANGLE"),
        ("angle", "ANGLE"),
    ]

    private static func nativeRenderer(in lines: [String]) -> String? {
        let lower = lines.map { $0.lowercased() }
        guard let signal = lower.firstIndex(where: { $0.contains("sigsegv") || $0.contains("sigbus") }) else { return nil }
        let fatal = lower[signal...]
        return nativeRendererMarkers.first { marker in fatal.contains { $0.contains(marker.marker) } }?.name
    }

    private static func nativeRendererCrash(_ renderer: String) -> String {
        "The \(renderer) renderer crashed."
    }

    /// Package attribution is derived from the installed archives. The cache is per mods directory.
    private static var modCache: [URL: [(package: String, name: String)]] = [:]
    private static let modCacheLock = NSLock()
    private static func modAttribution(for line: String, modsURL: URL?) -> String? {
        let packages: [(package: String, name: String)]
        if let modsURL {
            modCacheLock.lock(); defer { modCacheLock.unlock() }
            if let cached = modCache[modsURL] { packages = cached }
            else {
                let found = Self.scanMods(at: modsURL)
                modCache[modsURL] = found
                packages = found
            }
        } else {
            for token in line.split(whereSeparator: { $0 == " " || $0 == "(" }) {
                let parts = token.replacingOccurrences(of: "knot//", with: "").split(separator: ".")
                if (token.contains("net.") || token.contains("com.")), let mod = parts.dropLast().last(where: { $0.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" }) }) {
                    let id = String(mod)
                    return KnownModsCatalog.name(for: id) ?? id.replacingOccurrences(of: "_", with: " ").capitalized
                }
            }
            return nil
        }
        guard let package = packages.first(where: { line.contains($0.package) }) else { return nil }
        return KnownModsCatalog.name(for: package.name, fileName: package.name) ?? package.name
    }
    private static func scanMods(at url: URL) -> [(package: String, name: String)] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "jar" }.flatMap { jar in
            guard let data = try? Data(contentsOf: jar) else { return [(package: String, name: String)]() }
            let bytes = [UInt8](data); var p = 0; var packages = Set<String>(); var name = jar.deletingPathExtension().lastPathComponent
            while p + 30 <= bytes.count, bytes[p] == 0x50, bytes[p+1] == 0x4b, bytes[p+2] == 3, bytes[p+3] == 4 {
                let nl = Int(UInt16(bytes[p+26]) | UInt16(bytes[p+27]) << 8), xl = Int(UInt16(bytes[p+28]) | UInt16(bytes[p+29]) << 8)
                let b0 = UInt32(bytes[p + 18]), b1 = UInt32(bytes[p + 19]), b2 = UInt32(bytes[p + 20]), b3 = UInt32(bytes[p + 21])
                let size = Int(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
                let ns = p + 30, end = ns + nl, next = end + xl + size; guard next <= bytes.count else { break }
                let entry = String(decoding: bytes[ns..<end], as: UTF8.self)
                if entry.hasSuffix(".class"), let first = entry.split(separator: "/").first, first != "META-INF" { packages.insert(String(first)) }
                p = next
            }
            return packages.map { ($0, name) }
        }
    }
    /// The mod whose OpenGL code got a Metal object: the first stack frame after the cast error that names a mixin
    /// "from mod <id>" (Distant Horizons' `MixinLightTexture` on NeoForge 26.2 + MetalUniversal).
    public static func metalGLModID(in lines: [String]) -> String? {
        guard
            let cast = lines.firstIndex(where: {
                $0.range(of: #"Metal\w* cannot be cast to (class )?[\w.$]*\.opengl\.Gl"#, options: .regularExpression)
                    != nil
            })
        else { return nil }
        for line in lines[cast...].prefix(40) where line.trimmingCharacters(in: .whitespaces).hasPrefix("at ") {
            for match in line.matches(of: #/from mod ([A-Za-z0-9_\-]+)/#) {
                let id = String(match.1).lowercased()
                if !["minecraft", "neoforge", "forge", "fabricloader", "metallum"].contains(id) { return id }
            }
        }
        return nil
    }

    /// How a mod reads on the screen: known names, else its ID ("distanthorizons" → "Distant Horizons").
    public static func modName(_ id: String) -> String {
        KnownModsCatalog.name(for: id) ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static let needsGL = "needs OpenGL, which the Metal renderer doesn't have on this Minecraft version."

    /// Changing Graphics or resource packs in game reloads every texture and shader; Metallum can crash there.
    static let metalReload = "Metal crashed while reloading graphics (Graphics or resource packs changed in game)."

    private static func clean(_ line: String) -> String {
        // Drop log prefixes like "[12:00:01] [Render thread/ERROR]: " and keep it to one readable line.
        var s = Substring(line.trimmingCharacters(in: .whitespaces))
        while s.hasPrefix("["), let end = s.firstIndex(of: "]") {
            s = s[s.index(after: end)...].drop { $0 == " " || $0 == ":" }
        }
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count > 200 ? String(t.prefix(199)) + "…" : t
    }

    // MARK: Copy

    public var title: String { reason == .quit ? "Minecraft closed" : "Minecraft stopped" }

    public var explanation: String {
        switch reason {
        case .renderer where clue == Self.metalReload: "Metal crashed while reloading graphics."
        case .renderer where clue?.hasSuffix(" renderer crashed.") == true: clue!
        case .memory: "It ran out of memory."
        case .renderer: "The graphics renderer failed."
        case .missingLibrary: "A game file is missing or didn't load."
        case .mods where clue?.hasSuffix(Self.needsGL) == true: clue!
        case .mods: "Some mods don't work together, or one needs another mod."
        case .java: "Minecraft hit a Java error."
        case .unknown: "It closed unexpectedly."
        case .quit: "You quit the game."
        }
    }

    public var nextStep: String {
        switch reason {
        case .memory: "Lower Memory in Settings › Game, or remove a few mods, then play again."
        case .renderer where clue == Self.metalReload && !changedSettings.isEmpty:
            "Your change to \(changedSettings.formatted()) is saved for next time. "
                + "For now, change graphics and resource packs before joining a world, not in one."
        case .renderer where clue == Self.metalReload:
            "Play again. For now, change graphics and resource packs before joining a world, not in one."
        case .renderer where clue?.hasSuffix(" renderer crashed.") == true:
            "Play again. If it happens when you change video settings, change them less often or switch the renderer in the instance settings."
        case .renderer: "Turn off shader packs, or pick another renderer in Settings › Renderer."
        case .missingLibrary:
            "Play again to recheck the game files. If it happens again, this version may not run on iOS yet."
        case .mods where clue?.hasSuffix(Self.needsGL) == true:
            "Turn that mod off in Mods › Installed, then play again."
        case .mods: "Open Details to see which mod, then update or remove it, or add the mod it needs."
        case .java: "If you just changed mods, undo that. Otherwise share the log so someone can look."
        case .unknown: "Play again. If it keeps happening, share the log."
        case .quit: "Open Cofre again whenever you want to play."
        }
    }

    /// What Details › Copy puts on the clipboard: enough for a bug report without the whole log.
    public var detailsText: String {
        var lines = ["\(title): \(explanation)"]
        if let instance { lines.append("Instance: \(instance)") }
        lines.append("Exit code: \(code)")
        if let clue { lines.append("Clue: \(clue)") }
        if let report = files.dropFirst().first { lines.append("Crash report: \(report.lastPathComponent)") }
        if !logTail.isEmpty { lines += ["", "Last log lines:"] + logTail.suffix(20) }
        return lines.joined(separator: "\n")
    }
}
