#!/bin/bash
# Cadius wrapper that surfaces silent failures (notably "No enough
# space in the image") as real non-zero exit codes. Plain `cadius`
# happily prints "Error : ..." and exits 0, so `make` continues
# building a broken disk image. Without this, an over-full disk
# silently drops file(s) and downstream "Free : N" looks like a
# normal build with extra space.
#
# Usage: drop-in replacement for `cadius`:
#   cadius_strict.sh CATALOG image.po
#   cadius_strict.sh ADDFILE image.po /vol/dir/ src#TT0000 --quiet
#   ...etc.
set -o pipefail
output=$(cadius "$@" 2>&1)
rc=$?
printf '%s\n' "$output"
if printf '%s\n' "$output" | grep -qE '^[[:space:]]*Error[[:space:]]*:'; then
  printf 'cadius_strict: cadius reported an error for: cadius %s\n' "$*" >&2
  exit 1
fi
exit "$rc"
