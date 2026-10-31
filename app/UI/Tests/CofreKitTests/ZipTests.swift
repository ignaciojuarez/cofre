import XCTest

@testable import CofreKit

final class ZipTests: XCTestCase {
    private func archive() throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Zip.write([(path: "file.txt", data: { Data("hello".utf8) })], to: url)
        return try Data(contentsOf: url)
    }

    func testTruncatedAndOutOfBoundsArchivesThrow() throws {
        var truncated = try archive()
        truncated.removeLast()
        XCTAssertThrowsError(try Zip.entries(in: truncated))

        var badCentral = try archive()
        let end = badCentral.count - 22
        let central =
            Int(badCentral[end + 16]) | Int(badCentral[end + 17]) << 8
            | Int(badCentral[end + 18]) << 16 | Int(badCentral[end + 19]) << 24
        badCentral[central + 28] = 0xff
        badCentral[central + 29] = 0xff
        XCTAssertThrowsError(try Zip.entries(in: badCentral))

        let entries = try Zip.entries(in: archive())
        var badLocal = try archive()
        let local = entries[0]
        let localOffset = badLocal.count - 22 - 46 - local.path.utf8.count
        badLocal[localOffset + 42] = 0xff
        badLocal[localOffset + 43] = 0xff
        badLocal[localOffset + 44] = 0xff
        badLocal[localOffset + 45] = 0xff
        let parsed = try Zip.entries(in: badLocal)
        XCTAssertThrowsError(try Zip.data(of: parsed[0], in: badLocal))
    }

    func testForgedUncompressedSizeIsRejectedBeforeAllocating() throws {
        let body = try XCTUnwrap(Zip.deflate(Data(repeating: 65, count: 4096)))
        XCTAssertEqual(Zip.inflate(body, size: 4096), Data(repeating: 65, count: 4096))
        XCTAssertNil(Zip.inflate(body, size: Int(UInt32.max)))
    }
}
