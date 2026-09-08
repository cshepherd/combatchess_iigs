#!/usr/bin/env python3
"""Drive atari800 for the board capture session.

Runs atari800 under a pseudo-terminal so its built-in monitor (F8) is
scriptable, and posts keyboard events straight to the emulator's
process (Accessibility must be trusted) for the game's own input.
Together that gives: press keys, freeze the machine, read or dump
memory, take F10 screenshots, continue.

    from atari_drive import Atari
    a = Atari("reference/atari/combat_chess.atr", cwd="reference/raw/boards")
    a.boot(15)
    a.key("F2")                 # OPTION
    a.monitor()                 # freeze
    print(a.screen_text(0x4E00, 40, 12))
    a.cont()
    a.screenshot()              # atariNNN.pcx in cwd
    a.quit()

Key names: F1..F10, RETURN, ESC, SPACE, TAB, DELETE, UP DOWN LEFT
RIGHT, single characters, or a raw macOS key code as an int.
atari800's defaults: F2 OPTION, F3 SELECT, F4 START, F5 warm reset,
F8 monitor, F10 screenshot; the joystick is the numeric keypad
(KP8/KP2/KP4/KP6, fire = left/right Ctrl? see -kbdjoy options) unless
-joy-* remapped. Function keys are posted with the Fn flag so macOS
does not treat them as media keys.
"""
import ctypes
import ctypes.util
import os
import pty
import re
import select
import time

KEYCODES = {
    "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97,
    "F7": 98, "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111,
    "RETURN": 36, "ESC": 53, "SPACE": 49, "TAB": 48, "DELETE": 51,
    "UP": 126, "DOWN": 125, "LEFT": 123, "RIGHT": 124,
    "KP0": 82, "KP1": 83, "KP2": 84, "KP3": 85, "KP4": 86, "KP5": 87,
    "KP6": 88, "KP7": 89, "KP8": 91, "KP9": 92, "KPENTER": 76,
    "LCTRL": 59, "RCTRL": 62, "LSHIFT": 56, "LALT": 58,
}
CHARS = {c: k for k, c in zip(
    [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6],
    "asdfhgzxcvbqweryt123465=97-80]ou[ip"[:26])}  # placeholder, replaced below
# Proper letter and digit map (US layout)
CHARS = {
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
    "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
    "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33,
    "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
}
FN_FLAG = 0x800000
SHIFT_FLAG = 0x20000

_cg = ctypes.cdll.LoadLibrary(ctypes.util.find_library("ApplicationServices"))
_cg.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
_cg.CGEventCreateKeyboardEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool]
_cg.CGEventSetFlags.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
_cg.CGEventPostToPid.argtypes = [ctypes.c_int, ctypes.c_void_p]
_cg.CFRelease.argtypes = [ctypes.c_void_p]

# ATASCII screen codes -> printable, for text screens
def _screencode(c):
    c &= 0x7F
    if c < 64:
        return chr(c + 32)
    if c < 96:
        return chr(c - 64)
    return chr(c)


class Atari:
    def __init__(self, image, cwd=None, extra=(), win=(672, 480)):
        self.image = os.path.abspath(image)
        self.cwd = os.path.abspath(cwd or ".")
        args = ["atari800", "-xl", "-nobasic", "-ntsc", "-ntsc-artif", "none",
                "-scanlines", "0", "-no-scanlinesint",
                "-win-width", str(win[0]), "-win-height", str(win[1]),
                "-no-autosave-config", *extra]
        args.append(self.image) if not self.image.lower().endswith((".xex", ".com", ".exe")) \
            else args.extend(["-run", self.image])
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(self.cwd)
            os.execvp("atari800", args)
        self.in_monitor = False
        self.log = ""

    # ---- pty ----------------------------------------------------------
    def read_for(self, sec):
        out = b""
        end = time.time() + sec
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if r:
                try:
                    out += os.read(self.fd, 65536)
                except OSError:
                    break
        text = out.decode("latin-1")
        self.log += text
        return text

    def boot(self, sec=15):
        """Let the machine boot and the game come up."""
        self.read_for(sec)

    # ---- keys ---------------------------------------------------------
    def _post(self, code, flags=0, hold=0.06):
        for down in (True, False):
            ev = _cg.CGEventCreateKeyboardEvent(None, code, down)
            if flags:
                _cg.CGEventSetFlags(ev, flags)
            _cg.CGEventPostToPid(self.pid, ev)
            _cg.CFRelease(ev)
            time.sleep(hold)

    def key(self, name, settle=0.4, hold=0.06):
        """Press one key by name (see module doc)."""
        if isinstance(name, int):
            self._post(name, 0, hold)
        elif name.upper() in KEYCODES:
            up = name.upper()
            flags = FN_FLAG if up.startswith("F") and up[1:].isdigit() else 0
            self._post(KEYCODES[up], flags, hold)
        elif len(name) == 1 and name.lower() in CHARS:
            flags = SHIFT_FLAG if name.isupper() else 0
            self._post(CHARS[name.lower()], flags, hold)
        else:
            raise ValueError(f"unknown key {name!r}")
        time.sleep(settle)

    def keys(self, *names, settle=0.4):
        for n in names:
            self.key(n, settle=settle)

    # ---- monitor ------------------------------------------------------
    def monitor(self):
        """Freeze the machine in the monitor (F8). Returns the register line."""
        if self.in_monitor:
            return ""
        self.read_for(0.2)
        self._post(KEYCODES["F8"], FN_FLAG)
        out = self.read_for(1.5)
        if ">" not in out:
            raise RuntimeError("monitor prompt did not appear: " + out[-200:])
        self.in_monitor = True
        return out.strip().splitlines()[-2] if len(out.strip().splitlines()) > 1 else out

    def cmd(self, line, sec=1.5):
        """Run a monitor command, return its output (pager answered)."""
        assert self.in_monitor, "call monitor() first"
        os.write(self.fd, (line + "\n").encode())
        out = ""
        while True:
            out += self.read_for(sec)
            if "Press Return to continue" in out[-60:]:
                os.write(self.fd, b"\n")
                continue
            break
        return out

    def cont(self):
        assert self.in_monitor
        os.write(self.fd, b"CONT\n")
        self.read_for(0.3)
        self.in_monitor = False

    def read_mem(self, start, length):
        """Bytes from the frozen machine via the monitor's M command."""
        assert self.in_monitor
        data = bytearray()
        addr = start
        while len(data) < length:
            out = self.cmd(f"M {addr:04X}", 1.0)
            for m in re.finditer(r"^([0-9A-F]{4}): ((?:[0-9A-F]{2} ){16})", out, re.M):
                a = int(m.group(1), 16)
                if a == addr:
                    data += bytes(int(b, 16) for b in m.group(2).split())
                    addr += 16
            if len(data) == 0:
                raise RuntimeError("no memory lines parsed: " + out[-200:])
        return bytes(data[:length])

    def dump(self, start, end, path):
        """Monitor WRITE of a memory block to a file (in the emulator's cwd)."""
        assert self.in_monitor
        return self.cmd(f"WRITE {start:04X} {end:04X} {path}", 1.0)

    def screen_text(self, addr, cols, rows):
        """Decode a text-mode screen (ANTIC screen codes) as lines."""
        raw = self.read_mem(addr, cols * rows)
        return [("".join(_screencode(c) for c in raw[r * cols:(r + 1) * cols])).rstrip()
                for r in range(rows)]

    def dlist(self):
        assert self.in_monitor
        return self.cmd("DLIST", 1.5)

    # ---- screenshots --------------------------------------------------
    def screenshot(self, settle=1.5):
        """F10: atari800 writes the next atariNNN.png (or .pcx) in its cwd. Returns the path."""
        before = set(f for f in os.listdir(self.cwd) if f.endswith((".pcx", ".png")))
        self._post(KEYCODES["F10"], FN_FLAG)
        time.sleep(settle)
        after = set(f for f in os.listdir(self.cwd) if f.endswith((".pcx", ".png"))) - before
        if not after:
            raise RuntimeError("no screenshot appeared")
        return os.path.join(self.cwd, sorted(after)[-1])

    def quit(self):
        try:
            os.kill(self.pid, 9)
        except OSError:
            pass
