#!/usr/bin/env python3
"""pokey2mod.py - turn a captured POKEY title-music register log into a
4-channel Amiga MOD, for NinjaTracker Pro to play on the title screen of the
unenhanced build.

Input is an atari800 -pokeyrec-ascii log (9 bytes/row: AUDF1 AUDC1 .. AUDCTL,
one row every -pokeyrec-interval scanlines). The title tune is four POKEY
pure-tone (square) voices, so the MOD uses a single square-wave instrument and
maps each voice's pitch to an Amiga period:

    pure-tone freq  = 31960.5 / (AUDF + 1)          # 64 kHz base, AUDCTL 0
    Amiga period    = 3546895 / (freq * SAMPLE_LEN) # SAMPLE_LEN-byte 1-cycle square

One MOD row is sampled every --rowdiv-th log row; a voice emits a note (period +
Cxx set-volume) when its pitch changes, a bare Cxx when only its volume changes,
C00 when it goes silent, and nothing while it holds. The loop is packed into a
whole number of 64-row patterns and the order table repeats them.
"""
import argparse, struct, math

SCANLINE_HZ = 15720.0
POKEY_CLOCK = 31960.5      # 64 kHz / 2 -> pure-tone freq = this / (AUDF+1)
AMIGA_CLOCK = 3546895.0    # PAL Paula: playback rate = AMIGA_CLOCK / period
SAMPLE_LEN  = 32           # bytes in the one-cycle square (16 high, 16 low)

# Standard ProTracker period table, finetune 0, notes C-1..B-3. A note-index
# player (NinjaTracker+ .NTP) snaps arbitrary periods to this table at convert
# time, so we snap here too: the title tune is diatonic (mean ~17 cents off the
# nearest semitone, a consistent tuning bias that snapping removes), so the MOD
# then plays identically on a .NTP player and in any desktop MOD editor.
PT_PERIODS = [
    856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453,  # octave 1
    428, 404, 381, 360, 339, 320, 302, 285, 269, 254, 240, 226,  # octave 2
    214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113,  # octave 3
]


def parse_rec(path):
    rows = []
    for line in open(path):
        line = line.strip()
        if len(line) >= 18:
            rows.append([int(line[i:i + 2], 16) for i in range(0, 18, 2)])
    return rows


def audf_to_period(audf, snap=True):
    freq = POKEY_CLOCK / (audf + 1)
    raw = AMIGA_CLOCK / (freq * SAMPLE_LEN)
    if snap:
        return min(PT_PERIODS, key=lambda t: abs(math.log(t) - math.log(raw)))
    return max(28, min(4095, round(raw)))


def pokey_vol_to_mod(v):          # POKEY 0-15 -> MOD 0-64
    return round(v * 64.0 / 15.0)


def cell(sample, period, effect):
    """Pack one MOD channel cell (4 bytes)."""
    return bytes([
        (sample & 0xF0) | ((period >> 8) & 0x0F),
        period & 0xFF,
        ((sample & 0x0F) << 4) | ((effect >> 8) & 0x0F),
        effect & 0xFF,
    ])


EMPTY = cell(0, 0, 0)


def build(rows, start, loop, npatterns, speed, bpm, snap=True):
    nrows = npatterns * 64
    rowdiv = loop / nrows                      # log rows per MOD row (float)
    # grid[row][ch] -> packed 4-byte cell
    grid = [[EMPTY] * 4 for _ in range(nrows)]
    prev = [None] * 4                          # (period, vol) last emitted per ch
    for r in range(nrows):
        pr = start + int(round(r * rowdiv))
        if pr >= len(rows):
            pr = len(rows) - 1
        for c in range(4):
            audc = rows[pr][1 + 2 * c]
            vol = audc & 0x0F
            audf = rows[pr][2 * c]
            if not vol:                        # silent
                if prev[c] is not None:
                    grid[r][c] = cell(0, 0, 0x0C00)      # Cxx volume 0
                    prev[c] = None
                continue
            per = audf_to_period(audf, snap)
            pper, pvol = prev[c] if prev[c] else (None, None)
            mv = pokey_vol_to_mod(vol)
            if prev[c] is None or per != pper:           # (re)strike a note
                grid[r][c] = cell(1, per, 0x0C00 | mv)
            elif vol != pvol:                            # volume change only
                grid[r][c] = cell(0, 0, 0x0C00 | mv)
            prev[c] = (per, vol)
    # tempo on two voices that are silent at row 0 (ch2/ch3 come in later)
    grid[0][2] = cell(0, 0, 0x0F00 | (speed & 0x1F))     # Fxx speed
    grid[0][3] = cell(0, 0, 0x0F00 | (bpm & 0xFF))       # Fxx tempo (BPM)
    return grid


def write_mod(path, title, grid, npatterns):
    out = bytearray()
    out += title.encode("ascii", "replace")[:20].ljust(20, b"\x00")
    # 31 sample headers; #1 is the square, rest empty
    for s in range(31):
        name = (b"square" if s == 0 else b"").ljust(22, b"\x00")
        if s == 0:
            length = SAMPLE_LEN // 2           # in words
            vol, rstart, rlen = 64, 0, SAMPLE_LEN // 2   # loop whole sample
        else:
            length = vol = rstart = 0
            rlen = 1                           # ProTracker: min repeat len 1
        out += name
        out += struct.pack(">H", length)
        out += bytes([0, vol])                 # finetune, volume
        out += struct.pack(">HH", rstart, rlen)
    out += bytes([npatterns, 0x00])            # song length, restart pos
    order = bytes(range(npatterns)) + bytes(128 - npatterns)
    out += order
    out += b"M.K."
    for p in range(npatterns):
        for r in range(64):
            for c in range(4):
                out += grid[p * 64 + r][c]
    # sample data: one-cycle signed-8 square, +A first half then -A
    A = 96
    out += bytes([A] * (SAMPLE_LEN // 2) + [(256 - A)] * (SAMPLE_LEN // 2))
    open(path, "wb").write(out)
    return len(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rec", required=True)
    ap.add_argument("--interval", type=int, default=8)
    ap.add_argument("--out", required=True)
    ap.add_argument("--start", type=int, default=-1, help="loop start row (auto if <0)")
    ap.add_argument("--loop", type=int, default=64850, help="loop length in log rows")
    ap.add_argument("--patterns", type=int, default=8)
    ap.add_argument("--speed", type=int, default=3)
    ap.add_argument("--bpm", type=int, default=116)
    ap.add_argument("--title", default="COMBAT CHESS")
    ap.add_argument("--no-snap", action="store_true",
                    help="use exact POKEY periods instead of snapping to semitones")
    a = ap.parse_args()
    rows = parse_rec(a.rec)
    start = a.start
    if start < 0:
        start = next(i for i in range(len(rows))
                     if any(rows[i][1 + 2 * c] & 0x0F for c in range(4)))
    grid = build(rows, start, a.loop, a.patterns, a.speed, a.bpm, snap=not a.no_snap)
    n = write_mod(a.out, a.title, grid, a.patterns)
    rowms = a.loop / (SCANLINE_HZ / a.interval) / (a.patterns * 64) * 1000
    print(f"wrote {a.out}: {n} bytes, {a.patterns} patterns, "
          f"{a.patterns*64} rows @ {rowms:.1f} ms/row "
          f"(loop {a.loop/(SCANLINE_HZ/a.interval):.1f}s from row {start})")


if __name__ == "__main__":
    main()
