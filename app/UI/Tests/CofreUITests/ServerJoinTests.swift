#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import CofreUI

/// Join server sheet (GAP-14): deep links, gating, the one primary button, the mock flow, and a render of every state.
@MainActor
final class ServerJoinTests: XCTestCase {

    // SPEC §2 priority 1: `cofre://join?server=…&card=…&pin=…`, HTTPS cards only.
    func testDeepLinkParsing() throws {
        let link = try XCTUnwrap(URL(string: "cofre://join?server=play.example.com:25565&card=https%3A%2F%2Fexample.com%2Fserver-card.json&pin=vL10x4tF1n7tM1z9"))
        let r = try XCTUnwrap(ServerJoinRequest(url: link))
        XCTAssertEqual(r.server, "play.example.com:25565")
        XCTAssertEqual(r.card?.absoluteString, "https://example.com/server-card.json")
        XCTAssertEqual(r.pin, "vL10x4tF1n7tM1z9")

        XCTAssertNil(ServerJoinRequest(url: URL(string: "cofre://join?server=a.b&card=http%3A%2F%2Fevil.test%2Fc.json")!), "plain HTTP card")
        XCTAssertNil(ServerJoinRequest(url: URL(string: "cofre://join?card=https%3A%2F%2Fexample.com%2Fc.json")!), "no server")
        XCTAssertNil(ServerJoinRequest(url: URL(string: "cofre://join?server=a%20b%3Bc")!), "junk in server")
        XCTAssertNil(ServerJoinRequest(url: URL(string: "cofre://open?server=a.b")!))
        XCTAssertNil(ServerJoinRequest(url: URL(string: "https://join?server=a.b")!))

        let nav = NavModel()
        XCTAssertTrue(nav.open(link))
        XCTAssertEqual(nav.serverJoin, r)
        XCTAssertFalse(nav.open(URL(string: "cofre://settings")!))
    }

    // Off in production until the backend wires it; on in MockBackend.
    func testServerJoinIsGatedByCapability() {
        XCTAssertNil(BareJoin().serverJoin(ServerJoinRequest(server: "a.b")), "default facade has no model")
        XCTAssertFalse(BackendCapabilities().contains(.serverJoin))

        let mock = MockBackend(stepDelay: 0)
        let store = CofreStore(services: CofreServices(backend: mock), defaults: freshDefaults())
        XCTAssertTrue(store.can(.serverJoin))
        XCTAssertNotNil(store.openServerJoin(ServerJoinRequest(server: "play.ironwood.gg")))

        mock.capabilities = []
        let off = CofreStore(services: CofreServices(backend: mock), defaults: freshDefaults())
        XCTAssertNil(off.openServerJoin(ServerJoinRequest(server: "play.ironwood.gg")))
    }

    // Exactly one primary, disabled with "1 left" until CurseForge files arrive; a changed key blocks outright.
    func testPrimaryWaitsForWhatsLeft() {
        let attention = MockServerJoin.attention
        XCTAssertFalse(attention.canInstall)
        XCTAssertEqual(attention.primaryStatus, "1 left", "the voice chat notice doesn't count; one of two downloads is done")

        let resolved = ServerJoinWarningState(warnings: attention.warnings.map { var w = $0; w.isResolved = true; return w }, canProceedAnyway: false)
        XCTAssertTrue(resolved.canInstall)
        XCTAssertNil(resolved.primaryStatus)

        XCTAssertFalse(MockServerJoin.keyChange.canInstall)
        XCTAssertEqual(MockServerJoin.keyChange.primaryStatus, "Blocked", "no way to fix it from the sheet")
        let anyway = ServerJoinWarningState(warnings: MockServerJoin.keyChange.warnings, canProceedAnyway: true)
        XCTAssertFalse(anyway.canInstall, "canProceedAnyway never waives a security item")
    }

    func testOptionalSwitchChangesDownloadSize() throws {
        let model = MockServerJoin(scenario: .firstVisit, stepDelay: 0)
        guard case .requirements(let before) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(before.formattedDownloadSize, "237 MB")
        XCTAssertEqual(Fmt.bytes(before.requiredMods.reduce(0) { $0 + $1.sizeBytes }), "186 MB")
        XCTAssertEqual(before.requiredMods.count, before.requiredModCount)

        model.send(.setSelected(id: "complementary", isSelected: true))
        guard case .requirements(let after) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(after.formattedDownloadSize, "259 MB")
        XCTAssertEqual(after.shaderPacks.first?.isSelected, true)
    }

    func testInstallRunsToReadyAndCurseForgeResolves() async throws {
        let model = MockServerJoin(scenario: .needsAttention, stepDelay: 0)
        model.send(.install)
        XCTAssertEqual(model.state.phase, .warnings, "blocked until the last file arrives")
        model.send(.resolveWarning(id: "\(ServerJoinWarningState.StandardID.curseForgeManual):farmers-delight"))
        try await waitUntil { model.state.warnings?.canInstall == true }
        model.send(.install)
        try await waitUntil { model.state.phase == .ready }
    }

    // Closing the sheet never stops an install; other states are dropped so the card is read again.
    func testStoreKeepsRunningInstallAfterClose() async throws {
        let mock = MockBackend(stepDelay: 0.05)
        mock.serverJoinScenario = .firstVisit
        let store = CofreStore(services: CofreServices(backend: mock), defaults: freshDefaults())
        let request = ServerJoinRequest(server: "play.ironwood.gg")

        store.openServerJoin(request)
        store.closeServerJoin(request)
        XCTAssertNil(store.serverJoins[request.id])

        let model = try XCTUnwrap(store.openServerJoin(request))
        model.send(.install)
        store.closeServerJoin(request)
        XCTAssertTrue(store.serverJoins[request.id] === model)
        XCTAssertNotNil(store.serverJoinProgress(address: "play.ironwood.gg"))
        try await waitUntil(timeout: 5) { model.state.phase == .ready }
    }

    // The sheet uses its own words for every code, never the backend's raw text.
    func testErrorCopyNeverShowsRawText() {
        let raw = MockServerJoin.error
        for code in ServerJoinErrorState.ErrorCode.allCases {
            let copy = JoinErrorCopy(code)
            XCTAssertFalse(copy.title.isEmpty || copy.message.isEmpty, code.rawValue)
            for text in [copy.title, copy.message] {
                XCTAssertFalse(text.contains(raw.message) || text.contains("ERR_") || text.contains("NSURLErrorDomain"), code.rawValue)
            }
        }
    }

    func testTrustLineIsShort() {
        XCTAssertEqual(ServerJoinTrust.short("7f3a9c21e4b05d18aa"), "7f3a 9c21")
        XCTAssertEqual(ServerJoinTrust.short("vL10-x4tF_1n7"), "vL10 x4tF")
        XCTAssertEqual(ServerJoinTrust.short("ab12"), "ab12")
    }

    /// Render test: every state, as a bottom sheet (compact, 402 pt) and as the 560 pt card (regular), plus the largest
    /// accessibility text size. Fails on a blank render; set `COFRE_SNAPSHOT_DIR` to keep the PNGs.
    func testEveryStateRenders() throws {
        let out = ProcessInfo.processInfo.environment["COFRE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let out { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        CofreUI.bootstrap()
        let layouts: [(String, UIUserInterfaceSizeClass, CGSize, UIContentSizeCategory)] = [
            ("compact", .compact, CGSize(width: 402, height: 874), .large),
            ("card", .regular, CGSize(width: 560, height: 900), .large),
            ("compact-ax", .compact, CGSize(width: 402, height: 874), .accessibilityExtraExtraLarge),
        ]
        for scenario in MockServerJoin.Scenario.allCases {
            for (name, sizeClass, size, type) in layouts {
                let model = MockServerJoin(scenario: scenario, stepDelay: 60)
                let host = UIHostingController(rootView: JoinServerSheet(model: model).environment(\.cofreTheme, .standard))
                host.traitOverrides.horizontalSizeClass = sizeClass
                host.traitOverrides.preferredContentSizeCategory = type
                host.overrideUserInterfaceStyle = .dark
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                // The test runner has no app scene, so render the layer tree instead of the (offscreen) window.
                let image = UIGraphicsImageRenderer(size: size).image { ctx in host.view.layer.render(in: ctx.cgContext) }
                XCTAssertGreaterThan(distinctColors(image), 8, "\(scenario) \(name) rendered blank")
                let label = "join-\(scenario.rawValue)-\(name)"
                let attachment = XCTAttachment(image: image); attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
                if let out { try image.pngData()?.write(to: out.appendingPathComponent("\(label).png")) }
                window.isHidden = true
            }
        }
    }

    func testModdedServerRowRenders() async throws {
        let store = CofreStore(services: .mock(), defaults: freshDefaults())
        await store.start()
        XCTAssertTrue(store.servers.contains { $0.hasServerCard }, "mock lists Ironwood SMP with a card")
        let nav = NavModel(); nav.playPane = 1
        let host = UIHostingController(rootView: CofreRootView(store: store, nav: nav))
        host.traitOverrides.horizontalSizeClass = .compact
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        XCTAssertFalse(host.view.subviews.isEmpty)
        window.isHidden = true
    }

    // MARK: helpers

    private func waitUntil(timeout: Double = 2, _ condition: @MainActor () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func distinctColors(_ image: UIImage) -> Int {
        guard let cg = image.cgImage, let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return 0 }
        var seen = Set<UInt32>()
        let bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        for y in stride(from: 0, to: cg.height, by: 7) {
            for x in stride(from: 0, to: cg.width, by: 7) {
                let i = y * bpr + x * bpp
                seen.insert(UInt32(p[i]) << 16 | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]))
                if seen.count > 64 { return seen.count }
            }
        }
        return seen.count
    }

    private func freshDefaults() -> UserDefaults {
        let name = "cofre.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}

/// A backend that adopts GAP-14 without implementing it, to check the default.
private final class BareJoin: ServerJoinSource {}
#endif
