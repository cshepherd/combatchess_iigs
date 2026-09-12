#!/usr/bin/env python3
"""Reconnect / abandonment tests (spec 24, N6).

Runs an in-process match server and drives raw protocol clients over real
loopback TCP to verify:
  - a human that drops mid-match reconnects with its token and resumes,
    getting the full state back (S_RECONNECT_RESULT / RC_OK);
  - a wrong token is rejected (RC_BAD_TOKEN);
  - if nobody reconnects, the opponent wins by abandonment once the grace
    timer expires.

    python3 server/test_reconnect.py
"""
from __future__ import annotations

import asyncio
import os
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
    """A minimal, controllable protocol client (the counterpart to the bots)."""

    def __init__(self, port, name):
        self.port, self.name = port, name
        self.parser = P.FrameParser()
        self.inbox = []
        self.reader = self.writer = None
        self.match_id = self.side = self.token = None

    async def connect(self):
        self.reader, self.writer = await asyncio.open_connection("127.0.0.1", self.port)

    async def send(self, frame):
        self.writer.write(frame)
        await self.writer.drain()

    async def recv(self, want_type, timeout=2.0):
        """Return the next buffered/incoming frame of `want_type`."""
        while True:
            for f in self.inbox:
                if f.msg_type == want_type:
                    self.inbox.remove(f)
                    return f
            data = await asyncio.wait_for(self.reader.read(4096), timeout)
            if not data:
                raise EOFError("server closed the connection")
            self.inbox.extend(self.parser.feed(data))

    async def hello_queue(self):
        await self.send(P.hello_frame(
            P.Hello(1, 0, P.CAP_RECONNECT, P.CLIENT_HUMAN, self.name)))
        await self.recv(P.S_WELCOME)
        await self.send(P.pack_frame(P.C_QUEUE_JOIN,
                                     P.QueueJoin(P.QUEUE_HUMAN).encode()))

    async def recv_match(self):
        ms = await self.recv(P.S_MATCH_START)
        self.match_id, self.side = struct.unpack_from("<IB", ms.payload, 0)
        self.token = bytes(ms.payload[_MS_HDR:_MS_HDR + 16])
        return ms

    def close(self):
        try:
            self.writer.close()
        except Exception:
            pass


async def make_match(port):
    """Two human clients queue and are matched; a=RED, b=BLACK."""
    a = Client(port, "A")
    await a.connect()
    await a.hello_queue()
    await asyncio.sleep(0.05)            # a enqueues first -> a is RED
    b = Client(port, "B")
    await b.connect()
    await b.hello_queue()
    await a.recv_match()
    await b.recv_match()
    assert a.side == R.SIDE_RED and b.side == R.SIDE_BLACK, (a.side, b.side)
    assert a.token != b.token, "each player must get its own token"
    return a, b


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)
    print(f"  ok: {msg}")


async def test_reconnect_ok(server, port):
    print("test_reconnect_ok")
    a, b = await make_match(port)
    mid = a.match_id
    a.close()                            # RED's connection dies
    await asyncio.sleep(0.1)             # let the server enter grace
    check(mid in server.matches, "match survives a dropped human")
    check(not server.matches[mid].connected[R.SIDE_RED], "RED marked disconnected")

    a2 = Client(port, "A-again")         # RED comes back on a fresh connection
    await a2.connect()
    await a2.send(P.reconnect_frame(P.Reconnect(mid, a.token)))
    rr = await a2.recv(P.S_RECONNECT_RESULT)
    code, side = struct.unpack_from("<BB", rr.payload, 0)
    check(code == P.RC_OK, "reconnect accepted (RC_OK)")
    check(side == R.SIDE_RED, "reconnect restored the RED slot")
    snap = S.parse_snapshot(rr.payload[2:])
    check(len(snap["units"]) > 0, "reconnect result carries the full state")
    check(server.matches[mid].players[R.SIDE_RED] is not None
          and server.matches[mid].connected[R.SIDE_RED], "RED reconnected")
    check(R.SIDE_RED not in server.matches[mid].grace_tasks
          or server.matches[mid].grace_tasks[R.SIDE_RED].cancelled()
          or server.matches[mid].grace_tasks[R.SIDE_RED].done(),
          "grace timer cleared on reconnect")
    a2.close()
    b.close()
    await asyncio.sleep(0.05)


async def test_bad_token(server, port):
    print("test_bad_token")
    a, b = await make_match(port)
    c = Client(port, "intruder")
    await c.connect()
    await c.send(P.reconnect_frame(P.Reconnect(a.match_id, b"\x00" * 16)))
    rr = await c.recv(P.S_RECONNECT_RESULT)
    code, _side = struct.unpack_from("<BB", rr.payload, 0)
    check(code == P.RC_BAD_TOKEN, "unknown token rejected (RC_BAD_TOKEN)")
    a.close()
    b.close()
    c.close()
    await asyncio.sleep(0.05)


async def test_abandonment(server, port):
    print("test_abandonment")
    a, b = await make_match(port)
    mid = a.match_id
    a.close()                            # RED drops and never returns
    over = await b.recv(P.S_GAME_OVER, timeout=2.0)
    reason, winner = struct.unpack("<BB", over.payload)
    check(reason == S.OVER_SURRENDER, "abandonment ends the match by surrender")
    check(winner == R.SIDE_BLACK, "the present player (BLACK) wins")
    check(mid not in server.matches, "abandoned match is unregistered")
    b.close()
    await asyncio.sleep(0.05)


async def run():
    port = 19855
    server = MS.Server("127.0.0.1", port)
    server.grace_s = 0.4                 # short grace so the test is quick
    srv = await asyncio.start_server(server.handle_conn, server.host, server.port)
    async with srv:
        await test_reconnect_ok(server, port)
        await test_bad_token(server, port)
        await test_abandonment(server, port)
    print("ALL RECONNECT TESTS PASSED")


if __name__ == "__main__":
    asyncio.run(run())
