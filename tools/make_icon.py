#!/usr/bin/env python3
"""Generate the 1024x1024 app icon (plate + leaf) as an opaque PNG, pure Python."""
import math, struct, sys, zlib

S = 1024
def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
TOP, BOT = (64, 190, 120), (20, 120, 90)
PLATE, RIM, LEAF, VEIN = (255, 255, 255), (232, 245, 236), (46, 176, 107), (220, 245, 228)

def leaf_inside(x, y):
    # leaf = intersection of two circles, rotated 45 degrees, centered on plate
    cx, cy = S / 2, S / 2
    dx, dy = x - cx, y - cy
    a = math.radians(-45)
    u = dx * math.cos(a) - dy * math.sin(a)
    v = dx * math.sin(a) + dy * math.cos(a)
    r, off = 230, 150
    return (u ** 2 + (v - off) ** 2 < r * r) and (u ** 2 + (v + off) ** 2 < r * r), u, v

rows = []
for y in range(S):
    row = bytearray([0])
    for x in range(S):
        c = lerp(TOP, BOT, y / S)
        d = math.hypot(x - S / 2, y - S / 2)
        if d < 380:
            c = RIM if d > 330 else PLATE
            inside, u, v = leaf_inside(x, y)
            if inside:
                c = VEIN if abs(v) < 7 and abs(u) < 170 else LEAF
        elif d < 392:
            c = lerp(c, (255, 255, 255), 0.35)
        row += bytes(c)
    rows.append(bytes(row))

def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
