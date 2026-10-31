import Foundation

/// What a page's Gallery tab shows: video cards first, then the images in the page's order (featured first). The
/// viewer pages over `images` only; videos always open in YouTube.
public struct Gallery: Sendable, Hashable {
    public enum Item: Sendable, Hashable, Identifiable {
        case video(ProjectPage.Video)
        /// `index` is the image's place in `images`, where the viewer opens.
        case image(ProjectPage.Image, index: Int)
        public var id: String {
            switch self {
            case .video(let video): "video:\(video.id)"
            case .image(let image, _): "image:\(image.id)"
            }
        }
    }

    public let items: [Item]
    public let images: [ProjectPage.Image]
    public let videos: [ProjectPage.Video]

    public init(_ page: ProjectPage) {
        self.init(images: page.gallery, videos: page.videos)
    }

    /// A body can embed the same video twice, and a provider can repeat a shot; each shows once.
    public init(images: [ProjectPage.Image], videos: [ProjectPage.Video]) {
        var seenVideos = Set<String>()
        var seenImages = Set<String>()
        self.videos = videos.filter { seenVideos.insert($0.id).inserted }
        self.images = images.filter { seenImages.insert($0.id).inserted }
        items = self.videos.map(Item.video) + self.images.enumerated().map { Item.image($1, index: $0) }
    }

    /// The tab is hidden when this is true.
    public var isEmpty: Bool { items.isEmpty }
    /// The number in the tab's label ("Gallery 4").
    public var count: Int { items.count }

    /// A safe page for the viewer, whatever index it was asked for.
    public func clamped(_ index: Int) -> Int { images.isEmpty ? 0 : min(max(index, 0), images.count - 1) }

    /// "2 / 4" under the image.
    public func counter(_ index: Int) -> String { "\(clamped(index) + 1) / \(images.count)" }

    /// What VoiceOver reads for a page: "title, caption, image 2 of 4". Missing parts are skipped.
    public func spokenLabel(_ index: Int) -> String {
        let i = clamped(index)
        let image = images.indices.contains(i) ? images[i] : nil
        return [image?.title, image?.caption, "image \(i + 1) of \(images.count)"].compactMap { $0 }
            .joined(separator: ", ")
    }

    /// The viewer loads the full image only for the page on screen and its neighbours.
    public static func loadsFull(_ index: Int, current: Int) -> Bool { abs(index - current) <= 1 }

    /// Device log marker for opening the viewer.
    public static func openLog(id: String, index: Int) -> String { "[Cofre] gallery open id=\(id) index=\(index)" }
}
