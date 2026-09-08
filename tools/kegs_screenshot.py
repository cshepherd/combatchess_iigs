#!/usr/bin/env python3
"""Screenshot + register dump for a running KEGS session via the debug
socket (see KEGS_DEBUGGER.md; start KEGS with -dbgport).

Renders the SHR display ($E1/2000-9FFF: pixels, SCBs, palettes) to a
PNG through a temporary PPM and macOS `sips`, prints the CPU registers,
and optionally the value of symbols resolved from a merlin32 -V listing
so the dump tracks every rebuild.

Usage:
    python3 tools/kegs_screenshot.py <name> [--port 6510] [--no-resume]
                                     [--listing src/game_Output.txt]
                                     [--sym NAME[:WIDTH] ...]

Writes <name>.png in the current directory. The emulator is halted for
the duration of the dump and resumed afterwards unless --no-resume is
given.
"""
import argparse
import os
import re
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
from kegs_dbg import Kegs  # noqa: E402


def resolve_symbols(listing, names):
    """Map symbol name -> bank-0 address from a merlin32 listing."""
    addrs = {}
    want = set(names)
    if not want or not os.path.exists(listing):
        return addrs
    with open(listing) as f:
        for line in f:
            for name in list(want):
                if f"| {name} " in line:
                    m = re.search(r'00/([0-9A-F]{4})', line)
                    if m:
                        addrs[name] = int(m.group(1), 16)
                        want.discard(name)
            if not want:
                break
    return addrs


def parse(txt, mem=None):
    mem = {} if mem is None else mem
    for line in txt.splitlines():
        m = re.match(r'^([0-9a-f]{4,6}):((?: [0-9a-f]{2})+)', line.strip())
        if m:
            addr = int(m.group(1), 16)
            for i, b in enumerate(m.group(2).split()):
                mem[addr + i] = int(b, 16)
    return mem


def screenshot(k, name, scale=3):
    mem = {}
    for lo in range(0x2000, 0xA000, 0x800):
        parse(k.read_mem(0xE1, lo, min(lo + 0x800, 0xA000) - 1), mem)
    rows = []
    for y in range(200):
        scb = mem.get(0x9D00 + y, 0)
        pal = 0x9E00 + (scb & 0x0F) * 32
        colors = []
        for c in range(16):
            w = mem.get(pal + c * 2, 0) | (mem.get(pal + c * 2 + 1, 0) << 8)
            colors.append((((w >> 8) & 0xF) * 17, ((w >> 4) & 0xF) * 17,
                           (w & 0xF) * 17))
        row = []
        base = 0x2000 + y * 160
        for x in range(160):
            v = mem.get(base + x, 0)
            row.append(colors[v >> 4])
            row.append(colors[v & 0x0F])
        rows.append(row)
    ppm = f"{name}.ppm"
    with open(ppm, "wb") as f:
        f.write(f"P6 {320*scale} {200*scale} 255\n".encode())
        for row in rows:
            line = bytearray()
            for px in row:
                line += bytes(px) * scale
            f.write(bytes(line) * scale)
    subprocess.run(["sips", "-s", "format", "png", ppm,
                    "--out", f"{name}.png"], capture_output=True)
    os.unlink(ppm)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name", nargs="?", default="kegs_shot")
    ap.add_argument("--port", type=int, default=6510)
    ap.add_argument("--no-resume", action="store_true")
    ap.add_argument("--listing", default=os.path.join(TOOLS, "..", "src",
                                                      "game_Output.txt"))
    ap.add_argument("--sym", action="append", default=[],
                    help="symbol to print, optionally NAME:2 for a word")
    args = ap.parse_args()

    syms = {}
    for s in args.sym:
        name, _, width = s.partition(":")
        syms[name] = int(width) if width else 1
    addrs = resolve_symbols(args.listing, syms)

    k = Kegs(port=args.port)
    k.halt()
    regs = k.regs()
    screenshot(k, args.name)
    mem = {}
    for sym, a in addrs.items():
        parse(k.read_mem(0x00, a, a + syms[sym]), mem)
    if not args.no_resume:
        k.go()
    k.close()

    print(regs.strip())
    for sym, a in sorted(addrs.items(), key=lambda kv: kv[1]):
        v = mem.get(a, 0)
        if syms[sym] == 2:
            v |= mem.get(a + 1, 0) << 8
        print(f"{sym} (${a:04X}): {v}")
    for sym in syms:
        if sym not in addrs:
            print(f"{sym}: not found in {args.listing}")
    print(f"wrote {args.name}.png")


if __name__ == "__main__":
    main()
