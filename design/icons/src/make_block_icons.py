# Cofre icon variations. Pure Python PNG writer (no PIL). Every icon is an NxN grid scaled to 1024.
import zlib, struct, random, os
OUT = "/tmp/cofre-icons"

def png(path, px):  # px: list of rows of 0xRRGGBB
    h, w = len(px), len(px[0])
    raw = b"".join(b"\0" + b"".join(struct.pack(">I", c)[1:] for c in row) for row in px)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

def scale(grid, size=1024):
    n = len(grid); k = size // n
    assert k * n == size
    return [[grid[y // k][x // k] for x in range(size)] for y in range(size)]

def from_art(art, pal):
    return [[pal[ch] for ch in row] for row in art]

def blank(n, c): return [[c] * n for _ in range(n)]

# ---- Cofre tokens ----
PURPLE = dict(hi=0xc3b8ff, a=0x9a86ff, b=0x8a74ff, c=0x6e55e8, face=0x5b3fd6, lip=0x3a2694)
GOLD = dict(hi=0xffe29a, a=0xf0b84f, b=0xc98a1c, c=0xb27a12, k=0x2b1608)
DARK = dict(page=0x0f0d17, side=0x0b0a11, panel=0x1a1727, raised=0x221e34, button=0x2b2641,
            bbevel=0x3d3560, bevel=0x342d52, lip=0x07060b, outline=0x05040a, hc=0x8a82a3, muted=0xa29cb8)
GREEN = dict(hi=0x8fe3ad, a=0x57d58c, b=0x45c27a, c=0x2f8f57, d=0x1f6b40)

def noise(n, y0, shades, weights, seed):
    r = random.Random(seed)
    return [[r.choices(shades, weights)[0] for _ in range(n)] for _ in range(y0, n)]

def grass_block(n, heights, top, body, seed, top_shades=None):
    """Chunky look: body texture in 2x2 cells, top layer shaded by depth. top: [hi, a, b, under]."""
    r = random.Random(seed)
    m = n // 2
    cells = [[r.choices(*body)[0] for _ in range(m)] for _ in range(m)]
    g = [[cells[y // 2][x // 2] for x in range(n)] for y in range(n)]
    hi, a, b, under = top[0], top[1], top[2], top[-2] if len(top) > 4 else top[-1]
    toprow = [[r.random() for _ in range(m)] for _ in range(m)]
    for x in range(n):
        hgt = heights[x]
        for y in range(hgt):
            if y == hgt - 1 and y > 1:
                g[y][x] = under
            elif y == 0:
                g[y][x] = hi if toprow[0][x // 2] < 0.45 else a
            else:
                g[y][x] = a if toprow[y // 2 + 1][x // 2] < 0.6 else b
    return g

def put(g, art, pal, ox, oy):
    for y, row in enumerate(art):
        for x, ch in enumerate(row):
            if ch != ".": g[oy + y][ox + x] = pal[ch]

# ---- 1. Amethyst Classic: 8x8, reference layout, palette swap only ----
def v1():
    pal = {"C": PURPLE["hi"], "A": PURPLE["a"], "B": PURPLE["b"], "a": PURPLE["c"],
           "D": 0x3d3560, "d": 0x2b2641, "f": 0x342d52, "e": 0x221e34, "s": DARK["hc"]}
    art = ["ACBAABCA",
           "BAaBAdBa",
           "dBedaDae",
           "DfdDadfd",
           "dsdfdDdf",
           "fdDdedsd",
           "deDsfDde",
           "Dfdedfdd"]
    return from_art(art, pal)

# ---- 2. Gold Ore: 16x16 purple grass over dark dirt with gold ore ----
def v2():
    top = [PURPLE["hi"], PURPLE["a"], PURPLE["b"], PURPLE["c"], PURPLE["lip"]]
    body = ([0x2b2641, 0x342d52, 0x221e34, 0x3d3560], [5, 3, 3, 1])
    h = [4, 4, 5, 5, 4, 4, 3, 3, 4, 4, 6, 6, 4, 5, 4, 4]
    g = grass_block(16, h, top, body, 7)
    ore = [".hg.", "gab.", ".bc."]
    pal = {"h": GOLD["hi"], "g": GOLD["a"], "a": GOLD["a"], "b": GOLD["b"], "c": GOLD["c"]}
    put(g, ["hg", "gb"], pal, 2, 8)
    put(g, [".hg", "gab", ".b."], pal, 9, 10)
    put(g, ["hg", "bc"], pal, 4, 13)
    return g

# ---- 3. Chest Hasp: grass block whose top layer is the lid, gold latch on the seam ----
def v3():
    n = 16
    top = [PURPLE["hi"], PURPLE["a"], PURPLE["b"], PURPLE["c"], PURPLE["lip"]]
    body = ([0x2b2641, 0x342d52, 0x221e34], [5, 3, 3])
    h = [5, 5, 6, 6, 5, 5, 6, 6, 6, 6, 5, 5, 6, 6, 5, 5]
    g = grass_block(n, h, top, body, 11)
    k = DARK["outline"]
    pal = {"k": 0x150f24, "h": GOLD["hi"], "a": GOLD["a"], "b": GOLD["b"], "c": GOLD["c"], "x": GOLD["k"]}
    latch = ["kkkkkk",
             "khaaak",
             "khaabk",
             "kaxxbk",
             "kaxxbk",
             "kbbbck",
             "kkkkkk"]
    put(g, latch, pal, 5, 4)
    return g

# ---- 4. Keyhole: bold 8x8-ish, gold lock plate with keyhole in the dirt ----
def v4():
    n = 16
    top = [PURPLE["hi"], PURPLE["a"], PURPLE["b"], PURPLE["c"], PURPLE["lip"]]
    body = ([0x221e34, 0x2b2641, 0x1a1727], [4, 3, 2])
    h = [4, 4, 3, 3, 4, 5, 4, 4, 4, 4, 5, 4, 3, 3, 4, 4]
    g = grass_block(n, h, top, body, 23)
    pal = {"k": 0x0b0a11, "h": GOLD["hi"], "a": GOLD["a"], "b": GOLD["b"], "c": GOLD["c"], "x": 0x0b0a11}
    plate = ["..hhaa..",
             ".haaaaa.",
             "haaxxaab",
             "haxxxxab",
             "haxxxxab",
             "haaxxaab",
             "haaxxabb",
             "haxxxxbb",
             ".abbbbb.",
             "..bccb.."]
    pal["."] = None
    for y, row in enumerate(plate):
        for x, ch in enumerate(row):
            if ch != ".": g[5 + y][4 + x] = pal[ch]
    return g

# ---- 5. Emerald: Cofre success green over Cofre purple-dark dirt, gold flecks ----
def v5():
    top = [GREEN["hi"], GREEN["a"], GREEN["b"], GREEN["c"], GREEN["d"]]
    body = ([0x2b2641, 0x342d52, 0x221e34, 0x3d3560], [5, 3, 3, 1])
    h = [4, 4, 3, 3, 5, 5, 4, 4, 3, 4, 4, 4, 6, 6, 4, 4]
    g = grass_block(16, h, top, body, 31)
    pal = {"h": GOLD["hi"], "g": GOLD["a"], "b": GOLD["b"]}
    put(g, ["hg", "gb"], pal, 11, 9)
    put(g, ["h", "b"], pal, 4, 12)
    put(g, ["s"], {"s": DARK["hc"]}, 2, 7)
    put(g, ["s"], {"s": DARK["hc"]}, 8, 14)
    return g

# ---- 6. Daylight: light-friendly; amethyst over pale lavender stone ----
def v6():
    top = [PURPLE["hi"], PURPLE["a"], PURPLE["b"], PURPLE["c"], PURPLE["face"]]
    body = ([0xf3f0fb, 0xece7f7, 0xe2dbf2, 0xd6cdee], [4, 4, 3, 1])
    h = [4, 4, 5, 5, 4, 4, 3, 3, 4, 4, 6, 6, 4, 5, 4, 4]
    g = grass_block(16, h, [PURPLE["hi"], PURPLE["a"], PURPLE["b"], PURPLE["face"], PURPLE["face"]], body, 41)
    pal = {"h": GOLD["a"], "g": GOLD["b"], "b": GOLD["c"], "c": 0x8a5c0c}
    put(g, ["hg", "bc"], pal, 3, 9)
    put(g, [".hg", "gbb", ".c."], pal, 10, 11)
    put(g, ["g"], pal, 6, 14)
    return g

# ---- 7. Floating Block: current-icon composition, 8x8 block inset on stone page ----
def v7():
    n = 32
    r = random.Random(5)
    stone = [0x0f0d17, 0x121020, 0x0d0b14, 0x151225]
    g = [[r.choice(stone) for _ in range(n)] for _ in range(n)]
    # block 24x24 at (4,3): 8 cells of 3px
    top = [PURPLE["hi"], PURPLE["a"], PURPLE["b"], PURPLE["c"]]
    D = {"D": 0x3d3560, "d": 0x2b2641, "f": 0x342d52, "e": 0x221e34, "s": DARK["hc"],
         "C": PURPLE["hi"], "A": PURPLE["a"], "B": PURPLE["b"], "a": PURPLE["c"], "g": GOLD["a"], "h": GOLD["hi"], "b": GOLD["b"]}
    art = ["CACCACAC",
           "ABaABdAa",
           "daedadae",
           "Dfdfadfd",
           "dhgDdDdf",
           "fbdedhgd",
           "deDsfbde",
           "Dfdedfdd"]
    ox, oy, c = 4, 3, 3
    for y in range(oy + 1, oy + 27):          # hard drop shadow, 2px down-right
        for x in range(ox + 1, ox + 27):
            g[y][x] = 0x07060b
    for y in range(oy - 1, oy + 25):          # 1px outline
        for x in range(ox - 1, ox + 25):
            g[y][x] = 0x05040a
    for cy, row in enumerate(art):
        for cx, ch in enumerate(row):
            for yy in range(c):
                for xx in range(c):
                    g[oy + cy * c + yy][ox + cx * c + xx] = D[ch]
    return g

# ---- 8. Chest Wood: amethyst grass over warm chest-wood (closest to the warm original dirt) ----
def v8():
    top = [PURPLE["hi"], PURPLE["a"], PURPLE["b"], PURPLE["c"], PURPLE["lip"]]
    body = ([0x6e3d17, 0x7a4520, 0x633616, 0x8a5229], [4, 3, 3, 1])
    h = [4, 4, 3, 3, 4, 4, 5, 5, 4, 4, 3, 4, 5, 5, 4, 4]
    g = grass_block(16, h, top, body, 53)
    pal = {"h": GOLD["hi"], "g": GOLD["a"], "b": GOLD["b"], "c": GOLD["c"]}
    put(g, ["hg", "gb"], pal, 2, 10)
    put(g, [".h", "hgb", ".b"][0:1] + ["hg"] + ["bc"], pal, 10, 8) if False else put(g, ["hg", "bc"], pal, 11, 9)
    put(g, ["g"], pal, 7, 13)
    put(g, ["s"], {"s": 0xa29cb8}, 13, 14)
    return g

VARIANTS = [
    ("amethyst-classic", v1), ("gold-ore", v2), ("chest-hasp", v3), ("keyhole", v4),
    ("emerald", v5), ("daylight", v6), ("floating-block", v7), ("chest-wood", v8),
]
if __name__ == "__main__":
    for i, (name, f) in enumerate(VARIANTS, 1):
        png(f"{OUT}/icon-{i}-{name}.png", scale(f()))
        print(f"icon-{i}-{name}.png")
