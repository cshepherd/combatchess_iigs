#!/usr/bin/env python3
"""Decode a Combat Chess board from an atari800 RAM dump taken at a
board's starting screen (tools/atari_drive.py, WRITE 0000 BFFF).

What the Atari game keeps in memory (found on board 1, checked on the
others as they were captured):

  $7A00  220 bytes  the screen: ANTIC mode 7, 20 x 11 characters,
                    one per board square. Bits 6-7 pick the colour
                    register (0 COLPF0, 1 COLPF1, 2 COLPF2, 3 COLPF3),
                    bits 0-5 the glyph. Units are drawn here in place
                    of their square's terrain.
  $5740  220 bytes  the terrain itself, same encoding, units absent.
  $9800  1 KB       the character set (CHBAS shadow $02F4 = $98).
  $02C4  5 bytes    COLOR0-3 and COLOR4 (background) shadows.

Terrain by (colour, glyph), natural boards:
  colour 0 glyph $00           clear ground (the background shows)
  colour 2 glyph $08           tree
  colour 1 any                 water (river-piece shapes)
  colour 3 $06 $07 $0E $0F     bridge
  colour 0 other               mountain (edge shapes, $28 solid)
Units (screen only): glyph $01 Battle Cruiser, $02 Tank, $03 Armored
Car; colour 3 Red, colour 0 Black.

Usage:
    python3 tools/atari_boards_decode.py reference/raw/boards/board01_ram.dat [--out reference/maps/board01.txt]
Prints the map in checklist notation, the unit list as start_units
lines, and the colour registers; --out writes just the 11 map rows.
"""
import argparse
import collections

SCREEN, TERRAIN, CHBASE, COLORS = 0x7A00, 0x5740, 0x9800, 0x02C4
BRIDGE_GLYPHS = {0x06, 0x07, 0x0E, 0x0F}
UNIT_GLYPHS = {1: "CLASS_CRUISER", 2: "CLASS_TANK", 3: "CLASS_CAR"}
UNIT_LETTER = {1: "C", 2: "T", 3: "A"}
SIDE = {3: "SIDE_RED", 0: "SIDE_BLACK"}

# Abstract boards 6-9 reuse the glyphs with other meanings, by board
# (--board N). (colour, glyph) -> checklist letter. Open squares are
# 'w' rather than '.' so the display can tell the two families apart;
# the engine treats them alike.
CORNERS = {(3, g): "w" for g in BRIDGE_GLYPHS}   # brown corner marks: passable
# Colour 2 glyph $0D is board 9's grey destructible square (every
# starting unit there stands on a plain square, never on one of these)
# and the same code sits inside board 6's black blocks, so it is read
# as destructible there too. UNVERIFIED how it is destroyed (spec 34).
MOUNTAIN_GLYPHS = {0x1A, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x28, 0x2A, 0x2B, 0x2C,
                   0x32, 0x33, 0x34, 0x35, 0x36, 0x37}
ABSTRACT = {
    6: {(0, 0x00): "w", (0, 0x28): "b", (2, 0x0D): "g", (1, 0x28): "p", **CORNERS},
    7: {(0, 0x00): "w", (0, 0x28): "b", (1, 0x28): "y"},
    8: {(0, 0x00): "w", (0, 0x28): "b", (1, 0x28): "y", (2, 0x28): "b"},   # colour 2 border = outside the arena
    9: {(0, 0x00): "w", (2, 0x0D): "g", (0, 0x28): "b", (1, 0x28): "p"},
    # Board 10 is board 1 at night: mountains and bridges drawn in colour 2.
    10: {**{(2, g): "M" for g in MOUNTAIN_GLYPHS}, **{(2, g): "=" for g in BRIDGE_GLYPHS}},
}


def terrain_symbol(code, abstract=None):
    colour, glyph = code >> 6, code & 0x3F
    if abstract and (colour, glyph) in abstract:
        return abstract[(colour, glyph)]
    if code == 0x00:
        return "."
    if glyph in BRIDGE_GLYPHS:
        return "="                    # colour 3 on board 1, colour 0 on board 2
    if colour == 2 and glyph == 0x08:
        return "T"
    if colour == 1:
        return "~"
    if colour == 0 and glyph not in UNIT_GLYPHS:
        return "M"
    return "?"


def decode(path, abstract=None):
    ram = open(path, "rb").read()
    screen = ram[SCREEN:SCREEN + 220]
    terrain = ram[TERRAIN:TERRAIN + 220]
    rows = ["".join(terrain_symbol(terrain[y * 20 + x], abstract) for x in range(20)) for y in range(11)]
    units = []
    for i, code in enumerate(screen):
        colour, glyph = code >> 6, code & 0x3F
        if glyph in UNIT_GLYPHS and colour in SIDE:
            units.append((SIDE[colour], UNIT_GLYPHS[glyph], i % 20, i // 20))
    # differences between screen and terrain that are not units: worth a look
    odd = [(i % 20, i // 20, screen[i], terrain[i]) for i in range(220)
           if screen[i] != terrain[i] and (screen[i] & 0x3F) not in UNIT_GLYPHS]
    colours = ram[COLORS:COLORS + 5]
    codes = collections.Counter(terrain)
    return rows, units, odd, colours, codes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--out")
    ap.add_argument("--board", type=int, help="board number: 6-10 have their own tables")
    a = ap.parse_args()
    rows, units, odd, colours, codes = decode(a.dump, ABSTRACT.get(a.board))
    print("\n".join(rows))
    print()
    print("* side, class, x, y")
    for side, cls, x, y in units:
        print(f" dfb {side},{cls},{x},{y}")
    print(f"\n{len(units)} units; terrain codes used:",
          " ".join(f"{c >> 6}:{c & 0x3F:02X}x{n}" for c, n in sorted(codes.items())))
    print("COLOR0-3, COLOR4(background):", " ".join(f"${b:02X}" for b in colours))
    if odd:
        print("screen differs from terrain at non-unit squares:", odd)
    if a.out:
        open(a.out, "w").write("\n".join(rows) + "\n")
        units_path = a.out.rsplit(".", 1)[0] + "_units.txt"
        with open(units_path, "w") as f:
            f.write("# side class x y (checklist section 16: units kept apart from terrain)\n")
            for side, cls, x, y in units:
                f.write(f"{side} {cls} {x} {y}\n")
        print("wrote", a.out, "and", units_path)


if __name__ == "__main__":
    main()
