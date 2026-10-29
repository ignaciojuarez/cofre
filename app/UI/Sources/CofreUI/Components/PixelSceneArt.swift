import Foundation

// PixelScene's moonlit lake. Pure pixel math: deterministic per seed, no SwiftUI, one pixel = one art pixel.
// The top stays dark for white titles, the moon sits near the middle so narrow crops keep it, and the shore sits
// near 0.86 of the height for sprites (Llave).

enum SceneArt {
    /// A square moon over a cube-tree forest, mirrored in a still lake; a cabin window glows gold.
    static func render(seed: UInt32, w: Int, h: Int) -> [UInt32] {
        typealias P = PixelArtColors.Lake
        var c = SceneCanvas(w: w, h: h, seed: seed)
        var r = Mulberry32(seed: seed)
        let horizon = c.ph(0.6), shore = c.ph(0.86)
        c.gradient(0..<horizon, P.sky, curve: 1.2)
        c.stars(&r, rows: 0..<c.ph(0.45), count: w * h / 110)

        // The moon sits just off center on a random side; the cabin takes the other side.
        let side = r.chance(0.5) ? 1 : -1
        let m = max(6, c.ph(0.16))
        let mx = w / 2 + side * r.int(w / 24...max(w / 24, w / 10)) - m / 2, my = c.ph(0.1 + r.next() * 0.05)
        let mcx = Double(mx) + Double(m) / 2, mcy = Double(my) + Double(m) / 2
        c.glow(cx: mcx, cy: mcy, radius: Double(m) * 1.5, P.halo, strength: 0.75)  // before the trees, behind them

        // Cube-tree forest in two rows, the near one rimmed on the side facing the moon.
        for row in 0..<2 {
            let colors = P.forest[row], ground = horizon - (row == 0 ? 2 : 0)
            c.fill(0, ground - 1, w, horizon - ground + 2, colors.0)
            var x = -r.int(0...4)
            while x < w {
                let s =
                    row == 0
                    ? r.int(max(3, c.ph(0.04))...max(3, c.ph(0.08))) : r.int(max(4, c.ph(0.06))...max(4, c.ph(0.12)))
                let trunk = r.int(1...max(2, s * 2 / 3)) + (row == 0 ? c.ph(0.04) : 0)
                // Oak-like: a wide canopy with a narrower step on top.
                let top = ground - trunk - s, cap = max(1, s / 3), rim = x + s / 2 < mx + m / 2 ? x + s - 1 : x
                c.fill(x + s / 2, ground - trunk, 1, trunk, colors.0)
                c.fill(x, top, s, s, colors.0)
                c.fill(x + 1, top - cap, s - 2, cap, colors.0)
                c.fill(x, top, s, 1, colors.1)
                c.fill(x + 1, top - cap, s - 2, 1, colors.1)
                c.fill(rim, top, 1, s * 2 / 3, colors.1)
                x += s + r.int(row == 0 ? 0...3 : 1...5)
            }
        }

        // Cabin with a lit window, its warm light spilling onto the trees around it.
        let cw = max(7, c.ph(0.12)), ch = max(5, c.ph(0.07)), base = horizon - 1
        let cabinX = w / 2 - side * r.int(w / 10...max(w / 10, w / 5)) - cw / 2
        let winW = cw >= 9 ? 3 : 2, winX = cabinX + (cw - winW) / 2, winY = base - ch + 1 + ch / 4
        c.glow(cx: Double(winX) + 1, cy: Double(winY) + 1, radius: Double(cw) * 1.2, P.glow, strength: 0.85)
        c.fill(cabinX, base - ch, cw, ch + 1, P.cabin.0)
        for k in 0..<(cw / 2 + 1) { c.fill(cabinX - 1 + k, base - ch - 1 - k, cw + 2 - 2 * k, 1, P.cabin.1) }
        c.fill(winX - 1, winY + 2, winW + 2, 1, P.glow.0)  // sill light
        c.fill(winX, winY, winW, 2, P.window.1)
        c.fill(winX, winY, winW - 1, 1, P.window.0)

        // Lake: the sky and forest mirrored, darkened with depth, broken by ripples.
        for y in horizon..<h {  // under the bank too, so its uneven edge never shows a gap
            let sy = horizon - 1 - (y - horizon) * 3 / 2
            let wobble = Int(c.hash(y, 7) % 3) - 1
            let depth = min(1, Double(y - horizon) / Double(max(1, shore - horizon)))
            for x in 0..<w { c.set(x, y, SceneCanvas.mix(c[x + wobble, max(0, sy)], P.water, 0.25 + 0.45 * depth)) }
            if c.hash(y, 3) % 3 == 0 {
                let rx = Int(c.hash(y, 5) % UInt32(w)), len = 3 + Int(c.hash(y, 9) % 8)
                for k in 0..<len { c.set(rx + k, y, P.ripple) }
            }
        }
        c.fill(0, horizon, w, 1, P.ripple)

        // The moon's face, drawn after the mirror so only its path shows in the water.
        c.fill(mx, my, m, m, P.moon.0)
        c.fill(mx + m - 1, my + 1, 1, m - 1, P.moon.1)
        c.fill(mx + 1, my + m - 1, m - 1, 1, P.moon.1)
        for _ in 0..<3 { c.fill(mx + r.int(1...max(1, m - 4)), my + r.int(1...max(1, m - 4)), 2, 2, P.moon.1) }

        // Moon path: broken bars that widen and dim toward the shore, bright at the core.
        for y in (horizon + 1)..<shore where c.hash(y, 17) % 4 != 0 && (y - horizon) % 2 == 1 {
            let t = Double(y - horizon) / Double(max(1, shore - horizon))
            let spread = Double(m) * (0.5 + 0.9 * t), jitter = Int(c.hash(y, 11) % 3) - 1
            let len = max(1, Int(spread * (0.45 + Double(c.hash(y, 13) % 6) * 0.11)))
            let x0 = Int(mcx) - len / 2 + jitter
            let edge = P.glint[min(3, 1 + Int(t * 3))]
            c.fill(x0, y, len, 1, edge)
            if len > 2 { c.fill(x0 + 1, y, len - 2, 1, P.glint[min(2, Int(t * 3))]) }
        }
        // Window light on the water.
        for y in stride(from: horizon + 2, to: min(shore, horizon + c.ph(0.18)), by: 2) where c.hash(y, 19) % 3 != 0 {
            let near = y - horizon < c.ph(0.08), jitter = Int(c.hash(y, 23) % 3) - 1
            c.fill(winX + jitter, y, near ? winW + 1 : winW, 1, near ? P.window.1 : P.glow.1)
        }

        // Shore with reeds and fireflies.
        let bank = c.plateaus(&r, base: shore, range: c.ph(0.03), widths: 5...14)
        for x in 0..<w { c.column(x, from: bank[x], to: h, P.shore.0, top: P.shore.1) }
        for _ in 0..<max(4, w / 10) {
            let x = r.int(0...w - 1), tall = r.int(2...max(3, c.ph(0.08)))
            for k in 1...tall { c.set(x, bank[x] - k, P.reed.0) }
            if r.chance(0.5) { c.fill(x, bank[x] - tall - 1, 1, 2, P.reed.1) }
        }
        for _ in 0..<max(3, w / 30) { c.set(r.int(0...w), r.int(c.ph(0.66)...c.ph(0.92)), P.window.1) }
        return c.px
    }
}

// MARK: - Canvas

struct SceneCanvas {
    let w: Int, h: Int, seed: UInt32
    var px: [UInt32]

    init(w: Int, h: Int, seed: UInt32) {
        self.w = w
        self.h = h
        self.seed = seed
        px = [UInt32](repeating: 0, count: w * h)
    }

    /// Reads clamp to the edge; writes outside are dropped.
    subscript(x: Int, y: Int) -> UInt32 { px[min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))] }

    mutating func set(_ x: Int, _ y: Int, _ c: UInt32) { if x >= 0, x < w, y >= 0, y < h { px[y * w + x] = c } }

    mutating func fill(_ x: Int, _ y: Int, _ fw: Int, _ fh: Int, _ c: UInt32) {
        let ys = max(0, y)..<max(max(0, y), min(h, y + fh)), xs = max(0, x)..<max(max(0, x), min(w, x + fw))
        for yy in ys { for xx in xs { px[yy * w + xx] = c } }
    }

    /// A fraction of the height, in pixels.
    func ph(_ f: Double) -> Int { Int((Double(h) * f).rounded()) }

    /// Stable per-seed noise for textures, so they don't consume the generator.
    func hash(_ a: Int, _ b: Int) -> UInt32 {
        var x = UInt32(truncatingIfNeeded: a) &* 0x9E37_79B1 ^ UInt32(truncatingIfNeeded: b) &* 0x85EB_CA77 ^ seed
        x ^= x >> 15
        x = x &* 0x2C1B_3C6D
        x ^= x >> 12
        return x
    }

    private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    /// Ordered dither: true for about `f` of the pixels.
    static func dither(_ x: Int, _ y: Int, _ f: Double) -> Bool { f * 16 > bayer[(y & 3) * 4 + (x & 3)] }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ s: UInt32) -> UInt32 {
            let p = Double((a >> s) & 0xff), q = Double((b >> s) & 0xff)
            return UInt32((p + (q - p) * t).rounded()) << s
        }
        return ch(16) | ch(8) | ch(0)
    }

    /// Dithered pick from a color ramp at `t` in 0..<1.
    func ramp(_ colors: [UInt32], _ t: Double, _ x: Int, _ y: Int) -> UInt32 {
        let v = t * Double(colors.count - 1), i = Int(v)
        return Self.dither(x, y, v - Double(i)) ? colors[min(i + 1, colors.count - 1)] : colors[i]
    }

    mutating func gradient(_ rows: Range<Int>, _ colors: [UInt32], curve: Double) {
        for y in rows {
            let t = pow(Double(y - rows.lowerBound) / Double(max(1, rows.count)), curve)
            for x in 0..<w { set(x, y, ramp(colors, t, x, y)) }
        }
    }

    mutating func stars(_ r: inout Mulberry32, rows: Range<Int>, count: Int) {
        for _ in 0..<count {
            let x = r.int(0...w), y = r.int(rows.lowerBound...max(rows.lowerBound, rows.upperBound))
            set(x, y, r.next() > 0.75 ? PixelArtColors.starBright : PixelArtColors.starDim)
        }
    }

    /// Blocky skyline: flat runs of random width, each at a random height around `base`.
    func plateaus(_ r: inout Mulberry32, base: Int, range: Int, widths: ClosedRange<Int>) -> [Int] {
        var out: [Int] = []
        var y = base
        while out.count < w {
            y = max(base - range, min(base + range, y + r.int(-max(1, range / 2)...max(1, range / 2))))
            out += Array(repeating: y, count: r.int(widths))
        }
        return Array(out.prefix(w))
    }

    mutating func column(_ x: Int, from top: Int, to bottom: Int, _ fill: UInt32, top edge: UInt32) {
        for y in max(0, top)..<max(max(0, top), min(h, bottom)) { set(x, y, fill) }
        set(x, top, edge)
    }

    /// A soft light: a dithered disk, denser toward the middle, in an outer and an inner color.
    mutating func glow(cx: Double, cy: Double, radius: Double, _ c: (UInt32, UInt32), strength: Double) {
        let r = Int(radius.rounded(.up))
        for y in (Int(cy) - r)...(Int(cy) + r) {
            for x in (Int(cx) - r)...(Int(cx) + r) {
                let dx = Double(x) - cx, dy = Double(y) - cy
                let f = (1 - (dx * dx + dy * dy).squareRoot() / radius) * strength
                if f > 0, Self.dither(x, y, f) { set(x, y, f > 0.45 ? c.1 : c.0) }
            }
        }
    }

}

extension Mulberry32 {
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        return range.lowerBound + Int(next() * Double(range.count))
    }
    mutating func chance(_ p: Double) -> Bool { next() < p }
}
