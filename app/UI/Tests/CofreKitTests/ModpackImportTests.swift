import XCTest
@testable import CofreKit

final class ModpackImportTests: XCTestCase {
    func testInterruptedImportRemovesOnlyNewFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("options.txt")
        try Data("keep".utf8).write(to: existing)
        try ModpackImport.markImportStarted(in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("mods"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: root.appendingPathComponent("mods/new.jar"), options: .atomic)
        ModpackImport.cleanupAbandonedImport(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("mods/new.jar").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".cofre-import-in-progress").path))
    }
}
