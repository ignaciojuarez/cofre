import XCTest
@testable import CofreKit

final class ModrinthTests: XCTestCase {
    /// Modrinth sends "" for a missing icon; one such hit used to fail the whole search.
    func testSearchHitWithEmptyIconDecodes() throws {
        let json = #"[{"project_id":"a","slug":"badoptimizations","title":"BadOptimizations","description":"d","project_type":"mod","categories":["fabric"],"downloads":1,"icon_url":""},{"project_id":"b","slug":"sodium","title":"Sodium","description":"d","project_type":"mod","categories":[],"downloads":2,"icon_url":"https://cdn.modrinth.com/i.png"}]"#
        let hits = try JSONDecoder().decode([Modrinth.SearchResult].self, from: Data(json.utf8))
        XCTAssertNil(hits[0].iconURL)
        XCTAssertEqual(hits[1].iconURL?.absoluteString, "https://cdn.modrinth.com/i.png")
        XCTAssertEqual(hits[0].pageURL?.absoluteString, "https://modrinth.com/mod/badoptimizations")
    }
}
