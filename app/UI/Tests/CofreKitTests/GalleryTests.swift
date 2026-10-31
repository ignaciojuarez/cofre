import XCTest

@testable import CofreKit

final class GalleryTests: XCTestCase {
    func testIrisShowsVideosFirstThenFeaturedImage() throws {
        var page = try iris()
        page.videos = [ProjectPage.Video(youTubeID: "rR8W-f9YhYA")!]
        let gallery = Gallery(page)
        XCTAssertEqual(gallery.count, 5)
        XCTAssertFalse(gallery.isEmpty)
        XCTAssertEqual(gallery.items.first?.id, "video:rR8W-f9YhYA")
        guard case .image(let first, let index) = gallery.items[1] else { return XCTFail("Images follow videos") }
        XCTAssertEqual(first.title, "Grand Teton National Park")
        XCTAssertEqual(index, 0, "Image cells open the viewer at their place among images, not among items")
        XCTAssertEqual(gallery.images.map(\.title), page.gallery.map(\.title))
    }

    func testCounterAndSpokenLabel() throws {
        let gallery = Gallery(try iris())
        XCTAssertEqual(gallery.counter(1), "2 / 4")
        XCTAssertEqual(gallery.spokenLabel(1), "A nice sunset, Complementary Shaders 4.4 dev5, image 2 of 4")
        // Out-of-range indexes land on the nearest page.
        XCTAssertEqual(gallery.counter(9), "4 / 4")
        XCTAssertEqual(gallery.counter(-3), "1 / 4")
    }

    func testSpokenLabelSkipsMissingTitleAndCaption() {
        let url = URL(string: "https://cdn.modrinth.com/a.webp")!
        let gallery = Gallery(
            images: [.init(id: "a", thumb: url), .init(id: "b", thumb: url, caption: "Night")], videos: [])
        XCTAssertEqual(gallery.spokenLabel(0), "image 1 of 2")
        XCTAssertEqual(gallery.spokenLabel(1), "Night, image 2 of 2")
    }

    func testEmptyGalleryIsHiddenAndDuplicatesShowOnce() {
        let empty = Gallery(images: [], videos: [])
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.clamped(3), 0)
        let video = ProjectPage.Video(youTubeID: "rR8W-f9YhYA")!
        let url = URL(string: "https://cdn.modrinth.com/a.webp")!
        let image = ProjectPage.Image(id: "a", thumb: url)
        let gallery = Gallery(images: [image, image], videos: [video, video])
        XCTAssertEqual(gallery.items.map(\.id), ["video:rR8W-f9YhYA", "image:a"])
        XCTAssertFalse(Gallery(images: [], videos: [video]).isEmpty, "Videos alone keep the tab")
    }

    func testFullImagesLoadOnlyNearTheCurrentPage() {
        XCTAssertEqual((0..<5).filter { Gallery.loadsFull($0, current: 2) }, [1, 2, 3])
        XCTAssertEqual(Gallery.openLog(id: "YL57xq9U", index: 2), "[Cofre] gallery open id=YL57xq9U index=2")
    }

    private func iris() throws -> ProjectPage {
        let url = Bundle.module.url(
            forResource: "modrinth-project-iris", withExtension: "json", subdirectory: "Fixtures")!
        return ProjectPage(modrinth: try JSONDecoder().decode(Modrinth.ProjectDetail.self, from: Data(contentsOf: url)))
    }
}
