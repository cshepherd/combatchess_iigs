#!/usr/bin/env python3
"""Bot difficulty selection test (N12).

A QUEUE_BOT join carries a bot_level the player picked on the options screen;
the server must spawn that bot. Each level is checked by the opponent name in
the resulting MATCH_START (RandomBot / GreedyBot / Chooser), and BOT_DEFAULT
must fall back to the CC_BOT env.

    python3 server/test_botlevel.py
"""
import asyncio
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import protocol as P
from match_server import Server

PORT = 19881
_MS_HDR = struct.calcsize("<IBBBBBBBBBII")


def check(cond, msg):
    if not cond:
        raise AssertionError("FAIL: " + msg)
    print("  ok:", msg)


async def opponent_for(port, level):
    """Queue a bot match at `level` (None = omit -> BOT_DEFAULT) and return the
    opponent's name from MATCH_START."""
    reader, writer = await asyncio.open_connection("127.0.0.1", port)
    parser = P.FrameParser()

    async def recv(want):
        while True:
            data = await asyncio.wait_for(reader.read(4096), 3.0)
            if not data:
                raise EOFError
            for f in parser.feed(data):
                if f.msg_type == want:
                    return f

    writer.write(P.hello_frame(P.Hello(1, 0, 0, P.CLIENT_HUMAN, "picker")))
    await writer.drain()
    await recv(P.S_WELCOME)
    join = P.QueueJoin(P.QUEUE_BOT) if level is None else P.QueueJoin(P.QUEUE_BOT, level)
    writer.write(P.pack_frame(P.C_QUEUE_JOIN, join.encode()))
    await writer.drain()
    ms = await recv(P.S_MATCH_START)
    name = bytes(ms.payload[_MS_HDR + 16:_MS_HDR + 32]).split(b"\x00")[0].decode()
    # surrender to end the match cleanly so the bot exits (no lingering grace)
    match_id = struct.unpack_from("<I", ms.payload, 0)[0]
    writer.write(P.pack_frame(P.C_SURRENDER, P.SimpleAction(match_id, 1).encode()))
    await writer.drain()
    await recv(P.S_GAME_OVER)
    writer.close()
    await asyncio.sleep(0.05)
    return name


async def run():
    server = Server("127.0.0.1", PORT)
    server.grace_s = 0.2
    srv = await asyncio.start_server(server.handle_conn, server.host, server.port)
    try:
        print("test_bot_level_selects_the_opponent")
        check(await opponent_for(PORT, P.BOT_RANDOM) == "RandomBot",
              "level RANDOM spawns the random bot")
        check(await opponent_for(PORT, P.BOT_GREEDY) == "GreedyBot",
              "level GREEDY spawns the greedy bot")
        check(await opponent_for(PORT, P.BOT_CHOOSER) == "Chooser",
              "level CHOOSER spawns the search bot")

        print("test_default_falls_back_to_cc_bot")
        os.environ["CC_BOT"] = "chooser"
        check(await opponent_for(PORT, None) == "Chooser",
              "BOT_DEFAULT with CC_BOT=chooser spawns the search bot")
        os.environ["CC_BOT"] = "random"
        check(await opponent_for(PORT, P.BOT_DEFAULT) == "RandomBot",
              "BOT_DEFAULT with CC_BOT=random spawns the random bot")
        print("ALL BOT-LEVEL TESTS PASSED")
    finally:
        srv.close()


if __name__ == "__main__":
    try:
        asyncio.run(asyncio.wait_for(run(), 20))
    except Exception:
        import traceback
        traceback.print_exc()
        raise SystemExit(1)
