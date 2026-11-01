import Foundation

/// A renderer compatibility rule maintained in Resources/known-mods.json.
public struct KnownMod: Codable, Hashable, Sendable, Identifiable {
    public enum Scope: String, Codable, Sendable { case metal, anyRenderer, gl26 }
    public enum Severity: String, Codable, Sendable { case broken, slow }
    public enum Evidence: String, Codable, Sendable { case device, expected }

    public let ids: [String]
    public let slugs: [String]
    public let fileNamePrefixes: [String]
    public let namePatterns: [String]
    public let name: String
    public let scope: Scope
    public let loaders: Set<Instance.Loader>?
    public let gameVersions: Set<String>?
    public let severity: Severity
    public let reason: String
    public let evidence: Evidence
    public let evidenceRef: String?

    public var id: String { name + ":" + scope.rawValue + ":" + reason }

    public init(
        ids: [String] = [], slugs: [String] = [], fileNamePrefixes: [String] = [], namePatterns: [String] = [],
        name: String, scope: Scope, loaders: Set<Instance.Loader>? = nil, gameVersions: Set<String>? = nil,
        severity: Severity, reason: String, evidence: Evidence, evidenceRef: String? = nil
    ) {
        self.ids = ids
        self.slugs = slugs
        self.fileNamePrefixes = fileNamePrefixes
        self.namePatterns = namePatterns
        self.name = name
        self.scope = scope
        self.loaders = loaders
        self.gameVersions = gameVersions
        self.severity = severity
        self.reason = reason
        self.evidence = evidence
        self.evidenceRef = evidenceRef
    }

    public func matches(
        id: String, name: String, fileName: String?, gameVersion: String,
        renderer: String, loader: Instance.Loader
    ) -> Bool {
        guard matchesIdentity(id: id, name: name, fileName: fileName) else { return false }
        if let loaders, !loaders.isEmpty, !loaders.contains(loader) { return false }
        if let gameVersions, !gameVersions.isEmpty,
            !gameVersions.contains(gameVersion), !(gameVersions.contains("26.x") && gameVersion.hasPrefix("26."))
        {
            return false
        }
        switch scope {
        case .metal: guard ContentCompatibility.rendererName(renderer) == "Metal" else { return false }
        case .anyRenderer: break
        case .gl26:
            guard gameVersion.hasPrefix("26."),
                ["MobileGlues", "ANGLE"].contains(ContentCompatibility.rendererName(renderer))
            else { return false }
        }
        return true
    }

    public func renderedReason(renderer: String, gameVersion: String) -> String {
        reason.replacingOccurrences(of: "{renderer}", with: renderer)
            .replacingOccurrences(of: "{gameVersion}", with: gameVersion)
    }

    private func matchesIdentity(id: String, name: String, fileName: String?) -> Bool {
        let normalizedID = Self.normalizedIdentity(id)
        let normalizedName = Self.normalized(name)
        let fileBase = (fileName ?? id) as NSString
        let normalizedFile = Self.normalized(fileBase.deletingPathExtension)
        let exact = Set((ids + slugs + namePatterns).map(Self.normalized))
        if exact.contains(normalizedID) || exact.contains(normalizedName) { return true }
        let prefixes = fileNamePrefixes.map(Self.normalized)
        return prefixes.contains { normalizedID.hasPrefix($0) || normalizedFile.hasPrefix($0) }
    }

    static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func normalizedIdentity(_ value: String) -> String {
        let lower = value.lowercased()
        return normalized(lower.hasSuffix(".jar") ? String(lower.dropLast(4)) : lower)
    }
}

public enum KnownModsCatalog {
    public struct Manifest: Codable, Sendable {
        public let schema: Int
        public let mods: [KnownMod]
        public init(schema: Int, mods: [KnownMod]) {
            self.schema = schema
            self.mods = mods
        }
    }

    /// The bundled list is decoded once for the lifetime of the process.
    public static let entries: [KnownMod] = load().mods

    public static func decode(_ data: Data) throws -> Manifest { try JSONDecoder().decode(Manifest.self, from: data) }

    public static func validate(_ manifest: Manifest) throws {
        guard manifest.schema == 1 else { throw CatalogValidationError.unsupportedSchema(manifest.schema) }
        var ids = Set<String>()
        for mod in manifest.mods {
            guard !mod.name.isEmpty, !mod.reason.isEmpty else { throw CatalogValidationError.missingCopy(mod.name) }
            guard mod.evidence != .device || mod.evidenceRef?.isEmpty == false else {
                throw CatalogValidationError.missingEvidence(mod.name)
            }
            guard ids.insert(mod.id).inserted else { throw CatalogValidationError.duplicateEntry(mod.id) }
        }
    }

    public static func match(
        id: String, name: String, fileName: String? = nil, gameVersion: String,
        renderer: String, loader: Instance.Loader
    ) -> KnownMod? {
        entries.filter {
            $0.matches(
                id: id, name: name, fileName: fileName, gameVersion: gameVersion, renderer: renderer, loader: loader)
        }.max { lhs, rhs in
            lhs.identitySpecificity(id: id, name: name, fileName: fileName)
                < rhs.identitySpecificity(id: id, name: name, fileName: fileName)
        }
    }

    public static func name(for id: String, name: String? = nil, fileName: String? = nil) -> String? {
        let normalizedID = KnownMod.normalizedIdentity(id)
        let normalizedName = KnownMod.normalized(name ?? "")
        let normalizedFile = KnownMod.normalized(fileName ?? "")
        return entries.filter { entry in
            let exact = Set((entry.ids + entry.slugs + entry.namePatterns).map(KnownMod.normalized))
            return exact.contains(normalizedID) || exact.contains(normalizedName)
                || entry.fileNamePrefixes.map(KnownMod.normalized).contains {
                    normalizedID.hasPrefix($0) || normalizedFile.hasPrefix($0)
                }
        }.max { lhs, rhs in
            lhs.identitySpecificity(id: id, name: name ?? "", fileName: fileName)
                < rhs.identitySpecificity(id: id, name: name ?? "", fileName: fileName)
        }?.name
    }

    public enum CatalogValidationError: Error, Equatable, Sendable {
        case unsupportedSchema(Int)
        case missingCopy(String)
        case missingEvidence(String)
        case duplicateEntry(String)
    }

    private static func load() -> Manifest {
        guard let url = Bundle.module.url(forResource: "known-mods", withExtension: "json"),
            let data = try? Data(contentsOf: url), let manifest = try? decode(data),
            (try? validate(manifest)) != nil
        else { return Manifest(schema: 1, mods: []) }
        return manifest
    }
}

extension KnownMod {
    fileprivate func identitySpecificity(id: String, name: String, fileName: String?) -> Int {
        let normalizedID = Self.normalizedIdentity(id)
        let normalizedName = Self.normalized(name)
        if (ids + slugs + namePatterns).map(Self.normalized).contains(normalizedID)
            || (ids + slugs + namePatterns).map(Self.normalized).contains(normalizedName)
        {
            return 10_000
        }
        let file = Self.normalized(fileName ?? id)
        return fileNamePrefixes.map(Self.normalized)
            .filter { normalizedID.hasPrefix($0) || file.hasPrefix($0) }
            .map(\.count).max() ?? 0
    }
}
