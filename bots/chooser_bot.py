#!/usr/bin/env python3
"""Chooser bot (spec 29.1 "Search Bot", N11) -- the stronger opponent tier.

Like the Greedy bot it is an ordinary TCP client that only ever enumerates the
*legal* actions a snapshot allows (via the shared ClientView), but instead of
scoring each action by its immediate effect it looks one ply ahead: it
simulates the action on a copy of the authoritative state, then charges the
opponent's single best counter-shot against the result, and CHOOSES the action
whose position survives that reply best. This shallow minimax over move/fire
sequences (spec 36 / 29.1) makes it noticeably stronger than Greedy -- it will
not advance a unit into a lethal enemy shot, and it values shots that blunt the
opponent's threats, not just its own immediate damage.

Fires are modelled by their *expected* damage (hit% x class damage) so the
search stays deterministic and never touches the server's real hit RNG; moves
are simulated through the authoritative GameState.apply_move, so a simulated
line can never diverge from what the server would allow.

    python3 bots/chooser_bot.py [--host 127.0.0.1] [--port 1984] [--name Chooser]
"""
from __future__ import annotations

import argparse
import asyncio
import copy
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "server"))
import protocol as P
import state as S
import rules as R

_MS_HDR = struct.calcsize("<IBBBBBBBBBII")

# Material value per class; the Battle Cruiser is the win condition so it dwarfs
# the others (which track their durability, CLASS_MAX_HP 24 / 18).
CLASS_VALUE = (100.0, 24.0, 18.0)
WIN = 1.0e6                     # our position after the enemy cruiser dies
LOSS = -1.0e6                   # ... after ours does
BEAM = 8                        # candidate moves carried into the deeper search
EPS = 0.25                      # an action must beat passing by this to be worth it
SAFETY = 0.5                    # weight on the opponent's counter-shot: enough to
#                                 refuse hanging the cruiser (that reply is LOSS) but
#                                 not so much that pressing the attack looks bad


def _match_start_state(payload: bytes):
    (match_id, side, _board, mpt, _shoot, _start,
     _rt, _rc, _bt, _bc, _r_ms, _b_ms) = struct.unpack_from("<IBBBBBBBBBII", payload, 0)
    return match_id, side, mpt, payload[_MS_HDR + 16 + 16:]  # +token +name16


def _action_result_state(payload: bytes):
    off = struct.calcsize("<IHBB")
    n = payload[off]; off += 1
    for _ in range(n):
        off += 1
        nargs = payload[off]; off += 1
        off += nargs
    return payload[off:]


def _dist(ax, ay, bx, by):
    return max(abs(ax - bx), abs(ay - by))


def _cruiser(g, side):
    for u in g.units.values():
        if u.alive and u.hp > 0 and u.cls == R.CLASS_CRUISER and u.side == side:
            return u
    return None


def _legal_moves(g, side):
    out = []
    for u in g.units.values():
        if not u.alive or u.side != side:
            continue
        for ty in range(R.BOARD_H):
            for tx in range(R.BOARD_W):
                rsn, cost, _ = g.validate_move(side, u.id, tx, ty)
                if rsn == S.MV_OK:
                    out.append((u.id, tx, ty, cost))
    return out


def _legal_fires(g, side):
    out = []
    for a in g.units.values():
        if not a.alive or a.side != side:
            continue
        for t in g.units.values():
            if not t.alive or t.side == side:
                continue
            rsn, pct, _ = g.validate_fire(side, a.id, t.id)
            if rsn == S.FR_OK:
                out.append((a.id, t.id, pct))
    return out


def _evaluate(g, me):
    """Static value of a position from `me`'s seat: material (weighted by health
    and class), plus pressure on the enemy cruiser and danger to our own."""
    enemy = 1 - me
    ec = _cruiser(g, enemy)
    mc = _cruiser(g, me)
    if ec is None:
        return WIN
    if mc is None:
        return LOSS
    score = 0.0
    for u in g.units.values():
        if not u.alive or u.hp <= 0:
            continue
        v = CLASS_VALUE[u.cls] * (u.hp / R.CLASS_MAX_HP[u.cls])
        if u.side == me:
            score += v
            if u.cls != R.CLASS_CRUISER:                       # press the attack
                score += max(0, R.BOARD_W - _dist(u.x, u.y, ec.x, ec.y)) * 0.5
        else:
            score -= v
            score -= max(0, R.BOARD_W - _dist(u.x, u.y, mc.x, mc.y)) * 0.4
    return score


def _expected_fire(g, a_id, t_id, pct):
    """Charge one shot's expected damage to the target on g (mutates it)."""
    a = g.units[a_id]
    t = g.units[t_id]
    t.hp -= R.CLASS_DAMAGE[a.cls] * (pct / 100.0)
    if t.hp <= 0:
        t.hp = 0
        t.alive = False
        g.occupant[t.y * R.BOARD_W + t.x] = None


def _reply_value(g, me):
    """Our value after the opponent's single most damaging expected counter-shot
    (its whole turn is deeper, but one clean reply already captures exposure).
    Restores each trial in place, so it never allocates a copy."""
    enemy = 1 - me
    worst = _evaluate(g, me)
    for (a, t_id, pct) in _legal_fires(g, enemy):
        t = g.units[t_id]
        hp0, alive0 = t.hp, t.alive
        cell = t.y * R.BOARD_W + t.x
        occ0 = g.occupant[cell]
        _expected_fire(g, a, t_id, pct)
        v = _evaluate(g, me)
        t.hp, t.alive, g.occupant[cell] = hp0, alive0, occ0
        if v < worst:
            worst = v
    return worst


def _score_move_quick(g, ec, uid, tx, ty, cost):
    u = g.units[uid]
    progress = 0 if ec is None else _dist(u.x, u.y, ec.x, ec.y) - _dist(tx, ty, ec.x, ec.y)
    s = progress * 10.0
    if u.cls == R.CLASS_CRUISER:
        s *= 0.3
    return s - cost * 0.05


class Chooser:
    def __init__(self, my_side, moves_per_turn):
        self.me = my_side
        self.mpt = moves_per_turn
        self.turn_active = False
        self.fired = set()          # spec-13: targets already shot this turn
        self.tried = set()          # actions rejected at the current serial
        self.last_serial = -1

    def choose(self, snap):
        """Return ("fire", a, t) | ("move", uid, tx, ty) | ("end",) | None."""
        if snap["active_side"] != self.me:
            self.turn_active = False
            return None
        if not self.turn_active:
            self.turn_active = True
            self.fired.clear()
        serial = snap.get("state_serial", 0)
        if serial != self.last_serial:
            self.tried.clear()
            self.last_serial = serial

        g = S.ClientView(snap).g
        # ClientView bypasses __init__, so give the simulated state the few
        # fields GameState.apply_move touches (serial + the move cap).
        g.state_serial = 0
        g.moves_per_turn = self.mpt
        ec = _cruiser(g, 1 - self.me)

        # candidate actions: every legal shot we have not already used, plus the
        # best few advancing moves (pruned so the deeper search stays cheap).
        cands = []
        for (a, t, pct) in _legal_fires(g, self.me):
            if (a, t) in self.fired or ("F", a, t) in self.tried:
                continue
            cands.append(("fire", a, t, pct))
        if snap["moves_used"] < self.mpt:
            moves = [m for m in _legal_moves(g, self.me)
                     if ("M", m[0], m[1], m[2]) not in self.tried]
            moves.sort(key=lambda m: _score_move_quick(g, ec, *m), reverse=True)
            for (uid, tx, ty, cost) in moves[:BEAM]:
                cands.append(("move", uid, tx, ty))

        # Passing means we stop and the opponent takes their turn, so passing is
        # charged the FULL counter-shot. An action keeps us on the move (no reply
        # yet), so it is scored by the position it makes, minus only a fraction of
        # the reply it would expose us to -- aggressive, but never hanging a piece
        # to a killer shot (that reply drags the value to LOSS).
        pass_value = _reply_value(g, self.me)
        best_value = pass_value + EPS
        best = None
        for c in cands:
            g2 = copy.deepcopy(g)
            if c[0] == "fire":
                _, a, t, pct = c
                _expected_fire(g2, a, t, pct)
            else:
                _, uid, tx, ty = c
                try:
                    g2.apply_move(self.me, uid, tx, ty)
                except S.RuleError:
                    continue
            base = _evaluate(g2, self.me)
            v = base - SAFETY * (base - _reply_value(g2, self.me))
            if v > best_value:
                best_value = v
                best = c

        if best is None:
            self.turn_active = False
            return ("end",)
        if best[0] == "fire":
            _, a, t, _pct = best
            self.fired.add((a, t))
            self.tried.add(("F", a, t))
            return ("fire", a, t)
        _, uid, tx, ty = best
        self.tried.add(("M", uid, tx, ty))
        return ("move", uid, tx, ty)


async def run(host="127.0.0.1", port=1984, name="Chooser", max_actions=2000):
    reader, writer = await asyncio.open_connection(host, port)
    parser = P.FrameParser()
    out_seq = 0

    async def send(frame):
        nonlocal out_seq
        writer.write(frame)
        await writer.drain()
        out_seq += 1

    await send(P.hello_frame(P.Hello(1, 0, P.CAP_BOT_CLIENT, P.CLIENT_BOT,
                                     name[:P.MAX_NAME]), seq=out_seq))
    match_id = my_side = None
    brain = None
    actions = 0

    async def act_on(blob):
        nonlocal actions
        snap = S.parse_snapshot(blob)
        decision = brain.choose(snap)
        if decision is None:
            return
        kind = decision[0]
        if kind == "fire":
            _, a, t = decision
            await send(P.pack_frame(P.C_FIRE, P.Fire(match_id, actions, a, t).encode(),
                                    seq=out_seq))
        elif kind == "move":
            _, uid, tx, ty = decision
            await send(P.pack_frame(P.C_MOVE, P.Move(match_id, actions, uid, tx, ty).encode(),
                                    seq=out_seq))
        else:
            await send(P.pack_frame(P.C_END_TURN, P.SimpleAction(match_id, actions).encode(),
                                    seq=out_seq))
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
                elif t == P.S_MATCH_START:
                    match_id, my_side, mpt, blob = _match_start_state(frame.payload)
                    brain = Chooser(my_side, mpt)
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
    ap = argparse.ArgumentParser(description="Combat Chess Chooser bot (N11, spec Search Bot)")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=1984)
    ap.add_argument("--name", default="Chooser")
    a = ap.parse_args()
    print(await run(a.host, a.port, a.name))


if __name__ == "__main__":
    asyncio.run(_main())
