#!/bin/bash
# Run the Atari 8-bit original in atari800 with the capture rules of
# combat_chess_visual_capture_checklist.md section 3: NTSC, no
# artifacting, no scanlines, no filtering, integer scaling, and the
# real XL OS ROM if atari800 has one (it fetched a set to ~/rom on first
# run), else its built-in Altirra OS.
#
#   tools/atari_capture.sh reference/atari/<disk.atr | program.xex> [session]
#
# Screenshots (F10 in the emulator) land in reference/raw/<session>/
# as atari000.pcx, atari001.pcx, ... Rename them to the checklist's
# pattern (cc_atari_<category>_<subject>_<state>_<nn>.png) once
# converted with tools/atari_shot.py. The session's input is recorded
# to <session>.rec beside them so a capture can be replayed.
#
# atari800 keys: F2 OPTION, F3 SELECT, F4 START, F5 warm reset,
# Shift-F5 cold reset, F8 monitor, F9 quit, F10 screenshot,
# F1 emulator menu (disk swapping, save states).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:?usage: $0 <atari image> [session name]}"
SESSION="${2:-session}"
OUT="$REPO/reference/raw/$SESSION"
mkdir -p "$OUT"

case "$IMG" in
  *.xex|*.XEX|*.com|*.COM|*.exe|*.EXE) LOAD=(-run "$IMG") ;;
  *) LOAD=("$IMG") ;;   # disk or cartridge image as a positional argument
esac

cd "$OUT"
exec atari800 \
  -xl -nobasic \
  -ntsc -ntsc-artif none -scanlines 0 -no-scanlinesint \
  -win-width 672 -win-height 480 \
  -no-autosave-config \
  -record "$SESSION.rec" \
  "${LOAD[@]}"
