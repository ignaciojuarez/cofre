import Foundation
import Network

public struct MinecraftServerAddress: Equatable, Sendable {
    public let host: String
    public let port: UInt16?
    public init(host: String, port: UInt16? = nil) { self.host = host; self.port = port }
    public static func parse(_ value: String) -> Self? {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.utf8.count <= 255,
              s.allSatisfy({ $0.isLetter || $0.isNumber || ".-:[]".contains($0) }) else { return nil }
        if s.first == "[" {
            guard let close = s.firstIndex(of: "]") else { return nil }
            let host = String(s[s.index(after: s.startIndex)..<close])
            guard host.contains(":"), !host.contains("[") else { return nil }
            let rest = s[s.index(after: close)...]
            if rest.isEmpty { return .init(host: host) }
            guard rest.first == ":", let port = UInt16(rest.dropFirst()), port > 0 else { return nil }
            return .init(host: host, port: port)
        }
        guard !s.contains("["), !s.contains("]") else { return nil }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2 {
            guard !parts[0].isEmpty, let port = UInt16(parts[1]), port > 0 else { return nil }
            return .init(host: String(parts[0]), port: port)
        }
        return .init(host: s)
    }
    public var effectivePort: UInt16 { port ?? 25565 }
    public var display: String { port.map { host.contains(":") ? "[\(host)]:\($0)" : "\(host):\($0)" } ?? (host.contains(":") ? "[\(host)]" : host) }
}

public enum MinecraftLaunchArguments {
    public static func singleplayer(folder: String, gameVersion: String) -> [String] {
        let numbers = gameVersion.split(separator: ".").compactMap { Int($0) }
        let modern = numbers.count >= 2 && (numbers[0] > 1 || (numbers[0] == 1 && numbers[1] >= 20))
        return modern ? ["--quickPlaySingleplayer", folder] : []
    }

    public static func server(_ address: MinecraftServerAddress, gameVersion: String) -> [String] {
        let numbers = gameVersion.split(separator: ".").compactMap { Int($0) }
        let modern = numbers.count >= 2 && (numbers[0] > 1 || (numbers[0] == 1 && numbers[1] >= 20))
        if modern { return ["--quickPlayMultiplayer", address.display] }
        return ["--server", address.host, "--port", String(address.effectivePort)]
    }
}

public enum MinecraftMOTD {
    public static func flatten(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let a = value as? [Any] { return a.map(flatten).joined() }
        guard let d = value as? [String: Any] else { return "" }
        var out = (d["text"] as? String) ?? ""
        if let extra = d["extra"] { out += flatten(extra) }
        return out
    }
    public static func flattenJSON(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return "" }
        return flatten(json)
    }
}

public struct MinecraftServerStatus: Sendable, Equatable {
    public let motd: String, versionName: String?, protocolVersion: Int?, online: Int?, max: Int?, faviconPNG: Data?, latency: TimeInterval
}

public enum MinecraftServerPingError: Error { case invalidAddress, timeout, malformedResponse }

public final class MinecraftServerPinger: @unchecked Sendable {
    public init() {}
    public func ping(_ input: String, timeout: Duration = .seconds(5)) async throws -> MinecraftServerStatus {
        guard let address = MinecraftServerAddress.parse(input) else { throw MinecraftServerPingError.invalidAddress }
        let started = ContinuousClock.now
        let endpoint = await MinecraftSRV.resolve(address)
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: NWEndpoint.Port(rawValue: endpoint.effectivePort)!, using: .tcp)
        let transport = ConnectionTransport(connection)
        defer { transport.cancel() }
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: MinecraftServerStatus.self) { group in
                group.addTask {
                    try await transport.start()
                    try await transport.send(packet: Self.handshake(host: address.host, port: address.effectivePort))
                    try await transport.send(packet: Self.packet(id: 0))
                    let payload = try await transport.readPacket()
                    let object = try Self.statusObject(payload)
                    let players = object["players"] as? [String: Any]
                    let version = object["version"] as? [String: Any]
                    let elapsed = started.duration(to: .now).components
                    return MinecraftServerStatus(motd: MinecraftMOTD.flatten(object["description"] ?? ""),
                        versionName: version?["name"] as? String, protocolVersion: version?["protocol"] as? Int,
                        online: players?["online"] as? Int, max: players?["max"] as? Int,
                        faviconPNG: Self.favicon(object["favicon"] as? String),
                        latency: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
                }
                group.addTask {
                    try await Task.sleep(for: max(.zero, timeout - started.duration(to: .now)))
                    transport.cancel()
                    throw MinecraftServerPingError.timeout
                }
                defer { group.cancelAll(); transport.cancel() }
                return try await group.next()!
            }
        } onCancel: { transport.cancel() }
    }
    static func statusObject(_ packet: Data) throws -> [String: Any] {
        var reader = PacketReader(data: Array(packet))
        guard try reader.varint() == 0 else { throw MinecraftServerPingError.malformedResponse }
        let length = try reader.varint()
        guard length == reader.data.count - reader.index else { throw MinecraftServerPingError.malformedResponse }
        guard let object = try JSONSerialization.jsonObject(with: Data(reader.data.dropFirst(reader.index))) as? [String: Any] else {
            throw MinecraftServerPingError.malformedResponse
        }
        return object
    }
    private static func favicon(_ value: String?) -> Data? {
        guard let value, let comma = value.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...]))
    }
    private static func varint(_ n: Int) -> [UInt8] { var x = UInt32(n); var b:[UInt8]=[]; repeat { var c=UInt8(x&127); x >>= 7; if x != 0 { c |= 128 }; b.append(c) } while x != 0; return b }
    private static func packet(id: Int, long: Int64? = nil) -> Data { var p = Data(varint(id)); if let long { p.append(contentsOf: withUnsafeBytes(of: long.bigEndian, Array.init)) }; return Data(varint(p.count)) + p }
    private static func handshake(host: String, port: UInt16) -> Data { var p = Data(varint(0)); p.append(contentsOf: varint(765)); p.append(contentsOf: varint(host.utf8.count)); p.append(contentsOf: host.utf8); p.append(contentsOf: withUnsafeBytes(of: port.bigEndian, Array.init)); p.append(contentsOf: varint(1)); return Data(varint(p.count)) + p }
}

private struct PacketReader {
    let data: [UInt8]
    var index = 0
    mutating func varint() throws -> Int {
        var value = 0
        for shift in stride(from: 0, through: 28, by: 7) {
            guard index < data.count else { throw MinecraftServerPingError.malformedResponse }
            let byte = data[index]; index += 1
            value |= Int(byte & 127) << shift
            if byte & 128 == 0 { return value }
        }
        throw MinecraftServerPingError.malformedResponse
    }
}

private final class ConnectionTransport: @unchecked Sendable {
    let connection: NWConnection
    let queue = DispatchQueue(label: "cofre.server-ping")
    init(_ connection: NWConnection) { self.connection = connection }
    func start() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            var completed = false // All state callbacks run on queue.
            connection.stateUpdateHandler = { state in
                guard !completed else { return }
                switch state {
                case .ready: completed = true; c.resume()
                case .failed(let error): completed = true; c.resume(throwing: error)
                case .cancelled: completed = true; c.resume(throwing: CancellationError())
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }
    func send(packet: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            })
        }
    }
    func readPacket() async throws -> Data {
        var bytes: [UInt8] = []
        for _ in 0..<5 {
            let byte = try await receive(1)[0]; bytes.append(byte)
            if byte & 128 == 0 {
                var reader = PacketReader(data: bytes)
                let length = try reader.varint()
                guard length > 0, length < 4_000_000 else { throw MinecraftServerPingError.malformedResponse }
                return try await receive(length)
            }
        }
        throw MinecraftServerPingError.malformedResponse
    }
    private func receive(_ n: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            connection.receive(minimumIncompleteLength: n, maximumLength: n) { data, _, _, error in
                if let error { c.resume(throwing: error) }
                else if let data, data.count == n { c.resume(returning: data) }
                else { c.resume(throwing: MinecraftServerPingError.malformedResponse) }
            }
        }
    }
    func cancel() { connection.cancel() }
}


public struct CofreServerRecord: Sendable { public var name: String; public var ip: String; public var icon: Data?; public var acceptTextures: Int8?; public var hidden: Bool; public var unknown: [(String, NBTValue)] = []
    public init(name: String, ip: String, icon: Data? = nil, acceptTextures: Int8? = nil, hidden: Bool = false, unknown: [(String, NBTValue)] = []) { self.name=name; self.ip=ip; self.icon=icon; self.acceptTextures=acceptTextures; self.hidden=hidden; self.unknown=unknown }
}
@MainActor public final class CofreServersStore {
    public enum Failure: LocalizedError { case gameRunning, staleRecord
        public var errorDescription: String? { switch self { case .gameRunning: "Close the game first"; case .staleRecord: "The server list changed. Refresh and try again." } }
    }
    public let fileURL: URL
    private let running: () -> Bool
    public init(gameDirectory: URL, isGameRunning: @escaping () -> Bool = { false }) {
        fileURL = gameDirectory.appendingPathComponent("servers.dat"); running = isGameRunning
    }
    public func list() throws -> [CofreServerRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try ServersDatCodec.decode(Data(contentsOf: fileURL))
    }
    public static func id(index: Int, record: CofreServerRecord) -> String { "\(index):\(record.ip)" }
    public func record(id: String) throws -> CofreServerRecord {
        let records = try list()
        guard let index = records.indices.first(where: { Self.id(index: $0, record: records[$0]) == id }) else { throw Failure.staleRecord }
        return records[index]
    }
    @discardableResult public func add(_ server: CofreServerRecord) throws -> Int {
        try writable()
        var records = try list()
        if let index = records.firstIndex(where: { $0.ip.lowercased() == server.ip.lowercased() }) { return index }
        records.append(server); try save(records); return records.count - 1
    }
    public func remove(id: String) throws {
        try writable()
        var records = try list()
        guard let index = records.indices.first(where: { Self.id(index: $0, record: records[$0]) == id }) else { throw Failure.staleRecord }
        records.remove(at: index); try save(records)
    }
    public func remove(at index: Int) throws {
        try writable(); var records = try list()
        guard records.indices.contains(index) else { throw Failure.staleRecord }
        records.remove(at: index); try save(records)
    }
    @discardableResult public func copy(id: String, to destination: CofreServersStore) throws -> Int {
        try destination.add(record(id: id))
    }
    private func writable() throws { if running() { throw Failure.gameRunning } }
    private func save(_ records: [CofreServerRecord]) throws {
        try writable()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ServersDatCodec.encode(records).write(to: fileURL, options: .atomic)
    }
}

public enum ServersDatCodec {
    public static func decode(_ data: Data) throws -> [CofreServerRecord] {
        var r = Reader(d: data)
        guard try r.byte() == 10 else { throw MinecraftServerPingError.malformedResponse }
        _ = try r.string()
        let root = try r.compound()
        guard r.i == data.count, case .list(let list) = root.first(where: { $0.0 == "servers" })?.1 else { throw MinecraftServerPingError.malformedResponse }
        return try list.map { value in
            guard let record = record(value) else { throw MinecraftServerPingError.malformedResponse }
            return record
        }
    }
    public static func encode(_ records: [CofreServerRecord]) -> Data { var d=Data([10,0,0]); d.append(contentsOf: tagList("servers", records.map { value($0) })); d.append(0); return d }
    private static func value(_ s: CofreServerRecord) -> NBTValue { var p:[(String,NBTValue)]=[("name",.string(s.name)),("ip",.string(s.ip)),("hidden",.byte(s.hidden ? 1:0))]; if let i=s.icon { p.append(("icon",.string("data:image/png;base64,"+i.base64EncodedString()))) }; if let a=s.acceptTextures { p.append(("acceptTextures",.byte(a))) }; p.append(contentsOf:s.unknown); return .compound(p) }
    private static func record(_ v: NBTValue) -> CofreServerRecord? { guard case .compound(let p)=v, case .string(let n)=p.first(where:{$0.0=="name"})?.1, case .string(let ip)=p.first(where:{$0.0=="ip"})?.1 else{return nil}; var x=CofreServerRecord(name:n,ip:ip); for (k,v) in p { switch (k,v) { case ("icon",.string(let s)): x.icon=Data(base64Encoded:String(s.split(separator:",").last ?? "")); case ("acceptTextures",.byte(let b)): x.acceptTextures=b; case ("hidden",.byte(let b)): x.hidden=b != 0; case ("name",_), ("ip",_): break; default: x.unknown.append((k,v)) } }; return x }
    private static func tagList(_ name:String,_ vals:[NBTValue]) -> Data { var d=Data([9]); d.append(contentsOf:utf16(name)); d.append(10); d.append(contentsOf:Int32(vals.count).bigEndianBytes); for v in vals { d.append(compound(v)) }; return d }
    private static func compound(_ v:NBTValue)->Data { guard case .compound(let p)=v else{return Data()}; var d=Data(); for (k,v) in p { d.append(v.type); d.append(contentsOf:utf16(k)); switch v { case .byte(let x): d.append(UInt8(bitPattern:x)); case .string(let s): d.append(contentsOf:utf16(s)); case .compound: d.append(compound(v)); case .raw(_, let bytes): d.append(bytes); case .list(let values): d.append(values.first?.type ?? 10); d.append(contentsOf: Int32(values.count).bigEndianBytes); for value in values { d.append(compound(value)) } } }; d.append(0); return d }
    private static func utf16(_ s:String)->Data { var d=Data(); d.append(contentsOf:UInt16(s.utf8.count).bigEndianBytes); d.append(contentsOf:s.utf8); return d }
}
private extension FixedWidthInteger { var bigEndianBytes:[UInt8] { withUnsafeBytes(of: bigEndian, Array.init) } }
