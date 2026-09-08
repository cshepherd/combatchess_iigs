# Combat Chess — Apple IIGS

A port of Avalon Hill's *Combat Chess* (Atari 8-bit, 1984) to the Apple IIGS, written in 65816 assembly with Merlin32.

The rules specification lives in `combat_chess_iigs_spec-3.md`; the plan for harvesting reference art from the original is `combat_chess_visual_capture_checklist.md`. The project follows the spec's milestones: headless rules engine, Atari verification, programmer-art debug board, final art, sound, AI.

## Status

Milestone 1 in progress. The disk boots into a launcher that chains a placeholder title screen and a placeholder game part. The headless rules engine is functionally complete for the printed rules: data tables, board and terrain, line tracing, units, movement, fire, turns with both Shoot Options, chess clocks with pause, and victory, time loss, surrender and stalemate, all with self-tests. Items the manual leaves open are marked UNVERIFIED in the source for milestone 2.

The ten original boards and their starting positions have been captured from the Atari game (see `reference/notes/capture_session.md`) and generated into `src/boards.s`. The game part is the milestone 3 debug board: a programmer-art 20 x 11 board on any of the ten boards, playable hot-seat with the keyboard. Arrows or WASD move the cursor, RETURN selects a friendly unit and then confirms a move or a shot, M and F switch between move and fire (legal destinations and targets are highlighted), ESC cancels, E ends the turn, P pauses, X surrenders, the number keys restart on another board (0 is board 10), Q quits to the title.

Press T on the title screen to run the rules self-tests.

## Building

Requirements:

- [Merlin32](https://github.com/lroathe/merlin32) — 65816 cross-assembler (`merlin32` on the path)
- [cadius](https://github.com/fadden/CiderPress2) — ProDOS disk image utility (`cadius` on the path)
- Python 3 — build and debugging tools

```bash
make package   # assemble everything and build out/combatchess.po
make clean     # remove out/ and the merlin32 listings
```

The build assembles each part in `src/` with `merlin32 -V` (which also writes a `*_Output.txt` listing beside the source), creates an 800 KB ProDOS volume, and copies PRODOS plus the parts onto it through `tools/cadius_strict.sh`, a wrapper that fails the build when cadius reports an error instead of exiting zero.

## Running

Boot `out/combatchess.po` in KEGS, GSplus, or on real hardware. The volume contains only one `.SYSTEM` file, so ProDOS runs the launcher directly.

`tools/kegs_run.sh` boots the image in the patched KEGS described in `tools/KEGS_DEBUGGER.md`. Add `-dbgport 6520` to open the debug socket, then `tools/kegs_screenshot.py` dumps the screen and registers.

## Layout

| Path | Contents |
|---|---|
| `src/cc.s` | `CC.SYSTEM` launcher: relocates to $1000, chains TITLE and GAME |
| `src/title.s` | Title screen part (will also own the options screen) |
| `src/game.s` | Game part: rules engine and board display go here |
| `src/test.s` | Rules self-tests part (spec section 33) |
| `src/tables.s` | Rules data: unit class, fuel cost and hit probability tables with their lookups |
| `src/board.s` | Board geometry, directions, 220-cell terrain board and occupant map, terrain flag tables, destruction |
| `src/line.s` | Line classification and tracing shared by movement paths and line of sight |
| `src/units.s` | Unit list as parallel arrays, placement with army limits, occupant upkeep, per-turn fired-at masks |
| `src/events.s` | Event queue from the rules engine to the display layer |
| `src/move.s` | Movement action: validate and price a move, execute it with fuel, terrain HP and event |
| `src/fire.s` | Fire action: validate a shot with its odds, execute with ammo, roll, damage, destruction and events |
| `src/turn.s` | Turns, Shoot Option phases, chess clocks on the tick counter, pause, victory, time loss, surrender, stalemate |
| `src/dbg.s` | Debug board: programmer-art display, keyboard cursor, highlights, status lines, hot-seat loop |
| `tools/kegs_key.py` | Pokes keys into the running debug board through the KEGS debug socket, with optional screenshot |
| `src/rng.s` | Seedable xorshift32 generator, 0-99 roll, `resolve_hit` with injectable roll |
| `tools/rng_ref.py` | Byte-exact Python mirror of `rng.s` for replay tools and test known answers |
| `src/shared.s` | Equates shared by every part (launcher entries, page $11 globals) |
| `src/common.s` | Routines shared by every part (toolbox start-up, SHR init, text, keys) |
| `res/` | `PRODOS` system file |
| `tools/` | Build and KEGS debugging tools |
| `assets/` | SHR art and audio (empty until milestone 4) |
| `reference/` | Atari capture archive, laid out per the visual checklist |
| `out/` | Build output (generated) |
