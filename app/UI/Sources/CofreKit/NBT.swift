import Compression
import Foundation

/// Minecraft's NBT, as used by servers.dat and level.dat. One reader for both.
public enum NBTValue: Sendable { case byte(Int8), string(String), compound([(String, NBTValue)]), list([NBTValue]), raw(UInt8, Data); var type: UInt8 { switch self { case .byte: 1; case .string: 8; case .compound: 10; case .list: 9; case .raw(let type, _): type } } }

extension NBTValue {
    public subscript(key: String) -> NBTValue? {
        if case .compound(let pairs) = self { pairs.first { $0.0 == key }?.1 } else { nil }
    }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    /// Byte, short, int or long, sign-extended.
    public var integer: Int64? {
        switch self {
        case .byte(let b): return Int64(b)
        case .raw(let type, let data) where (2...4).contains(type):
            let shift = UInt64(64 - 8 * data.count)
            return Int64(bitPattern: data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } << shift) >> shift
        default: return nil
        }
    }
}

public enum NBT {
    public struct Malformed: Error {}

    /// The root compound of an NBT file, gzipped (level.dat) or not (servers.dat).
    public static func read(_ data: Data) throws -> NBTValue {
        var r = Reader(d: data.starts(with: [0x1f, 0x8b]) ? try gunzip(data) : data)
        guard try r.byte() == 10 else { throw Malformed() }
        _ = try r.string()
        return .compound(try r.compound())
    }

    static func gunzip(_ data: Data) throws -> Data {
        // RFC 1952 header: 10 bytes, then optional extra, name, comment and header CRC per the flag byte.
        guard data.count > 18 else { throw Malformed() }
        let flags = data[3]
        var start = 10
        if flags & 4 != 0 {
            guard data.count > start + 2 else { throw Malformed() }
            start += 2 + (Int(data[start]) | Int(data[start + 1]) << 8)
        }
        for bit: UInt8 in [8, 16] where flags & bit != 0 {
            guard let end = data[start...].firstIndex(of: 0) else { throw Malformed() }
            start = end + 1
        }
        if flags & 2 != 0 { start += 2 }
        guard start < data.count - 8 else { throw Malformed() }
        let deflated = data.subdata(in: start..<(data.count - 8))
        // The trailer holds the uncompressed size (mod 2^32); grow if that's wrong.
        var capacity = max(Int(data[data.count - 4..<data.count].reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }), 1024)
        while capacity <= 64 << 20 {
            var out = Data(count: capacity + 1)
            let n = out.withUnsafeMutableBytes { dst in
                deflated.withUnsafeBytes { src in
                    compression_decode_buffer(
                        dst.bindMemory(to: UInt8.self).baseAddress!, capacity + 1,
                        src.bindMemory(to: UInt8.self).baseAddress!, deflated.count, nil, COMPRESSION_ZLIB)
                }
            }
            if n > 0 && n <= capacity { return out.prefix(n) }
            capacity *= 2
        }
        throw Malformed()
    }
}

/// Bounds-checked: malformed or truncated data throws instead of reading past the end.
struct Reader {
    var d: Data; var i = 0
    mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, count <= d.count - i else { throw MinecraftServerPingError.malformedResponse }
        defer { i += count }; return d.subdata(in: i..<i+count)
    }
    mutating func byte() throws -> UInt8 { try take(1)[0] }
    mutating func int32() throws -> Int { Int(Int32(bitPattern: try take(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })) }
    mutating func string() throws -> String {
        let size = try take(2).reduce(0) { ($0 << 8) | Int($1) }
        guard let value = String(data: try take(size), encoding: .utf8) else { throw MinecraftServerPingError.malformedResponse }; return value
    }
    mutating func compound(depth: Int = 0) throws -> [(String, NBTValue)] {
        guard depth < 64 else { throw MinecraftServerPingError.malformedResponse }
        var result: [(String, NBTValue)] = []
        while true {
            let type = try byte(); if type == 0 { return result }
            let key = try string(); result.append((key, try val(type, depth: depth + 1)))
        }
    }
    mutating func val(_ type: UInt8, depth: Int) throws -> NBTValue {
        guard depth < 64 else { throw MinecraftServerPingError.malformedResponse }
        let start = i
        switch type {
        case 1: return .byte(Int8(bitPattern: try byte()))
        case 8: return .string(try string())
        case 10: return .compound(try compound(depth: depth))
        case 9:
            let element = try byte(), count = try int32()
            guard count >= 0, count <= d.count - i else { throw MinecraftServerPingError.malformedResponse }
            var values: [NBTValue] = []
            for _ in 0..<count { values.append(try val(element, depth: depth + 1)) }
            if element == 10 { return .list(values) }
        case 2: _ = try take(2)
        case 3, 5: _ = try take(4)
        case 4, 6: _ = try take(8)
        case 7, 11, 12:
            let count = try int32(), width = type == 7 ? 1 : (type == 11 ? 4 : 8)
            guard count >= 0, count <= (d.count - i) / width else { throw MinecraftServerPingError.malformedResponse }
            _ = try take(count * width)
        default: throw MinecraftServerPingError.malformedResponse
        }
        return .raw(type, d.subdata(in: start..<i))
    }
}
