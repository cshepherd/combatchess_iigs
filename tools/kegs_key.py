#!/usr/bin/env python3
"""Drive the debug board in a running KEGS session by poking keys.

The board's loop checks the word `inject_key` every frame and treats a
nonzero value as a keypress (src/dbg.s). This tool writes a key there
through the debug socket's load-memory command, one key per frame, so
scripted play-throughs and screenshots need no keyboard.

Usage:
    python3 tools/kegs_key.py [--port 6520] [--listing src/game_Output.txt]
                              [--shot NAME] KEY [KEY ...]

KEY is a single character (case matters: 'E', 'q'), or one of
    up down left right return esc space
Numbers with a leading '#' are raw codes ('#13'). With --shot, a
screenshot NAME.png is taken after the last key.

Example: select the unit at (0,4), move it east four squares, end turn:
    python3 tools/kegs_key.py down down down down return \\
        right right right right return E --shot after_turn
"""
import argparse
import os
import sys
import tempfile
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from kegs_dbg import Kegs  # noqa: E402
from kegs_screenshot import resolve_symbols, screenshot  # noqa: E402

NAMED = {
    "up": 0x0B, "down": 0x0A, "left": 0x08, "right": 0x15,
    "return": 0x0D, "enter": 0x0D, "esc": 0x1B, "escape": 0x1B,
    "space": 0x20,
}


def key_code(name):
    if name.lower() in NAMED:
        return NAMED[name.lower()]
    if name.startswith("#"):
        return int(name[1:], 0)
    if len(name) == 1:
        return ord(name)
    raise SystemExit(f"unknown key: {name}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="+")
    ap.add_argument("--port", type=int, default=6520)
    ap.add_argument("--listing", default=os.path.join(TOOLS, "..", "src",
                                                      "game_Output.txt"))
    ap.add_argument("--settle", type=float, default=0.3,
                    help="seconds to run after each key")
    ap.add_argument("--shot", help="screenshot name after the last key")
    a = ap.parse_args()

    addr = resolve_symbols(a.listing, ["inject_key"]).get("inject_key")
    if addr is None:
        raise SystemExit(f"inject_key not found in {a.listing}")
    k = Kegs(port=a.port)
    k.halt()
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
        path = f.name
    try:
        for name in a.keys:
            open(path, "wb").write(bytes([key_code(name), 0]))
            k.cmd(f"00/{addr:04x}.{addr + 1:04x}ul{path}")
            k.go()
            time.sleep(a.settle)
            k.halt()
        if a.shot:
            screenshot(k, a.shot)
            print(f"wrote {a.shot}.png")
    finally:
        os.unlink(path)
        k.go()
        k.close()


if __name__ == "__main__":
    main()
