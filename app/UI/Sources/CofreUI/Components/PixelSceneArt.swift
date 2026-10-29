import Foundation

// The four PixelScene landscapes. Pure pixel math: deterministic per seed, no SwiftUI, one pixel = one art pixel.
// Every style keeps a dark top for white titles and a floor near 0.78 of the height for sprites (Llave).

enum SceneArt {
    static func render(_ style: PixelScene.Style, seed: UInt32, w: Int, h: Int) -> [UInt32] {
        var c = SceneCanvas(w: w, h: h, seed: seed)
        var r = Mulberry32(seed: seed)
        switch style {
        case .falls: falls(&c, &r)
        case .geode: geode(&c, &r)
        case .islands: islands(&c, &r)
        case .lake: lake(&c, &r)
        }
        return c.px
    }

    // MARK: Waterfall canyon

    /// Two terraced canyon walls frame a waterfall that drops into a misty pool.
    private static func falls(_ c: inout SceneCanvas, _ r: inout Mulberry32) {
        typealias P = PixelArtColors.Falls
        let w = c.w, h = c.h
        let cx = w / 2 + r.int(-w / 24...w / 24)
        let pool = c.ph(0.8), backTop = c.ph(0.3)
        c.gradient(0..<pool, P.sky, curve: 1.15)
        c.stars(&r, rows: 0..<c.ph(0.4), count: w * h / 160)

        // Far flat-topped mesas, seen through the canyon's V.
        let mesa = c.plateaus(&r, base: c.ph(0.42), range: c.ph(0.1), widths: 8...22)
        for x in 0..<w { c.column(x, from: mesa[x], to: backTop + 2, P.mesa.0, top: P.mesa.1) }

        // Back wall with the waterfall notch.
        let fallW = max(5, c.ph(0.11)), fallX = cx - fallW / 2
        for x in 0..<w {
            let notch = x >= fallX - 1 && x <= fallX + fallW ? 2 : 0
            let top = backTop + notch + abs(x - cx) / 9
            c.column(x, from: top, to: pool, P.rockBack.0, top: P.rockBack.1)
            for y in (top + 1)..<max(top + 1, pool) where c.hash(x / 3, y / 3) % 4 == 0 {
                c.set(x, y, P.rockBack.1)
            }
        }

        // The fall: streaky columns, foam lip at the top.
        for i in 0..<fallW {
            let x = fallX + i, phase = r.int(0...20), len = r.int(3...8)
            for y in (backTop + 2)..<pool {
                let k = (y + phase) / len
                let v = c.hash(i, k) % 10
                var col = v < 4 ? P.water[1] : v < 8 ? P.water[2] : P.water[3]
                if i == 0 || i == fallW - 1 { col = v < 6 ? P.water[0] : P.water[1] }
                c.set(x, y, col)
            }
        }
        for x in (fallX - 1)...(fallX + fallW) { c.set(x, backTop + 1, P.water[3]) }

        // Canyon walls: block-textured, stepping outward as they rise, grass on every exposed ledge.
        let bottomGap = max(fallW + 6, w / 10)
        var edges = [Int](repeating: 0, count: h)  // half gap per row
        var g = bottomGap
        var y = pool - 1
        while y >= 0 {
            let band = r.int(3...6)
            for k in 0..<band where y - k >= 0 { edges[y - k] = g }
            y -= band
            g += r.int(1...max(2, w / 28))
        }
        let leftTop = c.plateaus(&r, base: c.ph(0.16), range: c.ph(0.1), widths: 5...12)
        let rightTop = c.plateaus(&r, base: c.ph(0.2), range: c.ph(0.1), widths: 5...12)
        var solid = [Bool](repeating: false, count: w * h)
        for x in 0..<w {
            let left = x < cx
            for y in min(max(0, left ? leftTop[x] : rightTop[x]), pool)..<pool {
                solid[y * w + x] = left ? x < cx - edges[y] : x > cx + edges[y]
            }
        }
        func isWall(_ x: Int, _ y: Int) -> Bool { y >= 0 && y < h && solid[y * w + min(w - 1, max(0, x))] }
        var ledges: [(Int, Int)] = []
        for y in 0..<pool {
            for x in 0..<w where isWall(x, y) {
                var col = P.rock[Int(c.hash(x / 4, y / 4) % UInt32(P.rock.count))]
                if !isWall(x - 1, y) || !isWall(x + 1, y) { col = P.rockLit }
                if !isWall(x, y - 1) {
                    col = P.grass.0
                    ledges.append((x, y))
                } else if !isWall(x, y - 2) {
                    col = P.grass.1
                }
                c.set(x, y, col)
            }
        }
        // Vines hanging off the ledges, and cube trees on the rims.
        for (x, y) in ledges where c.hash(x, y) % 6 == 0 {
            for k in 2..<(3 + Int(c.hash(y, x) % 6)) where isWall(x, y + k) { c.set(x, y + k, P.vine) }
        }
        for _ in 0..<max(2, w / 40) {
            let x = r.int(1...w - 2)
            if let top = (0..<pool).first(where: { isWall(x, $0) }), top < c.ph(0.5) {
                c.cubeTree(x, ground: top, size: r.int(3...5), leaf: (P.tree.1, P.tree.0, P.tree.0), trunk: P.tree.2)
            }
        }
        // A thin second fall off a high ledge.
        if let (x, y) = ledges.filter({ abs($0.0 - cx) > fallW && $0.1 > c.ph(0.3) && $0.1 < c.ph(0.55) })
            .min(by: { c.hash($0.0, 1) < c.hash($1.0, 1) })
        {
            for yy in y..<pool {
                for i in 0..<2 { c.set(x + i, yy, c.hash(i, yy / 3) % 3 == 0 ? P.water[2] : P.water[1]) }
            }
        }
        for _ in 0..<max(3, w / 30) {
            let x = r.int(0...w), y = r.int(c.ph(0.55)...pool - 2)
            if !P.water.contains(c[x, y]) { c.set(x, y, P.firefly) }
        }

        // Pool, ripples, then mist rising from the foot of the fall.
        c.gradient(pool..<h, P.pool, curve: 1)
        for _ in 0..<(w * (h - pool) / 40) {
            let x = r.int(0...w), y = r.int(pool + 1...h)
            let len = r.int(2...6)
            for k in 0..<len { c.set(x + k, y, abs(x - cx) < fallW * 2 ? P.water[1] : P.ripple) }
        }
        c.mist(cx: cx, cy: pool, rx: Double(fallW) * 1.5 + 3, ry: Double(c.ph(0.1)), P.mist)
    }

    // MARK: Amethyst geode

    /// A glowing amethyst cave: crystal clusters on the floor and hanging from the ceiling, gold ore in the rock.
    private static func geode(_ c: inout SceneCanvas, _ r: inout Mulberry32) {
        typealias P = PixelArtColors.Geode
        let w = c.w, h = c.h
        let cx = w / 2 + r.int(-w / 10...w / 10), floor = c.ph(0.78)
        // Back wall: a radial glow around the hero cluster, broken into 4 px blocks.
        let gy = Double(c.ph(0.6)), span = Double(max(w, h)) * 0.5
        for y in 0..<h {
            for x in 0..<w {
                let bx = Double(x / 4 * 4 + 2) - Double(cx), by = Double(y / 4 * 4 + 2) - gy
                let d = (bx * bx * 0.6 + by * by * 1.4).squareRoot() / span
                c.set(x, y, c.ramp(P.glow, min(0.999, d + Double(c.hash(x / 4, y / 4) % 3) * 0.04), x, y))
            }
        }
        // Mid ledge with dim crystals for depth.
        let ledge = c.plateaus(&r, base: c.ph(0.64), range: c.ph(0.08), widths: 4...10)
        for x in 0..<w { c.column(x, from: ledge[x], to: floor, P.ledge.0, top: P.ledge.1) }
        for _ in 0..<max(3, w / 22) {
            let x = r.int(0...w - 1)
            c.crystal(
                x, base: ledge[x], height: r.int(3...max(4, c.ph(0.12))), width: 3, lean: r.int(-1...1), up: true,
                P.crystalDim, tip: P.crystalDim[0])
        }
        // Ceiling and floor rock.
        let ceil = c.plateaus(&r, base: c.ph(0.1), range: c.ph(0.1), widths: 3...8)
        let ground = c.plateaus(&r, base: floor, range: c.ph(0.04), widths: 6...16)
        for x in 0..<w {
            for y in 0...max(0, ceil[x]) { c.set(x, y, P.rock.0) }
            c.set(x, ceil[x], P.rock.1)
            c.column(x, from: ground[x], to: h, P.rock.0, top: P.rock.1)
        }
        // Gold and amethyst ore specks in the rock.
        for _ in 0..<max(2, w / 40) {
            let x = r.int(0...w - 2)
            let y = r.chance(0.4) ? r.int(0...max(0, ceil[x] - 3)) : r.int(min(h - 2, ground[x] + 3)...h - 2)
            c.fill(x, y, 2, 2, P.gold.1)
            c.set(x, y, P.gold.0)
        }
        // Hanging crystals.
        for _ in 0..<max(3, w / 18) {
            let x = r.int(0...w - 1)
            c.crystal(
                x, base: ceil[x] + 1, height: r.int(3...max(4, c.ph(0.16))), width: r.int(3...4), lean: 0, up: false,
                P.crystal, tip: P.tip)
        }
        // Floor clusters: one big hero cluster near the middle, smaller ones around it, each with a halo.
        var clusters: [(Int, Double)] = []
        for _ in 0..<max(3, w / 30) { clusters.append((r.int(0...w), 0.35 + r.next() * 0.35)) }
        clusters.append((cx, 1.0))
        for (x, scale) in clusters {
            let base = ground[min(w - 1, max(0, x))]
            let tall = Double(c.ph(0.42)) * scale
            let unit = max(2, Int(Double(c.ph(0.05)) * scale))
            // (offset, height, lean) in crystal widths; drawn back to front.
            let parts: [(Int, Double, Int)] = [(-2, 0.4, -1), (2, 0.45, 1), (-1, 0.7, -1), (1, 0.6, 1), (0, 1, 0)]
            for (dx, f, lean) in parts.suffix(scale > 0.9 ? 5 : 3) {
                c.crystal(
                    x + dx * unit, base: base, height: max(3, Int(tall * f)), width: dx == 0 ? unit + 2 : unit + 1,
                    lean: lean, up: true, P.crystal, tip: P.tip)
            }
        }
        // Sparkles in the air.
        for _ in 0..<(w * h / 400) {
            let x = r.int(0...w), y = r.int(c.ph(0.15)...c.ph(0.75))
            c.set(x, y, P.spark)
        }
    }

    // MARK: Sky islands

    /// Floating islands over a sea of clouds under an aurora; the big one spills a waterfall off its edge.
    private static func islands(_ c: inout SceneCanvas, _ r: inout Mulberry32) {
        typealias P = PixelArtColors.Islands
        let w = c.w, h = c.h
        c.gradient(0..<h, P.sky, curve: 1.1)
        // Aurora: a wavy curtain of 2 px rays with a bright hem, fading upward.
        var band = Double(c.ph(0.24)), slope = 0.0
        for x in stride(from: 0, to: w, by: 2) {
            slope = max(-0.5, min(0.5, slope + (r.next() - 0.5) * 0.3))
            band = max(Double(c.ph(0.12)), min(Double(c.ph(0.3)), band + slope))
            let ray = 0.3 + 0.7 * (0.5 + 0.5 * sin(Double(x) * 0.13 + Double(c.hash(x / 6, 1) % 7)))
            let tall = c.ph(0.06 + ray * 0.14)
            for k in 0..<tall {
                let f = k < 2 ? ray : pow(1 - Double(k) / Double(tall), 1.5) * ray * 0.8
                let y = Int(band) - k
                for dx in 0..<2 where SceneCanvas.dither(x + dx, y, f) {
                    c.set(x + dx, y, k == 0 ? P.aurora[2] : k < 3 ? P.aurora[1] : P.aurora[0])
                }
            }
        }
        c.stars(&r, rows: 0..<c.ph(0.6), count: w * h / 180)

        // Clouds: far and near layers of puffy blocks.
        c.clouds(&r, base: c.ph(0.8), P.cloud[0])

        // Two or three small far islands, then the big one.
        let mainW = max(c.ph(0.7), w * 3 / 10), mainX = w / 2 + r.int(-w / 12...w / 12) - mainW / 2
        for i in 0..<(w > 2 * h ? 3 : 2) {
            let iw = c.ph(0.18 + r.next() * 0.1)
            let left = i % 2 == 0
            let x = left ? r.int(2...max(2, mainX - iw - 2)) : r.int(min(w - iw - 2, mainX + mainW + 2)...w - iw - 2)
            let island = c.island(&r, x: x, top: c.ph(0.28 + r.next() * 0.18), width: iw, dim: 0.45)
            let leaf = c.dimmed(P.leaf, 0.45), trunk = SceneCanvas.mix(P.trunk, P.sky[3], 0.45)
            if r.chance(0.6) { c.cubeTree(island.0 + iw / 2, ground: island.1, size: 3, leaf: leaf, trunk: trunk) }
        }
        let top = c.ph(0.56)
        _ = c.island(&r, x: mainX, top: top, width: mainW, dim: 0)
        // Trees and a chest on the big island.
        c.cubeTree(mainX + mainW / 4, ground: top, size: max(4, c.ph(0.1)), leaf: P.leaf, trunk: P.trunk)
        c.cubeTree(mainX + mainW * 3 / 5, ground: top, size: max(3, c.ph(0.07)), leaf: P.leaf, trunk: P.trunk)
        let chestX = mainX + mainW * 2 / 5
        c.fill(chestX, top - 3, 4, 3, P.chest.0)
        c.fill(chestX, top - 1, 4, 1, P.chest.1)
        c.set(chestX + 1, top - 2, P.chest.2)
        c.set(chestX + 2, top - 2, P.chest.2)
        // Waterfall off the right edge, down into the clouds.
        let fx = mainX + mainW - 1
        for y in (top - 1)..<h {
            for i in 0..<3 {
                let v = c.hash(i, (y + i * 5) / 3) % 6
                c.set(fx + i - (y == top - 1 ? 2 : 0), y, v < 3 ? P.water[0] : v < 5 ? P.water[1] : P.water[2])
            }
        }
        c.mist(cx: fx + 1, cy: c.ph(0.9), rx: Double(c.ph(0.1)), ry: Double(c.ph(0.08)), P.cloud[1])
        c.clouds(&r, base: c.ph(0.92), P.cloud[1])
    }

    // MARK: Moonlit lake

    /// A square moon over a cube-tree forest, mirrored in a still lake; a cabin window glows gold.
    private static func lake(_ c: inout SceneCanvas, _ r: inout Mulberry32) {
        typealias P = PixelArtColors.Lake
        let w = c.w, h = c.h
        let horizon = c.ph(0.6), shore = c.ph(0.86)
        c.gradient(0..<horizon, P.sky, curve: 1.2)
        c.stars(&r, rows: 0..<c.ph(0.45), count: w * h / 110)

        let m = max(5, c.ph(0.14)), mx = Int(Double(w) * (0.58 + r.next() * 0.2)), my = c.ph(0.1 + r.next() * 0.06)

        // Cube-tree forest in two rows, the near one rimmed by moonlight; a cabin among the trees.
        for row in 0..<2 {
            let colors = P.forest[row], ground = horizon - (row == 0 ? 2 : 0)
            c.fill(0, ground - 1, w, horizon - ground + 2, colors.0)
            var x = -r.int(0...4)
            while x < w {
                let s =
                    row == 0
                    ? r.int(max(3, c.ph(0.04))...max(3, c.ph(0.08))) : r.int(max(4, c.ph(0.06))...max(4, c.ph(0.12)))
                let trunk = r.int(1...max(2, s * 2 / 3)) + (row == 0 ? c.ph(0.04) : 0)
                // Oak-like: a wide canopy with a narrower step on top, rimmed on the side facing the moon.
                let top = ground - trunk - s, cap = max(1, s / 3), rim = mx > w / 2 ? x + s - 1 : x
                c.fill(x + s / 2, ground - trunk, 1, trunk, colors.0)
                c.fill(x, top, s, s, colors.0)
                c.fill(x + 1, top - cap, s - 2, cap, colors.0)
                c.fill(x, top, s, 1, colors.1)
                c.fill(x + 1, top - cap, s - 2, 1, colors.1)
                c.fill(rim, top, 1, s * 2 / 3, colors.1)
                x += s + r.int(row == 0 ? 0...3 : 1...5)
            }
        }
        let cabinX = mx > w / 2 ? r.int(w / 6...w * 2 / 5) : r.int(w * 3 / 5...w * 5 / 6)
        let cw = max(6, c.ph(0.1)), ch = max(4, c.ph(0.06)), base = horizon - c.ph(0.02)
        c.fill(cabinX, base - ch, cw, ch + 1, P.cabin.0)
        for k in 0..<(cw / 2 + 1) { c.fill(cabinX - 1 + k, base - ch - 1 - k, cw + 2 - 2 * k, 1, P.cabin.1) }
        c.fill(cabinX + cw / 2 - 1, base - ch + 1, 2, 2, P.window)

        // Lake: the sky and forest mirrored, darkened with depth, broken by ripples; moon and window glints.
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
        // Square moon with a soft halo, drawn after the mirror so only its glint shows in the water.
        let reach = Double(m) * 1.2, mc = Double(mx) + Double(m - 1) / 2, mcy = Double(my) + Double(m - 1) / 2
        for y in (my - m)...(my + 2 * m) {
            for x in (mx - m)...(mx + 2 * m) {
                let dx = Double(x) - mc, dy = Double(y) - mcy
                let d = (dx * dx + dy * dy).squareRoot() / reach
                if d < 1, SceneCanvas.dither(x, y, 0.5 * (1 - d)) { c.set(x, y, P.halo) }
            }
        }
        c.fill(mx, my, m, m, P.moon.0)
        c.fill(mx + m - 1, my + 1, 1, m - 1, P.moon.1)
        c.fill(mx + 1, my + m - 1, m - 1, 1, P.moon.1)
        for _ in 0..<3 { c.fill(mx + r.int(1...max(1, m - 3)), my + r.int(1...max(1, m - 3)), 2, 2, P.moon.1) }

        for y in stride(from: horizon + 1, to: shore, by: 2) where c.hash(y, 17) % 3 != 0 {
            let spread = 1 + m / 2 + (y - horizon) / 3, jitter = Int(c.hash(y, 11) % 3) - 1
            let len = 1 + Int(c.hash(y, 13) % UInt32(spread))
            let near = y - horizon < (shore - horizon) / 2
            c.fill(mx + m / 2 - len / 2 + jitter, y, len, 1, near ? P.glint.0 : P.glint.1)
            if (y - horizon) % 4 == 1, y < horizon + c.ph(0.14) {
                c.fill(cabinX + cw / 2 - 1 + jitter, y, 2, 1, P.window)
            }
        }
        // Shore with reeds and fireflies.
        let bank = c.plateaus(&r, base: shore, range: c.ph(0.03), widths: 5...14)
        for x in 0..<w { c.column(x, from: bank[x], to: h, P.shore.0, top: P.shore.1) }
        for _ in 0..<max(4, w / 10) {
            let x = r.int(0...w - 1), tall = r.int(2...max(3, c.ph(0.08)))
            for k in 1...tall { c.set(x, bank[x] - k, P.reed.0) }
            if r.chance(0.5) { c.fill(x, bank[x] - tall - 1, 1, 2, P.reed.1) }
        }
        for _ in 0..<max(3, w / 30) {
            c.set(r.int(0...w), r.int(c.ph(0.66)...c.ph(0.92)), P.window)
        }
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

    func dimmed(_ c: (UInt32, UInt32, UInt32), _ t: Double) -> (UInt32, UInt32, UInt32) {
        (Self.mix(c.0, self[0, ph(0.4)], t), Self.mix(c.1, self[0, ph(0.4)], t), Self.mix(c.2, self[0, ph(0.4)], t))
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

    /// Mist or spray: a dithered oval, denser toward the middle.
    mutating func mist(cx: Int, cy: Int, rx: Double, ry: Double, _ c: (UInt32, UInt32)) {
        for y in (cy - Int(ry))...(cy + Int(ry)) {
            for x in (cx - Int(rx))...(cx + Int(rx)) {
                let dx = Double(x - cx) / rx, dy = Double(y - cy) / ry, d = dx * dx + dy * dy
                guard d < 1 else { continue }
                let f = (1 - d) * 0.9 + Double(hash(x / 3, y / 3) % 4) * 0.04
                if Self.dither(x, y, f) { set(x, y, f > 0.55 ? c.1 : c.0) }
            }
        }
    }

    /// A row of blocky cloud puffs along `base`, lit on top, filled down to the bottom edge.
    mutating func clouds(_ r: inout Mulberry32, base: Int, _ c: (UInt32, UInt32)) {
        var x = -r.int(0...6)
        while x < w + 8 {
            let rad = r.int(max(3, ph(0.05))...max(4, ph(0.11)))
            let cy = base + r.int(-2...2)
            for y in (cy - rad)...h {
                for xx in (x - rad * 2)...(x + rad * 2) {
                    let dx = Double((xx - x) / 2 * 2) / 2, dy = Double(min(0, (y - cy) / 2 * 2))
                    let d = dx * dx + dy * dy
                    if d <= Double(rad * rad) { set(xx, y, d > Double((rad - 1) * (rad - 1)) && y < cy ? c.1 : c.0) }
                }
            }
            x += rad * 2 + r.int(0...rad)
        }
    }

    /// A Minecraft-style tree: square canopy lit from the top left, one-pixel trunk.
    mutating func cubeTree(_ x: Int, ground: Int, size: Int, leaf: (UInt32, UInt32, UInt32), trunk: UInt32) {
        let trunkH = max(1, size / 2)
        fill(x, ground - trunkH, 1, trunkH, trunk)
        let left = x - size / 2, top = ground - trunkH - size
        fill(left, top, size, size, leaf.1)
        fill(left, top + size - 1, size, 1, leaf.2)
        fill(left + size - 1, top, 1, size, leaf.2)
        fill(left, top, size - 1, 1, leaf.0)
        fill(left, top, 1, size - 1, leaf.0)
    }

    /// A pointed crystal: lit left face with a highlight streak, shaded right face, tapering to a bright tip.
    mutating func crystal(
        _ x0: Int, base: Int, height: Int, width: Int, lean: Int, up: Bool, _ c: [UInt32], tip: UInt32
    ) {
        for k in 0..<height {
            let fromTip = height - 1 - k
            let wk = min(width, 1 + 2 * fromTip)
            let left = x0 - width / 2 + lean * k / 3
            let y = up ? base - k : base + k
            for pos in (width - wk) / 2..<(width - wk) / 2 + wk {
                var col = pos < width / 2 ? c[1] : pos == width - 1 ? c[3] : c[2]
                if pos == width / 2 - 1 { col = c[0] }
                set(left + pos, y, fromTip == 0 ? tip : col)
            }
        }
    }

    /// A floating island: grass, dirt, then a stepped stone underside. Returns its left edge and top.
    @discardableResult
    mutating func island(
        _ r: inout Mulberry32, x: Int, top: Int, width: Int, dim: Double
    ) -> (Int, Int) {
        typealias P = PixelArtColors.Islands
        let skyC = self[0, top]
        func d(_ c: UInt32) -> UInt32 { Self.mix(c, skyC, dim) }
        fill(x, top, width, 1, d(P.grass.0))
        fill(x, top + 1, width, 1, d(P.grass.1))
        fill(x, top + 2, width, 2, d(P.dirt.0))
        var l = x, rgt = x + width, y = top + 4
        while rgt - l > 1 {
            for yy in y..<(y + 2) {
                for xx in l..<rgt {
                    set(xx, yy, hash(xx / 3, yy / 3) % 3 == 0 ? d(P.stone.1) : xx == l ? d(P.dirt.1) : d(P.stone.0))
                }
            }
            if hash(l, y) % 4 == 0 { fill(l + 1, y + 2, 1, 2 + Int(hash(y, l) % 3), d(P.root)) }
            l += r.int(1...3)
            rgt -= r.int(1...3)
            y += 2
        }
        return (x, top)
    }
}

extension Mulberry32 {
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        guard range.upperBound > range.lowerBound else { return range.lowerBound }
        return range.lowerBound + Int(next() * Double(range.count))
    }
    mutating func chance(_ p: Double) -> Bool { next() < p }
}
