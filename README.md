# Combat Chess — Apple IIGS

A port of Avalon Hill's *Combat Chess* (Atari 8-bit, 1984) to the Apple IIGS, written in 65816 assembly with Merlin32.

The rules specification lives in `combat_chess_iigs_spec-3.md`; the plan for harvesting reference art from the original is `combat_chess_visual_capture_checklist.md`. The project follows the spec's milestones: headless rules engine, Atari verification, programmer-art debug board, final art, sound, AI.

## Status

Scaffold. The disk boots into a launcher that chains a placeholder title screen and a placeholder game part. No game logic yet.

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
| `src/shared.s` | Equates shared by every part (launcher entries, page $11 globals) |
| `src/common.s` | Routines shared by every part (toolbox start-up, SHR init, text, keys) |
| `res/` | `PRODOS` system file |
| `tools/` | Build and KEGS debugging tools |
| `assets/` | SHR art and audio (empty until milestone 4) |
| `reference/` | Atari capture archive, laid out per the visual checklist |
| `out/` | Build output (generated) |
