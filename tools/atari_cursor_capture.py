#!/usr/bin/env python3
"""Capture the Atari cursor states (checklist section 9): start a
game with the default options (Red is the human), then drive the
joystick (keypad keys and Right Ctrl as the trigger, atari800's
keyboard joystick) through the states and record each one:
screenshot, the player/missile shapes (PMBASE $4000, double-line:
missiles $4180, players $4200/$4280/$4300/$4380), the PM colour
shadows ($2C0-$2C3), the HUD text and the display list address.

The stick moves the cursor only after the trigger has selected the
unit it starts on, and auto-repeats while held, so the steps are
short pushes, each followed by a record. The steps are exploratory
(the manual does not say how the fire cursor is reached); read the
screenshots and cursor_states.json together.

Usage: python3 tools/atari_cursor_capture.py
Writes reference/raw/cursor/cursor_STEP.png, cursor_states.json and
git-ignored cursor_STEP_ram.dat.
"""
import json
import os
import sys
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from atari_drive import Atari  # noqa: E402
from atari_status_capture import IMAGE, TITLE_DL, GAME_DL, dlist_addr, wait_for  # noqa: E402

REPO = os.path.abspath(os.path.join(TOOLS, ".."))
OUT = os.path.join(REPO, "reference", "raw", "cursor")
PM_BASE = 0x4000
JOY = {"left": "KP4", "right": "KP6", "up": "KP8", "down": "KP2", "fire": "RCTRL"}  # KP2=down (KP5 is keypad-centre)


def shapes(pm):
    """Non-zero rows of each player, from the 1 KB PM area."""
    out = {}
    for name, off in (("missiles", 0x180), ("p0", 0x200), ("p1", 0x280), ("p2", 0x300), ("p3", 0x380)):
        rows = [(i, b) for i, b in enumerate(pm[off:off + 128]) if b]
        out[name] = {"first_row": rows[0][0] if rows else None,
                     "rows": [f"{b:02X}" for _, b in rows]}
    return out


def snap(a, name, note, states):
    shot = a.screenshot()
    os.replace(shot, os.path.join(OUT, f"cursor_{name}.png"))
    a.monitor()
    pm = a.read_mem(PM_BASE, 0x400)
    cols = [f"${c:02X}" for c in a.read_mem(0x2C0, 4)]
    hud = a.screen_text(0x1FB0, 40, 2)
    sd = a.read_mem(0x230, 2)
    a.dump(0x0000, 0xBFFF, f"cursor_{name}_ram.dat")
    a.cont()
    st = {"step": name, "note": note, "dlist": f"${sd[0] | (sd[1] << 8):04X}", "colpm": cols,
          "hud": [h.rstrip() for h in hud], "shapes": shapes(pm)}
    states.append(st)
    print(f"{name}: dl {st['dlist']} colpm {cols} hud {st['hud'][0]!r} shapes "
          + " ".join(f"{k}@{v['first_row']}x{len(v['rows'])}" for k, v in st["shapes"].items() if v["rows"]), flush=True)


def joy(a, direction, n=1, pause=0.6):
    """One short push per step: the game auto-repeats while the
    stick is held (a half-second push moves two squares)."""
    for _ in range(n):
        a.key(JOY[direction], hold=0.15)
        time.sleep(pause)


STEPS = [
    # (name, action, note); actions: joy direction, "key NAME", or None
    ("s01_start", None, "game start: the cursor on the Red cruiser, before any input; the stick does nothing yet"),
    ("s02_trigger", "fire", "trigger on the cruiser"),
    ("s03_left", "left", "stick left once"),
    ("s04_trigger", "fire", "trigger on the square left of the cruiser (a tree)"),
    ("s05_down", "down", "stick down once"),
    ("s06_trigger", "fire", "trigger"),
    ("s07_down", "down", "stick down once"),
    ("s08_right", "right", "stick right once"),
    ("s09_trigger", "fire", "trigger"),
    ("s10_right", "right", "stick right once"),
    ("s11_right", "right", "stick right once"),
    ("s12_trigger", "fire", "trigger"),
    ("s13_esc", "key ESC", "ESC"),
    ("s14_space", "key SPACE", "SPACE after ESC"),
    ("s15_select", "key F3", "SELECT (status screen)"),
    ("s16_select3", "key F3 F3", "SELECT twice more (back to the board)"),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    a = Atari(IMAGE, cwd=OUT, extra=("-nojoystick", "-kbdjoy0"))   # the keyboard is joystick 0
    states = []
    try:
        a.boot(12)
        wait_for(a, TITLE_DL, "title")
        a.key("F4", hold=0.3)
        wait_for(a, GAME_DL, "game")
        time.sleep(3)
        for name, action, note in STEPS:
            if action in JOY:
                joy(a, action)
            elif action and action.startswith("key "):
                for k in action.split()[1:]:
                    a.key(k, hold=0.15)
                    time.sleep(1.0)
            snap(a, name, note, states)
    finally:
        json.dump(states, open(os.path.join(OUT, "cursor_states.json"), "w"), indent=1)
        a.quit()
    print("done", flush=True)


if __name__ == "__main__":
    main()
