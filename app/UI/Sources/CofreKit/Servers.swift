import Foundation
import Network

public struct MinecraftServerAddress: Equatable, Sendable {
    public let host: String
    public let port: UInt16?
    public init(host: String, port: UInt16? = nil) { self.host = host; self.port = port }
    public static func parse(_ value: String) -> Self? {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.first == "[", let close = s.firstIndex(of: "]") {
            let host = String(s[s.index(after: s.startIndex)..<close])
            let rest = s[s.index(after: close)...]
            if rest.first == ":", let p = UInt16(rest.dropFirst()), p > 0 { return .init(host: host, port: p) }
            return .init(host: host)
        }
        let pieces = s.split(separator: ":", omittingEmptySubsequences: false)
        if pieces.count == 2, let p = UInt16(pieces[1]), p > 0 { return .init(host: String(pieces[0]), port: p) }
        return .init(host: s)
    }
    public var effectivePort: UInt16 { port ?? 25565 }
    public var display: String { port.map { host.contains(":") ? "[\(host)]:\($0)" : "\(host):\($0)" } ?? host }
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
        let connection = NWConnection(host: NWEndpoint.Host(address.host), port: NWEndpoint.Port(rawValue: address.effectivePort)!, using: .tcp)
        let transport = ConnectionTransport(connection)
        try await transport.start(timeout: timeout)
        let started = ContinuousClock.now
        try await transport.send(packet: Self.handshake(host: address.host, port: address.effectivePort))
        try await transport.send(packet: Self.packet(id: 0))
        let payload = try await transport.readPacket(timeout: timeout)
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] ?? [:]
        let desc = object["description"] ?? ""
        let players = object["players"] as? [String: Any]
        let version = object["version"] as? [String: Any]
        try await transport.send(packet: Self.packet(id: 1, long: Int64((started.duration(to: .now).components.attoseconds) / 1_000_000_000)))
        _ = try? await transport.readPacket(timeout: timeout)
        transport.cancel()
        return MinecraftServerStatus(motd: MinecraftMOTD.flatten(desc), versionName: version?["name"] as? String,
            protocolVersion: version?["protocol"] as? Int, online: players?["online"] as? Int, max: players?["max"] as? Int,
            faviconPNG: Self.favicon(object["favicon"] as? String), latency: Double(started.duration(to: .now).components.seconds))
    }
    private static func favicon(_ value: String?) -> Data? {
        guard let value, let comma = value.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...]))
    }
    private static func varint(_ n: Int) -> [UInt8] { var x = UInt32(n); var b:[UInt8]=[]; repeat { var c=UInt8(x&127); x >>= 7; if x != 0 { c |= 128 }; b.append(c) } while x != 0; return b }
    private static func packet(id: Int, long: Int64? = nil) -> Data { var p = Data(varint(id)); if let long { p.append(contentsOf: withUnsafeBytes(of: long.bigEndian, Array.init)) }; return Data(varint(p.count)) + p }
    private static func handshake(host: String, port: UInt16) -> Data { var p = Data(varint(0)); p.append(contentsOf: varint(765)); p.append(contentsOf: varint(host.utf8.count)); p.append(contentsOf: host.utf8); p.append(contentsOf: withUnsafeBytes(of: port.bigEndian, Array.init)); p.append(contentsOf: varint(1)); return Data(varint(p.count)) + p }
}

private final class ConnectionTransport: @unchecked Sendable {
    let connection: NWConnection
    init(_ connection: NWConnection) { self.connection = connection }
    func start(timeout: Duration) async throws { try await withThrowingTaskGroup(of: Void.self) { group in group.addTask { try await self.waitReady() }; group.addTask { try await Task.sleep(for: timeout); throw MinecraftServerPingError.timeout }; defer { group.cancelAll() }; return try await group.next()! } }
    private func waitReady() async throws { try await withCheckedThrowingContinuation { c in connection.stateUpdateHandler = { state in switch state { case .ready: c.resume(); case .failed(let e): c.resume(throwing: e); case .cancelled: c.resume(throwing: MinecraftServerPingError.timeout); default: break } }; connection.start(queue: .global()) } }
    func send(packet: Data) async throws { try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in connection.send(content: packet, completion: .contentProcessed { error in if let error { c.resume(throwing: error) } else { c.resume(returning: ()) } }) } }
    func readPacket(timeout: Duration) async throws -> Data { try await withThrowingTaskGroup(of: Data.self) { g in g.addTask { try await self.readPacketBody() }; g.addTask { try await Task.sleep(for: timeout); throw MinecraftServerPingError.timeout }; defer { g.cancelAll() }; return try await g.next()! } }
    private func readPacketBody() async throws -> Data { var length = 0; var shift = 0; var more = true; while more { let b = try await receive(1)[0]; length |= Int(b & 127) << shift; more = b & 128 != 0; shift += 7 }; guard length > 0, length < 4_000_000 else { throw MinecraftServerPingError.malformedResponse }; let body = try await receive(length); var i=0; repeat { more = body[i] & 128 != 0; i += 1 } while more; return Data(body.dropFirst(i)) }
    private func receive(_ n: Int) async throws -> Data { try await withCheckedThrowingContinuation { c in connection.receive(minimumIncompleteLength: n, maximumLength: n) { data,_,_,error in if let error { c.resume(throwing:error) } else if let data, data.count == n { c.resume(returning:data) } else { c.resume(throwing:MinecraftServerPingError.malformedResponse) } } } }
    func cancel() { connection.cancel() }
}

public enum NBTValue: Sendable { case byte(Int8), string(String), compound([(String, NBTValue)]), list([NBTValue]); var type: UInt8 { switch self { case .byte: 1; case .string: 8; case .compound: 10; case .list: 9 } } }

public struct CofreServerRecord: Sendable { public var name: String; public var ip: String; public var icon: Data?; public var acceptTextures: Int8?; public var hidden: Bool; public var unknown: [(String, NBTValue)] = []
    public init(name: String, ip: String, icon: Data? = nil, acceptTextures: Int8? = nil, hidden: Bool = false, unknown: [(String, NBTValue)] = []) { self.name=name; self.ip=ip; self.icon=icon; self.acceptTextures=acceptTextures; self.hidden=hidden; self.unknown=unknown }
}
public actor CofreServersStore {
    public let fileURL: URL
    public init(gameDirectory: URL) { fileURL = gameDirectory.appendingPathComponent("servers.dat") }
    public func list() throws -> [CofreServerRecord] { guard let d = try? Data(contentsOf: fileURL) else { return [] }; return try ServersDatCodec.decode(d) }
    public func add(_ server: CofreServerRecord) throws { var x=try list(); x.append(server); try save(x) }
    public func edit(at index: Int, _ update: (inout CofreServerRecord) -> Void) throws { var x=try list(); guard x.indices.contains(index) else{return}; update(&x[index]); try save(x) }
    public func remove(at index: Int) throws { var x=try list(); guard x.indices.contains(index) else{return}; x.remove(at:index); try save(x) }
    public func move(from index: Int, to destination: Int) throws { var x=try list(); guard x.indices.contains(index), destination >= 0, destination <= x.count else{return}; let v=x.remove(at:index); x.insert(v, at:min(destination,x.count)); try save(x) }
    public func copy(to directory: URL) throws { var x=try list(); let target=directory.appendingPathComponent("servers.dat"); try FileManager.default.createDirectory(at:directory, withIntermediateDirectories:true); let tmp=target.appendingPathExtension("tmp"); try ServersDatCodec.encode(x).write(to:tmp, options:.atomic); _=try FileManager.default.replaceItemAt(target, withItemAt:tmp) }
    private func save(_ x:[CofreServerRecord]) throws { try FileManager.default.createDirectory(at:fileURL.deletingLastPathComponent(), withIntermediateDirectories:true); let tmp=fileURL.appendingPathExtension("tmp"); try ServersDatCodec.encode(x).write(to:tmp, options:.atomic); if FileManager.default.fileExists(atPath:fileURL.path) { _=try FileManager.default.replaceItemAt(fileURL, withItemAt:tmp) } else { try FileManager.default.moveItem(at:tmp,to:fileURL) } }
}

public enum ServersDatCodec {
    public static func decode(_ data: Data) throws -> [CofreServerRecord] { var r=Reader(d: data); guard r.byte()==10 else { throw MinecraftServerPingError.malformedResponse }; _ = r.string(); let root=r.compound(); guard case .list(let list)=root.first(where:{$0.0=="servers"})?.1 else { return [] }; return list.compactMap { record($0) } }
    public static func encode(_ records: [CofreServerRecord]) -> Data { var d=Data([10,0,0]); d.append(contentsOf: tagList("servers", records.map { value($0) })); d.append(0); return d }
    private static func value(_ s: CofreServerRecord) -> NBTValue { var p:[(String,NBTValue)]=[("name",.string(s.name)),("ip",.string(s.ip)),("hidden",.byte(s.hidden ? 1:0))]; if let i=s.icon { p.append(("icon",.string("data:image/png;base64,"+i.base64EncodedString()))) }; if let a=s.acceptTextures { p.append(("acceptTextures",.byte(a))) }; p.append(contentsOf:s.unknown); return .compound(p) }
    private static func record(_ v: NBTValue) -> CofreServerRecord? { guard case .compound(let p)=v, case .string(let n)=p.first(where:{$0.0=="name"})?.1, case .string(let ip)=p.first(where:{$0.0=="ip"})?.1 else{return nil}; var x=CofreServerRecord(name:n,ip:ip); for (k,v) in p { switch (k,v) { case ("icon",.string(let s)): x.icon=Data(base64Encoded:String(s.split(separator:",").last ?? "")); case ("acceptTextures",.byte(let b)): x.acceptTextures=b; case ("hidden",.byte(let b)): x.hidden=b != 0; case ("name",_), ("ip",_): break; default: x.unknown.append((k,v)) } }; return x }
    private static func tagList(_ name:String,_ vals:[NBTValue]) -> Data { var d=Data([9]); d.append(contentsOf:utf16(name)); d.append(10); d.append(contentsOf:Int32(vals.count).bigEndianBytes); for v in vals { d.append(compound(v)) }; return d }
    private static func compound(_ v:NBTValue)->Data { guard case .compound(let p)=v else{return Data()}; var d=Data(); for (k,v) in p { d.append(v.type); d.append(contentsOf:utf16(k)); switch v { case .byte(let x): d.append(UInt8(bitPattern:x)); case .string(let s): d.append(contentsOf:utf16(s)); case .compound: d.append(compound(v)); case .list: break } }; d.append(0); return d }
    private static func utf16(_ s:String)->Data { var d=Data(); d.append(contentsOf:UInt16(s.utf8.count).bigEndianBytes); d.append(contentsOf:s.utf8); return d }
}
private extension FixedWidthInteger { var bigEndianBytes:[UInt8] { withUnsafeBytes(of: bigEndian, Array.init) } }
private struct Reader { var d:Data; var i=0; mutating func byte()->UInt8 { defer{i+=1}; return d[i] }; mutating func int32()->Int32 { let b=d[i..<i+4]; i += 4; return b.reduce(0){($0 << 8) | Int32($1)} }; mutating func string()->String { let n=Int(UInt16(byte())<<8|UInt16(byte())); let x=d[i..<i+n]; i += n; return String(decoding:x,as:UTF8.self) }; mutating func compound()->[(String,NBTValue)] { var p:[(String,NBTValue)]=[]; while d[i] != 0 { let t=byte(), k=string(); p.append((k, val(t))) }; i += 1; return p }; mutating func val(_ t:UInt8)->NBTValue { switch t { case 1:return .byte(Int8(bitPattern:byte())); case 8:return .string(string()); case 9:let et=byte(), n=Int(int32()); return .list((0..<n).map{ _ in val(et) }); case 10:return .compound(compound()); default:return .string("") } } }
