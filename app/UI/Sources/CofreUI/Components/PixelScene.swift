import SwiftUI

// §2 #18 PixelScene: seeded dusk scene (same generator as the mockups). Rendered once per seed and size, then cached.

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
    private static let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

    static func image(seed: UInt32, w: Int, h: Int) -> CGImage? {
        let key = "\(seed)-\(w)x\(h)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        var px = [UInt32](repeating: 0, count: w * h)
        func set(_ x: Int, _ y: Int, _ c: UInt32) { if x >= 0, x < w, y >= 0, y < h { px[y * w + x] = c } }
        var r = Mulberry32(seed: seed)
        let sky = PixelArtColors.sky
        let hz = Int((Double(h) * 0.66).rounded())

        for y in 0..<hz {
            let t = pow(Double(y) / Double(hz), 1.35) * Double(sky.count - 1)
            let i = Int(t)
            let f = t - Double(i)
            for x in 0..<w { set(x, y, f * 16 > bayer[y & 3][x & 3] ? sky[min(i + 1, sky.count - 1)] : sky[i]) }
        }
        for _ in 0..<(w * h / 90) {
            let sx = Int(r.next() * Double(w))
            let sy = Int(r.next() * Double(hz) * 0.55)
            set(sx, sy, r.next() > 0.7 ? PixelArtColors.starBright : PixelArtColors.starDim)
        }
        let sunX = Int((Double(w) * (0.55 + r.next() * 0.25)).rounded())
        let sunY = hz - Int((Double(h) * 0.05).rounded())
        let sr = Int((Double(h) * 0.13).rounded())
        if sr > 0 {
            for yy in -sr...sr {
                for xx in -sr...sr {
                    let d = Double(xx * xx + yy * yy)
                    if d <= Double(sr * sr) {
                        set(
                            sunX + xx, sunY + yy,
                            d < pow(Double(sr) * 0.55, 2) ? PixelArtColors.sunCore : PixelArtColors.sunRim)
                    }
                }
            }
        }
        for _ in 0..<3 {
            let cw = 8 + Int(r.next() * 14)
            let cx = Int(r.next() * Double(w))
            let cy = 4 + Int(r.next() * Double(hz) * 0.45)
            for k in 0..<cw { set(cx + k, cy, PixelArtColors.cloud) }
            for k in 0..<max(0, cw - 5) { set(cx + 2 + k, cy - 1, PixelArtColors.cloudTop) }
        }
        func layer(_ base: Int, _ amp: Int, _ step: Int, _ col: (UInt32, UInt32)) -> [Int] {
            var hgt = base
            var hs: [Int] = []
            var x = 0
            while x < w {
                hgt += Int(((r.next() - 0.5) * Double(amp)).rounded())
                hgt = max(base - amp * 2, min(base + amp, hgt))
                for _ in 0..<step { hs.append(hgt) }
                x += step
            }
            for x in 0..<w {
                for y in max(0, hs[x])..<h { set(x, y, col.0) }
                set(x, hs[x], col.1)
            }
            return hs
        }
        _ = layer(hz - Int((Double(h) * 0.16).rounded()), 5, 4, PixelArtColors.hillFar)
        _ = layer(hz - Int((Double(h) * 0.04).rounded()), 3, 3, PixelArtColors.hillMid)
        let g = layer(hz + Int((Double(h) * 0.1).rounded()), 2, 5, PixelArtColors.ground)
        for _ in 0..<Int((Double(w) / 14).rounded()) {
            let tx = Int(r.next() * Double(w - 6)) + 3
            let ty = g[tx]
            let c = PixelArtColors.tree
            for k in 1...3 { set(tx, ty - k, c) }
            for yy in (ty - 7)..<(ty - 3) { for xx in (tx - 2)...(tx + 2) { set(xx, yy, c) } }
            for xx in (tx - 1)...(tx + 1) { set(xx, ty - 8, c) }
        }

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
