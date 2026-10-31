#if canImport(UIKit)
    import CofreKit
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

        // MARK: Channels, labels, filters

        func testUpdatesNeverMoveToALessStableChannel() {
            XCTAssertTrue(VersionChannel.release.allowsUpdate(to: .release))
            XCTAssertFalse(VersionChannel.release.allowsUpdate(to: .beta))
            XCTAssertFalse(VersionChannel.release.allowsUpdate(to: .alpha))
            XCTAssertTrue(VersionChannel.beta.allowsUpdate(to: .release))
            XCTAssertTrue(VersionChannel.beta.allowsUpdate(to: .beta))
            XCTAssertFalse(VersionChannel.beta.allowsUpdate(to: .alpha))
            XCTAssertTrue(VersionChannel.alpha.allowsUpdate(to: .beta))
            XCTAssertEqual(VersionChannel.release.updateChannels, [.release])
            XCTAssertEqual(VersionChannel("BETA"), .beta)
            XCTAssertEqual(VersionChannel(nil), .release)
        }

        func testVersionLabelsDropLoaderAndGameTags() {
            let cases = [
                "mc1.21.1-0.6.0-fabric": "0.6.0",
                "0.9.2+mc26.3": "0.9.2",
                "1.11.6+mc26.3": "1.11.6",
                "0.160.5+26.3": "0.160.5",
                "mc26.3-0.9.3-beta.1-fabric": "0.9.3 beta 1",
                "mc26.3-0.9.0-alpha.3-neoforge": "0.9.0 alpha 3",
                "0.5.8+1.21.1-fabric": "0.5.8",
                "fabric-0.5.3": "0.5.3",
                "v2.1.0": "2.1.0",
                "sodium-fabric-0.6.0+mc1.21.1.jar (1.21.1)": "0.6.0",
                "6.0.4": "6.0.4",
            ]
            for (raw, label) in cases { XCTAssertEqual(VersionLabel.clean(raw), label, raw) }
        }

        func testGetPicksNewestReleaseElseBetaElseAlpha() async throws {
            func picked(_ versions: [ModCandidate]) async throws -> (String, VersionChannel) {
                let plan = try await resolver(["a": versions]).plan(projectID: "a")
                return (plan.target.versionID, plan.target.channel)
            }
            // Release available: it wins over a newer beta and alpha.
            var r = try await picked([
                candidate("a", channel: "alpha", version: "4"), candidate("a", channel: "beta", version: "3"),
                candidate("a", version: "2"),
            ])
            XCTAssertEqual(r.0, "a-2")
            XCTAssertEqual(r.1, .release)
            // Only beta.
            r = try await picked([candidate("a", channel: "beta", version: "3")])
            XCTAssertEqual(r.1, .beta)
            // Only alpha.
            r = try await picked([candidate("a", channel: "alpha", version: "4")])
            XCTAssertEqual(r.1, .alpha)
            // A release for another game version doesn't fit, so this version's beta wins.
            r = try await picked([
                candidate("a", game: "1.20.1", version: "2"), candidate("a", channel: "beta", version: "3"),
            ])
            XCTAssertEqual(r.0, "a-3")
        }

        func testDependenciesFollowTheSameRuleAndNonReleaseAsks() async throws {
            let plan = try await resolver([
                "a": [candidate("a", deps: [.init(projectID: "lib", relation: .required)])],
                "lib": [candidate("lib", channel: "beta", version: "9"), candidate("lib", version: "8")],
            ]).plan(projectID: "a")
            XCTAssertEqual(plan.required.first?.versionID, "lib-8")
            let beta = try await resolver(["a": [candidate("a", channel: "beta")]]).plan(projectID: "a")
            XCTAssertTrue(beta.needsConfirmation)
        }

        func testVersionFiltersDefaultToTheTarget() {
            let inst = InstanceSummary(id: "f", name: "Fabric Mods", loader: .fabric, gameVersion: "26.3")
            let versions = MockBackend.sodiumBuilds.map { c in
                ProjectVersion(
                    id: c.versionID, name: VersionLabel.clean(c.version), gameVersions: "", channel: c.channel,
                    fits: c.fits(game: "26.3", loader: .fabric), number: c.version, games: c.gameVersions,
                    loaders: c.loaders)
            }
            let f = VersionFilter.defaults(for: inst)
            XCTAssertEqual(f.channels, [.release, .beta])
            XCTAssertEqual(f.visible(versions, installed: nil, all: false).map(\.name), ["0.9.3 beta 1", "0.9.2"])
            // The installed build stays listed even when the filters hide it; All versions lists everything.
            XCTAssertEqual(f.visible(versions, installed: "sodium-0613", all: false).count, 3)
            XCTAssertEqual(f.visible(versions, installed: nil, all: true).count, versions.count)
            XCTAssertEqual(versions.preferred?.name, "0.9.2")
            XCTAssertEqual(
                VersionFilter.defaults(for: InstanceSummary(id: "q", name: "Q", loader: .quilt, gameVersion: "1"))
                    .loaders, [.quilt, .fabric])
            XCTAssertEqual(ModPagePane.title("Switch to", versions[0]), "Switch to 0.9.3 beta 1")
            XCTAssertEqual(
                ModPagePane.title("Install", ProjectVersion(id: "x", name: "1.0", gameVersions: "", channel: "Beta", fits: true)),
                "Install 1.0 · beta")
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

        func testNeedsGetInstallsTheMissingModWhateverTheSearchTab() async {
            let (s, mock) = await store()
            XCTAssertEqual(s.installed[.mods]?.first { $0.id == "bountiful" }?.needs.map(\.id), ["fabric-api"])
            s.query.kind = .shaders
            s.get("fabric-api", kind: .mods)
            await until { mock.mods.contains { $0.id == "fabric-api" } }
            XCTAssertEqual(s.modInstalls["fabric-api"]?.plan?.kind ?? .mods, .mods)
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

        func testScrollingFetchesTheNextPageWithoutRepeats() async {
            let (s, mock) = await store()
            func page(_ range: Range<Int>) -> [ProjectSummary] {
                range.map { ProjectSummary(id: "p\($0)", title: "Project \($0)", author: "", summary: "", downloads: 0, loaders: [], fits: true) }
            }
            // A full page, then a short one that repeats the last result.
            mock.searchPages = [page(0..<50), page(49..<60)]
            await s.search()
            XCTAssertEqual(s.results.count, 50)
            XCTAssertTrue(s.hasMoreResults)
            await s.loadMoreResults()
            XCTAssertEqual(s.results.map(\.id), (0..<60).map { "p\($0)" })
            XCTAssertFalse(s.hasMoreResults, "a short page is the last")
            await s.loadMoreResults()
            XCTAssertEqual(s.results.count, 60)
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

        func testUpdateInstallsTheOfferedBuild() async {
            let (s, mock) = await store()
            let i = mock.mods.firstIndex { $0.id == "lithium" }!
            mock.mods[i].updateVersionID = "lithium-187"
            await s.search()
            s.update(row(s, "lithium"))
            await until { mock.mods.contains { $0.versionID == "lithium-187" } }
            XCTAssertEqual(mock.mods.filter { $0.matches("lithium") }.count, 1)
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
