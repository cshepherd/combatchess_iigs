# Combat Chess IIGS

Port of *Combat Chess* (Atari 8-bit, Avalon Hill 1984) to the Apple IIGS in 65816 assembly (Merlin32). The rules specification is `combat_chess_iigs_spec-3.md`; treat it as the source of truth for game logic and follow its milestones in order. `combat_chess_visual_capture_checklist.md` governs the `reference/` archive.

## Build

```
make package   # out/combatchess.po
make clean
```

Dependencies: `merlin32`, `cadius`, `python3`. Build shape mirrors `../ddiigs`: one merlin32 rule per part, staged copies named `NAME#TTAAAA` so cadius assigns ProDOS type and aux type, all cadius calls through `tools/cadius_strict.sh`.

Adding a part: create `src/NAME.s` with `ORG $2000`, add `NAME` to `PARTS` in the Makefile, add a `cp`/`ADDFILE`/`rm` triple in the package step, and add a jump-table entry in `src/cc.s` if other parts need to chain to it.

## Testing in KEGS

`tools/kegs_run.sh -dbgport 6520` boots the image halted with the debug socket open (6510 is often taken by a ddiigs session). `tools/kegs_dbg.py` is the socket client; `tools/kegs_screenshot.py NAME --port 6520` renders the SHR screen to `NAME.png` and prints registers. Resume past a key-wait loop by `k.cmd("00/ADDRg")` with the address just after the `lda $C000 / bpl` pair; find it in `src/NAME_Output.txt`. KEGS keeps the old image inode open, so restart it after every `make package`.

## Rules self-tests

`src/test.s` is a SYS part that runs the spec section 33 checks and draws a per-section tally. Reach it with T on the title screen, or from the debugger with `k.cmd("00/1004g")` while the title waits for a key. Results also land in memory for scripted runs:

```
python3 tools/kegs_screenshot.py tests --port 6520 --listing src/test_Output.txt \
    --sym test_pass:2 --sym test_fail:2 --sym test_first_fail:2
```

Checks are numbered from 1 in run order; `test_first_fail` holds the id of the first failure, traceable by counting through the sections in test.s. Every new rules routine gets a section here before it is used by GAME.

A check is `sta expect` then `jsr check_eq` with the actual value in A. `expect` is the test's own variable, never engine scratch: two earlier failures came from holding the expected value in `rt1` across an engine call that clobbered it.

## Debug board (milestone 3)

`src/dbg.s`, included by GAME, draws the board with programmer art and runs the hot-seat loop; `src/game.s` holds the PLACEHOLDER map (checklist text notation, decoded by `board_load_text`) and starting positions until the real boards are captured. It runs in native 16-bit mode and calls the engine only through the `eng_*` wrappers. To drive it from a script, resume the title past its key wait so it chains into GAME, then `python3 tools/kegs_key.py --port 6520 down down return right return E --shot NAME` pokes keys into `inject_key` one per frame and screenshots. Terrain, units, highlights and the status lines are all read back from engine state, never from events.

## Board capture (milestone 2 groundwork)

The Atari original runs in atari800 (Homebrew; it fetched the XL OS ROM to `~/rom` on first run). `tools/atari_drive.py` runs it under a pty so the F8 monitor is scriptable and posts keys to its process (Accessibility is trusted for this terminal; function keys need the Fn flag or macOS eats them). `tools/atari_boards_capture.py --boards 1-10` boots, picks each board through the options screen with every step verified from screen memory, and saves `boardNN.png`, `boardNN_codes.txt` and `boardNN_ram.dat` in `reference/raw/boards/`. `tools/atari_boards_decode.py boardNN_ram.dat --board N --out reference/maps/boardNN.txt` reads the game's own terrain table at $5740 and the units from the screen at $7A00 into the checklist notation plus a `_units.txt` layer (boards 6-9 need `--board` for their abstract tables). `python3 tools/gen_boards.py` (also a Makefile rule) turns the maps into `src/boards.s`; GAME loads `opt_board` from it and the debug board's number keys switch boards. `tools/atari_shot.py` and `tools/atari_charset.py` handle screenshots and the glyph sheet. Findings and addresses are in `reference/notes/capture_session.md`. Game images under `reference/atari/` are git-ignored: never commit them.

## Clock under ProDOS 8

`_GetTick` only advances inside the Misc Tools heartbeat handler, which the firmware installs on the VBL vector (`IRQ_VBL`, $E1/0020) when the first heartbeat task is registered, and the interrupt manager disables VBL (bit 3 of `INTEN`, $C041) whenever the heartbeat chain is empty and the mouse does not use VBL. Enabling VBL alone therefore lasts one frame. `toolbox_init` copies a do-nothing task to `HB_TASK` ($1200, outside every part) and registers it with `_SetHeartBeat`; do not move or overwrite that record. The ROM source that settled this is under `~/Desktop/work/iigs_rom/.../GS_ROM` (Misc Tools and Monitor/BRAM.INTR071).

## Program structure

`CC.SYSTEM` (`src/cc.s`) is the only `.SYSTEM` file on the volume. ProDOS loads it at $2000; it relocates one page to $1000 and stays resident. Parts chain by jumping to its table in emulation mode with 8-bit M/X:

| Entry | Loads |
|---|---|
| `$1000` | TITLE |
| `$1002` | GAME |
| `$1004` | TEST |

Each stub forces emulation mode itself, so a caller (or the debugger) may enter in any mode.

Every part is a SYS file with `ORG $2000` that does `put shared` at the top (equates) and `put common` at the bottom (shared routines), so the entry point stays at $2000. Parts that carry the rules engine also `put tables` (and later includes) before `put common`. `toolbox_init` runs once per boot, gated by the `tb_inited` flag, and starts Tool Locator, Misc Tools, Integer Math and QuickDraw II.

## Rules engine

Lives in `src/tables.s`, `src/board.s`, `src/line.s`, `src/units.s`, `src/events.s`, `src/move.s`, `src/rng.s`, `src/fire.s`, `src/turn.s`, included by GAME and TEST in that order. Conventions:

- Routines are entered in native mode with 8-bit A/X/Y (`MX %11`), DBR $00, D $0000, and say so if they differ.
- Scratch is the direct-page range `rt0`-`rt3`, `rptr`, `rptr2`, `rt4`-`rt7` ($E0-$EB) from shared.s, live only within one routine. Each routine's header says which it clobbers.
- All class-dependent numbers are tables indexed by `CLASS_*`; never branch on class in logic code.
- Fuel costs come only from `fuel_cost` (class, orientation, distance); `FUEL_NONE` ($FF) marks an illegal distance and can never be afforded.
- Hit percentages come only from `hit_chance` (class, orientation, range), which returns 0 with carry clear beyond the class's firing range. The table itself depends on orientation and range only.
- The board is 220 one-byte terrain types at `board`, row-major, reached through `get_cell`/`set_cell` with X = x, Y = y. Terrain behaviour is the `terrain_flags` table (`TF_FIRE` bit 7, `TF_MOVE` bit 6, so `bit terrain_flags,x` then `bpl`/`bvc` tests them), destruction is a type change through `terrain_after`, and cells carry no hit points. Directions are `DIR_N`..`DIR_NW` clockwise, odd values diagonal. Tree penalties are tables of zeros marked UNVERIFIED until measured on the Atari executable.
- Occupancy is the `occupant` map parallel to `board` (0 empty, else unit id + 1), kept current by unit code and read through `get_occupant`.
- Lines are `src/line.s`: endpoints in `ln_x0`..`ln_y1`, `line_find` classifies (direction, distance, orientation), `line_trace` walks once and records flags, occupants and tree penalties, then `move_path_clear` or `los_clear` gives the verdict. Whether units block passage or line of fire is UNVERIFIED and sits behind `rule_units_block_move` / `rule_units_block_los`, both defaulting to 1.
- Units are parallel arrays in `src/units.s` indexed by id: Red 0-10, Black 11-21, slots filled in add order. `unit_add` (parameters in `un_side`/`un_class`/`un_x`/`un_y`) enforces placement and the spec 6 army limits from `side_class_max`; `unit_set_pos` and `unit_kill` are the only other writers of the occupant map. `UF_ALIVE` is bit 7 of `unit_flags`. The spec 13 fired-at rule is a 16-bit mask per attacker over enemy slots, cleared by `units_begin_turn`.
- Randomness comes only from `src/rng.s`: xorshift32 in the 4 bytes at `rng_state`, seeded through `rng_seed` (rt0-rt3, zero becomes a default). `resolve_hit` takes a percent, returns carry for hit and the roll in A, and draws through `roll_vec` so tests can inject rolls. `tools/rng_ref.py` is the byte-exact host mirror; the self-tests hold known answers from it, so any change to the generator must update both and will invalidate replays.
- No rendering or sound from rules code (spec section 32). Actions queue events through `event_push` (record in `ev_type`, `ev_p0`-`ev_p4`; types and parameter meanings listed in `src/events.s`); the display layer drains them with `event_pop`.
- Actions come in pairs: a `*_validate` that checks and prices without touching state and returns a reason code (`MV_*`, `FR_*`), and a `*_execute` that validates, changes state and queues events. Turn-level rules (whose turn, moves left, Shoot Option phase) are checked by the turn code around them, not inside. Victory is the game layer's check after an action, using `fr_outcome`.
- A hit goes through `unit_take_hit`, which drops unit HP and terrain HP together (spec 23) and destroys the square or the unit when either reaches 0. What happens to a unit whose square is destroyed under it, and what a miss does instead (`miss_resolve`, spec 12), are UNVERIFIED and marked as such in `src/fire.s`.
- The turn layer in `src/turn.s` is what the UI and AI call: `game_start` (after placing units, with the `opt_*` options set), `turn_move`, `turn_fire`, `turn_end`, `turn_pause`/`turn_resume`, `game_surrender`, and `clock_check` every frame. They return `TN_*` codes or pass the action's `MV_*`/`FR_*` reason through. The game ends through `game_over` only; read `game_result` and `result_reason`.
- Time is heartbeat ticks (60 Hz) from `get_tick`, which goes through `tick_vec` (default the Misc Tools tick counter, never the battery clock) so tests inject exact values. Each side's remaining time is stored; the active side's live time is `clock_remaining`, charged at turn end, pause and game over. `ticks_to_mmss` formats it. Whether the turn ends by itself after the last allowed move is UNVERIFIED and sits behind `rule_auto_end_turn`.
- Every value is 8-bit; the largest in the spec is max fuel, 240.

## Bank $00 map

| Range | Use |
|---|---|
| `$0C00-$0FFF` | ProDOS 8 I/O buffer for the launcher's MLI calls |
| `$1000-$10FF` | Launcher (an `err` in cc.s fails the build if it outgrows the page) |
| `$1100-$11FF` | Cross-part globals, zeroed at boot: `tb_inited` $1100, `myID` $1102, game options from $1104 |
| `$1200-$1213` | Heartbeat task record registered by `toolbox_init` so the VBL tick counter keeps running |
| `$1D00-$1FFF` | QuickDraw II direct page |
| `$2000-$BEFF` | Current part. `toolbox_init` reserves `$0800-$BEFF` from the Memory Manager |
| `$BF00` | ProDOS global page |

SHR screen is `$E1/2000-$9FFF` with bank `$01` shadowing enabled; QuickDraw II draws straight to `$E1`.

## Assembly conventions

- Merlin32 syntax: `]` variable labels, `:` local labels scoped to the nearest global label.
- Merlin32 tracks MX linearly and does not follow `XCE`. Put an explicit `MX %00` or `MX %11` after every mode switch and at the top of each routine.
- ProDOS 8 MLI calls and the launcher jump table need emulation mode, 8-bit M/X. Toolbox calls need native mode, 16-bit M/X.
- `*` in expressions is the current PC, not multiplication.
- `BEQ`/`BNE`/`BCC`/`BCS` reach +/-128 bytes; use an inverted branch plus `JMP` beyond that.
- `BIT $C019` must be done with 8-bit A.
- ProDOS pathnames use `str`, which emits the length byte.
- Keep the rules engine free of rendering and sound calls (spec section 32); it emits events that the display layer consumes.
