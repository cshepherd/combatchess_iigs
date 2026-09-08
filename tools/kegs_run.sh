#!/bin/bash
# Boot out/combatchess.po in the patched KEGS (see KEGS_DEBUGGER.md).
#
#   tools/kegs_run.sh            boot and run
#   tools/kegs_run.sh -dbgport 6510   boot halted with the debug socket
#                                     open; then use tools/kegs_dbg.py or
#                                     tools/kegs_screenshot.py
#
# Generates a config.kegs for this project from the ddiigs HDD config
# (same ROM, BRAM and window settings) with our image in s5d1 and s7d1
# and every other drive empty, so the boot scan finds it whichever slot
# the BRAM prefers. Extra arguments are passed straight to KEGSMAC.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="$REPO/out/combatchess.po"
KEGS_DIR="/Applications/Apple IIGS/kegs.1.34"
KEGS_BIN="$KEGS_DIR/KEGSMAC.app/Contents/MacOS/KEGSMAC"
TEMPLATE="$KEGS_DIR/config.kegs.hdd"
CFG="$REPO/out/config.kegs"

[ -f "$IMG" ] || { echo "no $IMG — run make package first" >&2; exit 1; }
[ -x "$KEGS_BIN" ] || { echo "KEGS not found at $KEGS_BIN" >&2; exit 1; }

sed -E \
  -e "s#^s5d1 = .*#s5d1 = $IMG#" \
  -e "s#^s7d1 = .*#s7d1 = $IMG#" \
  -e "s#^(s5d2|s6d1|s6d2|s7d2|s7d3|s7d4) = .*#\1 = #" \
  "$TEMPLATE" > "$CFG"

# KEGS resolves relative paths (ROM, etc.) against its own directory.
cd "$KEGS_DIR"
exec "$KEGS_BIN" -cfg "$CFG" "$@"
