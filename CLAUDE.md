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

Lives in `src/tables.s` and the includes that will follow it (movement, fire, turns), included by GAME and TEST. Conventions:

- Routines are entered in native mode with 8-bit A/X/Y (`MX %11`), DBR $00, D $0000, and say so if they differ.
- Scratch is the direct-page range `rt0`-`rt3`, `rptr`, `rptr2` ($E0-$E7) from shared.s, live only within one routine.
- All class-dependent numbers are tables indexed by `CLASS_*`; never branch on class in logic code.
- Fuel costs come only from `fuel_cost` (class, orientation, distance); `FUEL_NONE` ($FF) marks an illegal distance and can never be afforded.
- Hit percentages come only from `hit_chance` (class, orientation, range), which returns 0 with carry clear beyond the class's firing range. The table itself depends on orientation and range only.
- No rendering or sound from rules code (spec section 32); it will emit events for the display layer.
- Every value is 8-bit; the largest in the spec is max fuel, 240.

## Bank $00 map

| Range | Use |
|---|---|
| `$0C00-$0FFF` | ProDOS 8 I/O buffer for the launcher's MLI calls |
| `$1000-$10FF` | Launcher (an `err` in cc.s fails the build if it outgrows the page) |
| `$1100-$11FF` | Cross-part globals, zeroed at boot: `tb_inited` $1100, `myID` $1102, game options from $1104 |
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
