"""Cofre app icons: original 32x32 pixel art, exported to 1024 PNGs + gallery SVG data.

Pure stdlib (no PIL). Each variant returns (background, foreground) grids so the
top picks can ship as separate Icon Composer layers.
"""
import json, math, os, random, struct, zlib

N = 32
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)


def hx(c):
    if isinstance(c, tuple):
        return c
    c = c.lstrip('#')
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    a, b = hx(a), hx(b)
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


class G:
    def __init__(s, fill=None):
        s.p = [[hx(fill) if fill else None] * N for _ in range(N)]

    def set(s, x, y, c):
        if 0 <= x < N and 0 <= y < N and c is not None:
            s.p[y][x] = hx(c)

    def get(s, x, y):
        return s.p[y][x] if 0 <= x < N and 0 <= y < N else None

    def rect(s, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                s.set(xx, yy, c)

    def blend(s, x, y, c, t):
        cur = s.get(x, y)
        if cur is not None:
            s.p[y][x] = mix(cur, c, t)

    def sprite(s, rows, pal, ox, oy):
        w = len(rows[0])
        for y, row in enumerate(rows):
            assert len(row) == w, (row, w)
            for x, ch in enumerate(row):
                if ch in pal:
                    s.set(ox + x, oy + y, pal[ch])

    def copy(s):
        g = G()
        g.p = [r[:] for r in s.p]
        return g


def over(bg, fg):
    g = bg.copy()
    for y in range(N):
        for x in range(N):
            if fg.p[y][x] is not None:
                g.p[y][x] = fg.p[y][x]
    return g


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def dither(stops, fn):
    """Ordered-dither between palette stops; fn(x, y) -> 0..1."""
    g = G()
    n = len(stops) - 1
    for y in range(N):
        for x in range(N):
            t = max(0.0, min(1.0, fn(x, y))) * n
            i = min(int(t), n)
            f = t - i
            c = stops[min(i + 1, n)] if f * 16 > BAYER[y % 4][x % 4] + 0.5 else stops[i]
            g.set(x, y, c)
    return g


def radial(stops, cx=16, cy=15.5, r=23):
    return dither(stops, lambda x, y: math.hypot(x + .5 - cx, y + .5 - cy) / r)


def vertical(stops, y0=0, y1=N, gamma=1.0):
    return dither(stops, lambda x, y: ((y + .5 - y0) / (y1 - y0)) ** gamma)


def stars(g, n, seed, ymax=N, cols=('#8c86c4', '#ffffff'), avoid=None):
    r = random.Random(seed)
    for _ in range(n):
        x, y = r.randrange(1, N - 1), r.randrange(1, ymax)
        if avoid and avoid(x, y):
            continue
        g.set(x, y, cols[0] if r.random() < .65 else cols[1])


SPARK = ['..w..', '..w..', 'wwWww', '..w..', '..w..']
SPARK_S = ['.w.', 'wWw', '.w.']


def spark(g, x, y, big=True, w='#c9bcff', W='#ffffff'):
    rows = SPARK if big else SPARK_S
    o = len(rows) // 2
    g.sprite(rows, {'w': w, 'W': W}, x - o, y - o)


# ---------- palettes ----------
OUT_C = '#150c30'
WOOD = dict(o=OUT_C, H='#c4b8ff', L='#9a86ff', D='#3a2694', l='#7a63f0', M='#5b3fd6',
            g='#4b33c2', d='#4a31b8', Y='#f0b84f', W='#ffe39c', y='#b9801c', k='#2b1608')
ENDER = dict(o='#05040a', H='#7462c4', L='#43367c', D='#30245e', l='#251c4a', M='#18122e',
             g='#2c2154', d='#110c22', Y='#5ee6d0', W='#e6fff9', y='#239a90', k='#06302f')

# ---------- sprites (all drawn by hand for Cofre) ----------
CHEST = [
    '.oooooooooooooooooooo.',
    'oHHHHHHHHHHHHHHHHHHHHo',
    'oLLLLLLLLLLLLLLLLLLLLo',
    'oDDDDDDDDDDDDDDDDDDDDo',
    'oDllllllllllllllllllDo',
    'oDMMgggMMMMMMMMMMMMMDo',
    'oDMMMMMMMMMMMMMMgggMDo',
    'oDddddddddddddddddddDo',
    'oooooooooooooooooooooo',
    'oDDDDDDDDDDDDDDDDDDDDo',
    'oDllllllllllllllllllDo',
    'oDMMMMMMMMMMMMMMMMMMDo',
    'oDMgggMMMMMMMMMMMMMMDo',
    'oDMMMMMMMMMMMMMMMMMMDo',
    'oDMMMMMMMMMMMMMggggMDo',
    'oDMMMMMMMMMMMMMMMMMMDo',
    'oDMMMggMMMMMMMMMMMMMDo',
    'oDddddddddddddddddddDo',
    'oDDDDDDDDDDDDDDDDDDDDo',
    '.oooooooooooooooooooo.',
]
LATCH = [
    '.oooo.',
    'oWWYYo',
    'oWYYyo',
    'oYkkyo',
    'oYkkyo',
    'oyyyyo',
    '.oooo.',
]
CHEST_M = [
    '.oooooooooooooooo.',
    'oHHHHHHHHHHHHHHHHo',
    'oDDDDDDDDDDDDDDDDo',
    'oDllllllllllllllDo',
    'oDMMggMMMMMMMMMMDo',
    'oDddddddddddddddDo',
    'oooooooooooooooooo',
    'oDDDDDDDDDDDDDDDDo',
    'oDllllllllllllllDo',
    'oDMMMMMMMMMMgggMDo',
    'oDMggMMMMMMMMMMMDo',
    'oDMMMMMMMMMMMMMMDo',
    'oDddddddddddddddDo',
    'oDDDDDDDDDDDDDDDDo',
    '.oooooooooooooooo.',
]
LATCH_M = ['.oooo.', 'oWWYYo', 'oYkkyo', 'oyyyyo', '.oooo.']


def chest(g, pal, ox=5, oy=6):
    g.sprite(CHEST, pal, ox, oy)
    g.sprite(LATCH, pal, ox + 8, oy + 5)


def chest_m(g, pal, ox, oy):
    g.sprite(CHEST_M, pal, ox, oy)
    g.sprite(LATCH_M, pal, ox + 6, oy + 3)


def shadow(bg, x0, x1, y, c='#05040a', t=.55):
    for x in range(x0, x1 + 1):
        bg.blend(x, y, c, t)
    for x in range(x0 + 2, x1 - 1):
        bg.blend(x, y + 1, c, t * .5)


# ---------- variants ----------
def v_vanilla():
    bg = radial(['#3b2a7e', '#2c1f60', '#1f1644', '#160f2e', '#0f0d17'], cy=15, r=24)
    fg = G()
    chest(fg, WOOD)
    shadow(bg, 6, 25, 26)
    return bg, fg


def v_ender():
    bg = radial(['#2a1c58', '#1b1240', '#110b28', '#0a0716', '#07060b'], cy=15, r=22)
    r = random.Random(7)
    for _ in range(26):  # drifting ender motes
        x, y = r.randrange(1, 31), r.randrange(1, 31)
        if 4 <= x <= 27 and 5 <= y <= 26:
            continue
        bg.set(x, y, r.choice(['#7b4dff', '#b394ff', '#5a37c9', '#e2d6ff']))
    for x, y in [(3, 4), (28, 9), (2, 22), (29, 27)]:
        spark(bg, x, y, False, '#7b4dff', '#e2d6ff')
    fg = G()
    chest(fg, ENDER)
    for x, y in [(9, 11), (21, 12), (8, 20), (23, 19), (12, 22), (19, 21)]:  # obsidian flecks
        fg.set(x, y, '#4a3590')
    # the seam glows like a crack, brightest at the eye
    for x in range(6, 26):
        if 13 <= x <= 18:
            continue
        d = abs(x + .5 - 16)
        fg.set(x, 14, '#5ee6d0' if d < 5.5 else '#2fa89a' if d < 8 else '#1a5f5a')
        if d < 7:
            fg.blend(x, 13, '#5ee6d0', .22)
            fg.blend(x, 15, '#5ee6d0', .22)
    for x, y in [(13, 11), (18, 11), (13, 17), (18, 17), (12, 14), (19, 14)]:  # halo corners
        fg.set(x, y, '#1f7c74')
    shadow(bg, 6, 25, 26, '#000000', .6)
    return bg, fg


def v_open():
    bg = radial(['#5a44c4', '#3f2c96', '#2a1d66', '#1a1342', '#0f0d17'], cy=15, r=21)
    cx, cy = 16, 15
    for y in range(N):
        for x in range(N):
            dx, dy = x + .5 - cx, y + .5 - cy
            if dy >= 0:
                continue
            a = math.degrees(math.atan2(-dy, dx))
            d = math.hypot(dx, dy)
            if any(abs(a - c) < 5.5 for c in (22, 46, 70, 110, 134, 158)):
                bg.blend(x, y, '#d9d0ff', .42 if d < 13 else .26)
    shadow(bg, 6, 25, 29)
    fg = G()
    lid = [  # lid flipped back: we see its inner face, latch now points up
        '.oooooooooooooooooooo.',
        'oDDDDDDDDDDDDDDDDDDDDo',
        'oDddddddddddddddddddDo',
        'oDdMMMMMMMMMMMMMMMMdDo',
        'oDdllllllllllllllllDDo',
        'oDDDDDDDDDDDDDDDDDDDDo',
        'oooooooooooooooooooooo',
    ]
    fg.sprite(lid, WOOD, 5, 7)
    fg.sprite(['.oooo.', 'oWWYYo', 'oYYYyo', 'oyyyyo'], WOOD, 13, 4)
    for y, dim in ((14, 0), (15, 0), (16, 1)):  # light pouring out of the opening
        fg.set(5, y, OUT_C)
        fg.set(26, y, OUT_C)
        for x in range(6, 26):
            d = abs(x + .5 - 16) + dim * 2.5
            fg.set(x, y, '#ffffff' if d < 4.5 else '#e4dcff' if d < 7.5 else '#b9a9ff' if d < 9.5 else '#8a74ff')
    for y in range(7, 14):  # beam rising in front of the lid
        for x in range(6, 26):
            d = abs(x + .5 - 16)
            if d < 6.5 and fg.get(x, y) != hx(OUT_C):
                fg.blend(x, y, '#ffffff', (.5 if d < 3.5 else .28) * (y - 5) / 8)
    body = [
        'oooooooooooooooooooooo',
        'oHHHHHHHHHHHHHHHHHHHHo',
        'oDDDDDDDDDDDDDDDDDDDDo',
        'oDllllllllllllllllllDo',
        'oDMMMMMMMMMMMMMMMMMMDo',
        'oDMgggMMMMMMMMMMMMMMDo',
        'oDMMMMMMMMMMMMMggggMDo',
        'oDMMMMMMMMMMMMMMMMMMDo',
        'oDddddddddddddddddddDo',
        'oDDDDDDDDDDDDDDDDDDDDo',
        '.oooooooooooooooooooo.',
    ]
    fg.sprite(body, WOOD, 5, 17)
    fg.sprite(['oooo', 'oYyo', 'oooo'], WOOD, 14, 18)  # catch plate
    spark(fg, 4, 5, True, '#ffd98a', '#ffffff')
    spark(fg, 27, 9, True, '#ffd98a', '#ffffff')
    spark(fg, 24, 2, False, '#e4dcff', '#ffffff')
    spark(fg, 8, 1, False, '#e4dcff', '#ffffff')
    for x, y in [(11, 2), (21, 5), (19, 1), (3, 11)]:
        fg.set(x, y, '#e4dcff')
    return bg, fg


def v_enchanted():
    bg = radial(['#4a2386', '#371a6a', '#25114c', '#170b30', '#0f0819'], cy=15, r=24)
    stars(bg, 10, 3, cols=('#8f5fd6', '#e9c8ff'), avoid=lambda x, y: 4 <= x <= 27 and 5 <= y <= 27)
    fg = G()
    pal = dict(WOOD, M='#6142e0', l='#8268f5', g='#5136cc')
    chest(fg, pal)
    for y in range(N):
        for x in range(N):
            if fg.get(x, y) is None or fg.get(x, y) == hx(OUT_C):
                continue
            k = (x + y) % 15
            if k in (0, 1, 2):
                fg.blend(x, y, '#f4c8ff', .55 if k == 1 else .38)
            elif k == 8:
                fg.blend(x, y, '#f4c8ff', .25)
    shadow(bg, 6, 25, 26)
    spark(fg, 4, 5, True, '#e9b8ff', '#ffffff')
    spark(fg, 27, 23, True, '#e9b8ff', '#ffffff')
    spark(fg, 27, 4, False, '#e9b8ff', '#ffffff')
    spark(fg, 3, 26, False, '#e9b8ff', '#ffffff')
    return bg, fg


def v_iso():
    bg = radial(['#33246f', '#251a54', '#1a123b', '#120c27', '#0c0a14'], cy=14, r=24)
    W = D = 12
    Hh = 11
    cx, ty = 16, 4
    seam = 7.0
    fg = G()
    for y in range(N):
        for x in range(N):
            px, py = x + .5, y + .5
            u = px - cx
            c = None
            # top face
            v = 2 * (py - ty)
            X, Y = (u + v) / 2, (v - u) / 2
            if 0 <= X <= W and 0 <= Y <= D:
                edge = min(X, Y, W - X, D - Y) < 1.1
                c = '#5b3fd6' if edge else ('#b7a8ff' if X < 1.9 or Y < 1.9 else '#9a86ff')
                if not edge and int(Y) % 4 == 3:
                    c = '#8a74ff'
            else:
                # front-left face (Y = D)
                X = u + D
                Z = Hh - (py - ty - (X + D) / 2)
                if 0 <= X <= W and 0 <= Z <= Hh:
                    if abs(Z - seam) < .75:
                        c = OUT_C
                    elif X < 1 or X > W - 1 or Z < 1 or Z > Hh - 1:
                        c = '#3a2694'
                    else:
                        c = '#6a4fe6'
                    if 4.2 <= X <= 7.8 and 5.0 <= Z <= 9.6:
                        c = '#2b1608' if 5.3 <= X <= 6.7 and 6.2 <= Z <= 7.6 else '#f0b84f'
                        if X < 5 and Z > 8.3:
                            c = '#ffe39c'
                else:
                    Y = W - u
                    Z = Hh - (py - ty - (W + Y) / 2)
                    if 0 <= Y <= D and 0 <= Z <= Hh:
                        if abs(Z - seam) < .75:
                            c = OUT_C
                        elif Y < 1 or Y > D - 1 or Z < 1 or Z > Hh - 1:
                            c = '#2a1b72'
                        else:
                            c = '#4630b0'
            if c:
                fg.set(x, y, c)
    # outline
    pts = [(x, y) for y in range(N) for x in range(N) if fg.get(x, y) is None and any(
        fg.get(x + a, y + b) not in (None, hx(OUT_C)) for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    for x, y in pts:
        fg.set(x, y, OUT_C)
    # iso floor shadow
    for y in range(N):
        for x in range(N):
            u = x + .5 - cx
            v = 2 * (y + .5 - (ty + Hh + 1.5))
            X, Y = (u + v) / 2, (v - u) / 2
            if -1 <= X <= W + 1 and -1 <= Y <= D + 1:
                bg.blend(x, y, '#05040a', .5)
    return bg, fg


def v_dusk():
    sky = ['#0a0f2c', '#121338', '#1d1648', '#2a1a58', '#3d1f68', '#5a2774', '#7e3279', '#a6437c',
           '#cc5a78', '#e8786a', '#f2985c']
    bg = vertical(sky, 0, 22, 1.35)
    stars(bg, 22, 11, ymax=10, cols=('#8c86c4', '#ffffff'))
    for yy in range(-4, 5):  # setting sun
        for xx in range(-4, 5):
            d = xx * xx + yy * yy
            if d <= 18:
                bg.set(27 + xx, 16 + yy, '#fff2c4' if d < 7 else '#ffd27a')
    hills = [17, 17, 16, 16, 16, 15, 15, 16, 16, 17, 17, 17, 16, 16, 15, 15, 15, 16, 16, 16, 17, 17, 18, 18,
             17, 17, 16, 16, 16, 17, 17, 17]
    for x, h in enumerate(hills):
        bg.set(x, h, '#53359a')
        bg.rect(x, h + 1, 1, N - h - 1, '#3a2470')
    near = [21, 21, 20, 20, 20, 21, 21, 21, 20, 20, 20, 20, 21, 21, 21, 21, 20, 20, 20, 20, 21, 21, 21, 20,
            20, 20, 21, 21, 21, 20, 20, 21]
    for x, h in enumerate(near):
        bg.set(x, h, '#33276a')
        bg.rect(x, h + 1, 1, N - h - 1, '#241a4d')
    bg.rect(0, 25, N, 7, '#130f2e')
    bg.rect(0, 25, N, 1, '#2b6b3a')
    for tx in (2, 29):  # oak silhouettes
        bg.rect(tx, 21, 1, 4, '#0d0a22')
        bg.rect(tx - 2, 17, 5, 4, '#0d0a22')
        bg.rect(tx - 1, 16, 3, 1, '#0d0a22')
    fg = G()
    block = ['o' * 22, 'o' + 'G' * 20 + 'o', 'o' + 'gGGgGGGgGGgGGGgGGgGG' + 'o',
             'o' + 'dgddgdddgdddgddgdddg' + 'o']
    block += ['o' + ('dDdddDddDdddDdDdddDd' if i % 2 else 'DddDdddDddDdDdddDddd') + 'o' for i in range(7)]
    fg.sprite(block, dict(o=OUT_C, G='#6cbf3f', g='#4f9a2e', d='#5e3f2c', D='#74503a'), 5, 23)
    chest_m(fg, WOOD, 7, 9)
    return bg, fg


def v_java():
    bg = radial(['#3b2a7e', '#2c1f60', '#1f1644', '#160f2e', '#0f0d17'], cx=16, cy=17, r=24)
    fg = G()
    chest(fg, WOOD, 3, 10)
    handle = [
        'oooo..',
        'DDDDo.',
        'ooooDo',
        '...oDo',
        '...oDo',
        '...oDo',
        'ooooDo',
        'DDDDo.',
        'oooo..',
    ]
    fg.sprite(handle, dict(WOOD, D='#4a31b8'), 25, 14)
    # two hand-placed S-shaped wisps (left x of a 2px stroke, top to bottom)
    for xs, y0 in (([11, 10, 9, 9, 10, 11, 11, 10], 1), ([17, 18, 19, 19, 18, 17, 17, 18], 2)):
        for i, x in enumerate(xs):
            c = '#c9bcff' if i < 2 else '#ecedf3'
            fg.set(x, y0 + i, c)
            fg.set(x + 1, y0 + i, c)
    shadow(bg, 4, 28, 30)
    return bg, fg


def v_pickaxe():
    bg = radial(['#3b2a7e', '#2c1f60', '#1f1644', '#160f2e', '#0f0d17'], cy=14, r=24)
    fg = G()
    for i in range(4, 27):  # handle: top-left to bottom-right, behind the chest
        fg.set(i - 1, i, OUT_C)
        fg.set(i, i, '#a0683a')
        fg.set(i + 1, i, '#6e3d17')
        fg.set(i + 2, i, OUT_C)
    head = {}
    for s4 in range(-40, 41):  # head: arc perpendicular to the handle, tips curve toward the grip
        sv = s4 / 4
        bend = 0.05 * sv * sv
        x = 7.5 + sv * .7071 + bend * .7071
        y = 7.5 - sv * .7071 + bend * .7071
        ws = (-1, 0, 1) if abs(sv) < 5 else (0, 1) if abs(sv) < 8 else (0,)
        for w in ws:
            px, py = round(x - w * .7071), round(y - w * .7071)
            col = '#ffe39c' if w == -1 else '#f0b84f' if w == 0 else '#b9801c'
            if (px, py) not in head or w == 0:
                head[(px, py)] = col
    for (x, y) in list(head):
        for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (x + a, y + b) not in head:
                fg.set(x + a, y + b, OUT_C)
    for (x, y), c in head.items():
        fg.set(x, y, c)
    chest_m(fg, WOOD, 7, 14)
    shadow(bg, 8, 25, 29)
    return bg, fg


def v_shulker():
    bg = radial(['#26346e', '#1d2656', '#161b40', '#10122b', '#0b0c17'], cy=15, r=24)
    stars(bg, 12, 21, cols=('#6f7bc4', '#ffffff'), avoid=lambda x, y: 3 <= x <= 28 and 4 <= y <= 29)
    S = dict(o=OUT_C, H='#d6caff', L='#ab95ff', D='#4630b0', l='#9278ff', M='#7a5cf0', d='#5d40d0',
             e='#0b0816', E='#f0b84f', w='#ffffff')
    lid = [
        '..oooooooooooooooooooo..',
        '.oHHHHHHHHHHHHHHHHHHHHo.',
        'oHLLLLLLLLLLLLLLLLLLLLLo',
        'oLLLLLLLLLLLLLLLLLLLLLLo',
        'oDDDDDDDDDDDDDDDDDDDDDDo',
        'oDllllllllllllllllllllDo',
        'oDMMMMMMMMMMMMMMMMMMMMDo',
        'oDddddddddddddddddddddDo',
        'oDllllllllllllllllllllDo',
        'oDMMMMMMMMMMMMMMMMMMMMDo',
        'oDddddddddddddddddddddDo',
        'oooooooooooooooooooooooo',
    ]
    gap = [
        'oeeeeewEeeeeeewEeeeeeo',
        'oeeeeeEEeeeeeeEEeeeeeo',
    ]
    base = [
        'oooooooooooooooooooooo',
        'oDDDDDDDDDDDDDDDDDDDDo',
        'oDddddddddddddddddddDo',
        'oDMMMMMMMMMMMMMMMMMMDo',
        'oDMMMMMMMMMMMMMMMMMMDo',
        'oDddddddddddddddddddDo',
        'oDMMMMMMMMMMMMMMMMMMDo',
        'oDMMMMMMMMMMMMMMMMMMDo',
        'oDddddddddddddddddddDo',
        'oDDDDDDDDDDDDDDDDDDDDo',
        '.oooooooooooooooooooo.',
    ]
    fg = G()
    fg.sprite(base, S, 5, 18)
    fg.sprite(gap, S, 5, 16)
    fg.sprite(lid, S, 4, 4)
    shadow(bg, 6, 25, 29)
    return bg, fg


FLAT_SVG = '''<defs><linearGradient id="{id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7a5cff"/><stop offset="1" stop-color="#3f24b0"/></linearGradient></defs>
<rect width="1024" height="1024" fill="url(#{id})"/>
<path d="M212 444V362q0-110 110-110h380q110 0 110 110v82z" fill="#e4ddff"/>
<path d="M212 480h600v214q0 72-72 72H284q-72 0-72-72z" fill="#fff"/>
<rect x="212" y="444" width="600" height="36" fill="#2f1a8f" opacity=".55"/>
<rect x="444" y="388" width="136" height="156" rx="34" fill="#f0b84f"/>
<circle cx="512" cy="452" r="19" fill="#3a2694"/><rect x="502" y="458" width="20" height="44" rx="10" fill="#3a2694"/>'''

VARIANTS = [
    ('01', 'vanilla', 'Vanilla', 'Purple wood, gold latch. Closest to the block you know.', v_vanilla),
    ('02', 'ender', 'Ender', 'Obsidian-purple with a glowing teal eye latch.', v_ender),
    ('03', 'open', 'Open', 'Lid up, light pouring out, rays and sparkles.', v_open),
    ('04', 'enchanted', 'Enchanted', 'Vanilla chest with a diagonal glint shimmer.', v_enchanted),
    ('05', 'iso', 'Isometric', 'Three faces, 2:1 pixel iso, floor shadow.', v_iso),
    ('06', 'dusk', 'Dusk', 'On a grass block in the launcher dusk scene.', v_dusk),
    ('07', 'java', 'Java mug', 'Chest with a mug handle and steam. Java, literally.', v_java),
    ('08', 'pickaxe', 'Pickaxe', 'Gold pickaxe crossed behind a smaller chest.', v_pickaxe),
    ('09', 'flat', 'Flat', 'Minimal vector chest, iOS-clean, no pixels.', None),
    ('10', 'shulker', 'Shell box', 'Shulker-style shell, eyes peeking from the gap.', v_shulker),
]
TOP = ['01', '02', '03']


# ---------- output ----------
def png(path, grid, alpha=False):
    S = 1024 // N
    raw = bytearray()
    for row in grid.p:
        line = bytearray()
        for c in row:
            if alpha:
                px = bytes(c + (255,)) if c else b'\0\0\0\0'
            else:
                px = bytes(c)
            line += px * S
        raw += (b'\0' + line) * S
    ct = 6 if alpha else 2

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)

    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1024, 1024, 8, ct, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))


def svg_paths(grid):
    by = {}
    for y, row in enumerate(grid.p):
        x = 0
        while x < N:
            c = row[x]
            if c is None:
                x += 1
                continue
            s = x
            while x < N and row[x] == c:
                x += 1
            by.setdefault('%02x%02x%02x' % c, []).append('M%d %d.5h%d' % (s, y, x - s))
    return ''.join('<path stroke="#%s" d="%s"/>' % (k, ''.join(v)) for k, v in by.items())


def dark_bg():
    return radial(['#1a1530', '#131022', '#0e0c18', '#0a0910', '#07060b'], cy=15, r=24)


def tinted(fg):
    g = G()
    lum = {}
    for y in range(N):
        for x in range(N):
            c = fg.p[y][x]
            if c:
                lum[(x, y)] = .299 * c[0] + .587 * c[1] + .114 * c[2]
    hi = max(lum.values())
    for (x, y), l in lum.items():
        v = round(255 * (l / hi) ** .75)
        g.set(x, y, (v, v, v))
    return g


def main():
    data = {'icons': [], 'extras': {}}
    for num, slug, name, note, fn in VARIANTS:
        base = os.path.join(OUT, f'{num}-{slug}')
        if fn is None:
            data['icons'].append(dict(num=num, slug=slug, name=name, note=note, flat=True))
            continue
        bg, fg = fn()
        png(base + '.png', over(bg, fg))
        data['icons'].append(dict(num=num, slug=slug, name=name, note=note,
                                  bg=svg_paths(bg), fg=svg_paths(fg)))
        if num in TOP:
            png(base + '-background.png', bg)
            png(base + '-foreground.png', fg, alpha=True)
            png(base + '-dark.png', over(dark_bg(), fg))
            t = tinted(fg)
            png(base + '-tinted.png', over(G('#000000'), t))
            data['extras'][num] = dict(tint=svg_paths(t))
    data['darkbg'] = svg_paths(dark_bg())
    with open(os.path.join(HERE, 'flat.svg'), 'w') as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
                + FLAT_SVG.format(id='fbg') + '</svg>')
    data['flat'] = FLAT_SVG
    with open(os.path.join(HERE, 'icons.json'), 'w') as f:
        json.dump(data, f)


if __name__ == '__main__':
    main()
