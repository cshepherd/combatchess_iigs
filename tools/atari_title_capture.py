#!/usr/bin/env python3
"""Capture the Atari title screen and the options screen's ranges
(checklist sections A and B), driving atari800 through
tools/atari_drive.py.

Title: screenshot, the six mode-7 rows of screen memory at $7200 (the
tank plaque), the character set they use, the colour registers, and
the twelve text lines at $4E00, into reference/raw/title/.

Options: press OPTION to move the blinking cursor from field to field
and SELECT repeatedly on each until the screen text returns to where
it started, recording every value the field takes; that is the exact
range and wrap behaviour of each option. Written to
reference/notes/options_ranges.md and options_ranges.json.

Usage: python3 tools/atari_title_capture.py [--skip-options]
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

REPO = os.path.abspath(os.path.join(TOOLS, ".."))
IMAGE = os.path.join(REPO, "reference", "atari", "combat_chess.atr")
TITLE_DL, OPTIONS_DL = 0x7300, 0x6421


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
        except RuntimeError as e:       # monitor not answering yet: try again
            print("waiting:", str(e)[:80], flush=True)
        time.sleep(1.0)
    raise RuntimeError(f"never reached the {what} screen")


def options_text(a):
    a.monitor()
    t = a.screen_text(0x7C00, 40, 24)
    a.cont()
    return t


def capture_title(a, out):
    os.makedirs(out, exist_ok=True)
    shot = a.screenshot()
    os.replace(shot, os.path.join(out, "title.png"))
    a.monitor()
    plaque = a.read_mem(0x7200, 120)
    chbas = a.read_mem(0x2F4, 1)[0]
    charset = a.read_mem(chbas << 8, 1024)
    colours = a.read_mem(0x2C4, 5)
    gtia = a.cmd("GTIA", 1.0)
    text = a.screen_text(0x4E00, 40, 12)
    a.dump(0x0000, 0xBFFF, "title_ram.dat")
    a.cont()
    open(os.path.join(out, "title_plaque.bin"), "wb").write(plaque)
    open(os.path.join(out, "title_charset.bin"), "wb").write(charset)
    open(os.path.join(out, "title_text.txt"), "w").write("\n".join(text) + "\n")
    info = {
        "plaque": "title_plaque.bin: 6 rows x 20 mode-7 codes at $7200",
        "charset": f"title_charset.bin: 1 KB from ${chbas << 8:04X} (CHBAS ${chbas:02X})",
        "colours_shadow": [f"${c:02X}" for c in colours],
        "gtia": dict(re.findall(r"(COLPF\d|COLBK|COLPM\d)=\s*([0-9A-F]{2})", gtia)),
    }
    json.dump(info, open(os.path.join(out, "title_info.json"), "w"), indent=1)
    print("title captured:", info["charset"], "colours", info["colours_shadow"], flush=True)


def capture_options(a, out_dir):
    a.key("F2", hold=0.2)
    wait_for(a, OPTIONS_DL, "options")
    fields = []
    seen_first = None
    for _ in range(12):                 # at most a dozen fields
        start = options_text(a)
        values = []
        changed_line = None
        for _ in range(40):             # a field wraps within 40 presses (time limit is 1-30)
            a.key("F3", hold=0.2)
            time.sleep(0.45)
            now = options_text(a)
            diff = [i for i in range(24) if now[i] != start[i]]
            if not diff:
                break                   # wrapped back to the starting value
            if changed_line is None:
                changed_line = diff[0]
            values.append(now[changed_line].strip())
        if changed_line is None:
            print("a SELECT press changed nothing; stopping", flush=True)
            break
        entry = {"line": changed_line, "start": start[changed_line].strip(), "values": values}
        if seen_first is None:
            seen_first = entry["start"]
        elif entry["start"] == seen_first and fields:
            break                       # the cursor is back on the first field
        fields.append(entry)
        print(f"field on line {changed_line}: {entry['start']!r} cycles through {len(values)} values", flush=True)
        a.key("F2", hold=0.2)           # OPTION: next field
        time.sleep(0.5)
    json.dump(fields, open(os.path.join(out_dir, "options_ranges.json"), "w"), indent=1)
    with open(os.path.join(out_dir, "options_ranges.md"), "w") as f:
        f.write("# Options screen fields and ranges\n\n")
        f.write("Captured by tools/atari_title_capture.py: OPTION moves the cursor in this\n")
        f.write("order; SELECT cycles each field through these values and wraps.\n\n")
        for e in fields:
            f.write(f"## Line {e['line']}: `{e['start']}`\n\n")
            for v in e["values"]:
                f.write(f"- `{v}`\n")
            f.write("\n")
    return fields


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-options", action="store_true")
    ap.add_argument("--skip-title", action="store_true")
    args = ap.parse_args()
    out = os.path.join(REPO, "reference", "raw", "title")
    os.makedirs(out, exist_ok=True)
    a = Atari(IMAGE, cwd=out)
    try:
        a.boot(12)
        wait_for(a, TITLE_DL, "title")
        if not args.skip_title:
            capture_title(a, out)
        if not args.skip_options:
            capture_options(a, os.path.join(REPO, "reference", "notes"))
    finally:
        a.quit()
    print("done", flush=True)


if __name__ == "__main__":
    main()
