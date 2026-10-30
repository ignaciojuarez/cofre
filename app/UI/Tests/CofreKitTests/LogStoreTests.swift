import XCTest
@testable import CofreKit
final class LogStoreTests: XCTestCase {
    func testFiltersMetallumNoiseKeepsErrors() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        try "[metallum] push\nsetPipeline\nERROR kept\n".write(to: d.appendingPathComponent("latestlog.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(LogStore(documents: d).read(.launcher).map(\.text), ["ERROR kept"])
    }

    func testSearchAndLevel() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        try "ok\nWARN hi\nERROR bad\n".write(to: d.appendingPathComponent("latestlog.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(LogStore(documents: d).search("bad", levels: [.error]).count, 1)
    }
    func testRedaction() { let r = ReportBundle.redact("token=abc me@example.com player=Alex"); XCTAssertFalse(r.contains("abc") || r.contains("me@example.com") || r.contains("Alex")) }
}
