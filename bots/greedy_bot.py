#!/usr/bin/env python3
"""Greedy bot (spec 29.2, N5) -- an ordinary TCP client of the match server.

Like the Random bot it only ever enumerates the *legal* actions a snapshot
allows (via the shared ClientView, so it can never attempt an illegal one),
but instead of choosing at random it scores each action and takes the best:

- the best shot (expected damage x target value, with a probable kill worth
  extra and a probable kill of the enemy Battle Cruiser dominating), else
- the best advancing move (the one that brings a unit closest to the enemy
  cruiser; the cruiser itself advances cautiously), else
- end the turn.

This is the network mirror of the local greedy computer player in
src/aiplayer.s: a first-pass, look-ahead-free "reasonable default opponent"
(spec: do not block release on sophisticated AI).

    python3 bots/greedy_bot.py [--host 127.0.0.1] [--port 1984] [--name GreedyBot]
"""
from __future__ import annotations

import argparse
import asyncio
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "server"))
import protocol as P
import state as S
import rules as R

# S_MATCH_START fixed header (spec 12): <IBBBBBBBBBII> + 16-byte token.
_MS_HDR = struct.calcsize("<IBBBBBBBBBII")

# Material value per class for shot scoring. The Battle Cruiser is the win
# condition, so it is worth far more than its raw hit points; tank and car
# track their durability (CLASS_MAX_HP 24 / 18).
CLASS_VALUE = (100, 24, 18)


def _match_start_state(payload: bytes):
    (match_id, assigned_side, board, mpt, shoot, start,
     rt, rc, bt, bc, r_ms, b_ms) = struct.unpack_from("<IBBBBBBBBBII", payload, 0)
    return match_id, assigned_side, mpt, payload[_MS_HDR + 16:]


def _action_result_state(payload: bytes):
    # <IHBB> header, then events (u8 count; each u8 type,u8 nargs,args), then state
    off = struct.calcsize("<IHBB")
    n = payload[off]; off += 1
    for _ in range(n):
        off += 1                                # type
        nargs = payload[off]; off += 1
        off += nargs
    return payload[off:]


def _dist(ax, ay, bx, by):
    """King-move distance: the board moves in 8 directions, so a diagonal
    step closes both axes at once."""
    return max(abs(ax - bx), abs(ay - by))


def _enemy_cruiser(g, my_side):
    for u in g.units.values():
        if u.side != my_side and u.cls == R.CLASS_CRUISER:
            return u
    return None


def _score_fire(g, a_id, t_id, pct):
    """Expected-damage-weighted value of one shot, with kill and cruiser
    bonuses. All bonuses scale with the hit probability so a long, unlikely
    shot never outranks a solid one."""
    a = g.units[a_id]
    t = g.units[t_id]
    p = pct / 100.0
    dmg = R.CLASS_DAMAGE[a.cls]
    value = CLASS_VALUE[t.cls]
    score = p * dmg * value                     # expected damage x material
    lethal = dmg >= t.hp                         # this single hit would destroy it
    if lethal:
        score += p * value * 3.0                 # finishing a unit is worth extra
    if t.cls == R.CLASS_CRUISER:
        score += p * 500.0                       # any threat to the enemy cruiser
        if lethal:
            score += p * 100000.0                # a probable cruiser-kill wins the game
    return score


def _score_move(g, ec, uid, tx, ty, cost):
    """How much a move advances a unit toward the enemy cruiser (positive =
    closer), lightly penalised by fuel so ties favour the cheaper move. The
    cruiser advances cautiously (it is the piece we cannot afford to lose)."""
    u = g.units[uid]
    if ec is None:
        progress = 0
    else:
        progress = _dist(u.x, u.y, ec.x, ec.y) - _dist(tx, ty, ec.x, ec.y)
    score = progress * 10.0
    if u.cls == R.CLASS_CRUISER:
        score *= 0.3
    score -= cost * 0.05
    return score


async def run(host="127.0.0.1", port=1984, name="GreedyBot", max_actions=2000):
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
    # Per-turn / per-state memory. The S_STATE snapshot does not carry the
    # spec-13 "already fired at this target this turn" mask, so ClientView
    # keeps offering a shot the server has already consumed; `fired` remembers
    # the shots we took so we do not re-offer them for the rest of the turn.
    # `tried` guards any action the server rejects at an unchanged state (its
    # state_serial does not advance) so a deterministic choice cannot loop.
    turn_active = [False]
    fired = set()
    tried = set()
    last_serial = [-1]

    async def act_on(blob):
        nonlocal actions, out_seq
        snap = S.parse_snapshot(blob)
        if snap["active_side"] != my_side:
            turn_active[0] = False
            return
        if not turn_active[0]:                   # first action of a fresh turn
            turn_active[0] = True
            fired.clear()
        serial = snap.get("state_serial", 0)
        if serial != last_serial[0]:             # the board actually moved on
            tried.clear()
            last_serial[0] = serial
        cv = S.ClientView(snap)
        g = cv.g
        ec = _enemy_cruiser(g, my_side)

        fires = [f for f in cv.legal_fires(my_side)
                 if (f[0], f[1]) not in fired and ("F", f[0], f[1]) not in tried]
        if fires:                                # the best shot, always worth taking
            a, t, _pct = max(fires, key=lambda f: _score_fire(g, f[0], f[1], f[2]))
            fired.add((a, t))
            tried.add(("F", a, t))
            await send(P.pack_frame(P.C_FIRE,
                       P.Fire(match_id, actions, a, t).encode(), seq=out_seq))
        else:
            moves = cv.legal_moves(my_side) if snap["moves_used"] < moves_per_turn else []
            advancing = [(m, _score_move(g, ec, m[0], m[1], m[2], m[3])) for m in moves
                         if ("M", m[0], m[1], m[2]) not in tried]
            advancing = [ms for ms in advancing if ms[1] > 0]     # only real progress
            if advancing:
                (uid, tx, ty, _cost), _s = max(advancing, key=lambda ms: ms[1])
                tried.add(("M", uid, tx, ty))
                await send(P.pack_frame(P.C_MOVE,
                           P.Move(match_id, actions, uid, tx, ty).encode(), seq=out_seq))
            else:                                # nothing gains ground -> pass
                turn_active[0] = False
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
    ap = argparse.ArgumentParser(description="Combat Chess Greedy bot (N5)")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=1984)
    ap.add_argument("--name", default="GreedyBot")
    a = ap.parse_args()
    print(await run(a.host, a.port, a.name))


if __name__ == "__main__":
    asyncio.run(_main())
