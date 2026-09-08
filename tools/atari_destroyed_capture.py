#!/usr/bin/env python3
"""Capture how the Atari status roster shows a destroyed unit
(checklist C, spec 28/34): set COMPUTER WILL PLAY BOTH on the options
screen, start the game, poll the board's screen memory until a unit
glyph stays missing, then SELECT for both sides' rosters and check them
(the cursor overwrites a unit's glyph too, so the roster is the judge);
SELECT back and keep going until a roster row is not a bare name or a
name with four numbers, or a side has fewer numbered rows than it
started with.

Along the way it logs every board cell that no longer matches the
terrain table (destroyed terrain, wrecks) and captures whatever screen
the game switches to on its own (a game over after a cruiser dies).
Writes into reference/raw/status/ as status_destroyed_red / _black
(status screens: PNG, JSON, mode-7 codes, RAM dump), _board.png and
_board_ram.dat (the board afterwards) and _log.txt.

Usage: python3 tools/atari_destroyed_capture.py [--turbo] [--poll SEC]
                                                 [--timeout SEC]
"""
import argparse
import glob
import os
import re
import sys
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from atari_drive import Atari  # noqa: E402
from atari_status_capture import (IMAGE, OUT, TITLE_DL, GAME_DL,  # noqa: E402
                                  dlist_addr, wait_for, read_screen)

OPTIONS_DL, STATUS_DL = 0x6421, 0x4409
OPTIONS_SCREEN = 0x7C00
BOARD, TERRAIN, HUD = 0x7A00, 0x5740, 0x1FB0
ROSTER = 0x7D90                     # the status screen's twelve text rows
COMPUTER_LINE = 8                   # options_ranges.md: "COMPUTER WILL PLAY ..."
COMPUTER_FIELD = 6                  # cursor order: board, tanks x2, cars x2, first, computer


def options_text(a):
    a.monitor()
    t = a.screen_text(OPTIONS_SCREEN, 40, 24)
    a.cont()
    return t


def set_computer_both(a):
    """Cursor to the computer field, SELECT until it says BOTH."""
    for _ in range(COMPUTER_FIELD):
        a.key("F2", hold=0.2)
        time.sleep(0.4)
    before = options_text(a)
    a.key("F3", hold=0.2)
    time.sleep(0.5)
    after = options_text(a)
    changed = [i for i in range(24) if before[i] != after[i]]
    if changed != [COMPUTER_LINE]:
        raise RuntimeError(f"SELECT changed lines {changed}, not the computer line: "
                           f"{[after[i].strip() for i in changed]}")
    for _ in range(4):
        if "BOTH" in after[COMPUTER_LINE]:
            return after
        a.key("F3", hold=0.2)
        time.sleep(0.5)
        after = options_text(a)
    raise RuntimeError("computer field never read BOTH: " + after[COMPUTER_LINE])


def snapshot(a):
    """Board codes, terrain table and HUD text in one monitor visit."""
    a.monitor()
    board = a.read_mem(BOARD, 220)
    terrain = a.read_mem(TERRAIN, 220)
    hud = a.screen_text(HUD, 40, 2)
    sd = a.read_mem(0x230, 2)
    a.cont()
    return board, terrain, hud, sd[0] | (sd[1] << 8)


def units(board):
    """(x, y, colour, glyph) of every unit glyph on the board. The
    cursor is drawn into screen memory too, so a unit under it is
    missing here; a real loss is confirmed from the roster."""
    return [(i % 20, i // 20, c >> 6, c & 0x3F) for i, c in enumerate(board) if 1 <= (c & 0x3F) <= 3]


def roster(a):
    """The twelve 40-column text rows of the status screen at $7D90,
    read directly (the display list's block merges them with the
    mode-7 picture)."""
    a.monitor()
    rows = a.screen_text(ROSTER, 40, 12)
    a.cont()
    return rows


def numbered(rows):
    """Names of the roster rows that carry numbers."""
    return [r[1:21].strip() for r in rows[2:11] if r[21:].strip()]


def odd_rows(rows):
    """Roster rows that are neither a bare name nor name plus four
    numbers: whatever the original does for a destroyed unit."""
    out = []
    for r in rows[2:11]:
        name, rest = r[1:21].strip(), r[21:].split()
        if name not in ("BATTLE CRUISER", "TANK", "ARMOURED CAR"):
            out.append(r)
        elif rest and not (len(rest) == 4 and all(x.isdigit() for x in rest)):
            out.append(r)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--turbo", action="store_true", help="F12 (atari800 turbo) while waiting")
    ap.add_argument("--poll", type=float, default=4.0)
    ap.add_argument("--timeout", type=float, default=1800.0)
    ap.add_argument("--confirm", type=int, default=3, help="polls below strength before checking the roster")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    a = Atari(IMAGE, cwd=OUT)
    log = open(os.path.join(OUT, "status_destroyed_log.txt"), "w")

    def say(*s):
        line = " ".join(str(x) for x in s)
        print(line, flush=True)
        log.write(line + "\n")
        log.flush()

    def select(n=1):
        for _ in range(n):
            a.key("F3", hold=0.3)
            time.sleep(1.5)

    def select_to(dl, tries=6):
        """SELECT until the wanted display list is up; the game does
        not always poll the console keys (right after it starts, or
        during an animation), so a press can be lost."""
        for _ in range(tries):
            select()
            if dlist_addr(a) == dl:
                return True
            time.sleep(2)
        return False

    def open_status():
        return select_to(STATUS_DL)

    def header(rows):
        return rows[0][13:20].strip().lower()

    def other_side(side, tries=5):
        """From one side's status screen, SELECT to the other's and
        return its rows, riding out lost presses."""
        for _ in range(tries):
            select()
            dl = dlist_addr(a)
            if dl == GAME_DL and not open_status():
                return None
            rows = roster(a)
            if header(rows) != side:
                return rows
        return None

    def discard(side):
        for f in glob.glob(os.path.join(OUT, f"status_destroyed_{side}*")):
            os.remove(f)

    try:
        a.boot(12)
        wait_for(a, TITLE_DL, "title")
        a.key("F2", hold=0.2)
        wait_for(a, OPTIONS_DL, "options")
        opts = set_computer_both(a)
        say("options:", " / ".join(t.strip() for t in opts if t.strip()))
        a.key("F4", hold=0.3)
        wait_for(a, TITLE_DL, "title (after options)")
        a.key("F4", hold=0.3)
        wait_for(a, GAME_DL, "game")
        time.sleep(3)
        board0, terrain0, hud, _ = snapshot(a)
        start = units(board0)
        say(f"start: {len(start)} units, HUD {hud[0].strip()} | {hud[1].strip()}")
        # how many roster rows each side starts with, from the options
        tanks = re.search(r"TANKS:\s+BLACK (\d+), RED (\d+)", " ".join(opts))
        cars = re.search(r"CARS:\s+BLACK (\d+), RED (\d+)", " ".join(opts))
        armies = {"BLACK": 1 + int(tanks.group(1)) + int(cars.group(1)),
                  "RED": 1 + int(tanks.group(2)) + int(cars.group(2))}
        say("armies (numbered rows expected):", armies)
        if args.turbo:
            a.key("F12")
        low = 0
        terrain_seen = set()
        checks = 0
        t0 = time.time()
        while time.time() - t0 < args.timeout:
            time.sleep(args.poll)
            board, terrain, hud, dl = snapshot(a)
            if dl != GAME_DL:
                say(f"display list changed to ${dl:04X} at +{time.time() - t0:.0f}s; capturing that screen")
                if args.turbo:
                    a.key("F12")
                read_screen(a, "status_destroyed_gameover")
                break
            now = units(board)
            tdiff = {i for i in range(220) if terrain[i] != terrain0[i]}
            new_terrain = tdiff - terrain_seen
            terrain_seen |= tdiff
            line = (f"+{time.time() - t0:4.0f}s units {len(now)} (red {sum(1 for u in now if u[2] == 3)}, "
                    f"black {sum(1 for u in now if u[2] == 0)}) clocks {hud[0][:8].strip()} {hud[1][:8].strip()}")
            if new_terrain:
                line += " terrain changed: " + ", ".join(
                    f"({i % 20},{i // 20}) {terrain0[i] >> 6}:{terrain0[i] & 0x3F:02X}->{terrain[i] >> 6}:{terrain[i] & 0x3F:02X}"
                    for i in sorted(new_terrain))
            say(line)
            low = low + 1 if len(now) < len(start) else 0
            if low < args.confirm:
                continue
            low = 0
            checks += 1
            say(f"checking the roster (check {checks})")
            if args.turbo:
                a.key("F12")
            time.sleep(1)
            if not open_status():
                say(f"SELECT did not open the status screen (display list ${dlist_addr(a):04X})")
                break
            # capture both sides right now, named by their headers; the
            # side to move changes while the computer plays on
            rows1 = roster(a)
            side1 = header(rows1)
            read_screen(a, f"status_destroyed_{side1}")
            rows2 = other_side(side1)
            if rows2 is None:
                say("could not reach the other side's status screen")
                break
            side2 = header(rows2)
            read_screen(a, f"status_destroyed_{side2}")
            found = False
            for rows in (rows1, rows2):
                side = header(rows).upper()
                if odd_rows(rows) or len(numbered(rows)) < armies.get(side, 0):
                    found = True
                    say(f"{side}: {len(numbered(rows))} numbered rows of {armies.get(side, 0)}; odd rows {odd_rows(rows)}")
                    for r in rows:
                        say("   |" + r)
            if not found:
                say("no destroyed unit yet: " + "; ".join(f"{header(r)} {len(numbered(r))}" for r in (rows1, rows2)))
                discard(side1)
                discard(side2)
                if not select_to(GAME_DL):    # back to the board
                    say(f"lost the SELECT cycle (display list ${dlist_addr(a):04X})")
                    break
                if args.turbo:
                    a.key("F12")
                continue
            if not select_to(GAME_DL):
                say(f"lost the SELECT cycle (display list ${dlist_addr(a):04X})")
                break
            time.sleep(1)
            shot = a.screenshot()
            os.replace(shot, os.path.join(OUT, "status_destroyed_board.png"))
            a.monitor()
            a.dump(0x0000, 0xBFFF, "status_destroyed_board_ram.dat")
            a.cont()
            say(f"captured {side1} and {side2} status screens and the board")
            break
        else:
            say("timeout: no unit destroyed")
    finally:
        a.quit()
    say("done")


if __name__ == "__main__":
    main()
