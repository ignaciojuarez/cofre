#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers
    import XCTest
    @testable import CofreUI

    @MainActor
    final class CofreUITests: XCTestCase {

        // §3.1: the window decides, never the device.
        func testWidthClassBreakpoints() {
            XCTAssertEqual(WidthClass.resolve(sizeClass: .compact, width: 1400), .compact)
            XCTAssertEqual(WidthClass.resolve(sizeClass: .regular, width: 834), .medium)
            XCTAssertEqual(WidthClass.resolve(sizeClass: .regular, width: 1099), .medium)
            XCTAssertEqual(WidthClass.resolve(sizeClass: .regular, width: 1100), .expanded)
            XCTAssertEqual(WidthClass.resolve(sizeClass: .regular, width: 1376), .expanded)
        }

        func testSizeClassBreakpoints() {
            func classes(_ w: CGFloat, _ h: CGFloat) -> [UserInterfaceSizeClass] {
                let c = SizeClasses(CGSize(width: w, height: h))
                return [c.horizontal, c.vertical]
            }
            XCTAssertEqual(classes(402, 778), [.compact, .regular])  // iPhone 17 Pro
            XCTAssertEqual(classes(750, 381), [.regular, .compact])  // same, landscape
            XCTAssertEqual(classes(744, 1133), [.regular, .regular])  // iPad mini
            XCTAssertEqual(classes(320, 1024), [.compact, .regular])  // Slide Over
        }

        // Air reports regular/regular everywhere: a 402 pt window must still read compact.
        func testWindowSizeBeatsUIKitSizeClasses() {
            let seen = probeSizeClasses(uikit: .regular, measured: nil)
            XCTAssertEqual(seen["root"], .compact)
        }

        // Sheets get the root's classes, not their own UIKit ones (compact on an iPhone simulator).
        func testSheetsReuseTheRootSizeClasses() throws {
            guard UIApplication.shared.connectedScenes.first is UIWindowScene else { throw XCTSkip("no window scene") }
            let seen = probeSizeClasses(uikit: .compact, measured: SizeClasses(CGSize(width: 1000, height: 1000)))
            XCTAssertEqual(seen["root"], .regular)
            XCTAssertEqual(seen["sheet"], .regular)
        }

        /// Hosts a probe plus a `blockSheet` probe in a 402 × 874 window whose UIKit size classes are `uikit`.
        /// `measured: nil` measures the window like `CofreRootView`.
        private func probeSizeClasses(uikit: UIUserInterfaceSizeClass, measured: SizeClasses?)
            -> [String: UserInterfaceSizeClass]
        {
            let seen = SeenSizeClasses()
            let view = GeometryReader { g in
                SizeClassProbe(seen: seen, key: "root")
                    .blockSheet(isPresented: .constant(true)) { SizeClassProbe(seen: seen, key: "sheet") }
                    .sizeClasses(measured ?? SizeClasses(g.size))
            }
            let host = UIHostingController(rootView: view)
            host.traitOverrides.horizontalSizeClass = uikit
            host.traitOverrides.verticalSizeClass = uikit
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = host
            window.makeKeyAndVisible()
            let end = Date().addingTimeInterval(scene == nil ? 0.3 : 3)
            while seen.values["sheet"] == nil, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            host.dismiss(animated: false)
            window.isHidden = true
            return seen.values
        }

        // §1.1: every text pair passes WCAG AA (4.5:1).
        func testTextContrastPassesAA() {
            let c = UIColor.cofre
            let pairs: [(String, UIColor, UIColor)] = [
                ("ink/page", c.ink, c.page), ("muted/panel", c.muted, c.panel), ("muted/side", c.muted, c.side),
                ("accent/panel", c.accent, c.panel), ("onFace/face", c.onFace, c.face),
                ("success/panel", c.success, c.panel), ("warn/panel", c.warn, c.panel),
                ("danger/panel", c.danger, c.panel),
            ]
            let tc = UITraitCollection(accessibilityContrast: .normal)
            for (name, fg, bg) in pairs {
                let ratio = contrast(fg.resolvedColor(with: tc), bg.resolvedColor(with: tc))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) is \(ratio)")
            }
        }

        func testIncreaseContrastSwapsOutline() {
            let normal = UITraitCollection(traitsFrom: [
                .init(userInterfaceStyle: .dark), .init(accessibilityContrast: .normal),
            ])
            let high = UITraitCollection(traitsFrom: [
                .init(userInterfaceStyle: .dark), .init(accessibilityContrast: .high),
            ])
            let panel = UIColor.cofre.panel.resolvedColor(with: high)
            XCTAssertLessThan(contrast(UIColor.cofre.outline.resolvedColor(with: normal), panel), 2)
            XCTAssertGreaterThan(contrast(UIColor.cofre.outline.resolvedColor(with: high), panel), 4.5)
        }

        func testBundledFontsRegister() {
            XCTAssertTrue(CofreFonts.register())
            for name in [
                "PixelifySans-Medium", "PixelifySans-SemiBold", "PixelifySans-Bold", "Geist-Regular", "Geist-Medium",
                "Geist-SemiBold", "GeistMono-Regular", "GeistMono-Medium",
            ] {
                XCTAssertNotNil(UIFont(name: name, size: 12), name)
            }
            XCTAssertEqual(UIFont.cofre(.rowTitle).fontName, "Geist-Medium")
            XCTAssertNotNil(CofreFonts.licenseURL)
        }

        // S04 fallback: the Mac command's `.mobiledevicepairing` file is accepted, and so is a plain plist.
        func testPairingFileTypesAndLink() throws {
            let macFile = try XCTUnwrap(UTType(filenameExtension: "mobiledevicepairing"))
            XCTAssertTrue(UTType.pairingFiles.contains { macFile.conforms(to: $0) })
            XCTAssertTrue(UTType.pairingFiles.contains { UTType.xmlPropertyList.conforms(to: $0) })
            XCTAssertEqual(CofreLinks.short(CofreLinks.pairing), "ignaciojuarez.github.io/cofre/pair")
        }

        // Users paste what these pages show into Terminal: every link must stay on a host we control.
        func testLinksStayOnAllowedHosts() {
            for url in CofreLinks.all {
                XCTAssertEqual(url.scheme, "https", url.absoluteString)
                XCTAssertTrue(CofreLinks.allowedHosts.contains(url.host() ?? ""), url.absoluteString)
                if url.host() == "github.com" { XCTAssertTrue(url.path().hasPrefix("/ignaciojuarez/cofre/")) }
            }
            // The command Copy and Share hand over is the site's (docs/app.js) and runs only that script.
            XCTAssertEqual(CofreLinks.pairCommand, "curl -fsSL \(CofreLinks.pairScript.absoluteString) | sh")
        }

        func testMockLaunchStreamFinishes() async throws {
            let mock = MockBackend(stepDelay: 0)
            var last: LaunchProgress?
            for try await p in mock.launch(instanceID: "survival", accountID: nil) { last = p }
            XCTAssertEqual(last?.finished, true)
            XCTAssertEqual(last?.stage, 7)
            XCTAssertEqual(last?.of, 7)
        }

        func testStoreLoadsAndRunsJITTest() async {
            let store = CofreStore(
                services: CofreServices(backend: MockBackend(setupComplete: false, stepDelay: 0)),
                defaults: freshDefaults())
            XCTAssertFalse(store.showsSetup, "no wizard before setup state loads")
            await store.start()
            XCTAssertEqual(store.instances.count, 5)
            XCTAssertEqual(store.activeInstance?.name, "Survival+")
            XCTAssertTrue(store.showsSetup)
            await store.testJIT()
            XCTAssertTrue(store.setup.jit.isReady)
            XCTAssertTrue(store.jitSteps.allSatisfy { $0.state.isReady })
        }

        // Setup resumes where the user left off, and never shows again once finished.
        func testSetupProgressPersists() async {
            let defaults = freshDefaults()
            let mock = MockBackend(setupComplete: false, stepDelay: 0)
            let first = CofreStore(services: CofreServices(backend: mock), defaults: defaults)
            await first.start()
            XCTAssertEqual(first.resumeStep, 0, "first open shows Welcome")
            XCTAssertEqual(first.firstOpenStep, 3, "Dev Mode and Trust pass in the mock")
            first.setupStep = 4

            let second = CofreStore(services: CofreServices(backend: mock), defaults: defaults)
            await second.start()
            XCTAssertEqual(second.resumeStep, 4, "cold start resumes at the saved step")
            mock.state.vpn = .ready
            let third = CofreStore(services: CofreServices(backend: mock), defaults: defaults)
            await third.start()
            XCTAssertEqual(third.resumeStep, 3, "a passed step resumes at the first open check")

            third.finishSetup()
            let done = CofreStore(services: CofreServices(backend: mock), defaults: defaults)
            XCTAssertTrue(done.setupCompleted, "known before the first frame, so no wizard flash")
            XCTAssertFalse(done.showsSetup)
            await done.start()
            XCTAssertFalse(done.showsSetup, "live checks failing after setup don't bring the wizard back")
        }

        func testCompleteBackendSkipsWizard() async {
            let store = CofreStore(services: .mock(), defaults: freshDefaults())
            await store.start()
            XCTAssertTrue(store.setupCompleted)
            XCTAssertFalse(store.showsSetup)
        }

        // Every Delete goes through one confirmation; nothing is removed until it's confirmed.
        func testDeleteWaitsForConfirmation() async throws {
            let store = CofreStore(
                services: CofreServices(backend: MockBackend(stepDelay: 0)), defaults: freshDefaults())
            await store.start()
            let inst = try XCTUnwrap(store.instances.last)
            store.pendingConfirmation = .deleteInstance(inst)
            XCTAssertTrue(store.instances.contains(inst))
            await store.confirm(.deleteInstance(inst))
            XCTAssertFalse(store.instances.contains { $0.id == inst.id })
        }

        // Controls without a backend stay hidden: the default reports nothing, and actions throw instead of pretending.
        func testCapabilitiesDefaultToNothing() {
            let mock = MockBackend(stepDelay: 0)
            let store = CofreStore(services: CofreServices(backend: mock), defaults: freshDefaults())
            XCTAssertFalse(store.can(.controllerNavigation))
            XCTAssertEqual(MinimalActions().capabilities, [])
            mock.capabilities = [.controllerNavigation]
            XCTAssertTrue(store.can(.controllerNavigation))
        }

        func testOfflineSearchShowsError() async {
            let mock = MockBackend(stepDelay: 0)
            mock.offline = true
            let store = CofreStore(services: CofreServices(backend: mock), defaults: freshDefaults())
            await store.search()
            XCTAssertNotNil(store.searchError)
            XCTAssertTrue(store.results.isEmpty)
        }

        // Typing cancels the previous search; a cancelled search never shows "Can't reach".
        func testCancelledOrStaleSearchLeavesStateAlone() async {
            let mock = MockBackend(stepDelay: 0)
            mock.offline = true
            let store = CofreStore(services: CofreServices(backend: mock), defaults: freshDefaults())
            let cancelled = Task { await store.search() }
            cancelled.cancel()
            await cancelled.value
            XCTAssertNil(store.searchError)
            XCTAssertFalse(store.searching)
        }

        // Mods works on one instance that runs mods: Play's when it does, else the last one picked.
        func testModsTargetsAnInstanceThatRunsMods() async throws {
            let defaults = freshDefaults()
            let store = CofreStore(services: CofreServices(backend: MockBackend(stepDelay: 0)), defaults: defaults)
            await store.start()
            XCTAssertEqual(store.modsInstance?.id, "survival")
            XCTAssertEqual(store.query.instanceID, "survival")
            await store.search()
            XCTAssertTrue(store.results.contains { $0.id == "iris" })
            XCTAssertFalse(store.results.contains { $0.id == "create" })  // Forge and NeoForge only

            // Picking in Mods selects it in Play too; Vanilla in Play keeps Mods where it was.
            await store.selectInstance("cobblemon")
            await store.selectInstance("vanilla")
            XCTAssertEqual(store.activeInstance?.id, "vanilla")
            XCTAssertEqual(store.modsInstance?.id, "cobblemon")
            XCTAssertEqual(store.query.instanceID, "cobblemon")
            await store.search()
            XCTAssertTrue(store.results.contains { $0.id == "create" })
            XCTAssertFalse(store.results.contains { $0.id == "iris" })

            // Remembered across launches.
            let again = CofreStore(services: CofreServices(backend: MockBackend(stepDelay: 0)), defaults: defaults)
            await again.start()
            await again.selectInstance("vanilla")
            XCTAssertEqual(again.modsInstance?.id, "cobblemon")

            // Nothing runs mods: no target, so Mods shows only the hero.
            again.instances.removeAll { $0.loader != .vanilla }
            XCTAssertNil(again.modsInstance)
            XCTAssertNil(again.query.instanceID)
        }

        func testNewInstancePlanFromMods() async {
            let store = CofreStore(services: CofreServices(backend: MockBackend(stepDelay: 0)), defaults: freshDefaults())
            await store.start()
            await store.selectInstance("vanilla")
            // Fabric on the same version; taken names get a number.
            XCTAssertEqual(store.planNewInstance(), NewInstancePlan(name: "Fabric 26.3", version: "26.3", loader: .fabric))
            store.instances.append(InstanceSummary(id: "x", name: "Fabric 26.3", loader: .fabric, gameVersion: "26.3"))
            XCTAssertEqual(store.planNewInstance().name, "Fabric 26.3 2")
        }

        func testAgoLongCoversMonths() {
            let now = Date()
            XCTAssertEqual(Fmt.agoLong(now.addingTimeInterval(-10 * 86400), now: now), "last week")
            XCTAssertEqual(Fmt.agoLong(now.addingTimeInterval(-90 * 86400), now: now), "3 months ago")
            XCTAssertEqual(Fmt.agoLong(now.addingTimeInterval(-400 * 86400), now: now), "over a year ago")
        }

        func testUpdateAllClearsUpdates() async {
            let store = CofreStore(services: CofreServices(backend: MockBackend(stepDelay: 0)))
            await store.start()
            XCTAssertEqual(store.updateCount, 3)
            await store.updateAll()
            XCTAssertEqual(store.updateCount, 0)
            XCTAssertTrue((store.installed[.mods] ?? []).allSatisfy { $0.updateTo == nil })
        }

        func testNavStateSurvivesRestoration() {
            let nav = NavModel()
            nav.section = .mods
            nav.mod = .project("iris")
            nav.settingsPane = .jitJava
            nav.instance = "survival"
            let restored = NavModel()
            restored.restore(from: nav.userActivity())
            XCTAssertEqual(restored.section, .mods)
            XCTAssertEqual(restored.mod, .project("iris"))
            XCTAssertEqual(restored.settingsPane, .jitJava)
            XCTAssertEqual(restored.instance, "survival")
        }

        /// Renders every section in compact, medium and expanded windows (the same panes in all three).
        func testEverySectionRendersAtEveryWidth() throws {
            let sizes: [(UIUserInterfaceSizeClass, CGSize)] = [
                (.compact, .init(width: 402, height: 874)),
                (.regular, .init(width: 834, height: 1210)),
                (.regular, .init(width: 1376, height: 1032)),
            ]
            for section in NavModel.Section.allCases {
                for (sizeClass, size) in sizes {
                    let nav = NavModel()
                    nav.section = section
                    let store = CofreStore(services: .mock(), defaults: freshDefaults())
                    store.finishSetup()
                    let host = UIHostingController(rootView: CofreRootView(store: store, nav: nav))
                    host.traitOverrides.horizontalSizeClass = sizeClass
                    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    host.view.layoutIfNeeded()
                    XCTAssertFalse(host.view.subviews.isEmpty, "\(section) at \(size)")
                    window.isHidden = true
                }
            }
        }

        func testUIKitThemeApplies() {
            CofreUIKitTheme.apply()
            let bar = UINavigationBar.appearance(whenContainedInInstancesOf: [CofreAirHostController.self])
            XCTAssertNotNil(bar.standardAppearance.backgroundColor)
            let vc = CofreUI.makeRootViewController(services: .mock())
            XCTAssertTrue(vc is UIHostingController<CofreRootView>)
        }

        private func freshDefaults() -> UserDefaults {
            let name = "cofre.tests.\(UUID().uuidString)"
            let d = UserDefaults(suiteName: name)!
            d.removePersistentDomain(forName: name)
            return d
        }

        private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
            func lum(_ c: UIColor) -> Double {
                var r: CGFloat = 0
                var g: CGFloat = 0
                var bl: CGFloat = 0
                var al: CGFloat = 0
                c.getRed(&r, green: &g, blue: &bl, alpha: &al)
                func ch(_ v: CGFloat) -> Double {
                    let v = Double(v)
                    return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
                }
                return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(bl)
            }
            let (l1, l2) = (lum(a), lum(b))
            return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
        }
    }
    @MainActor private final class SeenSizeClasses { var values: [String: UserInterfaceSizeClass] = [:] }

    private struct SizeClassProbe: View {
        let seen: SeenSizeClasses, key: String
        @Environment(\.horizontalSizeClass) private var sizeClass
        var body: some View { Color.clear.onAppear { seen.values[key] = sizeClass } }
    }

    /// An `OptionalActions` conformer that implements nothing, to check the defaults.
    private final class MinimalActions: OptionalActions {}
#endif
