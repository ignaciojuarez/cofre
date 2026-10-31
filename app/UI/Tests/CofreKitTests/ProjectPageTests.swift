import XCTest

@testable import CofreKit

final class ProjectPageTests: XCTestCase {
    func testSodiumDecodesBodyGalleryLinksAndLicense() throws {
        let page = try page("sodium")
        XCTAssertEqual(page.id, "AANobbMI")
        XCTAssertEqual(page.source, .modrinth)
        XCTAssertEqual(page.title, "Sodium")
        XCTAssertNotNil(page.iconURL)
        guard case .markdown(let body)? = page.body else { return XCTFail("Modrinth bodies are Markdown") }
        XCTAssertFalse(body.isEmpty)
        // Ordering only (nothing featured): 0, 1, 10, 30, 999, 1000.
        XCTAssertEqual(page.gallery.count, 6)
        XCTAssertEqual(page.gallery.first?.title, "Underwater Lighting Improvements")
        XCTAssertEqual(page.gallery.last?.title, "Sodium 0.4.1")
        XCTAssertTrue(page.gallery[0].thumb.lastPathComponent.hasSuffix("_350.webp"))
        XCTAssertFalse(page.gallery[0].full.lastPathComponent.hasSuffix("_350.webp"), "raw_url is the full image")
        XCTAssertEqual(page.links.map(\.kind), [.source, .issues, .wiki, .discord, .donate("Ko-fi")])
        XCTAssertEqual(page.links.first?.url.absoluteString, "https://github.com/CaffeineMC/sodium")
        // A custom license has no name, only "LicenseRef-Polyform-Shield-1.0.0".
        XCTAssertEqual(page.license, "Polyform Shield 1.0.0")
        XCTAssertTrue(page.videos.isEmpty)
    }

    func testCreateHasAnEmptyGalleryAndTwoDonations() throws {
        let page = try page("create")
        XCTAssertTrue(page.gallery.isEmpty)
        XCTAssertEqual(
            page.links.map(\.kind), [.source, .issues, .wiki, .discord, .donate("Patreon"), .donate("Paypal")])
        XCTAssertEqual(page.license, "Create Mod License")
        guard case .markdown(let body)? = page.body else { return XCTFail("Missing body") }
        XCTAssertTrue(body.contains("youtube.com/embed/rR8W-f9YhYA"), "Step 2 extracts this video from the body")
    }

    func testIrisPutsTheFeaturedShotFirstAndSkipsMissingLinks() throws {
        let page = try page("iris")
        // All four share ordering 0; the featured one moves up and the rest keep Modrinth's order.
        XCTAssertEqual(
            page.gallery.map(\.title),
            ["Grand Teton National Park", "A nice sunset", "Wide Mountain", "Crying Obsidian Sky"])
        XCTAssertEqual(page.gallery.map(\.featured), [true, false, false, false])
        // No wiki.
        XCTAssertEqual(page.links.map(\.kind), [.source, .issues, .discord, .donate("Other"), .donate("Patreon")])
        XCTAssertEqual(page.license, "GNU Lesser General Public License v3.0 only")
    }

    func testEmptyIconBodyAndGalleryFallBack() throws {
        let json = #"""
            {"id":"x","title":"X","description":"d","body":"","icon_url":"","license":{"id":"MIT","name":""},
             "source_url":null,"issues_url":"","wiki_url":"javascript:alert(1)","discord_url":null,"donation_urls":[],
             "gallery":[{"url":"https://cdn.modrinth.com/b.webp","featured":false,"ordering":5},
                        {"url":"https://cdn.modrinth.com/a.webp","raw_url":"https://cdn.modrinth.com/a.png","featured":false,"title":"","ordering":-1}]}
            """#
        let page = ProjectPage(modrinth: try JSONDecoder().decode(Modrinth.ProjectDetail.self, from: Data(json.utf8)))
        XCTAssertNil(page.iconURL)
        XCTAssertNil(page.body)
        XCTAssertTrue(page.links.isEmpty, "Empty, null and non-web links are dropped")
        XCTAssertEqual(page.license, "MIT")
        XCTAssertEqual(page.gallery.map(\.thumb.lastPathComponent), ["a.webp", "b.webp"])
        XCTAssertEqual(page.gallery[0].full.lastPathComponent, "a.png")
        XCTAssertNil(page.gallery[0].title)
        // No raw_url: the thumbnail is the full image.
        XCTAssertEqual(page.gallery[1].full, page.gallery[1].thumb)
    }

    func testVideoAcceptsOnlyYouTubeIDs() {
        let video = ProjectPage.Video(youTubeID: "rR8W-f9YhYA")
        XCTAssertEqual(video?.watch.absoluteString, "https://www.youtube.com/watch?v=rR8W-f9YhYA")
        XCTAssertEqual(video?.thumb.absoluteString, "https://img.youtube.com/vi/rR8W-f9YhYA/hqdefault.jpg")
        XCTAssertNil(ProjectPage.Video(youTubeID: "a/../b?x=1"))
        XCTAssertNil(ProjectPage.Video(youTubeID: ""))
    }

    func testFullVersionListSkipsChangelogs() {
        let full = URLComponents(
            url: Modrinth.versionsURL(projectID: "sodium", includeChangelog: false), resolvingAgainstBaseURL: false)
        XCTAssertEqual(full?.queryItems, [URLQueryItem(name: "include_changelog", value: "false")])
        let filtered = URLComponents(
            url: Modrinth.versionsURL(projectID: "sodium", gameVersions: ["1.21.1"]), resolvingAgainstBaseURL: false)
        XCTAssertFalse(filtered?.queryItems?.contains { $0.name == "include_changelog" } ?? false)
    }

    func testVersionChangelogDecodesWhenPresent() throws {
        let json =
            #"[{"id":"a","project_id":"p","name":"1","version_number":"1","game_versions":[],"loaders":[],"version_type":"release","dependencies":[],"files":[],"changelog":"- Fixed"},{"id":"b","project_id":"p","name":"2","version_number":"2","game_versions":[],"loaders":[],"version_type":"release","dependencies":[],"files":[]}]"#
        let versions = try JSONDecoder().decode([Modrinth.Version].self, from: Data(json.utf8))
        XCTAssertEqual(versions.map(\.changelog), ["- Fixed", nil])
    }

    private func page(_ slug: String) throws -> ProjectPage {
        let url = Bundle.module.url(
            forResource: "modrinth-project-\(slug)", withExtension: "json", subdirectory: "Fixtures")!
        return ProjectPage(modrinth: try JSONDecoder().decode(Modrinth.ProjectDetail.self, from: Data(contentsOf: url)))
    }
}
