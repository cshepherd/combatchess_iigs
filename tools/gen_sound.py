#!/usr/bin/env python3
"""Rip Combat Chess's POKEY sound effects and turn them into Apple IIGS
DOC samples.

Input is a POKEY register recording made by atari800's -pokeyrec while
the computer plays itself (see reference/notes). Each line is nine
bytes: AUDF1 AUDC1 AUDF2 AUDC2 AUDF3 AUDC3 AUDF4 AUDC4 AUDCTL, sampled
every -pokeyrec-interval scanlines.

The three effects are told apart by AUDC distortion (spec 5, Milestone
5): pure tone ($A0/$E0) is the per-move / music note, poly5 ($20/$60)
the cannon report, poly noise ($00/$80) the four-channel explosion.

The register stream is rendered to audio with a faithful port of
atari800's Ron Fries POKEY engine (src/pokeysnd.c, GPL) rather than an
approximation, then downsampled to an unsigned 8-bit DOC waveform
($01-$FF; a $00 sample would halt the oscillator early) and written to
src/sound_samples.s, with WAVs for listening.

Usage:
    python3 tools/gen_sound.py --rec CAP.dat [--out src/sound_samples.s]
                               [--wavdir DIR]
"""
import argparse
import math
import os
import wave

FREQ17 = 1789790            # POKEY 1.79 MHz clock (exact)
SCANLINE_HZ = 15720.0       # NTSC scanlines per second
PLAYBACK = 44100            # render sample rate
# IIGS DOC free-form playback: it reads the waveform at
# osc_rate/512 per frequency unit. osc_rate ~26.3 kHz with the Sound
# Tool's oscillators enabled, so read_rate(Hz) = F_reg * DOC_K.
DOC_OSC_RATE = 26320.0
DOC_K = DOC_OSC_RATE / 512.0
DIV_64 = 28

# AUDC bits (pokey.h)
NOTPOLY5, POLY4, PURETONE, VOL_ONLY, VOL_MASK = 0x80, 0x40, 0x20, 0x10, 0x0f
# AUDCTL bits
POLY9, CH1_179, CH3_179, CH1_CH2, CH3_CH4, CH1_FILTER, CH2_FILTER, CLOCK_15 = \
    0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01

# poly4 / poly5 patterns, exactly as in the chip (pokeysnd.c "new table")
BIT4 = [1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 0]
BIT5 = [1, 1, 1, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0,
        0, 0, 1, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0]


def build_polys():
    poly9 = bytearray(511)
    reg = 0x1ff
    for i in range(511):
        reg = ((((reg >> 5) ^ reg) & 1) << 8) + (reg >> 1)
        poly9[i] = reg & 0xff
    poly17 = bytearray(16385)
    reg = 0x1ffff
    for i in range(16385):
        reg = ((((reg >> 5) ^ reg) & 0xff) << 9) + (reg >> 8)
        poly17[i] = (reg >> 1) & 0xff
    return poly9, poly17


POLY9_TAB, POLY17_TAB = build_polys()


class Pokey:
    """A single POKEY's Ron Fries sound engine (atari800 pokeysnd.c)."""

    def __init__(self, playback=PLAYBACK):
        self.AUDF = [0, 0, 0, 0]
        self.AUDC = [0, 0, 0, 0]
        self.AUDCTL = 0
        self.base_mult = DIV_64
        self.AUDV = [0, 0, 0, 0]
        self.Outvol = [0, 0, 0, 0]
        self.div_max = [0x7fffffff] * 4
        self.div_cnt = [0, 0, 0, 0]
        self.P4 = self.P5 = self.P9 = self.P17 = 0
        self.samp_max = (FREQ17 << 8) // playback   # 24.8 fixed
        self.samp_cnt = 0                            # 24.8 fixed
        self.cur_val = 0

    # register write -> recompute derived state (Update_pokey_sound_rf)
    def write(self, offset, val):
        a = self.AUDCTL
        mask = 0
        if offset == 0:                # AUDF1
            self.AUDF[0] = val; mask = 1 | (2 if a & CH1_CH2 else 0)
        elif offset == 1:              # AUDC1
            self.AUDC[0] = val; self.AUDV[0] = val & VOL_MASK; mask = 1
        elif offset == 2:              # AUDF2
            self.AUDF[1] = val; mask = 2
        elif offset == 3:              # AUDC2
            self.AUDC[1] = val; self.AUDV[1] = val & VOL_MASK; mask = 2
        elif offset == 4:              # AUDF3
            self.AUDF[2] = val; mask = 4 | (8 if a & CH3_CH4 else 0)
        elif offset == 5:              # AUDC3
            self.AUDC[2] = val; self.AUDV[2] = val & VOL_MASK; mask = 4
        elif offset == 6:              # AUDF4
            self.AUDF[3] = val; mask = 8
        elif offset == 7:              # AUDC4
            self.AUDC[3] = val; self.AUDV[3] = val & VOL_MASK; mask = 8
        elif offset == 8:              # AUDCTL
            self.AUDCTL = val
            self.base_mult = 114 if val & CLOCK_15 else DIV_64
            mask = 15
        a = self.AUDCTL
        bm = self.base_mult
        F, C = self.AUDF, self.AUDC
        for ch, bit in ((0, 1), (1, 2), (2, 4), (3, 8)):
            if not (mask & bit):
                continue
            if ch == 0:
                nv = F[0] + 4 if a & CH1_179 else (F[0] + 1) * bm
            elif ch == 1:
                if a & CH1_CH2:
                    nv = (F[1] * 256 + F[0] + 7) if a & CH1_179 \
                        else (F[1] * 256 + F[0] + 1) * bm
                else:
                    nv = (F[1] + 1) * bm
            elif ch == 2:
                nv = F[2] + 4 if a & CH3_179 else (F[2] + 1) * bm
            else:
                if a & CH3_CH4:
                    nv = (F[3] * 256 + F[2] + 7) if a & CH3_179 \
                        else (F[3] * 256 + F[2] + 1) * bm
                else:
                    nv = (F[3] + 1) * bm
            if nv != self.div_max[ch]:
                self.div_max[ch] = nv
                if self.div_cnt[ch] > nv:
                    self.div_cnt[ch] = nv
        # volume-only / silent channels: mark 'on' and idle the divider
        for ch in range(4):
            if not (mask & (1 << ch)):
                continue
            if (C[ch] & VOL_ONLY) or (C[ch] & VOL_MASK) == 0:
                self.Outvol[ch] = 1
                if (ch == 2 and not (a & CH1_FILTER)) or \
                   (ch == 3 and not (a & CH2_FILTER)) or ch in (0, 1):
                    self.div_max[ch] = 0x7fffffff
                    self.div_cnt[ch] = 0x7fffffff

    def process(self, n, out):
        """Generate n samples into the list `out` (pokeysnd_process_8)."""
        SAMP_MIN = 0
        cur = SAMP_MIN
        for ch in range(4):
            if self.Outvol[ch]:
                cur += self.AUDV[ch]
        div_cnt = self.div_cnt
        div_max = self.div_max
        Outvol = self.Outvol
        AUDV = self.AUDV
        AUDC = self.AUDC
        a = self.AUDCTL
        P4, P5, P9, P17 = self.P4, self.P5, self.P9, self.P17
        samp = self.samp_cnt
        smax = self.samp_max
        while n:
            emin = samp >> 8
            nxt = -1
            for ch in range(4):
                if div_cnt[ch] <= emin:
                    emin = div_cnt[ch]; nxt = ch
            if nxt >= 0:
                for ch in range(4):
                    div_cnt[ch] -= emin
                samp -= emin << 8
                P4 = (P4 + emin) % 15
                P5 = (P5 + emin) % 31
                P9 = (P9 + emin) % 511
                P17 = (P17 + emin) % 131071
                div_cnt[nxt] += div_max[nxt]
                audc = AUDC[nxt]
                toggle = False
                if not (audc & VOL_ONLY):
                    if (audc & NOTPOLY5) or BIT5[P5]:
                        if audc & PURETONE:
                            toggle = True
                        elif audc & POLY4:
                            toggle = (BIT4[P4] == (0 if Outvol[nxt] else 1))
                        elif a & POLY9:
                            toggle = ((POLY9_TAB[P9] & 1) == (0 if Outvol[nxt] else 1))
                        else:
                            b = (POLY17_TAB[P17 >> 3] >> (P17 & 7)) & 1
                            toggle = (b == (0 if Outvol[nxt] else 1))
                if toggle:
                    if Outvol[nxt]:
                        cur -= AUDV[nxt]; Outvol[nxt] = 0
                    else:
                        Outvol[nxt] = 1; cur += AUDV[nxt]
            else:
                out.append(cur)
                samp += smax
                n -= 1
        self.P4, self.P5, self.P9, self.P17 = P4, P5, P9, P17
        self.samp_cnt = samp
        self.cur_val = cur


def parse_rec(path):
    rows = []
    for line in open(path):
        line = line.strip()
        if len(line) >= 18:
            rows.append([int(line[i:i + 2], 16) for i in range(0, 18, 2)])
    return rows


def find_bursts(rows, gap=6):
    def sounding(r):
        return any(r[1 + 2 * c] & 0x0F for c in range(4))
    bursts = []
    i, n = 0, len(rows)
    while i < n:
        if sounding(rows[i]):
            j, silent = i, 0
            while j < n and silent < gap:
                silent = 0 if sounding(rows[j]) else silent + 1
                j += 1
            bursts.append((i, j - silent))
            i = j
        else:
            i += 1
    return bursts


def find_fanfare(rows):
    """The turn-start fanfare is a two-voice ascending sweep on channel 2, a
    short phrase whose AUDF2 steps down (pitch up) monotonically. The title
    tune also uses channel 2, so group nearby channel-2 activity into phrases
    (bridging the brief note-off gaps) and return the descending one's [s,e)."""
    MERGE = 60                        # rows of ch-2 silence still in one phrase
    phrases, s, e = [], None, None
    for i, r in enumerate(rows):
        if r[3] & 0x0F:               # AUDC2 volume nonzero
            if s is None:
                s = i
            e = i
        elif s is not None and i - e > MERGE:
            phrases.append((s, e + 1)); s = None
    if s is not None:
        phrases.append((s, e + 1))
    for (s, e) in phrases:
        af2 = [rows[j][2] for j in range(s, e) if rows[j][3] & 0x0F]
        seq = [af2[0]] + [af2[k] for k in range(1, len(af2)) if af2[k] != af2[k - 1]]
        if len(seq) >= 4 and all(seq[k + 1] < seq[k] for k in range(len(seq) - 1)):
            return (s, e)
    return None


def classify(rows, s, e):
    hist = {}
    for r in rows[s:e]:
        for c in range(4):
            v = r[1 + 2 * c]
            if v & 0x0F:
                hist[v & 0xE0] = hist.get(v & 0xE0, 0) + 1
    if not hist:
        return None
    dom = max(hist, key=hist.get)
    if dom in (0xA0, 0xE0):
        return "fire"          # pure-tone beep: the cannon report
    if dom in (0x20, 0x60):
        return "move"          # poly5 buzz: the movement engine sound
    return "explosion"         # poly noise: the four-channel blast


def render_burst(rows, s, e, interval):
    """Render [s,e) of the register log to a float PCM list at PLAYBACK."""
    pk = Pokey()
    # a little lead-in of silence trims cleanly and warms the engine
    prev = [None] * 9
    out = []
    samples_done = 0.0
    per_row = SCANLINE_HZ / interval          # rows per second
    for idx, ri in enumerate(range(s, e)):
        r = rows[ri]
        for off in range(9):
            if r[off] != prev[off]:
                pk.write(off, r[off])
                prev[off] = r[off]
        target = (idx + 1) / per_row * PLAYBACK
        n = int(round(target - samples_done))
        if n > 0:
            pk.process(n, out)
            samples_done += n
    # centre (POKEY output is unipolar) and return
    if out:
        mid = sum(out) / len(out)
        out = [x - mid for x in out]
    return out


def render_tone(audf, audc, dur_s, audctl=0x00):
    """Render a synthetic single-channel POKEY tone to float PCM at PLAYBACK.
    Used for the clock tick and cursor-move beep, whose register values were
    read off the log but which are simpler to reproduce than to cut out.
    audctl selects the base clock: 0 = 64 kHz (freq 31960/(AUDF+1)); CLOCK_15
    = the 15 kHz base (freq 7850/(AUDF+1)), for tones deeper than a single
    byte of AUDF can reach at 64 kHz."""
    pk = Pokey()
    pk.write(8, audctl)        # AUDCTL: base clock (0 = 64 kHz)
    pk.write(0, audf)          # AUDF1
    pk.write(1, audc)          # AUDC1 (distortion + volume)
    out = []
    pk.process(int(round(dur_s * PLAYBACK)), out)
    if out:
        mid = sum(out) / len(out)
        out = [x - mid for x in out]
    return out


def downsample(buf, n_out):
    out = []
    step = len(buf) / n_out if n_out else 1
    for i in range(n_out):
        a = int(i * step)
        b = max(a + 1, int((i + 1) * step))
        seg = buf[a:b]
        out.append(sum(seg) / len(seg) if seg else 0.0)
    return out


def to_u8(samples):
    peak = max((abs(x) for x in samples), default=1.0) or 1.0
    return bytes(max(1, min(255, int(round(128 + (x / peak) * 120)))) for x in samples)


def write_wav(path, u8, rate=PLAYBACK):
    w = wave.open(path, "wb")
    w.setnchannels(1); w.setsampwidth(1); w.setframerate(int(rate))
    w.writeframes(u8); w.close()


EFFECTS = [
    # kind, symbol, DOC size code (buffer = 256<<code), pick
    ("move", "snd_move_wave", 5, "mid"),          # poly5 buzz, 8192 bytes
    ("fire", "snd_fire_wave", 2, "short"),        # cannon beep, 1024 bytes
    ("explosion", "snd_explode_wave", 6, "long"), # blast, 16384 bytes
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rec", required=True)
    ap.add_argument("--rec-turn", help="capture holding the turn-start fanfare")
    ap.add_argument("--interval", type=int, default=8)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__),
                                                   "..", "src", "sound_samples.s"))
    ap.add_argument("--wavdir")
    ap.add_argument("--bin")
    a = ap.parse_args()

    rows = parse_rec(a.rec)
    by_kind = {"move": [], "fire": [], "explosion": []}
    for (s, e) in find_bursts(rows):
        k = classify(rows, s, e)
        if k:
            by_kind[k].append((s, e, e - s))
    for k, v in by_kind.items():
        print(f"{k}: {len(v)} bursts")

    rowps = SCANLINE_HZ / a.interval
    out_syms = []
    for kind, sym, code, pick in EFFECTS:
        nbytes = 256 << code
        cand = [t for t in by_kind[kind] if t[2] / rowps >= 0.040] or by_kind[kind]
        if not cand:
            print(f"!! no {kind} burst; skipping")
            continue
        cand.sort(key=lambda t: t[2])
        s, e, _ = cand[0] if pick == "short" else cand[-1] if pick == "long" \
            else cand[len(cand) // 2]
        dur = (e - s) / rowps
        buf = render_burst(rows, s, e, a.interval)
        # nbytes (= the DOC buffer, 256<<code) of sound, no $00 (to_u8 clamps
        # to 1-255). The emitted wave_size (below) is nbytes-1, strictly less
        # than the buffer, so the free-form synth uses a SINGLE buffer and
        # plays it ONE-SHOT: next_wave_ptr 0 halts the oscillator at the table
        # end. wave_size >= the buffer instead needs a second buffer and drops
        # the tool into SWAP/streaming mode - an interrupt-driven DOC-refill
        # loop that free-runs through DOC RAM (the sound "cycles through" its
        # neighbours) and, for the 16 KB blast, froze the whole machine (even
        # the heartbeat clock) for ~8 s. The dropped final sample is inaudible.
        u8 = to_u8(downsample(buf, nbytes))
        if kind != "fire":
            u8 = u8[:-16] + bytes(16)  # 16 $00 halt the direct-DOC one-shot;
                                       # the cannon trill loops (free-run), so
                                       # it must have no $00 to halt on
        # play the whole buffer back over the sound's real duration
        read_rate = nbytes / dur
        freq = max(1, min(0x1ff, round(read_rate / DOC_K)))
        print(f"{kind}: rows {s}-{e} ({dur*1000:.0f} ms) -> {sym}[{nbytes}] "
              f"read {read_rate:.0f}Hz freq ${freq:03X}")
        out_syms.append((sym, nbytes, code, freq, round(dur * 60), u8))
        if a.wavdir:
            write_wav(os.path.join(a.wavdir, f"{kind}.wav"), to_u8(buf))
            write_wav(os.path.join(a.wavdir, f"{kind}_doc.wav"), u8, read_rate)

    # Two short pure tones from the log: the ~329 Hz clock tick (AUDF $60)
    # heard once a second, and the ~2458 Hz cursor-move beep (AUDF $0c).
    # Rendered synthetically (they are trivial tones) into 256-byte samples.
    # Three more, the piece-placement beeps that sound as each unit is set
    # on the board at game start: one short pure tone per class, pitched
    # by class (cruiser low, car high, an octave apart) exactly as the
    # Atari does. AUDF $f3/$79/$3c = 131/262/524 Hz. They keep the sharp
    # attack the original has (that percussive onset is most of what makes
    # the low, few-cycle tones audible) but fade OUT to zero (fade=True) so
    # the DOC oscillator does not step from the last sample value back to
    # silence, which would click.
    for sym, audf, audc, dur, fade, zerotail in (
            ("snd_tick_wave", 0x60, 0xAF, 0.017, False, True),
            ("snd_beep_wave", 0x0C, 0xAF, 0.017, False, True),
            ("snd_place_cru_wave",  0xF3, 0xAF, 0.017, True, True),
            ("snd_place_tank_wave", 0x79, 0xAF, 0.017, True, True),
            ("snd_place_car_wave",  0x3C, 0xAF, 0.017, True, True)):
        code = 0
        nbytes = 256 << code
        buf = downsample(render_tone(audf, audc, dur), nbytes)
        if fade:
            k = 48                        # ~3 ms raised-cosine fade-out only
            for i in range(k):
                w = 0.5 - 0.5 * math.cos(math.pi * (i + 1) / (k + 1))
                buf[-1 - i] *= w
        u8 = to_u8(buf)
        if zerotail:
            # A run of 16 $00 bytes at the tail halts the DOC oscillator in
            # one-shot mode (a single zero can be strided over; 16 covers the
            # resolution). The cursor beep and placement tones play direct-DOC.
            u8 = u8[:-16] + bytes(16)
        read_rate = nbytes / dur
        freq = max(1, min(0x1ff, round(read_rate / DOC_K)))
        print(f"{sym}: {dur*1000:.0f} ms tone -> [{nbytes}] "
              f"read {read_rate:.0f}Hz freq ${freq:03X}")
        out_syms.append((sym, nbytes, code, freq, max(1, round(dur * 60)), u8))
        if a.wavdir:
            write_wav(os.path.join(a.wavdir, f"{sym}.wav"), u8, read_rate)

    # The turn-start fanfare: a two-voice ascending sweep ripped from a
    # separate capture that includes a turn beginning (--rec-turn).
    if a.rec_turn and os.path.exists(a.rec_turn):
        trows = parse_rec(a.rec_turn)
        span = find_fanfare(trows)
        if span:
            s, e = span
            code = 4                               # 4096-byte buffer
            nbytes = 256 << code
            dur = (e - s) / (SCANLINE_HZ / a.interval)
            buf = render_burst(trows, s, e, a.interval)
            u8 = to_u8(downsample(buf, nbytes))
            u8 = u8[:-16] + bytes(16)      # 16 $00 halt the direct-DOC one-shot
            read_rate = nbytes / dur
            freq = max(1, min(0x1ff, round(read_rate / DOC_K)))
            print(f"snd_turn_wave: rows {s}-{e} ({dur*1000:.0f} ms) "
                  f"read {read_rate:.0f}Hz freq ${freq:03X}")
            out_syms.append(("snd_turn_wave", nbytes, code, freq,
                             round(dur * 60), u8))
            if a.wavdir:
                write_wav(os.path.join(a.wavdir, "snd_turn_wave.wav"), u8, read_rate)
        else:
            print("!! no fanfare (channel-2 sweep) found in", a.rec_turn)

    # The invalid-move/shot UI buzz: a square wave (period 16 bytes)
    # played direct-DOC one-shot like the others, ending in a 16-$00 halt.
    ui = bytearray((0x30 if (i // 8) % 2 == 0 else 0xD0) for i in range(512))
    ui[-16:] = bytes(16)
    out_syms.append(("snd_ui_wave", 512, 1, 0x02C0, 0, bytes(ui)))

    # Per-class movement engine sounds (spec 5): the armored car keeps the
    # ripped buzz (snd_move_wave above); the tank is a mid poly5 buzz and
    # the battle cruiser a slow deep chug, synthesised as POKEY tones and
    # tuned by ear. 4 KB each (code 4), one-shot with the 16-$00 halt.
    for sym, audf, audc, dur, actl in (
        ("snd_move_tank_wave", 0xB4, 0x28, 0.25, 0x00),      # mid buzz (poly5)
        ("snd_move_cru_wave",  0x78, 0x28, 0.45, CLOCK_15),  # deep chug (~65 Hz)
    ):
        tone = render_tone(audf, audc, dur, actl)
        nb, code = 4096, 4
        u8 = to_u8(downsample(tone, nb))
        u8 = u8[:-16] + bytes(16)
        freq = max(1, min(0x1ff, round((nb / dur) / DOC_K)))
        print(f"{sym}: AUDF ${audf:02X} AUDC ${audc:02X} {dur*1000:.0f}ms "
              f"-> {nb}B freq ${freq:03X}")
        out_syms.append((sym, nb, code, freq, max(1, round(dur * 60)), u8))
        if a.wavdir:
            write_wav(os.path.join(a.wavdir, f"{sym}.wav"), u8, nb / dur)

    # the samples live in a separate disk file (SOUNDS), loaded at
    # game start into a spare RAM bank; sound_samples.s carries only
    # each one's size, DOC code, frequency and offset in the blob.
    blob = bytearray()
    offsets = []
    for sym, nbytes, code, freq, frames, u8 in out_syms:
        offsets.append(len(blob))
        blob += u8
    if a.bin:
        with open(a.bin, "wb") as bf:
            bf.write(blob)
        print("wrote", a.bin, len(blob), "bytes")
    with open(a.out, "w") as f:
        f.write("*----------------------------------------------------------\n")
        f.write("* sound_samples.s - sizes, DOC size codes, playback\n")
        f.write("* frequencies and blob offsets for Combat Chess's POKEY\n")
        f.write("* effects, ripped from the Atari original. The waveform\n")
        f.write("* bytes are in the SOUNDS disk file (res/sounds.bin), loaded\n")
        f.write("* at game start. GENERATED by tools/gen_sound.py (a port of\n")
        f.write("* atari800's Ron Fries POKEY engine). Do not edit.\n")
        f.write("*----------------------------------------------------------\n")
        for (sym, nbytes, code, freq, frames, u8), off in zip(out_syms, offsets):
            f.write(f"{sym}_size = {nbytes - 1}\n")
            f.write(f"{sym}_code = {code}\n")
            f.write(f"{sym}_freq = ${freq:04X}\n")
            f.write(f"{sym}_off  = {off}\n")
            f.write(f"{sym}_frames = {frames}\n")
        f.write(f"snd_blob_size = {len(blob)}\n")
    print("wrote", a.out)


if __name__ == "__main__":
    main()
