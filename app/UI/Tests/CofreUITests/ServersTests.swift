#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import XCTest
    @testable import CofreUI

    // Servers (plan/servers.md): servers.dat is the only saved list. Fit, pasted addresses, Join routing, copy and
    // delete, Recommended and pings.
    @MainActor
    final class ServersTests: XCTestCase {

        func testFitComparesTheInstanceVersion() {
            let inst = InstanceSummary(id: "i", name: "Survival+", loader: .fabric, gameVersion: "1.21.1")
            var s = ServerSummary(id: "s", name: "S", address: "a")
            XCTAssertEqual(s.fit(inst), .unknown)
            s.gameVersions = ["1.21.4", "1.21.1", "1.8.9"]
            XCTAssertEqual(s.fit(inst), .fits)
            s.gameVersions = ["1.20.4"]
            XCTAssertEqual(s.fit(inst), .needs("1.20.4"))
            XCTAssertEqual(s.fit(nil), .unknown)
        }

        func testPingFillsLiveFieldsAndStripsFormatting() {
            let ping = ServerPing(
                motd: "§aTowny§r · Economy\nSeason 4", online: 64, max: 200, protocolVersion: 765,
                gameVersions: ["1.20.4"], latencyMS: 71)
            let s = ServerSummary(id: "s", name: "Oakridge", address: "play.oakridge.gg").updated(with: ping)
            XCTAssertEqual(s.plainMOTD, "Towny · Economy · Season 4")
            XCTAssertEqual(s.playersLine, "64/200")
            XCTAssertEqual(s.pingMS, 71)
            XCTAssertEqual(s.gameVersions, ["1.20.4"])
            XCTAssertEqual(s.name, "Oakridge", "a ping never touches servers.dat fields")
            XCTAssertEqual(PingBars.level(71), 5)
            XCTAssertEqual(PingBars.level(450), 3)
            XCTAssertEqual(PingBars.level(1500), 1)
        }

        func testPastedAddressesAreCleaned() {
            XCTAssertEqual(ServerAddress.clean("  play.example.com\n"), "play.example.com")
            XCTAssertEqual(ServerAddress.clean("mc.example.com:25566"), "mc.example.com:25566")
            XCTAssertEqual(ServerAddress.clean("minecraft://mc.example.com/"), "mc.example.com")
            XCTAssertEqual(ServerAddress.clean("[::1]:25565"), "[::1]:25565")
            for bad in ["", "play example.com", "host:0", "host:70000", "host:abc", "https://x.net/page"] {
                XCTAssertNil(ServerAddress.clean(bad), bad)
            }
        }

        // Join: a server card opens GAP-14, another version offers an instance that fits, else straight in.
        func testJoinRoutes() async throws {
            let (mock, store) = await started()
            let ironwood = try server(store, "Ironwood SMP")
            XCTAssertEqual(store.route(ironwood), .card(ServerJoinRequest(server: ironwood.address)))
            XCTAssertEqual(store.route(try server(store, "Emberfall Network")), .join(instanceID: "survival"))
            guard case .otherVersion(let c)? = store.route(try server(store, "Oakridge Towny")) else {
                return XCTFail("Oakridge runs 1.20.4")
            }
            XCTAssertEqual(c.needs, "1.20.4")
            XCTAssertEqual(c.matches.map(\.id), ["skyblock"])
            mock.capabilities.remove(.serverJoin)
            XCTAssertEqual(store.route(ironwood), .join(instanceID: "survival"), "no card sheet: plain join")
        }

        func testJoinWithAnotherInstanceCopiesASavedServerThere() async throws {
            let (mock, store) = await started()
            let oakridge = try server(store, "Oakridge Towny")
            await store.join(oakridge, using: "skyblock")
            try await waitUntil { mock.lastJoin != nil }
            XCTAssertEqual(mock.lastJoin?.instanceID, "skyblock")
            XCTAssertEqual(mock.lastJoin?.address, "play.oakridge.gg")
            XCTAssertEqual(store.activeInstance?.id, "skyblock")
            XCTAssertEqual(try server(store, "Oakridge Towny").instanceID, "skyblock", "copied whole, name kept")
            XCTAssertEqual(store.joiningServer?.address, oakridge.address)
            await store.cancelLaunch()
        }

        func testJoiningARecommendedServerDoesNotSaveIt() async throws {
            let (mock, store) = await started()
            await store.loadRecommended()
            let pick = try XCTUnwrap(store.recommendedToShow.first { $0.name == "Lumen SMP" })
            await store.join(pick, using: "cobblemon")
            XCTAssertFalse(mock.serverLists["cobblemon"]?.contains { $0.address == pick.address } == true)
            await store.cancelLaunch()
        }

        func testNewInstancePlanCarriesTheServer() async throws {
            let (_, store) = await started()
            guard case .otherVersion(let c)? = store.route(try server(store, "Oakridge Towny")) else {
                return XCTFail("Oakridge runs 1.20.4")
            }
            store.planInstance(for: c)
            XCTAssertEqual(store.newInstancePlan?.version, "1.20.4")
            XCTAssertEqual(store.newInstancePlan?.loader, .vanilla)
            XCTAssertEqual(store.newInstancePlan?.server?.address, "play.oakridge.gg")
        }

        // The only writes: add (paste, link, Recommended), copy to an instance, delete. Each goes through servers.dat.
        func testServersDatWrites() async throws {
            let (mock, store) = await started()
            let added = await store.addServer(address: " new.example.net ", to: "survival")
            XCTAssertEqual(added?.name, "new.example.net")
            XCTAssertEqual(mock.serverLists["survival"]?.map(\.name), store.servers.map(\.name))
            let again = await store.addServer(address: "NEW.example.net", to: "survival")
            XCTAssertEqual(again?.id, added?.id, "no duplicates")
            XCTAssertEqual(store.servers.filter { $0.address == "new.example.net" }.count, 1)
            let bad = await store.addServer(address: "not an address", to: "survival")
            XCTAssertNil(bad)
            XCTAssertNotNil(store.lastError)

            let lan = try server(store, "Friends' world")
            await store.copyServer(lan, to: "create")
            XCTAssertTrue(mock.serverLists["create"]?.contains { $0.name == "Friends' world" } == true)

            store.pendingConfirmation = .removeServer(lan)
            XCTAssertTrue(store.servers.contains(lan), "nothing goes before the confirmation")
            await store.confirm(.removeServer(lan))
            XCTAssertFalse(store.servers.contains { $0.id == lan.id })
            XCTAssertTrue(mock.serverLists["create"]?.contains { $0.name == "Friends' world" } == true)
        }

        // What changed in game shows up: the list is read from servers.dat again, never cached.
        func testReloadPicksUpInGameChanges() async throws {
            let (mock, store) = await started()
            mock.serverLists["survival"]?[0].name = "Renamed in game"
            mock.serverLists["survival"]?.removeLast()
            await store.reloadServers()
            XCTAssertEqual(store.servers.first?.name, "Renamed in game")
            XCTAssertEqual(store.servers.count, 4)
        }

        func testRecommendedFitsAndSkipsSavedServers() async throws {
            let (mock, store) = await started()
            await store.loadRecommended()
            XCTAssertTrue(store.recommended.allSatisfy { $0.gameVersions.contains("1.21.1") })
            let shown = store.recommendedToShow.map(\.address)
            XCTAssertFalse(shown.contains("play.emberfall.net"), "already in My servers")
            XCTAssertFalse(shown.contains(MockServerJoin.ironwood.address))
            XCTAssertGreaterThan(shown.count, 6, "enough for Show more")

            let lumen = try XCTUnwrap(store.recommendedToShow.first { $0.name == "Lumen SMP" })
            await store.addServer(address: lumen.address, name: lumen.name, to: "survival")
            XCTAssertEqual(try server(store, "Lumen SMP").instanceID, "survival")
            XCTAssertFalse(store.recommendedToShow.contains { $0.address == lumen.address }, "moves up to My servers")

            mock.offline = true
            await store.loadRecommended(force: true)
            XCTAssertNotNil(store.recommendedError)
            XCTAssertTrue(store.recommended.isEmpty)
        }

        func testPingsMarkOfflineServers() async throws {
            let (mock, store) = await started()
            XCTAssertEqual(store.pingState(try server(store, "Old Factions")), .offline)
            XCTAssertEqual(store.live(try server(store, "Ironwood SMP")).playersOnline, 12)
            mock.serversOffline = true
            store.pingServers(force: true)
            try await waitUntil { store.servers.allSatisfy { store.pingState($0) == .offline } }
        }

        // The defaults hide every server control and never fake a join.
        func testServerControlsHiddenByDefault() async throws {
            let (_, store) = await started { $0.capabilities = [] }
            XCTAssertFalse(store.can(.serverFiles) || store.can(.discoverServers) || store.can(.quickPlay))
            XCTAssertTrue(store.servers.allSatisfy { store.pingState($0) == nil }, "no pings without .pingServers")
            await store.loadRecommended()
            XCTAssertTrue(store.recommended.isEmpty)
            do {
                _ = try await BareServers().discoverServers(instanceID: "a")
                XCTFail("should throw")
            } catch {}
        }

        func testServersPaneRendersEveryState() async throws {
            for state in ["mine", "empty", "offline"] {
                let (_, store) = await started {
                    if state == "empty" { $0.serverLists = [:] }
                    if state == "offline" { $0.serversOffline = true }
                }
                for (w, compact) in [(402.0, true), (1194.0, false)] {
                    let nav = NavModel()
                    nav.playPane = 2
                    let host = UIHostingController(rootView: CofreRootView(store: store, nav: nav))
                    host.traitOverrides.horizontalSizeClass = compact ? .compact : .regular
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: w, height: 874))
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    host.view.layoutIfNeeded()
                    XCTAssertFalse(host.view.subviews.isEmpty, "\(state) \(w)")
                    window.isHidden = true
                }
            }
        }

        // MARK: helpers

        private func started(_ configure: (MockBackend) -> Void = { _ in }) async -> (MockBackend, CofreStore) {
            let mock = MockBackend(stepDelay: 0)
            configure(mock)
            let store = CofreStore(services: CofreServices(backend: mock), defaults: freshDefaults())
            await store.start()
            try? await waitUntil { store.servers.allSatisfy { store.pingState($0) != .pinging } }
            return (mock, store)
        }

        private func server(_ store: CofreStore, _ name: String) throws -> ServerSummary {
            try XCTUnwrap(store.servers.first { $0.name == name }, name)
        }

        private func waitUntil(timeout: Double = 2, _ condition: @MainActor () -> Bool) async throws {
            let end = Date().addingTimeInterval(timeout)
            while !condition() {
                if Date() > end { return XCTFail("timed out") }
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        private func freshDefaults() -> UserDefaults {
            let name = "cofre.tests.\(UUID().uuidString)"
            let d = UserDefaults(suiteName: name)!
            d.removePersistentDomain(forName: name)
            return d
        }
    }

    /// A backend with nothing for servers: every `ServerService` member is the default.
    private final class BareServers: ServerService {
        func joinServer(instanceID: String, address: String, accountID: String?)
            -> AsyncThrowingStream<LaunchProgress, Error>
        { AsyncThrowingStream { $0.finish() } }
    }
#endif
