#if canImport(UIKit)
    import CofreKit
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

        private func needs(_ id: String, _ name: String) -> ModRequirement {
            ModRequirement(
                modID: id, name: name, projectID: id, reason: "dependency:\(id)", neededBy: "Biomes O' Plenty")
        }

        private func wait(_ done: () -> Bool) async throws {
            for _ in 0..<300 where !done() { try await Task.sleep(for: .milliseconds(10)) }
        }

        /// NeoForge 26.2 + Biomes O' Plenty without TerraBlender and GlitchCore: asked before Java starts.
        func testPlayAsksForMissingLibrariesThenGetsThemAndLaunches() async throws {
            let mock = MockBackend(stepDelay: 0)
            mock.missingRequirements = [needs("terrablender", "TerraBlender"), needs("glitchcore", "GlitchCore")]
            let store = CofreStore(services: CofreServices(backend: mock))
            store.instances = [.init(id: "neo", name: "Neo", loader: .neoforge, gameVersion: "26.2")]

            store.play("neo")
            try await wait { store.pendingRequirements != nil }
            XCTAssertEqual(store.pendingRequirements?.map(\.modID), ["terrablender", "glitchcore"])
            XCTAssertEqual(store.launch?.title, "Checking mods")
            XCTAssertEqual(
                PlayRequirementsRoute(missing: store.pendingRequirements ?? []).lines,
                ["Biomes O' Plenty needs TerraBlender and GlitchCore"])

            store.resolvePlayRequirements(get: true)
            XCTAssertNil(store.pendingRequirements)
            try await wait { store.launch?.finished == true }
            XCTAssertEqual(mock.installedRequirements.map(\.modID), ["terrablender", "glitchcore"])
            XCTAssertEqual(store.launch?.finished, true)
            XCTAssertNil(store.launchFailure)
        }

        func testPlayAnywaySkipsTheLibrariesAndOtherLoadersAreNotChecked() async throws {
            let mock = MockBackend(stepDelay: 0)
            mock.missingRequirements = [needs("terrablender", "TerraBlender")]
            let store = CofreStore(services: CofreServices(backend: mock))
            store.instances = [
                .init(id: "neo", name: "Neo", loader: .neoforge, gameVersion: "26.2"),
                .init(id: "fabric", name: "Fabric", loader: .fabric, gameVersion: "26.2"),
            ]
            store.play("neo")
            try await wait { store.pendingRequirements != nil }
            store.resolvePlayRequirements(get: false)
            try await wait { store.launch?.finished == true }
            XCTAssertTrue(mock.installedRequirements.isEmpty)
            XCTAssertEqual(store.launch?.finished, true)

            store.play("fabric")
            try await wait { store.launch?.finished == true }
            XCTAssertNil(store.pendingRequirements)

            // Closing the sheet without a choice cancels the launch.
            store.play("neo")
            try await wait { store.pendingRequirements != nil }
            await store.cancelPlayRequirements()
            XCTAssertNil(store.pendingRequirements)
            XCTAssertNil(store.launch)
        }
    }
#endif
