import Compression
import Foundation

/// The ZIP Cofre needs: instance and world exports, report bundles, `.mrpack` packs and mod jars. Raw DEFLATE comes
/// from Apple's Compression framework; entries are stored when deflate doesn't help. No zip64, no encryption.
public enum Zip {
    public enum Failure: Error { case notAZip, unsupported(String), unsafePath(String), corrupt(String) }

    public struct Entry: Sendable {
        public let path: String
        let method: UInt16, crc: UInt32, compressedSize: Int, size: Int, headerOffset: Int
        public var isDirectory: Bool { path.hasSuffix("/") }
    }

    // MARK: Write

    /// Writes `files` (archive path, data) to `destination`, one file at a time, so big exports never sit in memory.
    public static func write(_ files: some Sequence<(path: String, data: () throws -> Data)>, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let out = try FileHandle(forWritingTo: destination)
        defer { try? out.close() }
        var central = Data(), count = 0, offset = 0
        for (path, load) in files {
            let data = try load()
            let deflated = deflate(data)
            let body = deflated ?? data
            let name = Data(path.utf8)
            var header = Data()
            header.le(UInt32(0x0403_4b50)); header.le(UInt16(20)); header.le(UInt16(0x0800))
            header.le(UInt16(deflated == nil ? 0 : 8)); header.le(UInt32(0))
            header.le(crc32(data)); header.le(UInt32(body.count)); header.le(UInt32(data.count))
            header.le(UInt16(name.count)); header.le(UInt16(0))
            try out.write(contentsOf: header + name + body)

            central.le(UInt32(0x0201_4b50)); central.le(UInt16(20)); central.append(header[4..<30])
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt32(0))
            central.le(UInt32(offset)); central.append(name)
            offset += header.count + name.count + body.count
            count += 1
        }
        var end = Data()
        end.le(UInt32(0x0605_4b50)); end.le(UInt16(0)); end.le(UInt16(0)); end.le(UInt16(count)); end.le(UInt16(count))
        end.le(UInt32(central.count)); end.le(UInt32(offset)); end.le(UInt16(0))
        try out.write(contentsOf: central + end)
    }

    /// Zips every file under `directory` with paths relative to it. `skip` gets each relative path.
    public static func write(directory: URL, to destination: URL, skip: (String) -> Bool = { _ in false }) throws {
        let base = directory.standardizedFileURL.path + "/"
        let files = (FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { url in (path: String(url.standardizedFileURL.path.dropFirst(base.count)), url: url) }
            .filter { !skip($0.path) }
        try write(files.map { file in (path: file.path, data: { try Data(contentsOf: file.url) }) }, to: destination)
    }

    // MARK: Read

    /// The archive's entries, from its central directory.
    public static func entries(in archive: Data) throws -> [Entry] {
        guard archive.count >= 22, let end = (0...(archive.count - 22)).reversed().prefix(65_557)
            .first(where: { archive.u32($0) == 0x0605_4b50 })
        else { throw Failure.notAZip }
        let total = Int(archive.u16(end + 10)), start = Int(archive.u32(end + 16))
        var entries: [Entry] = [], at = start
        for _ in 0..<total {
            guard archive.u32(at) == 0x0201_4b50 else { throw Failure.corrupt("central directory") }
            let nameLength = Int(archive.u16(at + 28)), extra = Int(archive.u16(at + 30)), comment = Int(archive.u16(at + 32))
            let path = String(decoding: archive[archive.startIndex + at + 46 ..< archive.startIndex + at + 46 + nameLength], as: UTF8.self)
            entries.append(Entry(
                path: path, method: archive.u16(at + 10), crc: archive.u32(at + 16),
                compressedSize: Int(archive.u32(at + 20)), size: Int(archive.u32(at + 24)),
                headerOffset: Int(archive.u32(at + 42))))
            at += 46 + nameLength + extra + comment
        }
        return entries
    }

    /// One entry's contents.
    public static func data(of entry: Entry, in archive: Data) throws -> Data {
        let h = entry.headerOffset
        guard archive.u32(h) == 0x0403_4b50 else { throw Failure.corrupt(entry.path) }
        let start = archive.startIndex + h + 30 + Int(archive.u16(h + 26)) + Int(archive.u16(h + 28))
        let body = archive[start ..< start + entry.compressedSize]
        switch entry.method {
        case 0: return Data(body)
        case 8: guard let data = inflate(body, size: entry.size) else { throw Failure.corrupt(entry.path) }; return data
        default: throw Failure.unsupported("compression \(entry.method) in \(entry.path)")
        }
    }

    /// Extracts `archive` into `directory`. Refuses paths that would escape it.
    public static func extract(_ archive: URL, to directory: URL) throws {
        let zip = try Data(contentsOf: archive, options: .alwaysMapped)
        let fm = FileManager.default
        for entry in try entries(in: zip) {
            let parts = entry.path.split(separator: "/")
            guard !entry.path.hasPrefix("/"), !parts.contains("..") else { throw Failure.unsafePath(entry.path) }
            let target = directory.appendingPathComponent(entry.path)
            if entry.isDirectory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data(of: entry, in: zip).write(to: target)
            }
        }
    }

    // MARK: DEFLATE and CRC

    /// Raw DEFLATE (Apple's COMPRESSION_ZLIB has no zlib header), or nil when it doesn't make the data smaller.
    static func deflate(_ data: Data) -> Data? {
        guard data.count > 64 else { return nil }
        var out = Data(count: data.count)
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0, n < data.count else { return nil }
        return out.prefix(n)
    }

    static func inflate(_ body: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { dst in
            body.withUnsafeBytes { src in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, size,
                    src.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n == size ? out : nil
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crcTable[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}

extension Data {
    fileprivate mutating func le<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    fileprivate func u16(_ at: Int) -> UInt16 { UInt16(self[startIndex + at]) | UInt16(self[startIndex + at + 1]) << 8 }
    fileprivate func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }
}
