import XCTest

@testable import CofreKit

final class VersionManifestTests: XCTestCase {
    func testOnlyMinecraft26Point2AndNewerAreOptimized() {
        for id in ["26.2", "26.2.1", "26.3", "26.3-pre1", "26.10", "27.1"] {
            XCTAssertTrue(VersionManifest.isOptimized(id), id)
        }
        for id in ["26.1", "26.1.2", "1.21.11", "1.21.1", "1.20.1", "1.8.9", "26w44a", "b1.7.3", ""] {
            XCTAssertFalse(VersionManifest.isOptimized(id), id)
        }
    }
}
