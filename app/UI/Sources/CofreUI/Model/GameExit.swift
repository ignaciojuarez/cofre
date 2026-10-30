import Foundation

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
    /// Files for Share log: latestlog.txt, then the crash report when there is one.
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
        changedSettings: [String] = []
    ) {
        let logLines = (log ?? "").split(whereSeparator: \.isNewline).map(String.init)
        let (reason, clue) = Self.diagnose(
            code: code, crashReport: crashReport, logLines: logLines, settingsChanged: !changedSettings.isEmpty)
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

    static func diagnose(code: Int, crashReport: String?, logLines: [String], settingsChanged: Bool = false)
        -> (Reason, String?)
    {
        // System Details lists every mod and the shader pack, which would match anything.
        let report = (crashReport ?? "").split(whereSeparator: \.isNewline).map(String.init)
            .prefix { !$0.hasPrefix("-- System Details --") }.map { $0 }
        let errors = logLines.filter(isError)
        // A crash inside Apple's GPU driver names AGXMetal in the fatal trace but has no error word on that line.
        // Metallum's per-draw logging can push the reload line out of the tail, so a setting changed in game counts too.
        if logLines.contains(where: { $0.contains("AGXMetal") }) {
            let reloading = settingsChanged || logLines.contains { $0.contains("Reloading ResourceManager") }
            return (.renderer, reloading ? metalReload : "Metal crashed in the GPU driver.")
        }
        // OpenGL-only mods find no GL context on the Metal renderer; name the one at the top of the stack.
        if (report + logLines).contains(where: { $0.contains("No GLCapabilities instance set") }),
            let name = (report + logLines).lazy.compactMap({ line in
                glOnlyMods.first { line.contains($0.package) }?.name
            }).first
        {
            return (.mods, "\(name) \(needsGL)")
        }
        for source in [report, errors] {
            for (reason, keys) in signs {
                // The last match: the root cause in a stack trace, the newest line in a log.
                if let line = source.last(where: { line in keys.contains { line.lowercased().contains($0) } }) {
                    return (reason, clean(line))
                }
            }
        }
        // A crash report or a Java stack trace without a known sign.
        let java =
            (report + errors).first { $0.contains("Exception") || $0.contains("java.lang.") }
            ?? report.first { $0.hasPrefix("Description:") }.map { String($0.dropFirst(12)) }
        if let java { return (.java, clean(java)) }
        if !report.isEmpty { return (.java, nil) }
        return (code == 0 ? .quit : .unknown, errors.last.map(clean))
    }

    /// Mods that draw with OpenGL directly, by package. The Metal renderer only runs Iris and Sodium where Metallum
    /// ships support for them (Iris on 26.2; Sodium on 1.21.11 and 26.2).
    static let glOnlyMods: [(package: String, name: String)] = [
        ("net.irisshaders", "Iris"), ("net.coderbot.iris", "Iris"), ("com.seibel.distanthorizons", "Distant Horizons"),
        ("net.caffeinemc", "Sodium"), ("me.jellysquid.mods.sodium", "Sodium"),
    ]
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
        case .memory: "It ran out of memory."
        case .renderer: "The graphics renderer failed."
        case .missingLibrary: "A game file is missing or couldn't load."
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
            "You changed \(changedSettings.formatted()). That's saved and applies when you play again. "
                + "For now, changing graphics settings or resource packs inside a world crashes Metal."
        case .renderer where clue == Self.metalReload:
            "Play again, and for now don't change Graphics or resource packs while in a world."
        case .renderer: "Turn off shader packs, or pick another renderer in Settings › Renderer."
        case .missingLibrary: "Play again so the game files are checked. Some versions don't run on iOS yet."
        case .mods where clue?.hasSuffix(Self.needsGL) == true:
            "Turn that mod off in Mods › Installed, then play again. Shaders work on Minecraft 26.2 for now."
        case .mods: "Open Details to see which mod, then update or remove it, or add the mod it needs."
        case .java: "If you just changed mods, undo that. Otherwise share the log so someone can look."
        case .unknown: "Play again. If it keeps happening, share the log."
        case .quit: "Open Cofre again whenever you want to play."
        }
    }

    /// What Copy details puts on the clipboard: enough for a bug report without the whole log.
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
