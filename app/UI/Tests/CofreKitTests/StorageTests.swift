import Foundation
import XCTest
@testable import CofreKit

final class StorageTests: XCTestCase {
    func testCleanupPreservesContentAndSymlinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        func write(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("test".utf8).write(to: url)
            return url
        }
        let disposable = try ["home/latestlog.old.txt", "home/ame_shaderc_dump/a.src", "game/logs/old.log", "game/crash-reports/crash.txt", "tmp/old-installer"].map(write)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-172800)], ofItemAtPath: disposable.last!.path)
        let retained = try ["game/saves/world/level.dat", "game/mods/mod.jar", "game/resourcepacks/pack.zip", "game/shaderpacks/pack.zip", "home/accounts/account.json", "home/settings.json", "game/assets/a", "game/libraries/a", "tmp/active-download", "home/latestlog.txt", "game/logs/latest.log", "outside/important"].map(write)
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("game/logs/link").path, withDestinationPath: root.appendingPathComponent("outside").path)
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("game/ame_shaderc_dump").path, withDestinationPath: root.appendingPathComponent("game/saves").path)
        let cleanup = StorageCleanup(home: root.appendingPathComponent("home"), gameDirectories: [root.appendingPathComponent("game")], temporaryDirectory: root.appendingPathComponent("tmp"))
        XCTAssertEqual(cleanup.reclaimableBytes, 20)
        XCTAssertEqual(try cleanup.clear(), 20)
        XCTAssertTrue(disposable.allSatisfy { !fm.fileExists(atPath: $0.path) })
        XCTAssertTrue(retained.allSatisfy { fm.fileExists(atPath: $0.path) })
        XCTAssertEqual(cleanup.reclaimableBytes, 0)
    }
}
