# Capture session log

Companion to `combat_chess_visual_capture_checklist.md`. Fill in as the
session runs; every capture in `reference/raw/` should be traceable to
an entry here.

## Setup (session of 2026-09-08)

| Item | Value |
|---|---|
| Emulator | atari800 7.1.2 (Homebrew), SDL2, libpng screenshots |
| Machine | Atari 800 XL, 64 KB (`-xl -nobasic`) |
| OS ROM | Real XL OS, `~/rom/ATARIXL.ROM` (atari800 fetched it on first run) |
| Video | NTSC (`-ntsc -ntsc-artif none -scanlines 0`), 672x480 window, no filtering |
| Palette preset | atari800 default NTSC palette; the indexed PNGs carry all 256 entries |
| Game image | `reference/atari/combat_chess.atr` (92176 bytes, user-supplied) |
| Driver | `tools/atari_drive.py` (pty monitor + posted key events), `tools/atari_boards_capture.py` |

Screenshots are the emulator's own F10 captures, indexed PNG, 336 x 224,
uncropped; the palette index of every pixel is the Atari colour byte.

## Screens and memory (from the running game)

| Screen | Display list | Screen memory | Notes |
|---|---|---|---|
| Title | $7300 | $7200 mode 7 (6 lines), $4E00 mode 2 (12 lines) | START game, OPTION options, SELECT demo |
| Options | $6421 | $7C00 mode 2, 24 lines | OPTION moves the cursor, SELECT changes, START returns to the title |
| Game | $2180 | $7A00 mode 7, 11 lines of 20; $1FB0 mode 2, 2 lines | board + two status lines |

Board geometry: the board is ANTIC mode 7, 20 x 11 characters of
16 x 16 pixels, starting after 3 x 8 blank scanlines. One screen byte
per square: bits 6-7 pick COLPF0-3, bits 0-5 the glyph in the
character set at $9800. The game's own terrain table is the same 220
bytes at $5740 with no units in it; units appear only on the screen
as glyphs $01 cruiser, $02 tank, $03 car, colour 3 Red, colour 0
Black. `tools/atari_boards_decode.py` turns a RAM dump into the map
and the starting positions, so no pixel sampling is needed.

## Terrain by (colour register, glyph)

Natural boards (see `reference/palette/natural.txt` for the colours):

| Colour | Glyph | Terrain / symbol |
|---|---|---|
| 0 | $00 | `.` clear (background shows through) |
| 2 | $08 | `T` tree |
| 1 | any | `~` water (river-piece shapes $30-$3F, solid $28 on board 2) |
| 3 or 0 | $06 $07 $0E $0F | `=` bridge (colour 3 on board 1, colour 0 on board 2) |
| 0 | other | `M` mountain (solid $28 plus edge shapes) |

Abstract boards (grey background $0A; the register colours change
per board, so the glyph is what identifies the terrain):

| Board | Colour | Glyph | Terrain / symbol |
|---|---|---|---|
| 6-9 | 0 | $00 | `w` open square (plain grey) |
| 6 | 0 | $28 | `b` black block |
| 6 | 2 | $0D | `b` green stripe glyph inside the black blocks (decoration) |
| 6 | 1 ($56) | $28 | `p` purple centre block: fire across, no movement |
| 6 | 3 ($34) | $06 $07 $0E $0F | `w` brown corner marks at the diagonal touching points between blocks: passable |
| 7-8 | 0 | $28 | `b` the black arms of the cross |
| 7-8 | 1 ($1A) | $28 | `y` the yellow centre |

| 6, 9 | 2 ($C6 / $06) | $0D | `g` grey destructible square: board 9's dark checker squares (no starting unit ever stands on one) and the striped cells inside board 6's blocks, which share the code |
| 8 | 2 ($72) | $28 | `b` the blue-violet ring outside board 8's arena |
| 9 | 1 ($54) | $28 | `p` purple pairs down the centre column |
| 10 | 2 ($02) | mountain / bridge glyphs | `M` / `=`: board 10 draws board 1's mountains and bridges in colour 2 (night) |

Board 6 is fifteen blocks in a 5 x 3 grid: 4 columns wide, and 4, 3
and 4 rows tall from top to bottom; open and black alternate with the
purple centre in the middle. Board 7 is a 2 x 2 yellow centre with
black arms two squares wide and two or three squares long on an
otherwise open field. Board 8 is an open field ringed by a solid
border with a plain black cross and no yellow centre. Board 9 is a
full checkerboard of open and grey squares with purple pairs at
(9-10, 2), (9-10, 4), (9-10, 6) and (9-10, 8); it has no black
squares at the start. Board 10's terrain is identical to board 1's
(`diff` of the two maps is empty) but its starting positions differ.

## Captures

All in `reference/raw/boards/` from `tools/atari_boards_capture.py`,
each board at its untouched start with the default armies:

| Files | Checklist item |
|---|---|
| `boardNN.png` (indexed PNG, 336 x 224) | 5: full board screenshot, boards 1-10 |
| `boardNN_codes.txt` | 5: every terrain cell transcribed (raw codes) |
| `boardNN_ram.dat` | whole RAM at the start, for anything else later |
| `reference/maps/boardNN.txt` | 16: 20 x 11 map in the text notation |
| `reference/maps/boardNN_units.txt` | 16: unit placement layer |
| `reference/crops/terrain/charset_board1.png` | 6, 8: every glyph in all four colours |
| `reference/palette/natural.txt` and `boards_capture.json` | 12: colour registers per board |

Still to capture (checklist sections A-C, 9-11, 13): title states,
the options screen fields and ranges, both status displays, cursor
states, HUD extremes, firing and destruction effects, typography.

## Starting positions

`reference/maps/boardNN_units.txt`, generated into `src/boards.s`.
Every board starts with the default armies from the options screen:
Red 1 cruiser, 2 tanks, 4 armored cars; Black 1 cruiser, 3 tanks,
5 armored cars (16 units). Red starts on the left on boards 1, 2,
4-10 and on the right on board 3. Board 10 starts both armies near
the middle-left (Black around x 13-14), unlike board 1.

## Open questions resolved

Spec section 34 items settled or narrowed by this session:

- **Exact initial piece placement on all ten boards**: captured
  (default armies). Placement for other army sizes not yet captured.
- **Exact selectable army compositions**: the options screen's
  defaults are Red 2 tanks 4 cars, Black 3 tanks 5 cars, so Red can
  field at least 4 armored cars; spec section 6's "Red up to 3
  armored cars" is wrong or incomplete. The full SELECT ranges of
  each field still need cycling and reading.
- **Board 9 grey squares**: they are the dark checker squares, half
  the board; how they are destroyed is still open, as is whether
  board 6's striped block cells (same code) are destructible.
- **Board 10 is mechanically board 1**: confirmed for terrain; the
  starting positions differ.
- **Options screen** (checklist B): 24 lines of text at $7C00; OPTION
  moves the cursor, SELECT changes the field, START returns to the
  title, START again begins the game. Fields: GAME BOARD, TANKS
  (Black, Red), ARMORED CARS (Black, Red), who starts first, computer
  side, time limits (Black, Red, minutes), MOVES PER TURN, SHOOT
  OPTION.
- **Status line** (checklist H): two lines of 40 columns at $1FB0:
  `MM:SS # SQ=15, GM=30, AM=16, FL=240` for Red (`#`) and `_` for
  Black, matching spec section 25.
