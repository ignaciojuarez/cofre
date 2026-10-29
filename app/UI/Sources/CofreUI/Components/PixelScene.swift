import SwiftUI

// §2 #18 PixelScene: Cofre's seeded moonlit lake (art in PixelSceneArt.swift). Rendered once per seed and size, then
// cached.

public struct PixelScene: View {
    let seed: UInt32, pixels: CGSize
    public init(seed: UInt32, pixels: CGSize = .init(width: 120, height: 80)) {
        self.seed = seed
        self.pixels = pixels
    }

    public var body: some View {
        // Takes the offered size and fills it, cropped. A bare `.fill` image reports its overflowing size, which
        // widened whole columns past the screen (the iPhone launch screen was clipped on both sides).
        Color.clear.overlay {
            if let img = SceneRenderer.image(seed: seed, w: Int(pixels.width), h: Int(pixels.height)) {
                Image(decorative: img, scale: 1).interpolation(.none).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .clipped()
        .accessibilityIgnoresInvertColors()
        .accessibilityHidden(true)
    }
}

enum SceneRenderer {
    private static let cache = NSCache<NSString, CGImage>()

    static func image(seed: UInt32, w: Int, h: Int) -> CGImage? {
        guard w > 0, h > 0 else { return nil }
        let key = "\(seed)-\(w)x\(h)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let px = SceneArt.render(seed: seed, w: w, h: h)
        var rgba = px.flatMap { c -> [UInt8] in [UInt8((c >> 16) & 0xff), UInt8((c >> 8) & 0xff), UInt8(c & 0xff), 255]
        }
        guard
            let image: CGImage = rgba.withUnsafeMutableBytes({ buf in
                let ctx = CGContext(
                    data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                return ctx?.makeImage()
            })
        else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
