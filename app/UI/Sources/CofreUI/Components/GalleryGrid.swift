#if canImport(UIKit)
    import SwiftUI
    import CofreKit

    // A page's Gallery tab (rich mod pages §3): 2 columns on iPhone, 3–4 on iPad. Video cards come first and open in
    // YouTube (never inline); an image opens the full-screen viewer at that image. Hide the tab when
    // `Gallery(page).isEmpty`.

    public struct GalleryGrid: View {
        let projectID: String, gallery: Gallery
        @State private var opening: Opening?
        @Environment(\.widthClass) private var width
        @Environment(\.openURL) private var openURL

        public init(page: ProjectPage) {
            projectID = page.id
            gallery = Gallery(page)
        }

        public var body: some View {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                ForEach(gallery.items) { item in
                    switch item {
                    case .video(let video):
                        Button {
                            openURL(video.watch)
                        } label: {
                            cell(video.thumb, video: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: videoLabel(video)))
                        .accessibilityHint("Opens in YouTube")
                    case .image(let image, let index):
                        Button {
                            opening = Opening(index: index)
                        } label: {
                            cell(image.thumb, video: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: gallery.spokenLabel(index)))
                        .accessibilityHint("Opens full screen")
                    }
                }
            }
            .fullScreenTakeover(item: $opening) {
                GalleryViewer(projectID: projectID, gallery: gallery, start: $0.index)
            }
        }

        private var columns: Int {
            switch width {
            case .compact: 2
            case .medium: 3
            case .expanded: 4
            }
        }

        private func cell(_ thumb: URL, video: Bool) -> some View {
            Color.cofre.well
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { GalleryImage(thumb: thumb, contentMode: .fill) }
                .clipped()
                .overlay {
                    if video {
                        PixelIcon(.play, size: 18)
                            .foregroundStyle(Color.cofre.onFace)
                            .frame(width: 44, height: 36)
                            .block(.primary)
                    }
                }
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                .contentShape(Rectangle())
        }

        private func videoLabel(_ video: ProjectPage.Video) -> String {
            let n = (gallery.videos.firstIndex(of: video) ?? 0) + 1
            return gallery.videos.count > 1 ? "Video \(n) of \(gallery.videos.count)" : "Video"
        }

        struct Opening: Identifiable {
            let index: Int
            var id: Int { index }
        }
    }

    /// The one place gallery pictures load: the thumbnail at once, the full image on top when there is one. Step 6
    /// swaps `AsyncImage` for the shared cached image session here.
    struct GalleryImage: View {
        let thumb: URL
        var full: URL?
        var contentMode: ContentMode = .fit

        var body: some View {
            ZStack {
                remote(thumb)
                if let full, full != thumb { remote(full) }
            }
        }

        private func remote(_ url: URL) -> some View {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: contentMode)
                } else {
                    Color.clear
                }
            }
        }
    }

    #if DEBUG
        extension ProjectPage {
            /// Iris's real gallery (featured first) plus one video, for previews.
            static let galleryPreview: ProjectPage = {
                let base = "https://cdn.modrinth.com/data/YL57xq9U/images/"
                let shots: [(String, String, String, String, Bool)] = [
                    (
                        "f47cea26f135d74c2d69df0a1806751818d705d3", "f47cea26f135d74c2d69df0a1806751818d705d3",
                        "Grand Teton National Park", "Taken by IMS, Continuum 2.0 Redux", true
                    ),
                    (
                        "17f09a3d424d6e2005fcecc81838780a6847f8ce", "d382106b9a2b943d06107c31c139c77849f1a0e8",
                        "A nice sunset", "Complementary Shaders 4.4 dev5", false
                    ),
                    (
                        "44245979cecbf237a3b26f375a0dc4f3a21dcf3d", "2fbd04f5d123577696e29b28bb7981a2bc95a0c8",
                        "Wide Mountain", "woodiertexas - Complementary Shaders", false
                    ),
                    (
                        "d69f13ea9889652c02f8cf91a3e55c8ef7cd6316", "1c3d0dfbedf31dbee4e30e20c5329e5db9a881ae",
                        "Crying Obsidian Sky", "Complementary Shaders 4.4 dev3", false
                    ),
                ]
                let gallery = shots.map { thumb, full, title, caption, featured in
                    Image(
                        id: thumb, thumb: URL(string: base + thumb + "_350.webp")!,
                        full: URL(string: base + full + ".png"), title: title, caption: caption, featured: featured)
                }
                return ProjectPage(
                    id: "YL57xq9U", source: .modrinth, title: "Iris Shaders", gallery: gallery,
                    videos: [Video(youTubeID: "rR8W-f9YhYA")!])
            }()
        }

        #Preview("Gallery · Iris") {
            ScrollView { GalleryGrid(page: .galleryPreview).padding(16) }
                .background(Color.cofre.page)
        }
    #endif
#endif
