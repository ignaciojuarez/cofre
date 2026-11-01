import Foundation

/// What a Forge or NeoForge mod jar says it needs to load, from its own `META-INF/neoforge.mods.toml` (or Forge's
/// `META-INF/mods.toml`). Modrinth's dependency list is the author's and can be empty (Bountiful 8.0.0-beta.2 lists
/// none but needs Kotlin for Forge), so installs and the Installed list check the jar too.
public struct ModsToml: Hashable, Sendable {
    public struct Dependency: Hashable, Sendable {
        public var owner: String, modID: String, required: Bool
    }
    /// The language provider the jar loads with: "javafml", or "kotlinforforge" for Kotlin mods.
    public var modLoader: String?
    /// `[[mods]] modId` entries, plus the mods bundled inside it (jar-in-jar).
    public var modIDs: [String] = []
    public var dependencies: [Dependency] = []
    /// Artifact names of bundled jars (`META-INF/jarjar/metadata.json`), for libraries without a mods.toml.
    public var bundled: [String] = []

    /// A small reader for the keys FML uses: root keys, `[[mods]]` and `[[dependencies.<owner>]]` tables. Multi-line
    /// strings (descriptions) are skipped; build-time placeholders like `${mod_id}` are ignored.
    public init(text: String) {
        var table = ""
        var entry: [String: String] = [:]
        var closing: String?
        func flush() {
            if table == "mods", let id = entry["modId"] { modIDs.append(id) }
            if table.hasPrefix("dependencies."), let id = entry["modId"] {
                let required = entry["type"]?.lowercased() == "required" || entry["mandatory"] == "true"
                let side = entry["side"]?.uppercased() ?? "BOTH"
                dependencies.append(
                    Dependency(owner: String(table.dropFirst(13)), modID: id, required: required && side != "SERVER"))
            }
            entry = [:]
        }
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let end = closing {
                if line.contains(end) { closing = nil }
                continue
            }
            if line.hasPrefix("[") {
                flush()
                table = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t")).replacingOccurrences(
                    of: "\"", with: "")
                continue
            }
            guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
            let key = line[..<eq].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let quote = ["'''", "\"\"\""].first(where: { value.hasPrefix($0) }) {
                if !value.dropFirst(3).contains(quote) { closing = quote }
                continue
            }
            if let q = value.first, q == "\"" || q == "'", let end = value.dropFirst().firstIndex(of: q) {
                value = String(value[value.index(after: value.startIndex)..<end])
            } else if let hash = value.firstIndex(of: "#") {
                value = value[..<hash].trimmingCharacters(in: .whitespaces)
            }
            guard !value.contains("${") else { continue }
            if table.isEmpty, key == "modLoader" { modLoader = value } else { entry[key] = value }
        }
        flush()
    }

    /// The jar's mods.toml (NeoForge's own file first on NeoForge), with its bundled jars' mod IDs. Nil for a jar
    /// without one (a Fabric mod, a plain library) or one that isn't a zip.
    public static func read(jar: URL, neoForge: Bool) -> ModsToml? {
        guard let data = try? Data(contentsOf: jar, options: .alwaysMapped) else { return nil }
        return read(data, neoForge: neoForge, nested: true)
    }

    static func read(_ data: Data, neoForge: Bool, nested: Bool) -> ModsToml? {
        guard let entries = try? Zip.entries(in: data) else { return nil }
        let names =
            neoForge
            ? ["META-INF/neoforge.mods.toml", "META-INF/mods.toml"]
            : ["META-INF/mods.toml", "META-INF/neoforge.mods.toml"]
        // A toml bigger than this is not a mods.toml; the size check also keeps a hostile jar from inflating gigabytes.
        func text(_ path: String) -> String? {
            guard let entry = entries.first(where: { $0.path == path }), entry.size < 1_000_000,
                let body = try? Zip.data(of: entry, in: data)
            else { return nil }
            return String(decoding: body, as: UTF8.self)
        }
        guard var toml = names.lazy.compactMap(text).first.map(ModsToml.init(text:)) else { return nil }
        guard nested else { return toml }
        for entry in entries
        where entry.path.hasPrefix("META-INF/jarjar/") && entry.path.hasSuffix(".jar")
            && entry.size < 64_000_000
        {
            if let inner = try? Zip.data(of: entry, in: data),
                let found = read(inner, neoForge: neoForge, nested: false)
            {
                toml.modIDs += found.modIDs
            }
        }
        if let json = text("META-INF/jarjar/metadata.json"),
            let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let jars = root["jars"] as? [[String: Any]]
        {
            toml.bundled = jars.compactMap { ($0["identifier"] as? [String: Any])?["artifact"] as? String }
        }
        return toml
    }
}

/// A mod another one needs that nothing installed provides.
public struct ModRequirement: Hashable, Sendable {
    /// The mod ID FML knows it by ("kotlinforforge").
    public var modID: String
    /// "Kotlin for Forge" when known, else the mod ID.
    public var name: String
    /// The Modrinth project when known; else `slugs` are tried.
    public var projectID: String?
    /// Why: "modLoader:kotlinforforge" or "dependency:architectury". Logged with the install.
    public var reason: String
    /// The file that needs it ("bountiful-neoforge-8.0.0-beta.2.jar"), when known.
    public var neededBy: String?

    public init(modID: String, name: String, projectID: String? = nil, reason: String, neededBy: String? = nil) {
        self.modID = modID
        self.name = name
        self.projectID = projectID
        self.reason = reason
        self.neededBy = neededBy
    }

    /// Modrinth slugs to look up when `projectID` is nil: the alias first, then the mod ID as written and dashed.
    public var slugs: [String] {
        var out = [ModRequirements.aliases[modID], modID, modID.replacingOccurrences(of: "_", with: "-")].compactMap {
            $0
        }
        out = out.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        return projectID == nil ? out : []
    }
}

public enum ModRequirements {
    /// Language providers that are mods on Modrinth: provider → (project, name).
    static let providers: [String: (project: String, name: String)] = [
        "kotlinforforge": ("ordsPcFz", "Kotlin for Forge")
    ]
    /// Shipped with the loader or the game: never missing.
    static let builtIn: Set<String> = [
        "minecraft", "forge", "neoforge", "fml", "javafml", "lowcodefml", "mcp", "java", "fabricloader",
        "fabric-loader",
    ]
    /// Mod IDs whose Modrinth slug reads differently.
    static let aliases: [String: String] = [
        "kotlinforforge": "kotlin-for-forge", "architectury": "architectury-api", "cloth_config": "cloth-config",
        "forgeconfigapiport": "forge-config-api-port", "puzzleslib": "puzzles-lib", "resourcefullib": "resourceful-lib",
        "bookshelf": "bookshelf-lib", "owo": "owo-lib", "yet_another_config_lib_v3": "yacl", "fabric": "fabric-api",
        "fabric_language_kotlin": "fabric-language-kotlin", "sophisticatedcore": "sophisticated-core",
    ]
    /// How a library is written, for "Get TerraBlender, GlitchCore" before Modrinth has said.
    static let names: [String: String] = ["terrablender": "TerraBlender", "glitchcore": "GlitchCore"]

    /// Required by a jar in `jars` (file name → its mods.toml) and provided by none of them, nor by a file whose name
    /// carries the mod ID (`otherFiles`: enabled jars without a mods.toml, like a provider jar). Language providers
    /// always count; plain dependencies only when the jar says required.
    public static func missing(in jars: [(file: String, toml: ModsToml)], otherFiles: [String] = []) -> [ModRequirement]
    {
        let ids = Set(jars.flatMap(\.toml.modIDs).map { $0.lowercased() })
        let names = (jars.map(\.file) + otherFiles + jars.flatMap(\.toml.bundled)).map(key)
        func present(_ id: String) -> Bool {
            let id = id.lowercased()
            return builtIn.contains(id) || ids.contains(id) || names.contains { $0.contains(key(id)) }
        }
        var out: [ModRequirement] = []
        func add(_ r: ModRequirement) { if !out.contains(where: { $0.modID == r.modID }) { out.append(r) } }
        for (file, toml) in jars {
            if let loader = toml.modLoader?.lowercased(), let known = providers[loader], !present(loader) {
                add(
                    ModRequirement(
                        modID: loader, name: known.name, projectID: known.project,
                        reason: "modLoader:\(loader)", neededBy: file))
            }
            for d in toml.dependencies where d.required && !present(d.modID) {
                add(requirement(d.modID, reason: "dependency:\(d.modID)", neededBy: file))
            }
        }
        return out
    }

    /// What a mod-loading crash says is missing:
    /// - NeoForge: "Mod File mods/x.jar needs language provider kotlinforforge:4 or above to load"
    /// - NeoForge: "Mod bountiful requires kotlinforforge 4.0 or above" + "Currently, kotlinforforge is not installed"
    /// - Forge, and NeoForge 26.2's "Missing or unsupported mandatory dependencies:" list: "Mod ID: 'kotlinforforge',
    ///   Requested by: 'bountiful', Expected range: '[4,)', Actual version: '[MISSING]'"
    /// - Fabric: "… requires any version of fabric-language-kotlin, which is missing!"
    /// A version that's installed but too old isn't missing; that needs an update, not a Get.
    public static func fromCrash(_ text: String) -> [ModRequirement] {
        // NeoForge colours its own copy of the message ("Mod §ebiomesoplenty§r requires §6terrablender§r").
        let text = text.replacingOccurrences(of: "§[0-9a-fk-or]", with: "", options: .regularExpression)
        var out: [ModRequirement] = []
        func add(_ r: ModRequirement) {
            if !builtIn.contains(r.modID), !out.contains(where: { $0.modID == r.modID }) { out.append(r) }
        }
        for m in matches(#"Mod File (?:mods/)?(\S+?\.jar) needs language provider ([A-Za-z0-9_.-]+?)(?::|\s)"#, text) {
            let id = m[1].lowercased()
            if let known = providers[id] {
                add(
                    ModRequirement(
                        modID: id, name: known.name, projectID: known.project, reason: "modLoader:\(id)",
                        neededBy: m[0]))
            } else {
                add(requirement(id, reason: "modLoader:\(id)", neededBy: m[0]))
            }
        }
        for m in matches(#"Mod (\S+) requires (\S+) "#, text)
        where text.contains("Currently, \(m[1]) is not installed") {
            add(requirement(m[1], reason: "dependency:\(m[1])", neededBy: m[0]))
        }
        for m in matches(#"Mod ID: '([^']+)', Requested by: '([^']+)'[^\n]*Actual version: '\[MISSING\]'"#, text) {
            add(requirement(m[0], reason: "dependency:\(m[0])", neededBy: m[1]))
        }
        for m in matches(#"requires (?:any version|version \S+) of ([A-Za-z0-9_.-]+), which is missing"#, text) {
            add(requirement(m[0], reason: "dependency:\(m[0])", neededBy: nil))
        }
        return out
    }

    static func requirement(_ id: String, reason: String, neededBy: String?) -> ModRequirement {
        let id = id.lowercased()
        let known = providers[id]
        return ModRequirement(
            modID: id, name: known?.name ?? names[id] ?? id, projectID: known?.project, reason: reason,
            neededBy: neededBy)
    }

    private static func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// Capture groups of every match.
    private static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
        }
    }
}
