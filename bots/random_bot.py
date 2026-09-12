#!/usr/bin/env python3
"""Random bot (spec 29.1) -- an ordinary TCP client of the match server.

Connects, HELLOs as a bot, joins matchmaking, and on each authoritative
snapshot where it is the side to move it takes one random legal action
(prefer a legal shot, else a legal move, else end the turn). It never
computes rules itself beyond enumerating legal actions from the snapshot
via the shared ClientView, so it can only ever attempt legal moves.

    python3 bots/random_bot.py [--host 127.0.0.1] [--port 1984] [--name RandomBot]
"""
from __future__ import annotations

import argparse
import asyncio
import os
import random
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "server"))
import protocol as P
import state as S

# S_MATCH_START (spec 12): <IBBBBBBBBBII> header + 16-byte token +
# 16-byte opponent name + serialized state.
_MS_HDR = struct.calcsize("<IBBBBBBBBBII")


def _match_start_state(payload: bytes):
    (match_id, assigned_side) = struct.unpack_from("<IB", payload, 0)
    moves_per_turn = payload[3]                 # 4th byte after match_id (offset 6? see below)
    # decode the fields we need explicitly
    (match_id, assigned_side, board, mpt, shoot, start,
     rt, rc, bt, bc, r_ms, b_ms) = struct.unpack_from("<IBBBBBBBBBII", payload, 0)
    blob = payload[_MS_HDR + 16 + 16:]      # skip token + 16-byte opponent name
    return match_id, assigned_side, mpt, blob


def _action_result_state(payload: bytes):
    # <IHBB> header, then events (u8 count; each u8 type,u8 nargs,args), then state
    off = struct.calcsize("<IHBB")
    n = payload[off]; off += 1
    for _ in range(n):
        off += 1                                # type
        nargs = payload[off]; off += 1
        off += nargs
    return payload[off:]


async def run(host="127.0.0.1", port=1984, name="RandomBot", max_actions=2000,
              seed=None, pass_prob=0.0):
    # pass_prob: chance per action of ending the turn instead of acting, so
    # random-vs-random games reach the idle-turn stalemate instead of running
    # to the action cap. 0 (the default, used by the live bot) never passes.
    rng = random.Random(seed)
    reader, writer = await asyncio.open_connection(host, port)
    parser = P.FrameParser()
    out_seq = 0

    async def send(frame):
        writer.write(frame)
        await writer.drain()

    hello = P.Hello(1, 0, P.CAP_BOT_CLIENT, P.CLIENT_BOT, name[:P.MAX_NAME])
    await send(P.hello_frame(hello, seq=out_seq)); out_seq += 1

    match_id = None
    my_side = None
    moves_per_turn = 5
    actions = 0

    async def act_on(blob):
        nonlocal actions, out_seq
        snap = S.parse_snapshot(blob)
        if snap["active_side"] != my_side:
            return
        cv = S.ClientView(snap)
        fires = cv.legal_fires(my_side)
        moves = cv.legal_moves(my_side) if snap["moves_used"] < moves_per_turn else []
        if pass_prob and rng.random() < pass_prob:
            fires = moves = []                    # pass -> ends the turn below
        if fires:
            a, t, _ = rng.choice(fires)
            await send(P.pack_frame(P.C_FIRE,
                       P.Fire(match_id, actions, a, t).encode(), seq=out_seq))
        elif moves:
            uid, tx, ty, _ = rng.choice(moves)
            await send(P.pack_frame(P.C_MOVE,
                       P.Move(match_id, actions, uid, tx, ty).encode(), seq=out_seq))
        else:
            await send(P.pack_frame(P.C_END_TURN,
                       P.SimpleAction(match_id, actions).encode(), seq=out_seq))
        out_seq += 1
        actions += 1

    try:
        while actions < max_actions:
            data = await reader.read(2048)
            if not data:
                break
            for frame in parser.feed(data):
                t = frame.msg_type
                if t == P.S_WELCOME:
                    await send(P.pack_frame(P.C_QUEUE_JOIN,
                               P.QueueJoin(P.QUEUE_HUMAN).encode(), seq=out_seq))
                    out_seq += 1
                elif t == P.S_MATCH_START:
                    match_id, my_side, moves_per_turn, blob = _match_start_state(frame.payload)
                    await act_on(blob)
                elif t == P.S_ACTION_RESULT:
                    await act_on(_action_result_state(frame.payload))
                elif t == P.S_GAME_OVER:
                    reason, winner = struct.unpack("<BB", frame.payload)
                    return {"reason": reason, "winner": winner,
                            "actions": actions, "side": my_side}
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionResetError, OSError):
            pass
    return {"reason": None, "winner": None, "actions": actions, "side": my_side}


async def _main():
    ap = argparse.ArgumentParser(description="Combat Chess Random bot (N5)")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=1984)
    ap.add_argument("--name", default="RandomBot")
    a = ap.parse_args()
    print(await run(a.host, a.port, a.name))


if __name__ == "__main__":
    asyncio.run(_main())
