#!/usr/bin/env python3
"""Capture every Combat Chess board at its starting state from the
Atari original (checklist section 5), driving atari800 through
tools/atari_drive.py.

For each board: cold boot, wait for the title, OPTION, put the
blinking cursor on GAME BOARD and SELECT until it reads the wanted
number (every step verified by reading screen memory), START twice
(the first returns to the title), wait for the game display list,
then F10 screenshot, screen codes, HUD text, colour registers and a
full RAM dump into reference/raw/boards/:

    boardNN.png         the emulator's screenshot (indexed PNG)
    boardNN_codes.txt   the 220 screen codes as colour:glyph
    boardNN_ram.dat     $0000-$BFFF, for tools/atari_boards_decode.py
    boards_capture.json HUD lines and colours per board

Usage: python3 tools/atari_boards_capture.py [--boards 2-10] [--out DIR]
"""
import argparse
import json
import os
import re
import sys
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from atari_drive import Atari  # noqa: E402

TITLE_DL, OPTIONS_DL, GAME_DL = 0x7300, 0x6421, 0x2180
OPTIONS_SCREEN = 0x7C00


def dlist_addr(a):
    a.monitor()
    sd = a.read_mem(0x230, 2)
    a.cont()
    return sd[0] | (sd[1] << 8)


def wait_for(a, addr, what, tries=20, pause=1.0):
    for _ in range(tries):
        if dlist_addr(a) == addr:
            return True
        time.sleep(pause)
    raise RuntimeError(f"never reached the {what} screen")


def board_line(a):
    a.monitor()
    t = a.screen_text(OPTIONS_SCREEN, 40, 4)[2]
    a.cont()
    return t


def board_number(line):
    m = re.search(r"#(\d+)", line)
    return int(m.group(1)) if m else None


def select_board(a, n):
    """On the options screen: move the cursor to GAME BOARD and cycle
    SELECT until the line reads #n."""
    for field in range(8):
        before = board_line(a)
        a.key("F3", hold=0.2)
        time.sleep(0.5)
        after = board_line(a)
        if after != before:
            break
        a.key("F2", hold=0.2)          # cursor to the next field
        time.sleep(0.5)
    else:
        raise RuntimeError("could not find the GAME BOARD field")
    for _ in range(12):
        if board_number(after) == n:
            return after
        a.key("F3", hold=0.2)
        time.sleep(0.5)
        after = board_line(a)
    raise RuntimeError(f"board number never reached {n}: {after!r}")


def capture(n, out, image):
    a = Atari(image, cwd=out)
    try:
        a.boot(12)
        wait_for(a, TITLE_DL, "title")
        a.key("F2", hold=0.2)
        wait_for(a, OPTIONS_DL, "options")
        line = select_board(a, n)
        a.key("F4", hold=0.3)
        wait_for(a, TITLE_DL, "title (after options)")
        a.key("F4", hold=0.3)
        wait_for(a, GAME_DL, "game")
        time.sleep(3)                  # let the board finish drawing
        shot = a.screenshot()
        os.replace(shot, os.path.join(out, f"board{n:02d}.png"))
        a.monitor()
        codes = a.read_mem(0x5740, 220)   # the terrain table (no units), for the look table
        hud = a.screen_text(0x1FB0, 40, 2)
        gtia = a.cmd("GTIA", 1.0)
        cols = dict(re.findall(r"(COLPF\d|COLBK)=\s*([0-9A-F]{2})", gtia))
        a.dump(0x0000, 0xBFFF, f"board{n:02d}_ram.dat")
        a.cont()
        with open(os.path.join(out, f"board{n:02d}_codes.txt"), "w") as f:
            for r in range(11):
                f.write(" ".join(f"{c >> 6}:{c & 0x3F:02X}" for c in codes[r * 20:(r + 1) * 20]) + "\n")
        return {"options_line": line.strip(), "hud": hud, "colours": cols}
    finally:
        a.quit()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--boards", default="1-10")
    ap.add_argument("--out", default=os.path.join(TOOLS, "..", "reference", "raw", "boards"))
    ap.add_argument("--image", default=os.path.join(TOOLS, "..", "reference", "atari", "combat_chess.atr"))
    a = ap.parse_args()
    lo, _, hi = a.boards.partition("-")
    boards = range(int(lo), int(hi or lo) + 1)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "boards_capture.json")
    results = json.load(open(path)) if os.path.exists(path) else {}
    for n in boards:
        try:
            results[str(n)] = capture(n, out, a.image)
            print(f"board {n}: {results[str(n)]['options_line']}; colours {results[str(n)]['colours']}", flush=True)
        except Exception as e:  # keep going, report at the end
            results[str(n)] = {"error": str(e)}
            print(f"board {n}: FAILED: {e}", flush=True)
        json.dump(results, open(path, "w"), indent=1)
    print("done", flush=True)


if __name__ == "__main__":
    main()
