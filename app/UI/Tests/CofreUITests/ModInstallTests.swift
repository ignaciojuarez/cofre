#if canImport(UIKit)
    import XCTest
    @testable import CofreUI

    /// M05 Get: dependency plans (`ModResolver`), the Get sheet's phases, and installed rows.
    @MainActor
    final class ModInstallTests: XCTestCase {

        // MARK: Resolver

        private func candidate(
            _ id: String, game: String = "1.21.1", loaders: [String] = ["fabric"], channel: String = "release",
            version: String = "1", deps: [ModCandidate.Dependency] = [], downloadable: Bool = true
        ) -> ModCandidate {
            ModCandidate(
                projectID: id, versionID: "\(id)-\(version)", title: id.capitalized, version: version,
                gameVersions: [game], loaders: loaders, channel: channel, sizeBytes: 1000, dependencies: deps,
                downloadable: downloadable)
        }

        private func resolver(
            _ catalog: [String: [ModCandidate]], loader: Loader = .fabric, kind: ContentKind = .mods,
            installed: [InstalledItem] = []
        ) -> ModResolver {
            ModResolver(game: "1.21.1", loader: loader, kind: kind, installed: installed) { id in
                guard let v = catalog[id] else { throw URLError(.badServerResponse) }
                return v
            }
        }

        func testCircularDependenciesResolveOnce() async throws {
            let plan = try await resolver([
                "a": [candidate("a", deps: [.init(projectID: "b", relation: .required)])],
                "b": [candidate("b", deps: [.init(projectID: "a", relation: .required)])],
            ]).plan(projectID: "a")
            XCTAssertNil(plan.blocked)
            XCTAssertEqual(plan.required.map(\.id), ["b"])
        }

        func testDependencyForAnotherLoaderBlocks() async throws {
            let plan = try await resolver([
                "a": [candidate("a", deps: [.init(projectID: "lib", relation: .required)])],
                "lib": [candidate("lib", loaders: ["forge"])],
            ]).plan(projectID: "a")
            XCTAssertEqual(plan.blocked, "A needs Lib. Lib has no Fabric 1.21.1 version, only Forge.")
        }

        func testDependencyWithNoVersionForThisGameBlocks() async throws {
            let plan = try await resolver([
                "a": [candidate("a", deps: [.init(projectID: "lib", relation: .required)])],
                "lib": [candidate("lib", game: "1.20.1")],
            ]).plan(projectID: "a")
            XCTAssertEqual(plan.blocked, "A needs Lib. Lib has no Fabric 1.21.1 version yet.")
        }

        func testDisabledDependencyTurnsOnInsteadOfDownloading() async throws {
            let plan = try await resolver(
                [
                    "a": [candidate("a", deps: [.init(projectID: "lib", relation: .required)])],
                    "lib": [candidate("lib")],
                ],
                installed: [InstalledItem(id: "lib.jar", name: "Lib", version: "2", enabled: false, projectID: "lib")]
            ).plan(projectID: "a")
            XCTAssertEqual(plan.required.map(\.turnsOn), [true])
            XCTAssertTrue(plan.needsConfirmation)
        }

        func testEnabledDependencyIsSkippedAndNoSheetNeeded() async throws {
            let plan = try await resolver(
                [
                    "a": [candidate("a", deps: [.init(projectID: "lib", relation: .required)])],
                    "lib": [candidate("lib")],
                ],
                installed: [InstalledItem(id: "lib.jar", name: "Lib", version: "2", enabled: true, projectID: "lib")]
            ).plan(projectID: "a")
            XCTAssertTrue(plan.required.isEmpty)
            XCTAssertEqual(plan.present, ["Lib"])
            XCTAssertFalse(plan.needsConfirmation)
        }

        func testIncompatibleInstalledModBlocks() async throws {
            let plan = try await resolver(
                ["a": [candidate("a", deps: [.init(projectID: "x", relation: .incompatible)])]],
                installed: [InstalledItem(id: "x.jar", name: "Xray", version: "1", enabled: true, projectID: "x")]
            ).plan(projectID: "a")
            XCTAssertEqual(plan.blocked, "A can't run with Xray. Turn Xray off first.")
        }

        func testOptionalIsOfferedNeverForcedAndOnlyForTheTarget() async throws {
            let plan = try await resolver([
                "a": [
                    candidate(
                        "a",
                        deps: [
                            .init(projectID: "opt", relation: .optional), .init(projectID: "lib", relation: .required),
                        ])
                ],
                "lib": [candidate("lib", deps: [.init(projectID: "deep", relation: .optional)])],
                "opt": [candidate("opt")], "deep": [candidate("deep")],
            ]).plan(projectID: "a")
            XCTAssertEqual(plan.optional.map(\.id), ["opt"])
            XCTAssertEqual(plan.files().map(\.id), ["a", "lib"])
            XCTAssertEqual(plan.files(picking: ["opt"]).map(\.id), ["a", "lib", "opt"])
        }

        func testPicksStableFittingVersionAndQuiltRunsFabricMods() async throws {
            let r = resolver(
                [
                    "a": [
                        candidate("a", channel: "beta", version: "3"), candidate("a", game: "1.20.1", version: "2"),
                        candidate("a", version: "1"),
                    ]
                ], loader: .quilt)
            let plan = try await r.plan(projectID: "a")
            XCTAssertEqual(plan.target.versionID, "a-1")
            // A pin that doesn't fit falls back to the best fit.
            let all = try await r.versions("a")
            XCTAssertEqual(r.pick(all, pinned: "a-2")?.versionID, "a-1")
        }

        func testCurseForgeFileWithoutDownloadBlocks() async throws {
            let plan = try await resolver([
                "a": [candidate("a", deps: [.init(projectID: "lib", relation: .required)])],
                "lib": [candidate("lib", downloadable: false)],
            ]).plan(projectID: "a")
            XCTAssertEqual(plan.blocked, "A needs Lib, which only downloads in CurseForge's app.")
        }

        func testShadersHaveNoDependenciesAndIgnoreLoaders() async throws {
            let plan = try await resolver(
                ["bsl": [candidate("bsl", loaders: ["iris"], deps: [.init(projectID: "iris", relation: .required)])]],
                kind: .shaders
            ).plan(projectID: "bsl")
            XCTAssertNil(plan.blocked)
            XCTAssertTrue(plan.required.isEmpty)
            XCTAssertFalse(plan.needsConfirmation)
        }

        // MARK: Store

        private func store(_ configure: (MockBackend) -> Void = { _ in }) async -> (CofreStore, MockBackend) {
            let mock = MockBackend(stepDelay: 0)
            configure(mock)
            let name = "cofre.tests.\(UUID().uuidString)"
            let s = CofreStore(services: CofreServices(backend: mock), defaults: UserDefaults(suiteName: name)!)
            await s.start()
            await s.search()
            return (s, mock)
        }

        private func until(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
            for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
            XCTAssertTrue(condition(), "timed out", file: file, line: line)
        }

        private func row(_ s: CofreStore, _ id: String) -> ProjectSummary {
            s.results.first { $0.id == id } ?? MockBackend.projects.first { $0.id == id }!
        }

        func testGetWithNothingExtraInstallsWithoutAsking() async {
            let (s, mock) = await store()
            XCTAssertEqual(s.installState(row(s, "iris")), .installed)
            XCTAssertEqual(s.installState(row(s, "appleskin")), .notInstalled)
            s.get("appleskin")
            await until { s.installState(row(s, "appleskin")) == .installed }
            XCTAssertNil(s.modInstallSheet)
            XCTAssertNil(s.modInstalls["appleskin"])
            XCTAssertTrue(mock.mods.contains { $0.id == "appleskin" })
        }

        func testGetWithDependenciesConfirmsThenInstallsAll() async {
            let (s, mock) = await store()
            s.get("culling")
            await until { s.modInstalls["culling"]?.phase == .confirm }
            XCTAssertEqual(s.modInstallSheet, "culling")
            let plan = s.modInstalls["culling"]!.plan!
            XCTAssertEqual(plan.required.map(\.id), ["fabric-api", "cloth-config"])
            XCTAssertEqual(plan.required.map(\.turnsOn), [false, true])
            XCTAssertTrue(plan.optional.isEmpty)  // Mod Menu is already there
            XCTAssertEqual(s.modInstalls["culling"]?.downloadBytes, 386_000 + 2_412_000)
            s.confirmInstall("culling")
            await until { s.modInstalls["culling"]?.phase == .done }
            XCTAssertEqual(mock.mods.first { $0.id == "cloth-config" }?.enabled, true)
            XCTAssertTrue(mock.mods.contains { $0.id == "fabric-api" })
            XCTAssertEqual(s.installState(row(s, "culling")), .installed)
            s.closeModInstall("culling")
            XCTAssertNil(s.modInstalls["culling"])
            XCTAssertNil(s.modInstallSheet)
        }

        func testFailedDependencyInstallsNothingAndSaysWhat() async {
            let (s, mock) = await store { $0.failDownload = "fabric-api" }
            let before = mock.mods
            s.get("culling")
            await until { s.modInstalls["culling"]?.phase == .confirm }
            s.confirmInstall("culling")
            await until { s.modInstalls["culling"]?.isFinished == true }
            XCTAssertEqual(
                s.modInstalls["culling"]?.phase, .failed("Fabric API didn't download: the connection dropped."))
            XCTAssertEqual(s.modInstalls["culling"]?.canRetry, true)
            XCTAssertEqual(s.modInstalls["culling"]?.progress?.stages.first { $0.state.isFailed }?.title, "Fabric API")
            XCTAssertEqual(mock.mods, before)
            XCTAssertEqual(s.installState(row(s, "culling")), .notInstalled)
        }

        func testBlockedGetOpensSheetWithReason() async {
            let (s, _) = await store()
            s.get("continuity")
            await until { s.modInstalls["continuity"]?.isFinished == true }
            XCTAssertEqual(
                s.modInstalls["continuity"]?.phase,
                .failed("Continuity needs Indium. Indium has no Fabric 1.21.1 version yet."))
            XCTAssertEqual(s.modInstalls["continuity"]?.canRetry, false)
            XCTAssertEqual(s.modInstallSheet, "continuity")
            s.get("canvas")
            await until { s.modInstalls["canvas"]?.isFinished == true }
            XCTAssertEqual(
                s.modInstalls["canvas"]?.phase, .failed("Canvas can't run with Sodium. Turn Sodium off first."))
        }

        func testOfflineGetSaysOfflineAndRetries() async {
            let (s, mock) = await store()
            mock.offline = true
            s.get("culling")
            await until { s.modInstalls["culling"]?.isFinished == true }
            XCTAssertEqual(s.modInstalls["culling"]?.phase, .failed("You're offline. Connect and try again."))
            mock.offline = false
            s.retryInstall("culling")
            await until { s.modInstalls["culling"]?.phase == .confirm }
        }

        func testTwoInstallsAtOnceShareADependencyOnce() async {
            let (s, mock) = await store { $0.stepDelay = 0.01 }
            s.get("culling")
            s.get("sodium-extra")
            s.get("sodium-extra")  // a second tap while planning does nothing
            await until { s.modInstalls["culling"]?.phase == .confirm && s.modInstalls["sodium-extra"]?.phase == .confirm }
            XCTAssertEqual(s.modInstalls["sodium-extra"]?.plan?.optional.map(\.id), ["reeses"])
            s.confirmInstall("culling")
            s.confirmInstall("sodium-extra")
            XCTAssertEqual(s.modInstalls["sodium-extra"]?.phase, .queued)
            await until { s.modInstalls["sodium-extra"]?.phase == .done }
            XCTAssertEqual(mock.mods.filter { $0.id == "fabric-api" }.count, 1)
            XCTAssertFalse(mock.mods.contains { $0.id == "reeses" })  // optional, not picked
        }

        func testInstalledRowsMatchOffAndUpdatesAndRefresh() async {
            let (s, mock) = await store()
            XCTAssertEqual(s.installState(row(s, "xaero")), .off)
            XCTAssertEqual(s.installState(row(s, "lithium")), .update("0.14.4"))
            // Files Cofre couldn't identify still match by name.
            mock.mods.append(InstalledItem(id: "AppleSkin-fabric.jar", name: "AppleSkin", version: "3", enabled: true))
            await s.search()
            XCTAssertEqual(s.installState(row(s, "appleskin")), .installed)
            // Deleting refreshes the row.
            s.deleteItem(s.installed[.mods]!.first { $0.name == "AppleSkin" }!)
            XCTAssertEqual(s.installState(row(s, "appleskin")), .notInstalled)
            // Other kinds read their own list.
            s.query.kind = .shaders
            mock.content[.shaders]?.append(
                InstalledItem(id: "x", name: "Sodium", version: "1", enabled: true, kind: .shaders))
            await s.search()
            XCTAssertEqual(s.installState(row(s, "sodium")), .installed)
            mock.content[.shaders] = []
            await s.selectInstance("cobblemon")
            await s.search()
            XCTAssertEqual(s.installState(row(s, "sodium")), .notInstalled)
        }

        func testModpackMakesItsOwnInstance() async {
            let (s, _) = await store()
            s.query.kind = .modpacks
            await s.search()
            let count = s.instances.count
            s.get("sodium")
            await until { s.modInstalls["sodium"]?.phase == .confirm }
            XCTAssertEqual(s.modInstalls["sodium"]?.plan?.makesInstance, true)
            XCTAssertEqual(s.installState(row(s, "sodium")), .notInstalled)
            s.confirmInstall("sodium")
            await until { s.modInstalls["sodium"]?.phase == .done }
            XCTAssertEqual(s.instances.count, count + 1)
        }
    }
#endif
