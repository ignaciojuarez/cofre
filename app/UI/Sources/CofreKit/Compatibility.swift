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
    public func supports(_ integration: String, gameVersion: String) -> Bool { integrations[integration.lowercased()]?.contains(gameVersion) == true || integrations[integration]?.contains(gameVersion) == true }
    public static func load(from url: URL) throws -> RendererManifest { try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
}

public struct CompatibilityEvidence: Codable, Sendable, Hashable {
    public enum Level: String, Codable, Sendable { case info, warning, blocker, verified }
    public let code: String, level: Level, message: String, source: String
    public init(code: String, level: Level, message: String, source: String) { self.code = code; self.level = level; self.message = message; self.source = source }
}

public struct CompatibilityReport: Codable, Sendable, Hashable {
    public let itemID: String, version: String, gameVersion: String, loader: String
    public let renderer: RendererManifest, evidence: [CompatibilityEvidence]
    public var canPlay: Bool { !evidence.contains { $0.level == .blocker } }
    public init(itemID: String, version: String = "", gameVersion: String, loader: String = "", renderer: RendererManifest, evidence: [CompatibilityEvidence]) { self.itemID = itemID; self.version = version; self.gameVersion = gameVersion; self.loader = loader; self.renderer = renderer; self.evidence = evidence }
}

public struct LaunchContext: Sendable { public let gameVersion: String, loader: String, renderer: String; public init(gameVersion: String, loader: String = "", renderer: String = "Metal") { self.gameVersion = gameVersion; self.loader = loader; self.renderer = renderer } }

public final class CompatibilityScanner: @unchecked Sendable {
    public static let defaultByteCap = 32 * 1024 * 1024
    private let cap: Int
    private var cache: [String: CompatibilityReport] = [:]
    public init(byteCap: Int = defaultByteCap) { cap = max(1, byteCap) }
    public func scan(contentURL: URL, context: LaunchContext, manifest: RendererManifest) throws -> CompatibilityReport {
        let data = try Data(contentsOf: contentURL, options: .mappedIfSafe)
        let key = sha1(data); if let cached = cache[key] { return cached }
        let entries = try ZipEntries(data: data, cap: cap).all()
        var evidence: [CompatibilityEvidence] = []
        var metadata: [String: Any] = [:]
        for e in entries { if ["fabric.mod.json", "quilt.mod.json"].contains(e.name) { if let obj = try? JSONSerialization.jsonObject(with: e.data) as? [String: Any] { metadata.merge(obj) { a, _ in a } } }; if e.name.hasSuffix("mods.toml") || e.name.hasSuffix("neoforge.mods.toml") { evidence += tomlEvidence(e.data, context: context) } }
        evidence += declarationEvidence(metadata, context: context)
        for e in entries {
            let lower = e.name.lowercased()
            if lower.hasPrefix("natives/") && [".so", ".dll", ".dylib"].contains(where: lower.hasSuffix) { evidence.append(.init(code: "desktop-native", level: .blocker, message: "bundles a desktop native library", source: e.name)) }
            if lower.hasSuffix(".class") { evidence += classEvidence(e.data, source: e.name) }
            if lower.hasSuffix("mixins.json") || lower.contains("mixin") && lower.hasSuffix(".json") { evidence += mixinEvidence(e.data, source: e.name) }
        }
        if (manifest.supports("iris", gameVersion: context.gameVersion) == false) && metadata.keys.contains(where: { $0.lowercased().contains("iris") }) { evidence.append(.init(code: "missing-renderer", level: .blocker, message: "requires Iris integration for this Minecraft version", source: "manifest")) }
        let id = (metadata["id"] as? String) ?? contentURL.deletingPathExtension().lastPathComponent
        let version = (metadata["version"] as? String) ?? ""
        let report = CompatibilityReport(itemID: id, version: version, gameVersion: context.gameVersion, loader: context.loader, renderer: manifest, evidence: evidence)
        cache[key] = report; return report
    }
    public struct ShaderRequirements: Sendable, Hashable {
        public var glslMin: Int = 0, compute = false, ssbo = false, imageLoadStore = false
        public var extensions: Set<String> = []
    }
    public func scanShader(contentURL: URL, context: LaunchContext, manifest: RendererManifest) throws -> ShaderRequirements {
        let entries = try ZipEntries(data: Data(contentsOf: contentURL), cap: cap).all()
        var r = ShaderRequirements()
        for e in entries where e.name.lowercased().hasSuffix(".glsl") || e.name.lowercased().contains("shaders/") {
            let text = String(decoding: e.data, as: UTF8.self)
            if let v = text.range(of: #"(?m)^\s*#version\s+\d+"#, options: .regularExpression),
                let n = Int(text[v].split(separator: " ").last ?? "") { r.glslMin = max(r.glslMin, n) }
            r.compute = r.compute || e.name.lowercased().contains("compute") || text.contains("gl_GlobalInvocationID")
            r.ssbo = r.ssbo || text.contains("std430") || text.contains("buffer ")
            r.imageLoadStore = r.imageLoadStore || text.contains("imageLoad") || text.contains("imageStore")
            for line in text.split(separator: "\n") where line.contains("#extension") { r.extensions.insert(String(line).trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return r
    }
    private func sha1(_ d: Data) -> String { InsecureHash.sha1(d) }
}

private func declarationEvidence(_ m: [String: Any], context: LaunchContext) -> [CompatibilityEvidence] { var out:[CompatibilityEvidence]=[]; if let env = m["environment"] as? String, env == "server" { out.append(.init(code:"server-only",level:.blocker,message:"declares a server-only environment",source:"metadata")) }; if let depends = m["depends"] as? [String: Any] { for (name, value) in depends { if name.lowercased().contains("minecraft"), let range = value as? String, !range.isEmpty && !range.contains(context.gameVersion) { out.append(.init(code:"mc-version",level:.blocker,message:"requires Minecraft \(range)",source:"fabric.mod.json")) } } }; return out }
private func tomlEvidence(_ d: Data, context: LaunchContext) -> [CompatibilityEvidence] { let s = String(decoding:d,as:UTF8.self); var o:[CompatibilityEvidence]=[]; if s.range(of:"clientSide\\s*=\\s*false",options:.regularExpression) != nil { o.append(.init(code:"server-only",level:.blocker,message:"declares a server-only environment",source:"mods.toml")) }; if s.range(of:"mandatory\\s*=\\s*true",options:.regularExpression) != nil && s.contains("minecraft") && !s.contains(context.gameVersion) { o.append(.init(code:"mc-version",level:.blocker,message:"requires a different Minecraft version",source:"mods.toml")) }; return o }
private func classEvidence(_ d: Data, source: String) -> [CompatibilityEvidence] { let s = String(decoding:d,as: UTF8.self); var o:[CompatibilityEvidence]=[]; for needle in ["org/lwjgl/opengl/GL4", "GL43", "org/lwjgl/vulkan", "compute", "SSBO", "imageLoad", "java/awt", "javax/swing", "javafx"] where s.range(of: needle, options: .caseInsensitive) != nil { o.append(.init(code:"renderer-reference",level:.warning,message:"references desktop graphics or UI APIs (\(needle))",source:source)) }; return o }
private func mixinEvidence(_ d: Data, source: String) -> [CompatibilityEvidence] { let s=String(decoding:d,as:UTF8.self); return (s.contains("renderer") || s.contains("Sodium") || s.contains("Iris")) ? [.init(code:"renderer-mixin",level:.warning,message:"targets renderer classes through a mixin",source:source)] : [] }

private struct ZipEntries { let data: Data; let cap: Int; func all() throws -> [(name:String,data:Data)] { var out:[(String,Data)]=[]; var p=0,total=0; let b=[UInt8](data); while p+30 <= b.count { guard b[p...].starts(with:[0x50,0x4b,0x03,0x04]) else { break }; let method=UInt16(b[p+8])|UInt16(b[p+9])<<8; let c=Int(UInt32(b[p+18])|UInt32(b[p+19])<<8|UInt32(b[p+20])<<16|UInt32(b[p+21])<<24); let u=Int(UInt32(b[p+22])|UInt32(b[p+23])<<8|UInt32(b[p+24])<<16|UInt32(b[p+25])<<24); let nl=Int(UInt16(b[p+26])|UInt16(b[p+27])<<8), xl=Int(UInt16(b[p+28])|UInt16(b[p+29])<<8); let ns=p+30, ds=ns+nl+xl; guard ds+c<=b.count else { throw NSError(domain:"zip",code:1) }; total += u; guard total <= cap else { throw NSError(domain:"zip",code:2) }; let name=String(decoding:b[ns..<ns+nl],as:UTF8.self); guard method == 0 else { p=ds+c; continue }; out.append((name,Data(b[ds..<ds+c]))); p=ds+c }; return out } }
private enum InsecureHash { static func sha1(_ d:Data)->String { var h:[UInt32]=[0x67452301,0xEFCDAB89,0x98BADCFE,0x10325476,0xC3D2E1F0]; var bytes=[UInt8](d); let n=UInt64(bytes.count)*8; bytes.append(0x80); while bytes.count%64 != 56 { bytes.append(0) }; bytes += Array(repeating:0,count:8); for i in 0..<8 { bytes[bytes.count-1-i]=UInt8(n >> UInt64(i*8)) }; for chunk in stride(from:0,to:bytes.count,by:64){ var w=[UInt32](repeating:0,count:80); for i in 0..<16 { let q=chunk+i*4; w[i]=UInt32(bytes[q])<<24|UInt32(bytes[q+1])<<16|UInt32(bytes[q+2])<<8|UInt32(bytes[q+3]) }; for i in 16..<80 { w[i]=(w[i-3]^w[i-8]^w[i-14]^w[i-16]).rotl(1) }; var (a,b,c,dv,e)=(h[0],h[1],h[2],h[3],h[4]); for i in 0..<80 { let f=i<20 ? ((b&c)|((~b)&dv)) : i<40 ? (b^c^dv) : i<60 ? ((b&c)|(b&dv)|(c&dv)) : (b^c^dv); let k:[UInt32]=[0x5A827999,0x6ED9EBA1,0x8F1BBCDC,0xCA62C1D6]; let t=a.rotl(5)&+f&+e&+k[i/20]&+w[i]; e=dv;dv=c;c=b.rotl(30);b=a;a=t }; h[0]&+=a;h[1]&+=b;h[2]&+=c;h[3]&+=dv;h[4]&+=e }; return h.map{String(format:"%08x",$0)}.joined() } }
private extension UInt32 { func rotl(_ n:UInt32)->UInt32 { (self << n) | (self >> (32-n)) } }
