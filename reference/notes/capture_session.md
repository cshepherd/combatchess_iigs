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
| Status | $4409 | $7D2C mode 7, 5 lines of 20 (the picture); $7D90 mode 2, 12 lines (the roster); $1FB0 mode 2, 2 lines | SELECT from the game: the side to move, SELECT again the opponent, SELECT again the board; character set $9A00 |

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
| `boardNN_codes.txt` | 5, 16: the terrain table ($5740, no units) as raw codes; the IIGS look table (`board_art.s`) comes from these, so a cell a unit started on shows its terrain once the unit leaves, not a ghost of the unit |
| `boardNN_ram.dat` | whole RAM at the start, for anything else later |
| `reference/maps/boardNN.txt` | 16: 20 x 11 map in the text notation |
| `reference/maps/boardNN_units.txt` | 16: unit placement layer |
| `reference/crops/terrain/charset_board1.png` | 6, 8: every glyph in all four colours |
| `board_charset.bin` | 6, 8: the 1 KB character set from $9800, identical on all ten boards; `tools/gen_board_art.py` turns it and the codes files into the IIGS board art |
| `reference/palette/natural.txt` and `boards_capture.json` | 12: colour registers per board |

Title (checklist A01) and options (B): `reference/raw/title/`
holds `title.png`, the plaque's 120 mode-7 codes
(`title_plaque.bin`), the character set they use (`title_charset.bin`,
from $7000), colours (`title_info.json`: COLBK $0C grey, COLPF0 $36
hull brown, COLPF1/2 $1C yellow, COLPF3 $76 plaque blue) and the
twelve text lines (`title_text.txt`). `options_ranges.md` and
`.json` list every option field in cursor order with the full SELECT
cycle of each. `tools/gen_title_art.py` turns the plaque into the IIGS
title bitmap.

Status screens (checklist C01, C02): `reference/raw/status/` holds
`status_own.png` and `status_other.png` with their display lists,
colour registers and screen memory (`status_own.json`,
`status_other.json`, `status_own_mode7_7D2C.bin`, and the character
set at $9A00 as `status_charset.bin`), from
`tools/atari_status_capture.py`. The picture is five mode-7 rows: a
tank in COLPF0 ($34 hull brown for Red, $00 for Black) and the word
STATUS in COLPF3 $58 purple on the grey background $0A. The roster is
twelve 40-column text rows (the `.bin` files stop after 340 bytes, so
the text is read from the RAM dump at $7D90):

```
 **STATUS FOR RED    FUEL AMMO GAME SQR
                                DMG DMG
 BATTLE CRUISER       240  16    30  15
 TANK                 240  16    24  12
 TANK                 240  16    24  12
 TANK
 ARMOURED CAR         160  08    18  09
 ARMOURED CAR         160  08    18  09
 ARMOURED CAR         160  08    18  09
 ARMOURED CAR         160  08    18  09
 ARMOURED CAR
```

Nine fixed rows in class order; a unit the army does not have leaves
its name alone (Red's default army has two tanks and four cars).
Two-digit values carry a leading zero. The spelling is ARMOURED here
and ARMORED on the options screen. The game's two HUD lines stay at
the bottom, and the clock runs while the screen is shown
(`status_own_5s.json` was read after a five-second pause following
`status_own.json`, each read taking a moment: the clock went from
19:55 to 19:48).

Destroyed unit (checklist C, spec 28): `status_destroyed_red.*` and
`status_destroyed_black.*` (PNG, JSON, mode-7 codes; the RAM dumps
stay git-ignored), from `tools/atari_destroyed_capture.py`, which sets
COMPUTER WILL PLAY BOTH and polls the board until a roster row goes
bare, then `status_destroyed_board.png` and `status_destroyed_log.txt`.
Red had lost an armoured car:

```
 **STATUS FOR RED    FUEL AMMO GAME SQR
                                DMG DMG
 BATTLE CRUISER       224  15    30  15
 TANK                 202  16    24  12
 TANK                 162  15    16  04
 TANK
 ARMOURED CAR         141  08    18  09
 ARMOURED CAR         139  08    14  05
 ARMOURED CAR         038  01    14  05
 ARMOURED CAR
 ARMOURED CAR
```

A destroyed unit's row looks exactly like a unit the army never had:
the game deletes its 16-byte record and closes the gap (Red's table at
$5600 holds six records, the dead car's mask bit $08 is gone and the
later records have moved up), so the survivors of each class fill the
first rows and the bare names follow. Two earlier runs showed the same
for a destroyed Red tank and a destroyed Black tank. The board
screenshot has a brown burst about two squares across over the
squares where the car stood: a player/missile shape (SDMCTL is $2E,
players and missiles on, and the screen memory under it is ordinary
terrain), presumably the destruction effect, still showing several
seconds later. The trees at (2, 1) and (3, 2) there had just become
clear squares.

## Cursor states (checklist section 9)

`reference/raw/cursor/` from `tools/atari_cursor_capture.py`, which
plays Red by hand: `cursor_sNN_*.png` walk the states with one stick
push per step, `cursor_uNN_*.png` show the terrain the HUD names, and
`cursor_states.json` / `cursor_terrain.json` record the display list,
the player/missile colour shadows and the sprite shapes for each.

The cursor is drawn with player/missile sprites, not the character
set. PMBASE is $4000 (double-line resolution): missiles at $4180,
players 0-3 at $4200, $4280, $4300, $4380. Two are used:

- **Player 0** the box, `FF 81 81 81 81 81 81 81 81 81 81 FF` (an
  8-wide hollow rectangle, 12 double-lines tall = one square), in
  COLPM0 `$1C` yellow-green.
- **Player 1** a white (COLPM1 `$0E`) inner shape that changes with
  the state: a cross `0C 0C 3F 3F 0C 0C` while the cursor roams free,
  gone once a friendly unit is triggered (the box alone), and a small
  block `1E 1E 1E` after a trigger on a destination or target.

So the three states are box + white cross (neutral / choosing a
unit), box alone (a unit is chosen, choosing where), box + white mark
(a square is triggered). This is looser than spec 26's "no cursor /
box / cross"; the box is always shown and the white shape inside is
what changes. How the game moves from the box state to a committed
move or shot is UNVERIFIED: triggering an empty square in range did
not visibly move the unit in these runs.

The lower HUD's unit line doubles as a terrain readout: over an empty
square it names the terrain and its hit points instead of a unit,
`TREE      = 01`, `BRIDGE    = 15`, water `OK TO SHOOT ACROSS`, an
out-of-reach square `IMPASSABLE`, and clear ground or mountains just
the clock with no text. (For later HUD/terrain work; checklist H10.)

ESC suspends the game to a `GAME SUSPENDED / PUSH ANY KEY TO
CONTINUE` screen (display list $2B15, `cursor_s13_esc.png`); the game
message table sits in RAM near $8B00 (`ARE YOU SURE YOU WANT TO END
THE GAME BY CAPITULATION?`, etc.).

Driving the joystick: atari800's keyboard joystick is off by default;
run it with `-nojoystick -kbdjoy0`, and post the keypad keys (KP8/2/4/6
directions, Right Ctrl trigger) with the numeric-pad event flag
(`NUMPAD_FLAG` in `tools/atari_drive.py`) or macOS routes them
elsewhere. The stick auto-repeats while held, so a capture uses one
short push per step. The cursor's board index is the byte at $00BC.

Still to capture (checklist A02-A06, 11, 13): title blink or
colour-cycle states and the demonstration game, HUD extremes, the
firing effect and the destruction effect's timing, typography.

## Unit records

The game keeps one 16-byte record per unit, Black's nine at $5500 and
Red's at $5600, in roster order (cruiser, tanks, cars; unused slots
zero). Located by searching a status-screen RAM dump for the roster's
fuel values, then read against the board 1 start dump
(`reference/raw/boards/board01_ram.dat`):

| Offset | Field | Start values |
|---|---|---|
| +0 | screen code of the unit's glyph (colour in bits 6-7: $01-$03 Black, $C1-$C3 Red) | |
| +1 | position as an offset into the 220-byte board, row x 20 + x | Black cruiser $C7 = (19, 9) |
| +2 | fuel | $F0 240, cars $A0 160 |
| +3 | ammo | $10 16, cars $08 8 |
| +4 | square hit points (the roster's SQR DMG) | $0F 15, $0C 12, $09 9 |
| +5 | unit hit points (GAME DMG) | $1E 30, $18 24, $12 18 |
| +6, +7 | zero at the start; $01 or $04 seen later on units that had been hit (UNVERIFIED use) | |
| +8 | this unit's bit in a two-byte mask: $01-$20 for slots 0-5, $81/$82/$84 for slots 6-8 (bit 7 selects the second byte); presumably the spec 13 fired-at bookkeeping | |
| +9 | class weight: cruiser $0C, tank $04, car $01 (UNVERIFIED meaning, likely the AI's valuation) | |
| +10..+12 | zero at the start; later a byte, a board offset and a small number on units that have acted (UNVERIFIED, likely the AI's last target or move) | |
| +13..+15 | zero | |

Seen while the computer played both sides (run of
`tools/atari_destroyed_capture.py`, board 1, default armies):

- Destroyed trees become clear squares: the board cell goes from
  colour 2 glyph $08 to colour 0 glyph $00 and the game's own terrain
  table at $5740 is updated to match, so the table always holds the
  current terrain.
- A unit's SQR DMG drops with its GAME DMG under fire (a tank at GAME
  16, SQR 04 after two 4-point hits from 24/12), as spec 23 says.
- Fuel is zero-padded to three digits on the status screen (`061`),
  as the other columns are to two.
- A unit's glyph can be missing from the board's screen memory for
  several seconds while it is still alive (the cursor or the move
  animation covers it), so counting glyphs does not detect a loss; the
  roster does.
- With the computer playing both sides the two HUD lines show only the
  clocks (`18:29` / `18:23`), no unit figures, and SELECT still opens
  the status screens.

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
- **Exact selectable army compositions**: cycled with SELECT
  (`options_ranges.md`). Both sides' tanks run 0-3 and both sides'
  armored cars 0-5; the defaults are Red 2 tanks 4 cars, Black 3
  tanks 5 cars. Spec section 6 (Red 3/3, Black 5/5 from the manual)
  is wrong on both counts. The cursor order is board, Black tanks,
  Red tanks, Black cars, Red cars, who starts, computer side, Black
  time, Red time, moves per turn, Shoot Option; every field wraps.
  Time limits are 1-30 minutes per side and are set separately for
  Black and Red; moves per turn 1-20; the computer field cycles
  BLACK, RED, "WILL NOT PLAY", BOTH. Where units go for army sizes
  other than the defaults is still uncaptured.
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
- **Timer behaviour during status screens** (spec 34): the clocks keep
  running; the side to move's clock read 19:55 on entering the
  status screen and 19:48 about seven seconds later.
- **Status display** (spec 28): nine fixed roster rows, name alone for
  a unit the army lacks, `FUEL AMMO GAME SQR / DMG DMG` heads, the
  tank in the picture coloured by side, both HUD lines kept.
- **Status roster for a destroyed unit** (spec 28): the name alone, as
  for a unit the army never had, with the class's survivors listed
  first: the unit record is deleted and the table compacted.
- **Destroyed trees** (spec 34): become clear squares, and the game's
  terrain table at $5740 is updated to match. Square hit points live
  in the unit record (+4) and drop with the unit's own, as spec 23
  says; the roster's SQR DMG column shows them.
- **Destruction effect**: a brown player/missile burst about two
  squares across, drawn over the square where the unit died.
- **Status line** (checklist H): two lines of 40 columns at $1FB0,
  one per side (two clocks, not one line per cursor as spec 25 reads
  the manual): `  19:55 #  SQ=15, GM=30, AM=16, FL=240` for Red with
  `#` on the side to move and `_` on the other, the clock at column
  2, the marker at 8, SQ GM AM FL at 11, 18, 25, 32. Black text on a
  grey strip (COLPF2 $08, painted by the display list interrupt on
  the last board row), and the border below the strip is brown
  ($36). With the computer playing both sides the lines show only
  the clocks.
