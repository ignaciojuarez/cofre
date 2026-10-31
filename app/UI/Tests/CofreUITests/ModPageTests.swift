#if canImport(UIKit)
    import CofreKit
    import SwiftUI
    import UIKit
    import WebKit
    import XCTest
    @testable import CofreUI

    /// M02 Mod page: tabs, the pinned Get, page memory and "What's new".
    @MainActor
    final class ModPageTests: XCTestCase {

        private func store() async -> CofreStore {
            let name = "cofre.tests.\(UUID().uuidString)"
            let s = CofreStore(
                services: CofreServices(backend: MockBackend(stepDelay: 0)), defaults: UserDefaults(suiteName: name)!)
            await s.start()
            await s.search()
            return s
        }

        func testGalleryTabHidesWhenEmpty() {
            XCTAssertEqual(ModPageTab.shown(nil), [.about, .versions])
            XCTAssertEqual(ModPageTab.shown(.sample(id: "lithium")), [.about, .versions])
            XCTAssertEqual(ModPageTab.shown(.sample(id: "sodium")), [.about, .gallery, .versions])
            // A video in the body is enough.
            let video = ProjectPage(
                id: "x", source: .modrinth, title: "X", videos: [ProjectPage.Video(youTubeID: "rR8W-f9YhYA")!])
            XCTAssertEqual(ModPageTab.shown(video), [.about, .gallery, .versions])
        }

        func testOnlyTheNewestPagesStayInMemory() async {
            let s = await store()
            let ids = (0...CofreStore.keptPages).map { "p\($0)" }
            for id in ids { await s.loadPage(id) }
            XCTAssertEqual(s.pages.count, CofreStore.keptPages)
            XCTAssertNil(s.pages["p0"])
            XCTAssertNil(s.pageDocuments["p0"])
            // Opening a kept page again makes it the newest, so the next load drops another one.
            await s.loadPage("p1")
            await s.loadPage("p0")
            XCTAssertNotNil(s.pages["p1"])
            XCTAssertNil(s.pages["p2"])
            XCTAssertEqual(s.pageDocuments.count, CofreStore.keptPages)
        }

        func testChangelogFillsTheVersionOnce() async throws {
            let s = await store()
            s.versions["iris"] = [ProjectVersion(id: "iris-1", name: "1.8.8", gameVersions: "1.21.1", fits: true)]
            try await s.loadChangelog("iris", versionID: "iris-1")
            XCTAssertEqual(s.versions["iris"]?.first?.changelog, .markdown(ProjectPage.sampleChangelog))
            XCTAssertEqual(ProjectPage.Body.markdown(" \n").isBlank, true)
            // CurseForge notes need their own client: an empty changelog says "No notes" instead of asking again.
            s.results = s.results.map {
                var p = $0
                p.source = .curseforge
                return p
            }
            s.versions["iris"] = [ProjectVersion(id: "iris-1", name: "1.8.8", gameVersions: "1.21.1", fits: true)]
            try await s.loadChangelog("iris", versionID: "iris-1")
            XCTAssertEqual(s.versions["iris"]?.first?.changelog?.isBlank, true)
        }

        func testGetTitleFollowsTheInstallState() async {
            let s = await store()
            let p = s.results.first { $0.id == "appleskin" }!
            // Before the versions arrive, Get still works: the store picks the build.
            XCTAssertEqual(ModPageState(store: s, project: p, versionID: nil).actionTitle, "Get")
            await s.loadProject("appleskin")
            let state = ModPageState(store: s, project: p, versionID: nil)
            XCTAssertEqual(state.actionTitle, "Get")
            let older = s.versions["appleskin"]!.last { $0.fits && $0.id != state.chosen }!
            XCTAssertEqual(
                ModPageState(store: s, project: p, versionID: older.id).actionTitle,
                ModPagePane.title("Install", older))
            // Installed and current: nothing pinned.
            let iris = s.results.first { $0.id == "iris" }!
            XCTAssertNil(ModPageState(store: s, project: iris, versionID: nil).actionTitle)
        }

        /// iPhone (bottom bar) and iPad (rail): each tab shows its own content, and ⌘↩ (the pinned Get's shortcut)
        /// starts an install from every one of them.
        func testGetWorksFromEveryTabAtBothSizes() async {
            let sizes: [(WidthClass, CGSize)] = [
                (.compact, CGSize(width: 402, height: 874)), (.expanded, CGSize(width: 1100, height: 1000)),
            ]
            for (width, size) in sizes {
                for tab in [ModPageTab.about, .gallery, .versions] {
                    await checkGet(on: tab, width: width, size: size)
                }
            }
        }

        private func checkGet(on tab: ModPageTab, width: WidthClass, size: CGSize) async {
            let name = "\(tab) at \(Int(size.width)) pt"
            let s = await store()
            await s.loadPage("appleskin")
            let shown = show(.init(id: "appleskin", tab: tab), store: s, width: width, size: size)
            // About renders the body, Versions the picked version's notes; the Gallery is native.
            let webViews = await settle(shown.host) { tab == .gallery || $0 > 0 }
            XCTAssertEqual(webViews > 0, tab != .gallery, name)
            let commands = shown.host.keyCommands ?? []
            XCTAssertEqual(commands.filter { $0.input == "\r" }.count, 1, "\(name): one Get")
            if let get = commands.first(where: { $0.input == "\r" && $0.modifierFlags == .command }) {
                // Sent to whichever responder handles it, from a plain main-queue callout the way a key press
                // arrives (not inside the test's task).
                let handler = get.action.flatMap { action in
                    ([shown.host] + views(shown.host.view)).lazy.compactMap {
                        $0.target(forAction: action, withSender: get) as? NSObject
                    }.first
                }
                XCTAssertNotNil(handler, name)
                await withCheckedContinuation { done in
                    DispatchQueue.main.async {
                        _ = handler?.perform(get.action, with: get)
                        done.resume()
                    }
                }
                for _ in 0..<100 where s.modInstalls["appleskin"] == nil && !installed(s) {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertTrue(s.modInstalls["appleskin"] != nil || installed(s), "\(name): Get didn't start")
            } else {
                XCTFail("\(name): no ⌘↩")
            }
            shown.window.isHidden = true
        }

        /// A hidden Gallery tab can't stay picked: the page falls back to About.
        func testHiddenGalleryFallsBackToAbout() async {
            let s = await store()
            await s.loadPage("lithium")
            let phone = CGSize(width: 402, height: 874)
            let shown = show(.init(id: "lithium", tab: .gallery), store: s, width: .compact, size: phone)
            let webViews = await settle(shown.host) { $0 > 0 }
            XCTAssertEqual(webViews, 1)
            shown.window.isHidden = true
        }

        // MARK: Hosting

        private func row(_ s: CofreStore) -> ProjectSummary { s.results.first { $0.id == "appleskin" }! }

        private func show(_ view: ModPagePane, store: CofreStore, width: WidthClass, size: CGSize)
            -> (window: UIWindow, host: UIViewController)
        {
            let host = UIHostingController(
                rootView: NavigationStack { view }.environment(store).environment(\.widthClass, width))
            host.traitOverrides.horizontalSizeClass = width == .compact ? .compact : .regular
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            return (window, host)
        }

        private func installed(_ s: CofreStore) -> Bool { s.installState(row(s)) == .installed }

        private func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }

        /// The page's web views, once `ready` holds (or after about a second).
        private func settle(_ host: UIViewController, until ready: (Int) -> Bool) async -> Int {
            var count = 0
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(20))
                host.view.layoutIfNeeded()
                count = views(host.view).filter { $0 is WKWebView }.count
                if ready(count) { break }
            }
            return count
        }
    }
#endif
