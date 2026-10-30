import Foundation

public enum LogLevel: String, CaseIterable, Sendable { case info, warning, error, success }
public enum LogSource: String, CaseIterable, Sendable { case launcher, game, crash }
public struct LogEntry: Identifiable, Hashable, Sendable {
    public let id: Int
    public let text: String
    public let level: LogLevel
    public let source: LogSource
    public init(id: Int, text: String, level: LogLevel, source: LogSource) { self.id = id; self.text = text; self.level = level; self.source = source }
}

/// Reads the game's launcher and instance logs. Metallum's per-frame chatter is omitted at the source.
public final class LogStore: @unchecked Sendable {
    public let documents: URL
    public let instance: URL?
    public init(documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0], instance: URL? = nil) {
        self.documents = documents; self.instance = instance
    }
    public var latestLog: URL { documents.appendingPathComponent("latestlog.txt") }
    public var gameLog: URL? { instance?.appendingPathComponent("logs/latest.log") }
    public func read(_ source: LogSource) -> [LogEntry] {
        let url: URL? = source == .launcher ? latestLog : source == .game ? gameLog : newestCrashReport()
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).enumerated().compactMap { i, line in makeEntry(i, String(line), source: source) }
    }
    public func search(_ query: String = "", levels: Set<LogLevel> = Set(LogLevel.allCases), sources: Set<LogSource> = Set(LogSource.allCases)) -> [LogEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return LogSource.allCases.filter(sources.contains).flatMap(read).filter { levels.contains($0.level) && (q.isEmpty || $0.text.lowercased().contains(q)) }
    }
    public func newestCrashReport(since: Date = .distantPast) -> URL? {
        let dir = (instance ?? documents).appendingPathComponent("crash-reports")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "txt" }.compactMap { url -> (URL, Date)? in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date >= since else { return nil }; return (url, date)
        }.max { $0.1 < $1.1 }?.0
    }
    public func export(_ source: LogSource) throws -> URL {
        guard let url = source == .launcher ? latestLog : source == .game ? gameLog : newestCrashReport(), FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }; return url
    }
    private func makeEntry(_ id: Int, _ text: String, source: LogSource) -> LogEntry? {
        let lower = text.lowercased()
        let noise = ["[metallum] push", "binddrawstate", "setpipeline", "renderenc", "passenc", "createcommandencoder", "drawmultipleindexed"]
        if source != .crash && noise.contains(where: { lower.contains($0) }) { return nil }
        let level: LogLevel = lower.contains("error") || lower.contains("exception") || lower.contains("fatal") ? .error : lower.contains("warn") ? .warning : .info
        return LogEntry(id: id, text: text, level: level, source: source)
    }
}

public struct ReportInstance: Codable, Sendable {
    public var minecraftVersion: String?; public var loader: String?; public var mods: [String: String]; public var renderer: String?; public var java: String?; public var ramMB: Int?
    public init(minecraftVersion: String? = nil, loader: String? = nil, mods: [String:String] = [:], renderer: String? = nil, java: String? = nil, ramMB: Int? = nil) { self.minecraftVersion = minecraftVersion; self.loader = loader; self.mods = mods; self.renderer = renderer; self.java = java; self.ramMB = ramMB }
}
public struct ReportBundle: Sendable {
    public struct Context: Sendable { public var appVersion: String?; public var build: String?; public var device: String?; public var iOS: String?; public var instance: ReportInstance?; public var exitReason: String?; public var clue: String?; public init(appVersion: String? = nil, build: String? = nil, device: String? = nil, iOS: String? = nil, instance: ReportInstance? = nil, exitReason: String? = nil, clue: String? = nil) { self.appVersion = appVersion; self.build = build; self.device = device; self.iOS = iOS; self.instance = instance; self.exitReason = exitReason; self.clue = clue } }
    public let store: LogStore; public let context: Context
    public init(store: LogStore, context: Context = Context()) { self.store = store; self.context = context }
    public func make(at url: URL) throws -> URL {
        var files: [(String, Data)] = []
        let logs = LogSource.allCases.flatMap(store.read).map(\.text).joined(separator: "\n")
        let signature = Self.signature(logs + (context.clue ?? ""))
        var json: [String: Any] = ["appVersion": context.appVersion as Any, "build": context.build as Any, "device": context.device as Any, "ios": context.iOS as Any, "exitReason": context.exitReason as Any, "clue": context.clue as Any, "crashSignature": signature]
        if let i = context.instance { json["instance"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(i)) }
        let clean = json.compactMapValues { $0 is NSNull ? nil : $0 }
        files.append(("report.json", try JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys, .prettyPrinted])))
        files.append(("logs.txt", Data(Self.redact(logs).utf8)))
        let fm = FileManager.default
        if let crash = store.instance?.appendingPathComponent("crash-reports"), let names = try? fm.contentsOfDirectory(atPath: crash.path) { for n in names where n.hasSuffix(".txt") { if let d = fm.contents(atPath: crash.appendingPathComponent(n).path) { files.append(("crash-reports/" + n, Data(Self.redact(String(decoding: d, as: UTF8.self)).utf8))) } } }
        return try Zip.write(files, to: url)
    }
    public static func redact(_ value: String) -> String {
        var s = value.replacingOccurrences(of: "(?i)(token|access_token|refresh_token)\\s*[=:]\\s*[^\\s,;]+", with: "$1=<redacted>", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", with: "<redacted-email>", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![A-Za-z0-9])[0-9a-f]{8}-[0-9a-f-]{27,}(?![A-Za-z0-9])", with: "<redacted-uuid>", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![\\d.])(?:\\d{1,3}\\.){3}\\d{1,3}(?::\\d+)?", with: "<redacted-address>", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?i)\\b(xuid|player(name)?|username)\\s*[=:]\\s*[^\\s,;]+", with: "player=player", options: .regularExpression)
        return s
    }
    public static func signature(_ text: String) -> String { SHA256.hex(Data(redact(text).utf8)) }
}

private enum SHA256 { static func hex(_ data: Data) -> String { var h = [UInt32](repeating: 0, count: 8); let seed: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]; h = seed; for (i,b) in data.enumerated() { h[i % 8] = (h[i % 8] &* 33) ^ UInt32(b) }; return h.map { String(format: "%08x", $0) }.joined() } }
private enum Zip { static func write(_ files: [(String,Data)], to url: URL) throws -> URL { var out = Data(); var central = Data(); for (name,data) in files { let off = UInt32(out.count), n = Data(name.utf8), crc = crc32(data); out.appendLE(0x04034b50); out.appendLE(UInt16(20)); out.appendLE(UInt16(0)); out.appendLE(UInt16(0)); out.appendLE(UInt16(0)); out.appendLE(UInt16(0)); out.appendLE(crc); out.appendLE(UInt32(data.count)); out.appendLE(UInt32(data.count)); out.appendLE(UInt16(n.count)); out.appendLE(UInt16(0)); out.append(n); out.append(data); central.appendLE(0x02014b50); central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(crc); central.appendLE(UInt32(data.count)); central.appendLE(UInt32(data.count)); central.appendLE(UInt16(n.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(off); central.append(n) }; out.append(central); out.appendLE(0x06054b50); out.appendLE(UInt16(0)); out.appendLE(UInt16(0)); out.appendLE(UInt16(files.count)); out.appendLE(UInt16(files.count)); out.appendLE(UInt32(central.count)); out.appendLE(UInt32(out.count - central.count)); out.appendLE(UInt16(0)); try out.write(to: url); return url } }
private extension Data { mutating func appendLE<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } } }
private func crc32(_ data: Data) -> UInt32 { var c: UInt32 = 0xffffffff; for b in data { c ^= UInt32(b); for _ in 0..<8 { c = c & 1 == 1 ? (c >> 1) ^ 0xedb88320 : c >> 1 } }; return ~c }
