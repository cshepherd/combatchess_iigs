#!/usr/bin/env python3
"""Human-vs-human matchmaking test (spec N7), all in-process.

Two clients each queue QUEUE_HUMAN and must be paired with *each other* --
opposite sides, each MATCH_START naming the other player -- and then play a
real round through the authoritative server: RED makes a legal move and ends
its turn, control passes to BLACK, BLACK moves and ends, control returns to
RED. This is the client-facing path the IIGS 'H' (vs human) title option
drives; here both peers are plain sockets so it needs no emulator.

    python3 server/test_human.py
"""
import asyncio
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import protocol as P
import state as S
import rules as R
from match_server import Server

PORT = 19863
_MS_HDR = struct.calcsize("<IBBBBBBBBBII")   # S_MATCH_START fixed header = 21
_TOKEN = 16
_NAME = P.MATCH_NAME_LEN                       # opponent-name field = 16


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
        self.out_seq = 0

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


def parse_match_start(payload):
    match_id, side = struct.unpack_from("<IB", payload, 0)
    mpt = payload[6]
    name = bytes(payload[_MS_HDR + _TOKEN:_MS_HDR + _TOKEN + _NAME]).split(b"\x00")[0]
    blob = payload[_MS_HDR + _TOKEN + _NAME:]
    return match_id, side, mpt, name.decode("ascii", "ignore"), S.parse_snapshot(blob)


async def run():
    os.environ.pop("CC_BOT", None)
    srv = Server("127.0.0.1", PORT)
    server_task = asyncio.create_task(srv.serve())
    await asyncio.sleep(0.2)

    print("test_human_pairing")
    a = Client(PORT, "alice")
    b = Client(PORT, "bob")
    await a.connect()
    await b.connect()
    # alice queues first and waits; bob's queue triggers the pairing
    await a.hello_queue()
    await asyncio.sleep(0.1)
    await b.hello_queue()

    fa = await a.recv(P.S_MATCH_START)
    fb = await b.recv(P.S_MATCH_START)
    mid_a, side_a, mpt_a, opp_a, snap_a = parse_match_start(fa.payload)
    mid_b, side_b, mpt_b, opp_b, snap_b = parse_match_start(fb.payload)

    check(mid_a == mid_b, "both peers are in the same match")
    check(mid_a in srv.matches, "the match is live on the server")
    check({side_a, side_b} == {R.SIDE_RED, R.SIDE_BLACK}, "peers took opposite sides")
    check(opp_a == "bob" and opp_b == "alice", "each MATCH_START names the other player")
    check(len(snap_a["units"]) > 0, "the match carries a full board")

    # map side -> (client, snapshot); RED moves first
    by_side = {side_a: (a, snap_a), side_b: (b, snap_b)}
    red_c, red_snap = by_side[R.SIDE_RED]
    black_c, black_snap = by_side[R.SIDE_BLACK]
    check(red_snap["active_side"] == R.SIDE_RED, "RED is to move at the start")

    # RED plays one legal move and ends the turn
    cv = S.ClientView(red_snap)
    uid, tx, ty, _ = cv.legal_moves(R.SIDE_RED)[0]
    await red_c.send(P.pack_frame(P.C_MOVE,
                                  P.Move(mid_a, 1, uid, tx, ty).encode(), seq=2))
    rf = await red_c.recv(P.S_ACTION_RESULT)
    _, _, _, rcode = struct.unpack_from("<IHBB", rf.payload, 0)
    check(rcode == S.MV_OK, "RED's move was accepted by the server")
    await red_c.send(P.pack_frame(P.C_END_TURN, P.SimpleAction(mid_a, 2).encode(), seq=3))

    # BLACK must now observe its turn and be able to move
    saw_black = False
    black_snap2 = None
    for _ in range(40):
        f = await black_c.recv(P.S_ACTION_RESULT, timeout=4.0)
        # the state blob sits after the header + event list; parse_snapshot needs
        # a clean blob, so decode the event list length to find it
        st = _ar_snapshot(f.payload)
        if st["active_side"] == R.SIDE_BLACK:
            saw_black = True
            black_snap2 = st
            break
    check(saw_black, "control passed to BLACK after RED ended the turn")

    cvb = S.ClientView(black_snap2)
    uidb, txb, tyb, _ = cvb.legal_moves(R.SIDE_BLACK)[0]
    await black_c.send(P.pack_frame(P.C_MOVE,
                                    P.Move(mid_a, 1, uidb, txb, tyb).encode(), seq=2))
    bf = await black_c.recv(P.S_ACTION_RESULT)
    _, _, _, rcodeb = struct.unpack_from("<IHBB", bf.payload, 0)
    check(rcodeb == S.MV_OK, "BLACK's move was accepted by the server")

    # RED resigns (allowed even on the opponent's turn): the server ends the
    # match and sends BOTH peers S_GAME_OVER, the winner being the side that
    # did not surrender. This is the contract the IIGS 'X' (surrender) key uses.
    await red_c.send(P.pack_frame(P.C_SURRENDER, P.SimpleAction(mid_a, 3).encode(), seq=4))
    goa = await red_c.recv(P.S_GAME_OVER)
    gob = await black_c.recv(P.S_GAME_OVER)
    ra, wa = struct.unpack_from("<BB", goa.payload, 0)
    rb, wb = struct.unpack_from("<BB", gob.payload, 0)
    check(ra == S.OVER_SURRENDER and rb == S.OVER_SURRENDER,
          "both peers see GAME_OVER with reason=surrender")
    check(wa == R.SIDE_BLACK and wb == R.SIDE_BLACK,
          "the winner is the side that did not surrender (BLACK)")

    a.close()
    b.close()
    await asyncio.sleep(0.05)
    server_task.cancel()
    print("ALL HUMAN-MATCH TESTS PASSED")


def _ar_snapshot(payload):
    """Pull the state blob out of an S_ACTION_RESULT (hdr + event list + blob)."""
    off = struct.calcsize("<IHBB")            # 8
    n = payload[off]
    off += 1
    for _ in range(n):
        off += 1                              # event type
        nargs = payload[off]
        off += 1 + nargs
    return S.parse_snapshot(payload[off:])


if __name__ == "__main__":
    try:
        asyncio.run(asyncio.wait_for(run(), 25))
    except Exception:
        import traceback
        traceback.print_exc()
        raise SystemExit(1)
