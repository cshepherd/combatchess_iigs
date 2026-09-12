#!/usr/bin/env bash
# Launch Combat Chess in MAME (apple2gs) with the Uthernet II in slot 1 and
# the claudebridge Lua bridge enabled. This is the user-provided Ample
# command line plus -plugin claudebridge. Run from anywhere.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HOME/Library/Application Support/Ample"
exec "/Applications/Apple IIGS/Ample.app/Contents/MacOS/mame64" apple2gs \
    -skip_gameinfo -nosamples -window -nounevenstretch -video bgfx \
    -ramsize 8M \
    -sl1 uthernet2 \
    -sl7 scsi -sl7:scsi:scsibus:5 harddisk \
    -hard1 '/Applications/Apple IIGS/kegs.1.34/images/microdrive/BOOT8.PO' \
    -hard2 "$REPO/out/combatchess.po" \
    -plugin claudebridge \
    "$@"
