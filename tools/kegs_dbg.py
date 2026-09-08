"""Tiny client for the KEGS debug socket.

Start KEGS with `-dbgport 6510` (or whatever port) and then:

    from kegs_dbg import Kegs
    k = Kegs()                          # connects to 127.0.0.1:6510
    k.regs()                            # dump CPU registers
    k.read_mem(0xe1, 0x0000, 0x00ff)    # hex dump of e1/0000..00ff
    k.set_bp(0x00, 0xc50a)              # break on entry to ProDOS MLI
    k.go()                              # resume the emulator
    k.wait_for_halt()                   # block until a breakpoint fires
    k.regs()
    k.step()
    k.halt()                            # async halt of a running emulator
    k.cmd("e1/0010.0020")               # raw command, returns response text

Wire protocol:
  * lines are LF-terminated
  * after each command, the emulator sends "(kegs)\\n" as a prompt marker
  * breakpoint hits and other async output arrive without a prompt;
    wait_for_halt() polls for the "Hit breakpoint at" line
"""

from __future__ import annotations

import socket
import time
from typing import Optional


PROMPT = "(kegs)"


class Kegs:
    def __init__(self, host: str = "127.0.0.1", port: int = 6510,
                 timeout: float = 5.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)
        self._buf = ""
        # Drain the greeting + first prompt
        self._read_until_prompt()

    # ---- low-level I/O --------------------------------------------------

    def _recv_some(self, timeout: Optional[float] = None) -> str:
        if timeout is not None:
            self.sock.settimeout(timeout)
        try:
            data = self.sock.recv(8192)
        except socket.timeout:
            return ""
        if not data:
            raise ConnectionError("kegs debug socket closed")
        return data.decode("utf-8", errors="replace")

    def _read_until_prompt(self, timeout: float = 5.0) -> str:
        """Read lines until we see the '(kegs)' prompt. Return everything
        before it (the prompt line itself is stripped)."""
        deadline = time.monotonic() + timeout
        while PROMPT + "\n" not in self._buf:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(
                    f"no prompt within {timeout}s; got: {self._buf!r}"
                )
            self._buf += self._recv_some(timeout=remaining)
        head, _, self._buf = self._buf.partition(PROMPT + "\n")
        # Trim leading echo line "*<cmd>" if present
        return head

    def cmd(self, line: str, timeout: float = 5.0) -> str:
        """Send a raw command and return its response text."""
        if "\n" in line:
            raise ValueError("cmd line may not contain newline")
        self.sock.sendall((line + "\n").encode("utf-8"))
        return self._read_until_prompt(timeout=timeout)

    def close(self) -> None:
        try:
            self.sock.sendall(b"bye\n")
        except Exception:
            pass
        self.sock.close()

    # ---- convenience wrappers ------------------------------------------

    def regs(self) -> str:
        """Dump CPU registers (mapped to monitor command 'q')."""
        return self.cmd("q")

    def read_mem(self, bank: int, start: int, end: int) -> str:
        """Hex dump memory range [bank/start .. bank/end] (inclusive)."""
        return self.cmd(f"{bank:02x}/{start:04x}.{end:04x}")

    def set_bp(self, bank: int, addr: int) -> str:
        return self.cmd(f"{bank:02x}/{addr:04x}B")

    def clear_bp(self, bank: int, addr: int) -> str:
        return self.cmd(f"{bank:02x}/{addr:04x}D")

    def list_bps(self) -> str:
        return self.cmd("B")

    def go(self) -> None:
        """Resume execution. Returns immediately; emulator runs in its
        own process. Use wait_for_halt() to block until a bp fires."""
        # 'g' has no command output; the prompt comes back right away.
        self.cmd("g")

    def step(self) -> str:
        return self.cmd("s")

    def reset(self) -> str:
        return self.cmd("r")

    def halt(self) -> str:
        """Force the running emulator into the debugger."""
        return self.cmd("halt")

    def wait_for_halt(self, timeout: float = 60.0) -> str:
        """Block until a breakpoint hit message arrives, then return the
        accumulated output. Useful after go()."""
        deadline = time.monotonic() + timeout
        while "Hit breakpoint" not in self._buf and \
                "g_halt_sim:" not in self._buf:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("emulator did not halt in time")
            self._buf += self._recv_some(timeout=remaining)
        # Drain any pending prompt too
        try:
            self._buf += self._recv_some(timeout=0.1)
        except Exception:
            pass
        out, self._buf = self._buf, ""
        return out


if __name__ == "__main__":
    import sys
    k = Kegs(port=int(sys.argv[1]) if len(sys.argv) > 1 else 6510)
    print("REGS:")
    print(k.regs())
    print("MEM e1/0000..001f:")
    print(k.read_mem(0xe1, 0x0000, 0x001f))
    k.close()
