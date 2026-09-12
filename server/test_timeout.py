#!/usr/bin/env python3
"""Server-authoritative time control test (spec N9).

The server runs each side's chess clock in wall time and ends the match when a
side's clock reaches zero -- the other side wins on time (OVER_TIME). Here two
human clients match with a tiny per-side budget; RED then sits idle and must
flag, and BOTH peers must receive S_GAME_OVER with reason=time, winner=BLACK.
A second match confirms the clock is charged to whoever is on the move: BLACK
idles on its turn and flags instead.

    python3 server/test_timeout.py
"""
import asyncio
import os
import struct
import sys

# a short per-side clock so the flag falls quickly; must be set before import
os.environ["CC_TIME"] = "0.6"                  # 600 ms per side

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import protocol as P
import state as S
import rules as R
import match_server as MS

PORT = 19871
_MS_HDR = struct.calcsize("<IBBBBBBBBBII")
_TOKEN = 16
_NAME = P.MATCH_NAME_LEN


def check(cond, msg):
    if not cond:
        raise AssertionError("FAIL: " + msg)
    print("  ok:", msg)


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

    async def recv(self, want_type, timeout=3.0):
        while True:
            for f in self.inbox:
                if f.msg_type == want_type:
                    self.inbox.remove(f)
                    return f
            data = await asyncio.wait_for(self.reader.read(4096), timeout)
            if not data:
                raise EOFError("server closed")
            self.inbox.extend(self.parser.feed(data))

    async def hello_queue(self):
        await self.send(P.hello_frame(P.Hello(1, 0, 0, P.CLIENT_HUMAN, self.name)))
        await self.recv(P.S_WELCOME)
        await self.send(P.pack_frame(P.C_QUEUE_JOIN, P.QueueJoin(P.QUEUE_HUMAN).encode()))

    def close(self):
        try:
            self.writer.close()
        except Exception:
            pass


async def _match_two(srv, port):
    a = Client(port, "alice")
    b = Client(port, "bob")
    await a.connect()
    await b.connect()
    await a.hello_queue()
    await asyncio.sleep(0.05)
    await b.hello_queue()
    fa = await a.recv(P.S_MATCH_START)
    fb = await b.recv(P.S_MATCH_START)
    mid, side_a = struct.unpack_from("<IB", fa.payload, 0)
    side_b = struct.unpack_from("<IB", fb.payload, 0)[1]
    by_side = {side_a: a, side_b: b}
    return by_side[R.SIDE_RED], by_side[R.SIDE_BLACK], mid


async def _await_over(client):
    f = await client.recv(P.S_GAME_OVER, timeout=3.0)
    reason, winner = struct.unpack_from("<BB", f.payload, 0)
    return reason, winner


async def run():
    srv = MS.Server("127.0.0.1", PORT)
    server_task = asyncio.create_task(srv.serve())
    await asyncio.sleep(0.2)
    check(MS.DEFAULT_TIME_MS == 600, "the test clock is 600 ms per side")

    # 1) RED idles on its own turn (RED moves first) and must flag; BLACK wins.
    print("test_red_flags")
    red, black, mid = await _match_two(srv, PORT)
    loop = asyncio.get_event_loop()
    t0 = loop.time()
    ra, wa = await _await_over(red)
    rb, wb = await _await_over(black)
    elapsed = loop.time() - t0
    check(ra == S.OVER_TIME and rb == S.OVER_TIME,
          "both peers see GAME_OVER with reason=time")
    check(wa == R.SIDE_BLACK and wb == R.SIDE_BLACK,
          "the winner is BLACK (RED ran out of time)")
    check(0.3 < elapsed < 2.0, f"the flag fell about a clock later ({elapsed:.2f}s)")
    red.close(); black.close()
    await asyncio.sleep(0.1)

    # 2) The clock follows the mover: RED ends its turn immediately, then BLACK
    #    idles on ITS turn and must be the one to flag (RED wins).
    print("test_clock_follows_the_mover")
    red, black, mid = await _match_two(srv, PORT)
    # RED hands the turn straight over (spends almost no time)
    await red.send(P.pack_frame(P.C_END_TURN, P.SimpleAction(mid, 1).encode(), seq=2))
    await red.recv(P.S_ACTION_RESULT)
    ra, wa = await _await_over(red)
    rb, wb = await _await_over(black)
    check(ra == S.OVER_TIME and rb == S.OVER_TIME,
          "both peers see GAME_OVER with reason=time")
    check(wa == R.SIDE_RED and wb == R.SIDE_RED,
          "the winner is RED (BLACK ran out of time on its own turn)")
    red.close(); black.close()
    await asyncio.sleep(0.1)

    server_task.cancel()
    print("ALL TIMEOUT TESTS PASSED")


if __name__ == "__main__":
    try:
        asyncio.run(asyncio.wait_for(run(), 20))
    except Exception:
        import traceback
        traceback.print_exc()
        raise SystemExit(1)
