#!/usr/bin/env python3
"""Work with atari800 screenshots for the board capture
(combat_chess_visual_capture_checklist.md).

atari800 saves screenshots with F10 as indexed-colour PNG when built
with libpng (this Homebrew build) or as PCX otherwise. Both keep the
exact palette index of every pixel, which is what we want: terrain can
be classified by index instead of by fuzzy RGB, and the archival copy
is written from the same data with no resampling.

Commands:
    convert  IN OUT.png [--scale N]
        Lossless RGB PNG of the capture, optionally integer-scaled
        (nearest neighbour) for viewing. Also prints the palette
        entries actually used and how many pixels use each.

    palette  IN
        The palette entries in use, as index, RGB and pixel count.

    grid     IN --origin X,Y --cell W,H [--cols 20 --rows 11]
             [--map file] [--out board.txt]
        Sample every cell of a 20 x 11 board whose top-left pixel is
        at X,Y with cells W x H pixels. Prints the dominant palette
        index per cell as a table. With --map, a file of lines
        "INDEX SYMBOL" (e.g. "196 ." or "212 T") turns indices into
        the checklist's map letters and --out writes the 11-row text
        map board_load_text reads. Cells with an unmapped index are
        written as '?'.

    cell     IN --origin X,Y --cell W,H --at CX,CY
        Dump one cell's pixels as palette indices, for telling apart
        terrain from a unit sprite or cursor sitting on it.

No third-party modules: PCX and PNG are decoded and PNG encoded here.
"""
import argparse
import collections
import struct
import sys
import zlib


def read_pcx(data):
    version, encoding, bpp = data[1], data[2], data[3]
    xmin, ymin, xmax, ymax = struct.unpack_from("<4H", data, 4)
    planes = data[65]
    bpl = struct.unpack_from("<H", data, 66)[0]
    if bpp != 8 or planes != 1 or encoding != 1:
        raise SystemExit(f"expected 8-bit single-plane RLE PCX, "
                         f"got {bpp} bpp x {planes} planes, encoding {encoding}")
    w, h = xmax - xmin + 1, ymax - ymin + 1
    if data[-769] != 0x0C:
        raise SystemExit("PCX has no 256-colour palette")
    pal = [tuple(data[-768 + i * 3:-768 + i * 3 + 3]) for i in range(256)]
    pixels = []
    pos = 128
    for _ in range(h):
        row = bytearray()
        while len(row) < bpl:
            b = data[pos]
            pos += 1
            if b >= 0xC0:
                n = b & 0x3F
                v = data[pos]
                pos += 1
                row += bytes([v]) * n
            else:
                row.append(b)
        pixels.append(bytes(row[:w]))
    return w, h, pixels, pal


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(data):
    """Indexed (type 3) or RGB (type 2) 8-bit PNG -> (w, h, rows of
    palette indices, palette). RGB images get a palette built from
    their distinct colours."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("not a PNG file")
    pos = 8
    idat = b""
    pal = None
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        if tag == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace or ctype not in (2, 3):
                raise SystemExit(f"unsupported PNG: depth {depth}, type {ctype}, interlace {interlace}")
        elif tag == b"PLTE":
            pal = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
        pos += 12 + n
    raw = zlib.decompress(idat)
    bpp = 1 if ctype == 3 else 3
    stride = w * bpp
    rows = []
    prev = bytearray(stride)
    p = 0
    for _ in range(h):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                line[i] = (line[i] + _paeth(a, b, c)) & 255
        rows.append(bytes(line))
        prev = line
    if ctype == 3:
        pal = (pal or []) + [(0, 0, 0)] * (256 - len(pal or []))
        return w, h, rows, pal
    colours = {}
    pixels = []
    for line in rows:
        out = bytearray()
        for i in range(0, stride, 3):
            rgb = tuple(line[i:i + 3])
            if rgb not in colours:
                if len(colours) == 256:
                    raise SystemExit("RGB PNG has more than 256 colours")
                colours[rgb] = len(colours)
            out.append(colours[rgb])
        pixels.append(bytes(out))
    pal = [None] * 256
    for rgb, i in colours.items():
        pal[i] = rgb
    pal = [c or (0, 0, 0) for c in pal]
    return w, h, pixels, pal


def read_image(path):
    data = open(path, "rb").read()
    if data[:1] == b"\x0A":
        return read_pcx(data)
    return read_png(data)


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


def used_palette(pixels, pal):
    counts = collections.Counter()
    for row in pixels:
        counts.update(row)
    return [(i, pal[i], n) for i, n in sorted(counts.items())]


def cmd_convert(a):
    w, h, pixels, pal = read_image(a.input)
    s = a.scale
    rows = []
    for row in pixels:
        line = b"".join(bytes(pal[v]) * s for v in row)
        rows.extend([line] * s)
    write_png(a.output, w * s, h * s, rows)
    print(f"{a.input}: {w}x{h}, wrote {a.output} at {s}x")
    for i, rgb, n in used_palette(pixels, pal):
        print(f"  index {i:3d}  rgb {rgb[0]:3d},{rgb[1]:3d},{rgb[2]:3d}  pixels {n}")


def cmd_palette(a):
    w, h, pixels, pal = read_image(a.input)
    for i, rgb, n in used_palette(pixels, pal):
        print(f"{i:3d} {rgb[0]:3d},{rgb[1]:3d},{rgb[2]:3d} {n}")


def parse_pair(s):
    x, y = s.split(",")
    return int(x), int(y)


def cell_indices(pixels, ox, oy, cw, ch, cx, cy):
    x0, y0 = ox + cx * cw, oy + cy * ch
    return [pixels[y][x0:x0 + cw] for y in range(y0, y0 + ch)]


def cmd_grid(a):
    w, h, pixels, pal = read_image(a.input)
    ox, oy = parse_pair(a.origin)
    cw, ch = parse_pair(a.cell)
    if ox + a.cols * cw > w or oy + a.rows * ch > h:
        raise SystemExit("grid runs off the image")
    mapping = {}
    if a.map:
        for line in open(a.map):
            line = line.split("#")[0].strip()
            if line:
                idx, sym = line.split()
                mapping[int(idx)] = sym
    table = []
    for cy in range(a.rows):
        row = []
        for cx in range(a.cols):
            counts = collections.Counter()
            for r in cell_indices(pixels, ox, oy, cw, ch, cx, cy):
                counts.update(r)
            row.append(counts.most_common(1)[0][0])
        table.append(row)
    print("dominant palette index per cell:")
    for row in table:
        print(" ".join(f"{v:3d}" for v in row))
    if mapping:
        text = ["".join(mapping.get(v, "?") for v in row) for row in table]
        print("\nmap:")
        print("\n".join(text))
        if a.out:
            open(a.out, "w").write("\n".join(text) + "\n")
            print(f"wrote {a.out}")


def cmd_cell(a):
    w, h, pixels, pal = read_image(a.input)
    ox, oy = parse_pair(a.origin)
    cw, ch = parse_pair(a.cell)
    cx, cy = parse_pair(a.at)
    for r in cell_indices(pixels, ox, oy, cw, ch, cx, cy):
        print(" ".join(f"{v:3d}" for v in r))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("convert")
    c.add_argument("input")
    c.add_argument("output")
    c.add_argument("--scale", type=int, default=1)
    c.set_defaults(fn=cmd_convert)
    p = sub.add_parser("palette")
    p.add_argument("input")
    p.set_defaults(fn=cmd_palette)
    g = sub.add_parser("grid")
    g.add_argument("input")
    g.add_argument("--origin", required=True)
    g.add_argument("--cell", required=True)
    g.add_argument("--cols", type=int, default=20)
    g.add_argument("--rows", type=int, default=11)
    g.add_argument("--map")
    g.add_argument("--out")
    g.set_defaults(fn=cmd_grid)
    d = sub.add_parser("cell")
    d.add_argument("input")
    d.add_argument("--origin", required=True)
    d.add_argument("--cell", required=True)
    d.add_argument("--at", required=True)
    d.set_defaults(fn=cmd_cell)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
