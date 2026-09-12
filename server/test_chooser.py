#!/usr/bin/env python3
"""Chooser (Search) bot strength test (spec 29.1, N11).

The Chooser bot must be a genuinely stronger opponent than Greedy, not just a
legal one. On the open, decidable boards it plays both colours against Greedy;
every game must terminate cleanly, and the Chooser must win more of them than
Greedy does. This locks in the search bot's edge (it looks a ply ahead and will
not hang a piece the way Greedy can), and doubles as a soak of the whole
protocol/rules/server stack driven by the strongest bot.

    python3 server/test_chooser.py
"""
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import rules as R
import match_server as MS
from soak import _play_one

PORT = 19877
BOARDS = [6, 7, 8]          # open boards where a stronger player can force a win
GAMES = 5                   # per board, per colour arrangement


def check(cond, msg):
    if not cond:
        raise AssertionError("FAIL: " + msg)
    print("  ok:", msg)


async def run():
    errors = []
    loop = asyncio.get_running_loop()
    prev = loop.get_exception_handler()
    loop.set_exception_handler(
        lambda l, ctx: (errors.append(str(ctx.get("exception") or ctx.get("message"))),
                        (prev or l.default_exception_handler)(l, ctx)))

    server = MS.Server("127.0.0.1", PORT)
    server.grace_s = 2.0
    srv = await asyncio.start_server(server.handle_conn, server.host, server.port)

    chooser_wins = greedy_wins = decisive = 0
    seed = 1
    async with srv:
        for board in BOARDS:
            server.board = board
            # play both colour arrangements so the board's first/second-mover
            # bias cancels out and only bot skill is compared
            for red_kind, black_kind in (("chooser", "greedy"), ("greedy", "chooser")):
                for _ in range(GAMES):
                    r, _b = await _play_one(PORT, red_kind, black_kind, seed, 0.0, 2000)
                    seed += 1
                    w = r["winner"]
                    check_terminated = w is not None and r["reason"] != "timeout" \
                        and r["actions"] < 2000
                    if not check_terminated:
                        raise AssertionError(
                            f"FAIL: a {red_kind}(R) vs {black_kind}(B) game on board "
                            f"{board} did not terminate cleanly: {r}")
                    decisive += 1
                    winner_kind = red_kind if w == R.SIDE_RED else black_kind
                    if winner_kind == "chooser":
                        chooser_wins += 1
                    else:
                        greedy_wins += 1

    total = len(BOARDS) * GAMES * 2
    print(f"\n  {total} games: chooser {chooser_wins}, greedy {greedy_wins}, "
          f"decisive {decisive}")
    check(not errors, "no server-side exceptions")
    check(decisive == total, "every game terminated cleanly (no timeouts/runaways)")
    check(chooser_wins > 0, "the Chooser can force wins (it is decisive, not passive)")
    check(chooser_wins > greedy_wins,
          f"the Chooser beats the Greedy bot head-to-head ({chooser_wins} > {greedy_wins})")
    print("ALL CHOOSER TESTS PASSED")


if __name__ == "__main__":
    try:
        asyncio.run(asyncio.wait_for(run(), 120))
    except Exception:
        import traceback
        traceback.print_exc()
        raise SystemExit(1)
