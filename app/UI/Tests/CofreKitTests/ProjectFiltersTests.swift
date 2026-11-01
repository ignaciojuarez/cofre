import XCTest

@testable import CofreKit

final class ProjectFiltersTests: XCTestCase {

    // Defaults follow the instance: a Fabric 1.21.1 instance starts Mods at version and loader. Server-side mods
    // (Terralith, Dungeons and Taverns) stay visible: single-player runs them.
    func testModsDefaultToTheInstance() {
        let f = ProjectFilters()
        XCTAssertEqual(
            f.facets(.mods, game: "1.21.1", loader: .fabric),
            [["versions:1.21.1"], ["categories:fabric"]])
        XCTAssertEqual(f.activeCount(.mods, source: .modrinth, game: "1.21.1", loader: .fabric), 2)
        // Packs filter the same way; resource packs only by version.
        XCTAssertEqual(f.activeCount(.modpacks, source: .modrinth, game: "1.21.1", loader: .fabric), 2)
        XCTAssertEqual(f.facets(.resourcePacks, game: "1.21.1", loader: .fabric), [["versions:1.21.1"]])
    }

    func testNoInstanceOrVanillaFallsBackToAny() {
        let f = ProjectFilters()
        XCTAssertEqual(f.facets(.mods, game: "", loader: .unknown), [])
        XCTAssertNil(f.loader(.mods, .vanilla))
        XCTAssertEqual(f.activeCount(.mods, source: .curseforge, game: "", loader: .unknown), 0)
    }

    func testShadersDefaultToIrisWhereItRuns() {
        let f = ProjectFilters()
        for loader in [Instance.Loader.fabric, .quilt, .neoforge] {
            XCTAssertEqual(
                f.facets(.shaders, game: "1.21.1", loader: loader), [["versions:1.21.1"], ["categories:iris"]])
        }
        XCTAssertEqual(f.facets(.shaders, game: "1.21.1", loader: .forge), [["versions:1.21.1"]])
        var any = f
        any.shaderLoader = .any
        XCTAssertEqual(any.facets(.shaders, game: "1.21.1", loader: .fabric), [["versions:1.21.1"]])
    }

    // Each category counts once, resolution once; sort never. CurseForge counts only version and loader.
    func testActiveCountRules() {
        var f = ProjectFilters.cleared
        XCTAssertEqual(f.activeCount(.mods, source: .modrinth, game: "1.21.1", loader: .fabric), 0)
        f.categories = ["magic", "technology", "not-a-category"]
        f.sort = .downloads
        XCTAssertEqual(
            f.facets(.mods, game: "1.21.1", loader: .fabric), [["categories:magic"], ["categories:technology"]])
        XCTAssertEqual(f.activeCount(.mods, source: .modrinth, game: "1.21.1", loader: .fabric), 2)
        XCTAssertEqual(f.activeCount(.mods, source: .curseforge, game: "1.21.1", loader: .fabric), 0)

        var packs = ProjectFilters()
        packs.resolution = .x128
        XCTAssertEqual(
            packs.facets(.resourcePacks, game: "1.21.1", loader: .fabric),
            [["versions:1.21.1"], ["categories:128x", "categories:256x", "categories:512x+"]])
        XCTAssertEqual(packs.activeCount(.resourcePacks, source: .modrinth, game: "1.21.1", loader: .fabric), 2)
        XCTAssertEqual(ProjectFilters().activeCount(.mods, source: .curseforge, game: "1.21.1", loader: .fabric), 2)
    }

    // A new instance: version and loader follow it again; categories, resolution and sort stay.
    func testFollowInstanceKeepsTasteFilters() {
        var f = ProjectFilters.cleared
        f.categories = ["magic"]
        f.resolution = .x32
        f.sort = .newest
        f.followInstance()
        XCTAssertEqual(f.version, .instance)
        XCTAssertEqual(f.loader, .instance)
        XCTAssertNil(f.shaderLoader)
        XCTAssertEqual(f.categories, ["magic"])
        XCTAssertEqual(f.resolution, .x32)
        XCTAssertEqual(f.sort, .newest)
    }

    func testCategoryLabels() {
        XCTAssertTrue(ProjectFilters.categories(for: .dataPacks).isEmpty)
        let labels = ProjectFilters.categories(for: .resourcePacks).map(\.label)
        XCTAssertTrue(labels.contains("GUI"))
        XCTAssertTrue(labels.contains("Vanilla-like"))
    }
}
