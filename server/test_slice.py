#!/usr/bin/env python3
"""N3 vertical-slice test (spec 46), all in-process.

Starts the match server, connects a human client, requests a bot match,
makes one legal move, ends the turn, and confirms the Random bot (a real
TCP client the server spawns) takes its own legal turn -- all validated
by the authoritative server. Exercises protocol.py + state.py + rules.py
+ match_server.py + bots/random_bot.py together.
"""
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import protocol as P
import state as S
import rules as R
from match_server import Server
from bots.random_bot import _match_start_state, _action_result_state

PORT = 19847


class Client:
    def __init__(self, reader, writer):
        self.reader, self.writer = reader, writer
        self.parser = P.FrameParser()
        self.seq = 0

    async def send(self, frame):
        self.writer.write(frame); await self.writer.drain()

    async def next_frame(self, want=None, timeout=3.0):
        while True:
            # drain already-parsed frames first
            data = await asyncio.wait_for(self.reader.read(2048), timeout)
            if not data:
                raise EOFError("server closed")
            for f in self.parser.feed(data):
                if want is None or f.msg_type == want:
                    return f


async def run():
    srv = Server("127.0.0.1", PORT)
    server_task = asyncio.create_task(srv.serve())
    await asyncio.sleep(0.2)
    ok = True

    reader, writer = await asyncio.open_connection("127.0.0.1", PORT)
    c = Client(reader, writer)

    # 1-2. HELLO -> WELCOME
    await c.send(P.hello_frame(P.Hello(1, 0, P.CAP_ENHANCED_UI, P.CLIENT_HUMAN,
                                       "cshepherd"), seq=0))
    wf = await c.next_frame(P.S_WELCOME)
    w = P.Welcome.decode(wf.payload)
    print(f"1-2. WELCOME from {w.server_name!r} session={w.session_id}")
    assert w.server_name == "CombatChess"

    # 3-4. request bot match -> MATCH_START on board 1
    await c.send(P.pack_frame(P.C_QUEUE_JOIN, P.QueueJoin(P.QUEUE_BOT).encode(), seq=1))
    mf = await c.next_frame(P.S_MATCH_START)
    match_id, my_side, mpt, blob = _match_start_state(mf.payload)
    snap = S.parse_snapshot(blob)
    print(f"3-5. MATCH_START match={match_id} my_side={my_side} "
          f"board=1 units={len(snap['units'])} moves/turn={mpt} "
          f"active={snap['active_side']}")
    assert my_side == R.SIDE_RED and snap["active_side"] == R.SIDE_RED

    # 5-6. make one legal move -> authoritative ACTION_RESULT
    cv = S.ClientView(snap)
    moves = cv.legal_moves(my_side)
    uid, tx, ty, cost = moves[0]
    before_serial = snap["state_serial"]
    await c.send(P.pack_frame(P.C_MOVE, P.Move(match_id, 1, uid, tx, ty).encode(), seq=2))
    rf = await c.next_frame(P.S_ACTION_RESULT)
    import struct
    mid, aid, atype, rcode = struct.unpack_from("<IHBB", rf.payload, 0)
    snap2 = S.parse_snapshot(_action_result_state(rf.payload))
    moved = next(u for u in snap2["units"] if u["id"] == uid)
    print(f"6. MOVE unit {uid} -> ({moved['x']},{moved['y']}) result={rcode} "
          f"serial {before_serial}->{snap2['state_serial']}")
    assert rcode == S.MV_OK and (moved["x"], moved["y"]) == (tx, ty)
    assert snap2["state_serial"] == before_serial + 1

    # 7. end our turn; the bot should then take its own turn
    await c.send(P.pack_frame(P.C_END_TURN, P.SimpleAction(match_id, 2).encode(), seq=3))
    # collect frames until we observe a BLACK-side action (the bot moving)
    saw_bot_turn = False
    saw_bot_action = False
    for _ in range(40):
        f = await c.next_frame(P.S_ACTION_RESULT, timeout=4.0)
        st = S.parse_snapshot(_action_result_state(f.payload))
        if st["active_side"] == R.SIDE_BLACK:
            saw_bot_turn = True
        # a bot move/fire increments serial while BLACK is active
        mid, aid, atype, rcode = struct.unpack_from("<IHBB", f.payload, 0)
        if atype in (P.C_MOVE, P.C_FIRE) and rcode in (S.MV_OK, S.FR_OK) \
           and st["active_side"] == R.SIDE_BLACK:
            saw_bot_action = True
            print(f"8. bot ({['RED','BLACK'][R.SIDE_BLACK]}) took action "
                  f"type=0x{atype:02X} serial={st['state_serial']}")
            break
    assert saw_bot_turn, "never became the bot's turn"
    assert saw_bot_action, "bot never acted"

    writer.close()
    try:
        await writer.wait_closed()
    except OSError:
        pass
    server_task.cancel()
    print("\nVERTICAL SLICE OK: connect -> welcome -> bot match -> board 1 ->"
          " human move -> authoritative state -> bot move")
    return ok


if __name__ == "__main__":
    try:
        asyncio.run(asyncio.wait_for(run(), 20))
    except Exception as e:
        import traceback; traceback.print_exc()
        raise SystemExit(1)
