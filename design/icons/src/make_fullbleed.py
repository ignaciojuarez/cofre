"""Full-bleed Cofre icons: the chest front IS the icon (no scene behind it).

Reuses the pixel engine from make_icons.py. iOS masks the corners itself.
"""
import math, os, random
from make_icons import G, N, png, mix, WOOD, ENDER, OUT

OUTDIR = os.path.join(OUT, 'fullbleed')
SEAM = 12  # first seam row; lid above, body below


def face(pal, seed=3):
    """Chest front filling the whole 32x32 square."""
    g = G(pal['M'])
    r = random.Random(seed)
    for y in range(N):
        for x in range(N):
            if y in (SEAM, SEAM + 1):
                g.set(x, y, pal['o'])
            elif x in (0, N - 1) or y in (0, N - 1):
                g.set(x, y, pal['D'])
            elif x in (1, N - 2) or y in (SEAM - 1, SEAM + 2, N - 2):
                g.set(x, y, pal['d'])
    for y in (1, SEAM + 2):  # top bevels
        for x in range(1, N - 1):
            g.set(x, y, pal['H'] if y == 1 else pal['l'])
    for x in range(2, N - 2):
        g.set(x, 2, pal['L'])
    for _ in range(26):  # wood grain streaks
        y = r.choice([y for y in range(4, N - 3) if abs(y - SEAM - .5) > 3])
        x, w = r.randrange(3, N - 6), r.randrange(2, 5)
        for xx in range(x, x + w):
            g.set(xx, y, pal['g'])
    return g


def latch(g, pal, x0=13, y0=8, w=6, h=10, glow=False):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            edge = x in (x0, x0 + w - 1) or y in (y0, y0 + h - 1)
            corner = x in (x0, x0 + w - 1) and y in (y0, y0 + h - 1)
            if corner:
                continue
            if edge:
                g.set(x, y, pal['o'])
            elif y == y0 + 1 or x == x0 + 1:
                g.set(x, y, pal['W'])
            elif y == y0 + h - 2 or x == x0 + w - 2:
                g.set(x, y, pal['y'])
            else:
                g.set(x, y, pal['Y'])
    cx = x0 + w // 2 - 1
    for y in (y0 + 4, y0 + 5):  # keyhole (or eye)
        for x in (cx, cx + 1):
            g.set(x, y, pal['W'] if glow else pal['k'])


def f_vanilla():
    g = face(WOOD)
    latch(g, WOOD)
    return g


def f_ender():
    g = face(ENDER, seed=9)
    for x, y in [(6, 6), (24, 4), (5, 21), (26, 24), (10, 27), (21, 19)]:
        g.set(x, y, '#4a3590')
    for x in range(N):  # seam glows from the eye outward
        d = abs(x + .5 - 16)
        c = '#5ee6d0' if d < 6 else '#2fa89a' if d < 10 else '#1a5f5a'
        for y in (SEAM, SEAM + 1):
            g.set(x, y, c)
        if d < 9:
            g.blend(x, SEAM - 1, '#5ee6d0', .3)
            g.blend(x, SEAM + 2, '#5ee6d0', .3)
    latch(g, ENDER, glow=True)
    return g


def f_treasure():
    g = face(WOOD, seed=5)
    gold = dict(o=WOOD['o'], Y='#f0b84f', W='#ffe39c', y='#b9801c')
    for x0 in (5, 25):  # gold straps over lid and body
        for y in range(N):
            if y in (SEAM, SEAM + 1):
                continue
            g.set(x0, y, gold['W'])
            g.set(x0 + 1, y, gold['y'])
        for y in (4, 8, 18, 23, 28):  # rivets
            g.set(x0, y, '#fff2c4')
    latch(g, WOOD)
    return g


def f_enchanted():
    g = face(WOOD, seed=11)
    latch(g, WOOD)
    for y in range(N):
        for x in range(N):
            k = (x + y) % 14
            if k in (0, 1, 2):
                g.blend(x, y, '#d9ccff', .42 if k == 1 else .24)
    for x, y in [(6, 5), (25, 22), (8, 25)]:
        g.set(x, y, '#ffffff')
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            g.set(x + dx, y + dy, '#c9bcff')
    return g


def f_glow():
    g = face(WOOD, seed=13)
    for x in range(N):  # light leaking from the seam
        d = abs(x + .5 - 16)
        c = '#ffffff' if d < 5 else '#e4dcff' if d < 9 else '#b9a9ff' if d < 13 else '#8a74ff'
        for y in (SEAM, SEAM + 1):
            g.set(x, y, c)
        for y, t in ((SEAM - 1, .55), (SEAM - 2, .3), (SEAM - 3, .14), (SEAM + 2, .55), (SEAM + 3, .3), (SEAM + 4, .14)):
            g.blend(x, y, '#e4dcff', t * max(0, 1 - d / 14))
    latch(g, WOOD, y0=4, h=8)  # latch sits on the lid, lid is lifting
    for x, y in [(4, 5), (27, 7), (7, 26), (25, 25)]:
        g.set(x, y, '#ffffff')
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            g.set(x + dx, y + dy, '#c9bcff')
    return g


def f_shulker():
    pal = dict(WOOD, M='#6a4ad8', g='#5a3cc8')
    g = G(pal['M'])
    gap0, gap1 = 13, 17
    for y in range(N):
        for x in range(N):
            if gap0 <= y <= gap1:
                g.set(x, y, '#0d0a1c')
            elif x in (0, N - 1) or y in (0, N - 1, gap0 - 1, gap1 + 1):
                g.set(x, y, pal['D'])
    for y in (1, gap1 + 2):
        for x in range(1, N - 1):
            g.set(x, y, pal['H'] if y == 1 else pal['l'])
    for y in (5, 9, 23, 27):  # shell ridges
        for x in range(2, N - 2):
            g.set(x, y, pal['g'])
    for x in range(N):  # lid rim overhang
        g.set(x, gap0 - 1, pal['o'])
    for ex in (10, 19):  # eyes peeking from the gap
        g.rect(ex, 14, 3, 2, '#f0b84f')
        g.set(ex + 1, 14, '#fff2c4')
        g.set(ex + 2, 15, '#b9801c')
    return g


VARIANTS = [
    ('F1', 'vanilla', 'Vanilla', f_vanilla),
    ('F2', 'ender', 'Ender', f_ender),
    ('F3', 'treasure', 'Treasure straps', f_treasure),
    ('F4', 'enchanted', 'Enchanted', f_enchanted),
    ('F5', 'glow', 'Glowing seam', f_glow),
    ('F6', 'shulker', 'Shulker face', f_shulker),
]


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    for num, slug, _, fn in VARIANTS:
        png(os.path.join(OUTDIR, f'{num}-{slug}.png'), fn())


if __name__ == '__main__':
    main()
