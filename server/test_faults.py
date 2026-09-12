#!/usr/bin/env python3
"""Network fault tests (spec N6).

The match server must survive hostile or broken traffic without crashing and
must keep healthy matches alive:
  - garbage on the wire (bad magic, oversized length, random bytes) drops
    only that session, and the server stays up for the next client;
  - a human in a live match can drop and reconnect with its token over and
    over, and the match survives each time (spec 24).

    python3 server/test_faults.py
"""
from __future__ import annotations

import asyncio
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import protocol as P
import state as S
import rules as R
import match_server as MS

_MS_HDR = struct.calcsize("<IBBBBBBBBBII")   # S_MATCH_START fixed header = 21


class Client:
    def __init__(self, port, name):
        self.port, self.name = port, name
        self.parser = P.FrameParser()
        self.inbox = []
        self.reader = self.writer = None

    async def connect(self):
        self.reader, self.writer = await asyncio.open_connection("127.0.0.1", self.port)

    async def send(self, frame):
        self.writer.write(frame)
        await self.writer.drain()

    async def recv(self, want_type, timeout=2.0):
        while True:
            for f in self.inbox:
                if f.msg_type == want_type:
                    self.inbox.remove(f)
                    return f
            data = await asyncio.wait_for(self.reader.read(4096), timeout)
            if not data:
                raise EOFError("server closed")
            self.inbox.extend(self.parser.feed(data))

    def close(self):
        try:
            self.writer.close()
        except Exception:
            pass


def check(cond, msg):
    if not cond:
        raise AssertionError("FAIL: " + msg)
    print("  ok:", msg)


async def server_alive(port):
    """The server is healthy iff a fresh client HELLO gets a WELCOME back."""
    c = Client(port, "probe")
    await c.connect()
    await c.send(P.hello_frame(P.Hello(1, 0, 0, P.CLIENT_HUMAN, "probe")))
    try:
        await c.recv(P.S_WELCOME)
        return True
    finally:
        c.close()


async def _garbage(port, payload, label):
    r, w = await asyncio.open_connection("127.0.0.1", port)
    w.write(payload)
    await w.drain()
    try:
        data = await asyncio.wait_for(r.read(256), 2.0)
        check(data == b"", f"server closed the {label} session")
    except (ConnectionResetError, asyncio.IncompleteReadError):
        check(True, f"server reset the {label} session")
    except asyncio.TimeoutError:
        # the server may just ignore/buffer -- fine as long as it stays alive
        check(True, f"server did not crash on {label}")
    finally:
        w.close()
    check(await server_alive(port), f"server still serving after {label}")


async def test_malformed(server, port):
    print("test_malformed")
    await _garbage(port, b"XXXXXXXXXXXXXXXX", "bad-magic")
    # valid magic, a length field claiming far more than MAX_PAYLOAD
    await _garbage(port, bytes([0x43, 0x43, 1, P.C_HELLO]) + struct.pack("<HH", 60000, 0),
                   "oversized-length")
    rnd = random.Random(7)
    await _garbage(port, bytes(rnd.randrange(256) for _ in range(8192)), "random-flood")
    # a half frame then silence must not wedge the server either
    await _garbage(port, bytes([0x43, 0x43, 1, P.C_HELLO]), "truncated-header")


async def test_reconnect_under_load(server, port):
    """Bot match; the human drops and reconnects with its token repeatedly."""
    print("test_reconnect_under_load")
    os.environ["CC_BOT"] = "random"
    a = Client(port, "iigs")
    await a.connect()
    await a.send(P.hello_frame(P.Hello(1, 0, P.CAP_RECONNECT, P.CLIENT_HUMAN, "iigs")))
    await a.recv(P.S_WELCOME)
    await a.send(P.pack_frame(P.C_QUEUE_JOIN, P.QueueJoin(P.QUEUE_BOT).encode()))
    ms = await a.recv(P.S_MATCH_START)
    mid, side = struct.unpack_from("<IB", ms.payload, 0)
    token = bytes(ms.payload[_MS_HDR:_MS_HDR + 16])
    check(mid in server.matches, "bot match is live")

    conn = a
    for i in range(6):
        conn.close()                              # network blip
        await asyncio.sleep(0.15)                  # let the server notice + grace
        check(mid in server.matches, f"match survives drop #{i+1}")
        conn = Client(port, "iigs-again")
        await conn.connect()
        await conn.send(P.reconnect_frame(P.Reconnect(mid, token)))
        rr = await conn.recv(P.S_RECONNECT_RESULT)
        code, rside = struct.unpack_from("<BB", rr.payload, 0)
        check(code == P.RC_OK and rside == side, f"reconnect #{i+1} restored the slot")
        snap = S.parse_snapshot(rr.payload[2:])
        check(len(snap["units"]) > 0, f"reconnect #{i+1} carried the full state")
    check(mid in server.matches, "match still live after 6 drop/reconnect cycles")
    conn.close()
    await asyncio.sleep(0.05)


async def test_alive_during_match(server, port):
    """Garbage from a stranger must not disturb a running match."""
    print("test_alive_during_match")
    os.environ["CC_BOT"] = "random"
    a = Client(port, "p1")
    await a.connect()
    await a.send(P.hello_frame(P.Hello(1, 0, P.CAP_RECONNECT, P.CLIENT_HUMAN, "p1")))
    await a.recv(P.S_WELCOME)
    await a.send(P.pack_frame(P.C_QUEUE_JOIN, P.QueueJoin(P.QUEUE_BOT).encode()))
    ms = await a.recv(P.S_MATCH_START)
    mid, _ = struct.unpack_from("<IB", ms.payload, 0)
    # a stranger floods garbage
    await _garbage(port, bytes(random.Random(3).randrange(256) for _ in range(4096)),
                   "stranger-flood-during-match")
    check(mid in server.matches, "the running match was untouched by the garbage")
    a.close()
    await asyncio.sleep(0.05)


async def run():
    port = 19855
    server = MS.Server("127.0.0.1", port)
    server.grace_s = 0.4
    srv = await asyncio.start_server(server.handle_conn, server.host, server.port)
    async with srv:
        await test_malformed(server, port)
        await test_reconnect_under_load(server, port)
        await test_alive_during_match(server, port)
    print("ALL FAULT TESTS PASSED")


if __name__ == "__main__":
    asyncio.run(run())
