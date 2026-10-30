import XCTest
@testable import CofreKit

final class BreadcrumbsTests: XCTestCase {
    func testActionLineHasStablePrefix() {
        XCTAssertEqual(CofreBreadcrumb.line(action: "play", details: "instance=Vanilla"), "[Cofre] action play instance=Vanilla")
        XCTAssertEqual(CofreBreadcrumb.line(action: "delete"), "[Cofre] action delete")
    }
    func testOptionsDiffReportsChangedAndAddedValues() {
        let before = "graphicsPreset: fast\nlang: en_us\n"
        let after = "graphicsPreset: fancy\nlang: en_us\nrenderDistance: 12\n"
        XCTAssertEqual(OptionsDiff.changes(before: before, after: after), ["[Cofre] options changed graphicsPreset: fast → fancy", "[Cofre] options changed renderDistance: <unset> → 12"])
    }
}
