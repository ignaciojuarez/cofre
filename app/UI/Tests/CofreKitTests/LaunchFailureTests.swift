import XCTest

@testable import CofreKit

final class LaunchFailureTests: XCTestCase {
    func testFailuresOfferTheRecoveryThatCanFixThem() {
        let cases: [(LaunchFailure, LaunchFailure.Recovery)] = [
            (.loaderMissing, .repairInstance), (.modsNeedLoader, .repairInstance), (.unknownLoader, .repairInstance),
            (.profileMissing, .repairInstance),
            (.restartRequired, .reopen), (.rendererUnsupported, .renderer), (.jitUnavailable, .jit),
            (.downloadFailed("Offline"), .retry), (.jvmExit(1), .log), (.unknown(""), .log),
        ]
        for (failure, recovery) in cases {
            XCTAssertEqual(failure.recovery, recovery)
            XCTAssertFalse(failure.localizedDescription.isEmpty)
            XCTAssertFalse(recovery.title.isEmpty)
        }
        XCTAssertTrue(LaunchFailure.jvmExit(17).localizedDescription.contains("17"))
        XCTAssertTrue(LaunchFailure.downloadFailed("Offline").localizedDescription.contains("Offline"))
    }
}
