#!/usr/bin/env python3
"""Bot-vs-bot soak runner (spec 30).

Starts an in-process match server on a local port and plays a batch of games
between two bots, then reports the win split. Because the bots only ever
submit actions the shared ClientView says are legal, a clean run is evidence
that both bots stay legal and that games actually terminate (cruiser kill or
the idle-turn stalemate). This is also the seed for the N6 fault/reconnect
soak.

    python3 server/soak.py --games 20 --red greedy --black random
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
SIDE = {R.SIDE_RED: "RED", R.SIDE_BLACK: "BLACK"}


async def _play_one(port, red_run, black_run, timeout=60.0):
    """RED connects a beat before BLACK so the server assigns sides in launch
    order; results carry each bot's own side, so attribution is exact anyway.
    A wall-clock guard keeps one wedged game from hanging the whole run."""
    red_task = asyncio.create_task(red_run(host="127.0.0.1", port=port, name="RED"))
    await asyncio.sleep(0.05)
    black_task = asyncio.create_task(black_run(host="127.0.0.1", port=port, name="BLACK"))
    try:
        return await asyncio.wait_for(asyncio.gather(red_task, black_task), timeout)
    except asyncio.TimeoutError:
        for t in (red_task, black_task):
            t.cancel()
        return ({"winner": None, "reason": "timeout", "actions": -1, "side": 0},
                {"winner": None, "reason": "timeout", "actions": -1, "side": 1})


async def run(games, red_kind, black_kind, port, board=1):
    os.environ["CC_BOARD"] = str(board)          # Server reads CC_BOARD in __init__
    server = MS.Server("127.0.0.1", port)
    srv = await asyncio.start_server(server.handle_conn, server.host, server.port)
    tally = {red_kind + "/RED": 0, black_kind + "/BLACK": 0, "draw": 0}
    reasons = {}
    async with srv:
        for i in range(games):
            red, black = await _play_one(port, BOTS[red_kind], BOTS[black_kind])
            # Take the outcome from whichever bot actually saw S_GAME_OVER; a bot
            # that hit its action cap and disconnected returns winner/reason None.
            go = next((r for r in (red, black) if r.get("winner") is not None), None)
            winner = go["winner"] if go else None
            reason = str(REASON.get(go["reason"], go["reason"])) if go else "capped"
            reasons[reason] = reasons.get(reason, 0) + 1
            if winner is None or winner == 0xFF:
                tally["draw"] += 1
                tag = "draw"
            elif winner == R.SIDE_RED:
                tally[red_kind + "/RED"] += 1
                tag = f"{red_kind}(RED)"
            else:
                tally[black_kind + "/BLACK"] += 1
                tag = f"{black_kind}(BLACK)"
            print(f"game {i+1:3d}: winner {tag:16s} by {reason:9s}"
                  f"  actions R={red['actions']} B={black['actions']}")
    print("\n=== tally ===")
    for k, v in tally.items():
        print(f"  {k:16s} {v}")
    print("  reasons:", reasons)
    return tally


async def _main():
    ap = argparse.ArgumentParser(description="Combat Chess bot-vs-bot soak (N5/N6)")
    ap.add_argument("--games", type=int, default=10)
    ap.add_argument("--red", choices=BOTS, default="greedy")
    ap.add_argument("--black", choices=BOTS, default="random")
    ap.add_argument("--port", type=int, default=19844)
    ap.add_argument("--board", type=int, default=1)
    a = ap.parse_args()
    await run(a.games, a.red, a.black, a.port, a.board)


if __name__ == "__main__":
    asyncio.run(_main())
