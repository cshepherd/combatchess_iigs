#!/usr/bin/env python3
"""Render the Combat Chess character set from a RAM dump as a contact
sheet PNG: the 64 glyphs of the board character set, each drawn in
all four colour registers over the background, at the board's own
16 x 16 pixel cell size, integer-scaled.

The board (ANTIC mode 7) draws every glyph 16 pixels wide and 16
tall from an 8 x 8 bitmap, so the sheet doubles each bitmap pixel.
Colours come from the dump's COLOR0-4 shadows, looked up in the
256-entry palette of an atari800 screenshot (--palette): the
emulator's indexed PNGs store its whole Atari palette, so the Atari
colour byte is the palette index and the RGB is exactly what the
capture shows. Without --palette a rough hue/luminance approximation
is used, good enough to pick glyphs out.

Usage:
    python3 tools/atari_charset.py reference/raw/boards/board01_ram.dat OUT.png
                                   [--scale 2] [--palette reference/raw/boards/board02.png]
"""
import argparse
import colorsys
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from atari_shot import read_image  # noqa: E402

CHBASE_SHADOW, COLORS = 0x02F4, 0x02C4


def atari_rgb(code):
    """Rough NTSC Atari colour: hue nibble around the wheel, lum nibble."""
    hue, lum = code >> 4, code & 0x0F
    v = lum / 15.0
    if hue == 0:
        g = int(v * 255)
        return (g, g, g)
    h = ((hue - 1) * 22.5 + 30) % 360 / 360.0
    r, g, b = colorsys.hls_to_rgb(h, 0.15 + 0.6 * v, 0.9)
    return (int(r * 255), int(g * 255), int(b * 255))


def write_png(path, w, h, rows_rgb):
    raw = b"".join(b"\x00" + r for r in rows_rgb)

    def chunk(tag, body):
        c = struct.pack(">I", len(body)) + tag + body
        return c + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("output")
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--palette", help="an atari800 indexed PNG whose palette gives exact RGB")
    a = ap.parse_args()
    ram = open(a.dump, "rb").read()
    chbase = ram[CHBASE_SHADOW] << 8
    cols = ram[COLORS:COLORS + 5]
    if a.palette:
        pal = read_image(a.palette)[3]
        rgb = lambda code: tuple(pal[code])  # noqa: E731
    else:
        rgb = atari_rgb
    pf = [rgb(c) for c in cols[:4]]
    bg = rgb(cols[4])
    s = a.scale
    cell = 16 * s
    gap = 2 * s
    # 16 glyphs across, 4 rows of glyphs x 4 colour rows
    cols_n, rows_n = 16, 4
    w = cols_n * (cell + gap) + gap
    h = 4 * (rows_n * (cell + gap) + gap)
    img = [bytearray(bytes(bg) * w) for _ in range(h)]

    def put(x, y, rgb):
        img[y][x * 3:x * 3 + 3] = bytes(rgb)

    for colour in range(4):
        for g in range(64):
            bitmap = ram[chbase + g * 8: chbase + g * 8 + 8]
            gx = gap + (g % 16) * (cell + gap)
            gy = colour * (rows_n * (cell + gap) + gap) + gap + (g // 16) * (cell + gap)
            for by in range(8):
                for bx in range(8):
                    on = bitmap[by] & (0x80 >> bx)
                    rgb = pf[colour] if on else bg
                    for dy in range(2 * s):
                        for dx in range(2 * s):
                            put(gx + bx * 2 * s + dx, gy + by * 2 * s + dy, rgb)
    write_png(a.output, w, h, [bytes(r) for r in img])
    print(f"wrote {a.output}: charset at ${chbase:04X}, colours "
          + " ".join(f"${c:02X}" for c in cols)
          + "; rows of 16 glyphs ($00-$3F), one block per colour register 0-3")


if __name__ == "__main__":
    main()
