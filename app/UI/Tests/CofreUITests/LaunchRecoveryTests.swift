#if canImport(UIKit)
    import XCTest
    @testable import CofreUI

    @MainActor final class LaunchRecoveryTests: XCTestCase {
        func testRestartRequiredBlocksPlainServerAndWorldLaunches() {
            let store = CofreStore(services: .mock())
            store.instances = [
                .init(id: "forge", name: "Forge", loader: .forge, gameVersion: "1.20.1", restartRequired: true)
            ]
            let server = ServerSummary(id: "s", name: "Server", address: "play.example.com")
            let world = RejoinIntent(instanceID: "forge", kind: .world, target: "World", displayName: "World")

            store.play("forge")
            XCTAssertEqual(store.launchFailure, .restartRequired)
            XCTAssertEqual(store.launchRecovery, .reopen)
            XCTAssertNotNil(store.launch)
            XCTAssertNil(store.pendingModCompatibility)
            store.play("forge", server: server)
            XCTAssertEqual(store.launchFailure, .restartRequired)
            store.play("forge", rejoin: world)
            XCTAssertEqual(store.launchFailure, .restartRequired)
            store.playAnywayAfterModWarning(turnOff: false)
            XCTAssertEqual(store.launchFailure, .restartRequired)
        }

        func testDownloadRetryIsOfferedOnlyBeforeJavaStarts() {
            let store = CofreStore(services: .mock())
            store.launch = .init(stage: 2, of: 7, title: "Game files")
            store.launchFailure = .downloadFailed("Offline")
            XCTAssertEqual(store.launchRecovery, .retry)
            store.launch?.stage = 5
            XCTAssertEqual(store.launchRecovery, .log)
            store.launchError = "Unclassified failure"
            XCTAssertEqual(store.launchFailure, .unknown("Unclassified failure"))
            XCTAssertEqual(store.launchRecovery, .log)
        }
    }
#endif
