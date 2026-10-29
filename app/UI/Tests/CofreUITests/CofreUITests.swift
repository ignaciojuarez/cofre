import SwiftUI
import UIKit
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

    // §1.1: every text pair passes WCAG AA (4.5:1) in both themes.
    func testTextContrastPassesAA() {
        let c = UIColor.cofre
        let pairs: [(String, UIColor, UIColor)] = [
            ("ink/page", c.ink, c.page), ("muted/panel", c.muted, c.panel), ("muted/side", c.muted, c.side),
            ("accent/panel", c.accent, c.panel), ("onFace/face", c.onFace, c.face),
            ("success/panel", c.success, c.panel), ("warn/panel", c.warn, c.panel), ("danger/panel", c.danger, c.panel),
        ]
        for style in [UIUserInterfaceStyle.dark, .light] {
            let tc = UITraitCollection(userInterfaceStyle: style)
            for (name, fg, bg) in pairs {
                let ratio = contrast(fg.resolvedColor(with: tc), bg.resolvedColor(with: tc))
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) in \(style == .dark ? "dark" : "light") is \(ratio)")
            }
        }
    }

    func testIncreaseContrastSwapsOutline() {
        let normal = UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .dark), .init(accessibilityContrast: .normal)])
        let high = UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .dark), .init(accessibilityContrast: .high)])
        let panel = UIColor.cofre.panel.resolvedColor(with: high)
        XCTAssertLessThan(contrast(UIColor.cofre.outline.resolvedColor(with: normal), panel), 2)
        XCTAssertGreaterThan(contrast(UIColor.cofre.outline.resolvedColor(with: high), panel), 4.5)
    }

    func testBundledFontsRegister() {
        XCTAssertTrue(CofreFonts.register())
        for name in ["PixelifySans-Medium", "PixelifySans-SemiBold", "PixelifySans-Bold", "Geist-Regular", "Geist-Medium",
                     "Geist-SemiBold", "GeistMono-Regular", "GeistMono-Medium"] {
            XCTAssertNotNil(UIFont(name: name, size: 12), name)
        }
        XCTAssertEqual(UIFont.cofre(.rowTitle).fontName, "Geist-Medium")
        XCTAssertNotNil(CofreFonts.licenseURL)
    }

    func testMockLaunchStreamFinishes() async throws {
        let mock = MockBackend(stepDelay: 0)
        var last: LaunchProgress?
        for try await p in mock.launch(instanceID: "survival", accountID: nil) { last = p }
        XCTAssertEqual(last?.finished, true)
        XCTAssertEqual(last?.stage, 8)
    }

    func testStoreLoadsAndRunsJITTest() async {
        let store = CofreStore(services: CofreServices(backend: MockBackend(setupComplete: false, stepDelay: 0)))
        await store.start()
        XCTAssertEqual(store.instances.count, 5)
        XCTAssertEqual(store.activeInstance?.name, "Survival+")
        XCTAssertTrue(store.showsSetup)
        await store.testJIT()
        XCTAssertTrue(store.setup.jit.isReady)
        XCTAssertTrue(store.jitSteps.allSatisfy { $0.state.isReady })
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
        nav.section = .mods; nav.mod = .project("iris"); nav.settingsPane = .jitJava; nav.instance = "survival"
        let restored = NavModel()
        restored.restore(from: nav.userActivity())
        XCTAssertEqual(restored.section, .mods)
        XCTAssertEqual(restored.mod, .project("iris"))
        XCTAssertEqual(restored.settingsPane, .jitJava)
        XCTAssertEqual(restored.instance, "survival")
    }

    /// Renders every section in compact, medium and expanded windows (the same panes in all three).
    func testEverySectionRendersAtEveryWidth() throws {
        let sizes: [(UIUserInterfaceSizeClass, CGSize)] = [(.compact, .init(width: 402, height: 874)),
                                                          (.regular, .init(width: 834, height: 1210)),
                                                          (.regular, .init(width: 1376, height: 1032))]
        for section in NavModel.Section.allCases {
            for (sizeClass, size) in sizes {
                let nav = NavModel(); nav.section = section
                let store = CofreStore(services: .mock())
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

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func lum(_ c: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
            c.getRed(&r, green: &g, blue: &bl, alpha: &al)
            func ch(_ v: CGFloat) -> Double { let v = Double(v); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(bl)
        }
        let (l1, l2) = (lum(a), lum(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
