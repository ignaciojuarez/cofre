import XCTest
@testable import CofreKit

final class ModrinthTests: XCTestCase {
    func testVersionsURLEncodesArrayFilters() {
        let url = Modrinth.versionsURL(projectID: "sodium", loaders: ["fabric", "quilt"], gameVersions: ["1.21.1"])
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.path, "/v2/project/sodium/version")
        XCTAssertEqual(components?.queryItems?.count, 2)
        XCTAssertEqual(components?.queryItems?[0].name, "loaders")
        XCTAssertEqual(components?.queryItems?[0].value, "[\"fabric\",\"quilt\"]")
        XCTAssertEqual(components?.queryItems?[1].name, "game_versions")
        XCTAssertEqual(components?.queryItems?[1].value, "[\"1.21.1\"]")
    }

    func testVersionFixtureDecodesFilesAndDependencies() throws {
        let versions = try JSONDecoder().decode([Modrinth.Version].self, from: fixture("modrinth-versions"))
        XCTAssertEqual(versions.map(\.id), ["v-new", "v-match", "v-old"])
        XCTAssertEqual(versions[1].gameVersions, ["1.21.1"])
        XCTAssertEqual(versions[1].files.first?.url?.absoluteString, "https://cdn.modrinth.com/match.jar")
        XCTAssertEqual(versions[1].files.first?.size, 100)
    }

    func testMatchingVersionsStayFirstWhenFullCatalogArrives() throws {
        let all = try JSONDecoder().decode([Modrinth.Version].self, from: fixture("modrinth-versions"))
        let matching = [all[1]]
        let merged = Modrinth.mergeVersions(matching: matching, all: all)
        XCTAssertEqual(merged.map(\.id), ["v-match", "v-new", "v-old"])
        XCTAssertEqual(Modrinth.mergeVersions(matching: matching, all: [all[1]]).count, 1)
    }

    func testSearchFixtureStillAllowsMissingIcons() throws {
        let hits = try JSONDecoder().decode([Modrinth.SearchResult].self, from: fixture("modrinth-search"))
        XCTAssertNil(hits[0].iconURL)
        XCTAssertEqual(hits[1].versions, ["1.21.1"])
        XCTAssertEqual(hits[1].pageURL?.absoluteString, "https://modrinth.com/mod/with-icon")
    }

    /// The mod page's "Updated" comes from the hit; Modrinth sends microseconds and a +00:00 offset.
    func testSearchHitCarriesItsUpdateDate() throws {
        let json = #"[{"project_id":"a","title":"A","description":"d","project_type":"mod","categories":[],"downloads":1,"date_modified":"2026-10-27T17:15:43.902761+00:00"},{"project_id":"b","title":"B","description":"d","project_type":"mod","categories":[],"downloads":1}]"#
        let hits = try JSONDecoder().decode([Modrinth.SearchResult].self, from: Data(json.utf8))
        XCTAssertEqual(hits[0].updated?.timeIntervalSince1970 ?? 0, 1_793_121_343.902, accuracy: 0.01)
        XCTAssertNil(hits[1].updated)
    }

    /// Modrinth sends "" for a missing icon; one such hit used to fail the whole search.
    func testSearchHitWithEmptyIconDecodes() throws {
        let json = #"[{"project_id":"a","slug":"badoptimizations","title":"BadOptimizations","description":"d","project_type":"mod","categories":["fabric"],"downloads":1,"icon_url":""},{"project_id":"b","slug":"sodium","title":"Sodium","description":"d","project_type":"mod","categories":[],"downloads":2,"icon_url":"https://cdn.modrinth.com/i.png"}]"#
        let hits = try JSONDecoder().decode([Modrinth.SearchResult].self, from: Data(json.utf8))
        XCTAssertNil(hits[0].iconURL)
        XCTAssertEqual(hits[1].iconURL?.absoluteString, "https://cdn.modrinth.com/i.png")
        XCTAssertEqual(hits[0].pageURL?.absoluteString, "https://modrinth.com/mod/badoptimizations")
    }

    func testVersionByIDCarriesItsChangelog() async throws {
        let client = Modrinth(session: FixtureProtocol.session(["/v2/version/OihdIimA": fixture("modrinth-version")]))
        let version = try await client.version(id: "OihdIimA")
        XCTAssertEqual(version.projectID, "AANobbMI")
        XCTAssertEqual(version.versionNumber, "mc1.21.1-0.6.13-fabric")
        XCTAssertTrue(version.changelog?.hasPrefix("## Fixes") == true)
    }

    func testPageByIDAsksForTheProject() async throws {
        let client = Modrinth(
            session: FixtureProtocol.session(["/v2/project/AANobbMI": fixture("modrinth-project-sodium")]))
        let page = try await client.page(id: "AANobbMI")
        XCTAssertEqual(page.title, "Sodium")
        XCTAssertFalse(page.gallery.isEmpty)
    }

    private func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }
}

/// Serves fixture bodies by URL path, so the client's requests run without a network.
final class FixtureProtocol: URLProtocol {
    nonisolated(unsafe) static var bodies: [String: Data] = [:]
    static func session(_ bodies: [String: Data]) -> URLSession {
        Self.bodies.merge(bodies) { $1 }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: config)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.url.flatMap { Self.bodies[$0.path] }
        let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
