import Compression
import Foundation

/// The smallest world fixture accepted by modern Minecraft quick play.
/// Scenario-only callers create it before passing `--quickPlaySingleplayer`.
public enum ScenarioWorld {
    public enum Failure: Error, LocalizedError, Equatable {
        case invalidFolder
        case unsupportedVersion(String)

        public var errorDescription: String? {
            switch self {
            case .invalidFolder: "invalid world folder"
            case .unsupportedVersion(let version): "unsupported scenario world version \(version)"
            }
        }
    }

    /// Creates a world folder only when it does not already contain level.dat.
    @discardableResult
    public static func ensure(
        in gameDirectory: URL, folder: String, seed: Int64?, gameVersion: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard validFolder(folder) else { throw Failure.invalidFolder }
        let world = gameDirectory.appendingPathComponent("saves", isDirectory: true).appendingPathComponent(
            folder, isDirectory: true)
        try fileManager.createDirectory(at: world, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: world.appendingPathComponent("level.dat").path) else { return world }
        try write(to: world, folder: folder, seed: seed ?? 0, gameVersion: gameVersion, fileManager: fileManager)
        return world
    }

    /// Writes the smallest gzipped world files accepted by the scenario versions.
    public static func write(
        to world: URL, folder: String, seed: Int64, gameVersion: String,
        fileManager: FileManager = .default
    ) throws {
        guard validFolder(folder), let version = dataVersion(for: gameVersion) else {
            throw Failure.unsupportedVersion(gameVersion)
        }
        try fileManager.createDirectory(at: world, withIntermediateDirectories: true)
        let dimensions: Value = .compound([
            (
                "minecraft:overworld",
                .compound([
                    ("type", .string("minecraft:overworld")),
                    (
                        "generator",
                        .compound([
                            ("type", .string("minecraft:noise")),
                            (
                                "biome_source",
                                .compound([
                                    ("type", .string("minecraft:multi_noise")),
                                    ("preset", .string("minecraft:overworld")),
                                ])
                            ),
                            ("settings", .string("minecraft:overworld")),
                        ])
                    ),
                ])
            )
        ])
        let worldGeneration: Value = .compound([
            ("seed", .long(seed)),
            (gameVersion == "26.2" ? "generate_structures" : "generate_features", .byte(1)),
            ("bonus_chest", .byte(0)),
            ("dimensions", dimensions),
        ])
        var dataFields: [(String, Value)] = [
            (
                "Version",
                .compound([
                    ("Name", .string(gameVersion)),
                    ("Id", .int(Int32(version))),
                    ("Snapshot", .byte(0)),
                    ("Series", .string("main")),
                ])
            ),
            ("DataVersion", .int(Int32(version))),
            ("GameType", .int(0)),
            ("LevelName", .string(folder)),
            ("RandomSeed", .long(seed)),
            ("Time", .long(0)),
            ("LastPlayed", .long(Int64(Date().timeIntervalSince1970 * 1000))),
            ("allowCommands", .byte(0)),
            ("initialized", .byte(1)),
            ("version", .int(19133)),
        ]
        if gameVersion == "1.21.11" { dataFields.append(("WorldGenSettings", worldGeneration)) }
        let data = compound([("Data", .compound(dataFields))])
        try gzip(data).write(to: world.appendingPathComponent("level.dat"), options: .atomic)

        if gameVersion == "26.2" {
            let generation = compound([
                ("data", worldGeneration),
                ("DataVersion", .int(Int32(version))),
            ])
            let dataDirectory = world.appendingPathComponent("data/minecraft", isDirectory: true)
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try gzip(generation).write(
                to: dataDirectory.appendingPathComponent("world_gen_settings.dat"), options: .atomic)
        }
    }

    /// Data versions published by Mojang for the two device scenario tracks.
    public static func dataVersion(for gameVersion: String) -> Int? {
        switch gameVersion {
        case "26.2": 4903
        case "1.21.11": 4671
        default: nil
        }
    }

    fileprivate enum Value {
        case byte(Int8)
        case int(Int32)
        case long(Int64)
        case string(String)
        case compound([(String, Value)])
    }

    private static func validFolder(_ folder: String) -> Bool {
        !folder.isEmpty && folder != "." && folder != ".." && !folder.contains("/") && !folder.contains("\\")
            && !folder.contains("\0")
    }

    private static func compound(_ values: [(String, Value)]) -> Data {
        var data = Data([10, 0, 0])
        for (name, value) in values {
            data.append(value.type)
            appendString(name, to: &data)
            append(value, to: &data)
        }
        data.append(0)
        return data
    }

    private static func append(_ value: Value, to data: inout Data) {
        switch value {
        case .byte(let value): data.append(UInt8(bitPattern: value))
        case .int(let value): append(UInt32(bitPattern: value), to: &data)
        case .long(let value): append(UInt64(bitPattern: value), to: &data)
        case .string(let value): appendString(value, to: &data)
        case .compound(let values):
            for (name, value) in values {
                data.append(value.type)
                appendString(name, to: &data)
                append(value, to: &data)
            }
            data.append(0)
        }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 24))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        append(UInt32(truncatingIfNeeded: value >> 32), to: &data)
        append(UInt32(truncatingIfNeeded: value), to: &data)
    }

    private static func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        append(UInt16(bytes.count), to: &data)
        data.append(bytes)
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func gzip(_ input: Data) throws -> Data {
        var capacity = max(input.count + 64, 256)
        var compressed = Data(count: capacity)
        var count = compressed.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        while count == 0 {
            capacity *= 2
            compressed = Data(count: capacity)
            count = compressed.withUnsafeMutableBytes { destination in
                input.withUnsafeBytes { source in
                    compression_encode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        source.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
                }
            }
        }
        compressed.count = count
        var output = Data([0x1f, 0x8b, 0x08, 0, 0, 0, 0, 0, 0, 0])
        output.append(compressed)
        append(UInt32(crc32(input)), littleEndianTo: &output)
        append(UInt32(input.count), littleEndianTo: &output)
        return output
    }

    private static func append(_ value: UInt32, littleEndianTo data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask: UInt32 = (crc & 1) == 0 ? 0 : UInt32.max
                crc = (crc >> 1) ^ (0xedb8_8320 & mask)
            }
        }
        return ~crc
    }
}

extension ScenarioWorld.Value {
    fileprivate var type: UInt8 {
        switch self {
        case .byte: 1
        case .int: 3
        case .long: 4
        case .string: 8
        case .compound: 10
        }
    }
}
