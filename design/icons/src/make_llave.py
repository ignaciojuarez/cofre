"""Llave (Cofre's Mac pairing app) icon: a gold Cofre-latch key with a purple chest gem.

Same 32x32 engine and background as 01 Vanilla. Writes:
  llave/llave-square.png   1024 full-bleed (web, docs)
  llave/llave-macos.png    1024 macOS squircle with shadow (source for .icns)
"""
import os, struct, zlib
from make_icons import G, N, OUT, hx, mix, radial, over, shadow, spark, png, WOOD

OUTDIR = os.path.join(OUT, 'llave')
GOLD = dict(o='#150c30', W='#ffe39c', Y='#f0b84f', y='#b9801c', P=WOOD['M'], p=WOOD['L'], q=WOOD['D'])


def key():
    g = G()
    o, W, Y, y = (GOLD[k] for k in 'oWYy')
    # bow: 12x12 rounded ring at (3, 7)
    bx, by, S = 3, 7, 12
    for j in range(S):
        for i in range(S):
            corner = (i in (0, S - 1) and j in (0, 1, S - 2, S - 1)) or (j in (0, S - 1) and i in (0, 1, S - 2, S - 1))
            if corner:
                continue
            edge = i in (0, S - 1) or j in (0, S - 1) or (i in (1, S - 2) and j in (1, S - 2))
            hole = 3 <= i <= S - 4 and 3 <= j <= S - 4
            if edge:
                c = o
            elif hole:
                c = None
            elif i <= 2 and j <= 6 or j <= 2 and i <= 6:
                c = W
            elif i >= S - 3 or j >= S - 3:
                c = y
            else:
                c = Y
            g.set(bx + i, by + j, c)
    # purple chest gem in the bow's hole
    for j in range(3, S - 3):
        for i in range(3, S - 3):
            edge = i in (3, S - 4) or j in (3, S - 4)
            c = o if edge else GOLD['p'] if (i <= 5 and j <= 5) else GOLD['q'] if (i >= S - 6 and j >= S - 6) else GOLD['P']
            g.set(bx + i, by + j, c)
    g.set(bx + 5, by + 5, '#ffffff')
    # shaft: x 15..27, rows 11..14 (outline rows 11 and 14)
    for x in range(bx + S - 1, 28):
        g.set(x, 11, o)
        g.set(x, 12, W)
        g.set(x, 13, y)
        g.set(x, 14, o)
    for yy in range(11, 15):
        g.set(28, yy, o)
    # teeth
    for tx in (20, 25):
        for yy in range(14, 19):
            g.set(tx - 1, yy, o)
            g.set(tx + 2, yy, o)
        for yy in range(14, 18):
            g.set(tx, yy, Y)
            g.set(tx + 1, yy, y)
        g.set(tx, 18, o)
        g.set(tx + 1, 18, o)
    return g


def build():
    bg = radial(['#3b2a7e', '#2c1f60', '#1f1644', '#160f2e', '#0f0d17'], cy=15, r=24)
    k, sh = key(), G()
    for y in range(N - 3):
        sh.p[y + 3] = k.p[y][:]
    g = over(bg, sh)
    spark(g, 25, 5)
    spark(g, 6, 27, big=False)
    return g


def png_rgba(path, rows, w, h):
    raw = b''.join(b'\0' + bytes(v for px in r for v in px) for r in rows)

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)

    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def macos(path, g):
    """832px art (26px cells) on a 1024 canvas, squircle mask, soft drop shadow."""
    C, cell, off, R = 1024, 26, 96, 186
    size = cell * N

    half, cx, cy = size / 2, off + size / 2, off + size / 2

    def sdf(x, y, dy=0.0):  # signed distance to the rounded square (negative inside)
        qx = abs(x + .5 - cx) - (half - R)
        qy = abs(y + .5 - cy - dy) - (half - R)
        return (max(qx, 0) ** 2 + max(qy, 0) ** 2) ** .5 + min(max(qx, qy), 0) - R

    rows = []
    for y in range(C):
        r = []
        for x in range(C):
            d = sdf(x, y)
            a_in = min(1.0, max(0.0, .5 - d))
            ds = sdf(x, y, dy=10)
            a_sh = 0.38 * max(0.0, 1 - max(ds, 0) / 30) ** 2
            if a_in > 0:
                c = g.p[min(N - 1, max(0, int((y - off) // cell)))][min(N - 1, max(0, int((x - off) // cell)))]
                a = a_in + a_sh * (1 - a_in)
                r.append(tuple(round(v * a_in / a) for v in c) + (round(255 * a),))
            else:
                r.append((0, 0, 0, round(255 * a_sh)))
        rows.append(r)
    png_rgba(path, rows, C, C)


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    g = build()
    png(os.path.join(OUTDIR, 'llave-square.png'), g)
    macos(os.path.join(OUTDIR, 'llave-macos.png'), g)


if __name__ == '__main__':
    main()
