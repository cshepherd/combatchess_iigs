#!/usr/bin/env bash
# Install (or refresh) the claudebridge MAME plugin from the repo copy into
# Ample's plugins directory, where mame64 looks for -plugin claudebridge.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/Library/Application Support/Ample/plugins/claudebridge"
mkdir -p "$dest"
cp "$here/claudebridge/plugin.json" "$dest/plugin.json"
cp "$here/claudebridge/init.lua"    "$dest/init.lua"
echo "claudebridge installed to: $dest"
