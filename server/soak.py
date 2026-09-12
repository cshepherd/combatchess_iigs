#!/usr/bin/env python3
"""Bot-vs-bot soak runner (spec 30, N6).

Starts one in-process match server and plays many bot-vs-bot games across a
set of boards, each game seeded differently, and reports the outcome split
plus anything that looks wrong: a server-side exception, a game that did not
finish within the wall-clock guard (timeout), or one that ran to the action
cap (runaway). Because the bots only ever submit actions the shared
ClientView calls legal, a CLEAN run is evidence that both bots stay legal and
that games actually terminate. random-vs-random with --pass-prob reaches the
idle-turn stalemate instead of the cap, giving fast, varied games.

    python3 server/soak.py --boards 1-10 --games 25 --red random --black random
    python3 server/soak.py --boards 6-8 --games 50 --red greedy --black random
"""
from __future__ import annotations

import argparse
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import match_server as MS
import rules as R
from bots import greedy_bot, random_bot

BOTS = {"greedy": greedy_bot.run, "random": random_bot.run}
REASON = {0: "cruiser", 1: "surrender", 2: "stalemate"}


def _parse_boards(spec):
    out = []
    for part in spec.split(","):
        if "-" in part:
            a, b = part.split("-"); out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def _make_run(kind, port, name, seed, pass_prob, max_actions):
    """A zero-arg coroutine factory for one bot connection."""
    if kind == "random":
        return lambda: random_bot.run(host="127.0.0.1", port=port, name=name,
                                      max_actions=max_actions, seed=seed,
                                      pass_prob=pass_prob)
    return lambda: greedy_bot.run(host="127.0.0.1", port=port, name=name,
                                  max_actions=max_actions)


async def _play_one(port, red_kind, black_kind, seed, pass_prob, max_actions,
                    timeout=60.0):
    """RED connects a beat before BLACK so the server assigns sides in launch
    order; results carry each bot's own side, so attribution is exact anyway."""
    red = _make_run(red_kind, port, "RED", seed, pass_prob, max_actions)
    black = _make_run(black_kind, port, "BLACK", seed ^ 0x5A5A, pass_prob, max_actions)
    red_task = asyncio.create_task(red())
    await asyncio.sleep(0.02)
    black_task = asyncio.create_task(black())
    try:
        return await asyncio.wait_for(asyncio.gather(red_task, black_task), timeout)
    except asyncio.TimeoutError:
        for t in (red_task, black_task):
            t.cancel()
        return ({"winner": None, "reason": "timeout", "actions": -1, "side": 0},
                {"winner": None, "reason": "timeout", "actions": -1, "side": 1})


async def run(games, red_kind, black_kind, boards, pass_prob, max_actions,
              base_seed, port, per_game=False):
    # Catch any server-side exception the event loop would otherwise just log.
    errors = []
    loop = asyncio.get_running_loop()
    prev = loop.get_exception_handler()
    def handler(loop, ctx):
        errors.append(str(ctx.get("exception") or ctx.get("message")))
        (prev or loop.default_exception_handler)(loop, ctx)
    loop.set_exception_handler(handler)

    server = MS.Server("127.0.0.1", port)
    server.grace_s = 2.0
    srv = await asyncio.start_server(server.handle_conn, server.host, server.port)

    total = dict(games=0, red=0, black=0, draw=0, runaway=0, timeout=0)
    reasons = {}
    gi = 0
    async with srv:
        for board in boards:
            server.board = board                 # _try_match reads server.board
            bd = dict(red=0, black=0, draw=0, runaway=0, timeout=0)
            for g in range(games):
                r, b = await _play_one(port, red_kind, black_kind,
                                       base_seed + gi, pass_prob, max_actions)
                gi += 1
                go = next((x for x in (r, b) if x.get("winner") is not None), None)
                reason = REASON.get(go["reason"], str(go["reason"])) if go else "none"
                reasons[reason] = reasons.get(reason, 0) + 1
                if any(x.get("reason") == "timeout" for x in (r, b)):
                    bd["timeout"] += 1
                if max(r.get("actions", 0), b.get("actions", 0)) >= max_actions:
                    bd["runaway"] += 1
                w = go["winner"] if go else None
                if w is None or w == 0xFF:
                    bd["draw"] += 1
                elif w == R.SIDE_RED:
                    bd["red"] += 1
                else:
                    bd["black"] += 1
                if per_game:
                    print(f"  board {board} game {g+1:3d}: {reason:9s} "
                          f"R={r.get('actions')} B={b.get('actions')}")
            for k in bd:
                total[k] += bd[k]
            total["games"] += games
            print(f"board {board:2d}: {games:3d} games | {red_kind}(R) {bd['red']:3d}"
                  f"  {black_kind}(B) {bd['black']:3d}  draw {bd['draw']:3d}"
                  f" | runaway {bd['runaway']:2d}  timeout {bd['timeout']:2d}")

    print("\n=== soak summary ===")
    print(f"  games={total['games']}  {red_kind}(R)={total['red']}  "
          f"{black_kind}(B)={total['black']}  draw={total['draw']}")
    print(f"  reasons={reasons}")
    print(f"  runaway(hit action cap)={total['runaway']}  timeout={total['timeout']}"
          f"  server_errors={len(errors)}")
    clean = not errors and total["timeout"] == 0
    print(f"\nSOAK RESULT: {'CLEAN' if clean else 'ISSUES'}"
          + ("" if clean else f"  ({len(errors)} errors, {total['timeout']} timeouts)"))
    for e in errors[:5]:
        print("  error:", e)
    return clean


async def _main():
    ap = argparse.ArgumentParser(description="Combat Chess bot-vs-bot soak (N6)")
    ap.add_argument("--boards", default="1-10", help='e.g. "1-10" or "6,7,8"')
    ap.add_argument("--games", type=int, default=20, help="games per board")
    ap.add_argument("--red", choices=BOTS, default="random")
    ap.add_argument("--black", choices=BOTS, default="random")
    ap.add_argument("--pass-prob", type=float, default=0.15,
                    help="random bot's per-action chance to pass (reach stalemate)")
    ap.add_argument("--max-actions", type=int, default=800)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--port", type=int, default=19844)
    ap.add_argument("--per-game", action="store_true")
    a = ap.parse_args()
    ok = await run(a.games, a.red, a.black, _parse_boards(a.boards), a.pass_prob,
                   a.max_actions, a.seed, a.port, a.per_game)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    asyncio.run(_main())
