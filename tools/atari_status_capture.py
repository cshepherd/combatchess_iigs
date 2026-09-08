#!/usr/bin/env python3
"""Capture the Atari status screens (checklist section C): start a
game with the default options, press SELECT for the active side's
status, again for the opponent's, again to return to the board.

For each status screen: screenshot, the display list, every screen
memory block it points at (mode-7 rows as codes, text rows as text),
and the colour registers, into reference/raw/status/. The first
screen is read twice five seconds apart to see whether the clocks
run while it is shown (spec 34, "timer behaviour during status
screens").

Usage: python3 tools/atari_status_capture.py
"""
import json
import os
import re
import sys
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from atari_drive import Atari  # noqa: E402

REPO = os.path.abspath(os.path.join(TOOLS, ".."))
IMAGE = os.path.join(REPO, "reference", "atari", "combat_chess.atr")
OUT = os.path.join(REPO, "reference", "raw", "status")
TITLE_DL, GAME_DL = 0x7300, 0x2180


def dlist_addr(a):
    a.monitor()
    sd = a.read_mem(0x230, 2)
    a.cont()
    return sd[0] | (sd[1] << 8)


def wait_for(a, addr, what, tries=20):
    for _ in range(tries):
        try:
            if dlist_addr(a) == addr:
                return
        except RuntimeError as e:
            print("waiting:", str(e)[:80], flush=True)
        time.sleep(1.0)
    raise RuntimeError(f"never reached the {what} screen")


def parse_dlist(text):
    """DLIST output -> [(lms_addr, mode, rows)] in display order."""
    segs = []
    for line in text.splitlines():
        m = re.match(r"\s*[0-9A-F]{4}: (?:DLI )?(?:LMS ([0-9A-F]{4}) )?(?:(\d+)x )?MODE (\d+)", line)
        if not m:
            continue
        lms, count, mode = m.group(1), int(m.group(2) or 1), int(m.group(3))
        if lms:
            segs.append([int(lms, 16), mode, count])
        elif segs:
            segs[-1][2] += count
    return segs


def read_screen(a, name):
    """Freeze, screenshot, and read everything the display list shows."""
    shot = a.screenshot()
    os.replace(shot, os.path.join(OUT, name + ".png"))
    a.monitor()
    dl = a.dlist()
    segs = parse_dlist(dl)
    blocks = []
    for addr, mode, rows in segs:
        width = 20 if mode in (6, 7) else 40
        if mode in (2, 6, 7):
            if mode == 2:
                blocks.append({"addr": f"${addr:04X}", "mode": mode, "rows": rows,
                               "text": a.screen_text(addr, width, rows)})
            else:
                raw = a.read_mem(addr, width * rows)
                open(os.path.join(OUT, f"{name}_mode{mode}_{addr:04X}.bin"), "wb").write(raw)
                blocks.append({"addr": f"${addr:04X}", "mode": mode, "rows": rows,
                               "codes_file": f"{name}_mode{mode}_{addr:04X}.bin"})
    chbas = a.read_mem(0x2F4, 1)[0]
    colours = [f"${c:02X}" for c in a.read_mem(0x2C4, 5)]
    gtia = dict(re.findall(r"(COLPF\d|COLBK)=\s*([0-9A-F]{2})", a.cmd("GTIA", 1.0)))
    a.dump(0x0000, 0xBFFF, f"{name}_ram.dat")
    a.cont()
    info = {"dlist": dl.strip().splitlines()[1:-1], "blocks": blocks, "chbas": f"${chbas:02X}00",
            "colours_shadow": colours, "gtia": gtia}
    json.dump(info, open(os.path.join(OUT, name + ".json"), "w"), indent=1)
    for b in blocks:
        if "text" in b:
            print(f"{name}: text at {b['addr']}:")
            for t in b["text"]:
                print("   |" + t)
        else:
            print(f"{name}: mode {b['mode']} codes at {b['addr']} x{b['rows']} -> {b['codes_file']}")
    print(f"{name}: charset {info['chbas']}, colours {colours}", flush=True)
    return info


def main():
    os.makedirs(OUT, exist_ok=True)
    a = Atari(IMAGE, cwd=OUT)
    try:
        a.boot(12)
        wait_for(a, TITLE_DL, "title")
        a.key("F4", hold=0.3)
        wait_for(a, GAME_DL, "game")
        time.sleep(3)
        a.key("F3", hold=0.3)          # SELECT: status of the side to move
        time.sleep(1.5)
        first = read_screen(a, "status_own")
        time.sleep(5)
        again = read_screen(a, "status_own_5s")
        a.key("F3", hold=0.3)          # SELECT: the opponent's status
        time.sleep(1.5)
        read_screen(a, "status_other")
        a.key("F3", hold=0.3)          # SELECT: back to the board
        time.sleep(1.5)
        back = dlist_addr(a)
        print("after the third SELECT the display list is $%04X (%s)" % (back, "the board" if back == GAME_DL else "NOT the board"))
    finally:
        a.quit()
    print("done", flush=True)


if __name__ == "__main__":
    main()
