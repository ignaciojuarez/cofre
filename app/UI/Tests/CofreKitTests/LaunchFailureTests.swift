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

    func testFailuresOnlyBlameTheirOwningLaunchStage() {
        XCTAssertEqual(LaunchFailure.jitUnavailable.failedStage, 1)
        XCTAssertEqual(LaunchFailure.downloadFailed("Offline").failedStage, 2)
        XCTAssertEqual(LaunchFailure.rendererUnsupported.failedStage, 3)

        for failure in [
            LaunchFailure.profileMissing, .restartRequired, .unknownLoader, .modsNeedLoader, .loaderMissing,
        ] {
            XCTAssertNil(failure.failedStage)
        }
    }

    func testLoaderMissingExplainsHowToRepairTheInstance() {
        XCTAssertTrue(LaunchFailure.loaderMissing.localizedDescription.contains("Pick a loader version"))
    }
}
