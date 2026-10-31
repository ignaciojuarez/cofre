import XCTest

@testable import CofreKit

final class PageLinkPolicyTests: XCTestCase {
    func testOnlyTheAppsOwnLoadStaysInside() {
        let blank = URL(string: "about:blank")!
        XCTAssertEqual(PageLinkPolicy.decide(blank, initialLoad: true), .allow)
        XCTAssertEqual(PageLinkPolicy.decide(blank, initialLoad: false), .cancel, "A later about:blank is a navigation")
        XCTAssertEqual(PageLinkPolicy.decide(nil, initialLoad: true), .cancel)
    }

    func testWebLinksOpenOutside() {
        for text in ["https://github.com/CaffeineMC/sodium", "http://example.com/a?b=1", "HTTPS://Example.com"] {
            let url = URL(string: text)!
            XCTAssertEqual(PageLinkPolicy.decide(url, initialLoad: false), .openOutside(url), text)
            // Even during the first load a web URL never replaces the document.
            XCTAssertEqual(PageLinkPolicy.decide(url, initialLoad: true), .openOutside(url), text)
        }
    }

    func testEveryOtherSchemeIsDropped() {
        for text in [
            "javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,<script>alert(1)</script>",
            "file:///etc/passwd", "mailto:a@b.c", "tel:123", "cofre://open", "itms-services://?action=download",
            "blob:https://a.com/x", "about:srcdoc", "https:///nohost",
        ] {
            XCTAssertEqual(PageLinkPolicy.decide(URL(string: text), initialLoad: false), .cancel, text)
        }
    }
}
