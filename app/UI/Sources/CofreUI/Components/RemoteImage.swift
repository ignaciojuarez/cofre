#if canImport(UIKit)
    import ImageIO
    import SwiftUI
    import UIKit

    /// Remote images, downloaded once and decoded off the main thread at the size they're shown. `AsyncImage` keeps no
    /// memory cache and decodes full-size images on the main thread, so every icon scrolled back into the mod list
    /// was fetched and decoded again, which made scrolling choppy.
    @MainActor final class ImagePipeline {
        static let shared = ImagePipeline()
        private let cache = NSCache<NSString, UIImage>()
        private var running: [NSString: Task<UIImage?, Never>] = [:]
        private let session: URLSession = {
            let config = URLSessionConfiguration.default
            config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20)
            config.requestCachePolicy = .returnCacheDataElseLoad
            return URLSession(configuration: config)
        }()

        private init() { cache.totalCostLimit = 96 << 20 }

        func cached(_ url: URL, maxPixels: Int) -> UIImage? { cache.object(forKey: key(url, maxPixels)) }

        func image(_ url: URL, maxPixels: Int) async -> UIImage? {
            let key = key(url, maxPixels)
            if let hit = cache.object(forKey: key) { return hit }
            // Rows that show the same icon share one download.
            if let task = running[key] { return await task.value }
            let session = session
            let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let (data, _) = try? await session.data(from: url) else { return nil }
                return Self.decode(data, maxPixels: maxPixels)
            }
            running[key] = task
            let image = await task.value
            running[key] = nil
            if let image, let cg = image.cgImage {
                cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
            }
            return image
        }

        /// Decoded now, never larger than `maxPixels` on its long side; smaller images keep their size.
        nonisolated static func decode(_ data: Data, maxPixels: Int) -> UIImage? {
            guard
                let source = CGImageSourceCreateWithData(
                    data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        }

        private func key(_ url: URL, _ maxPixels: Int) -> NSString { "\(maxPixels) \(url.absoluteString)" as NSString }
    }

    /// A remote image, or `placeholder` until it arrives. `maxPoints` is the largest side it's drawn at.
    struct RemoteImage<Placeholder: View>: View {
        let url: URL
        let maxPoints: CGFloat
        var contentMode: ContentMode = .fit
        /// Pixel art (mod icons) stays sharp when it's drawn larger than it is.
        var pixelated = false
        @ViewBuilder var placeholder: () -> Placeholder
        @Environment(\.displayScale) private var scale
        @State private var loaded: (url: URL, image: UIImage)?

        var body: some View {
            let maxPixels = Int((maxPoints * scale).rounded(.up))
            Group {
                if let image = loaded?.url == url
                    ? loaded?.image : ImagePipeline.shared.cached(url, maxPixels: maxPixels)
                {
                    Image(uiImage: image).interpolation(pixelated ? .none : .high).resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder()
                }
            }
            .task(id: url) {
                if let image = await ImagePipeline.shared.image(url, maxPixels: maxPixels) { loaded = (url, image) }
            }
        }
    }
#endif
