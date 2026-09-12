#!/usr/bin/env python3
"""Combat Chess authoritative match server (spec N3, sections 27-28).

Accepts TCP clients, runs the HELLO/WELCOME handshake, matchmaking
(QUICK / HUMAN / BOT), and authoritative matches: it validates and
applies every MOVE / FIRE / END_TURN / SURRENDER against a GameState and
broadcasts a full canonical snapshot after each accepted action. Clients
send actions; the server owns truth (spec 47).

    python3 server/match_server.py [--host 0.0.0.0] [--port 1984]

Bots (spec N5) connect as ordinary clients; a QUEUE_BOT request spawns a
Random bot client (bots/random_bot.py) that connects back to this server.
"""
from __future__ import annotations

import argparse
import asyncio
import datetime
import os
import secrets
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import protocol as P
import state as S
import rules as R

SERVER_NAME = "CombatChess"
DEFAULT_BOARD = 1
DEFAULT_MOVES = 5


def _stamp():
    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]


def log(*a):
    print(f"[{_stamp()}]", *a, flush=True)


class Session:
    _next_id = 1

    def __init__(self, server, reader, writer):
        self.server = server
        self.reader = reader
        self.writer = writer
        self.parser = P.FrameParser()
        self.peer = writer.get_extra_info("peername")
        self.session_id = Session._next_id
        Session._next_id += 1
        self.name = ""
        self.kind = P.CLIENT_HUMAN
        self.hello_done = False
        self.match = None
        self.side = None
        self.out_seq = 0
        self.closed = False

    async def send(self, frame: bytes):
        if self.closed:
            return
        try:
            self.writer.write(frame)
            await self.writer.drain()
        except (ConnectionResetError, BrokenPipeError, OSError):
            self.closed = True

    async def close(self):
        self.closed = True
        try:
            self.writer.close()
            await self.writer.wait_closed()
        except (ConnectionResetError, OSError):
            pass


class Match:
    _next_id = 1

    def __init__(self, server, red: Session, black: Session,
                 board=DEFAULT_BOARD, moves=DEFAULT_MOVES):
        self.server = server
        self.match_id = Match._next_id
        Match._next_id += 1
        self.players = {R.SIDE_RED: red, R.SIDE_BLACK: black}
        red.match = black.match = self
        red.side, black.side = R.SIDE_RED, R.SIDE_BLACK
        self.state = S.GameState(board, moves_per_turn=moves)
        log(f"match {self.match_id}: {red.name!r}(RED) vs {black.name!r}(BLACK) "
            f"board {board}")

    async def start(self):
        token = secrets.token_bytes(16)
        blob = self.state.serialize()
        for side, sess in self.players.items():
            frame = P.match_start_frame(
                self.match_id, side, self.state.board_number,
                self.state.moves_per_turn, self.state.shoot_option,
                self.state.active_side, 3, 5, 3, 5,
                self.state.red_remaining_ms, self.state.black_remaining_ms,
                token, blob, seq=sess.out_seq)
            sess.out_seq += 1
            await sess.send(frame)

    async def broadcast(self, frame_fn):
        blob = self.state.serialize()
        for sess in self.players.values():
            await sess.send(frame_fn(blob, sess))

    async def handle_action(self, sess: Session, frame: P.Frame):
        """Validate + apply one action; broadcast the result. Server-authority:
        reject wrong turn / wrong side with an S_ACTION_RESULT reason."""
        t = frame.msg_type
        # decode common header (match_id, action_id)
        if t in (P.C_MOVE,):
            msg = P.Move.decode(frame.payload)
        elif t == P.C_FIRE:
            msg = P.Fire.decode(frame.payload)
        else:
            msg = P.SimpleAction.decode(frame.payload)
        action_id = msg.action_id

        def result(code, events):
            def fn(blob, _s):
                return P.action_result_frame(self.match_id, action_id, t, code,
                                             events, blob)
            return fn

        # must be this player's turn
        if self.state.game_over:
            await sess.send(P.error_frame(1, "game over"))
            return
        if sess.side != self.state.active_side and t != P.C_SURRENDER:
            await self.broadcast(result(0xFE, []))    # not your turn
            return
        try:
            if t == P.C_MOVE:
                if self.state.moves_used >= self.state.moves_per_turn:
                    await self.broadcast(result(0xFD, []))   # no moves left
                    return
                events = self.state.apply_move(sess.side, msg.unit_id,
                                               msg.dest_x, msg.dest_y)
                await self.broadcast(result(S.MV_OK, events))
            elif t == P.C_FIRE:
                outcome, events = self.state.apply_fire(sess.side,
                                                        msg.attacker_id, msg.target_id)
                await self.broadcast(result(S.FR_OK, events))
            elif t == P.C_END_TURN:
                events = self.state.end_turn()
                await self.broadcast(result(0, events))
            elif t == P.C_SURRENDER:
                self.state.surrender(sess.side)
                await self.broadcast(result(0, [(S.EV_TURN_CHANGED,
                                                 self.state.active_side)]))
        except S.RuleError as e:
            await self.broadcast(result(e.code, []))
            return

        if self.state.game_over:
            winner = 0xFF if self.state.winner is None else self.state.winner
            for s2 in self.players.values():
                await s2.send(P.game_over_frame(self.state.over_reason, winner))
            log(f"match {self.match_id}: over reason={self.state.over_reason} "
                f"winner={self.state.winner}")


class Server:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.sessions = set()
        self.waiting: list[Session] = []      # simple FIFO matchmaking queue
        self.board = int(os.environ.get("CC_BOARD", DEFAULT_BOARD))

    async def handle_conn(self, reader, writer):
        sess = Session(self, reader, writer)
        self.sessions.add(sess)
        log(f"+ connect {sess.peer} (session {sess.session_id})")
        try:
            while not sess.closed:
                data = await reader.read(2048)
                if not data:
                    break
                for frame in sess.parser.feed(data):
                    await self.dispatch(sess, frame)
        except (ConnectionResetError, asyncio.IncompleteReadError, P.ProtocolError) as e:
            log(f"session {sess.session_id} error: {e}")
        finally:
            await self.drop(sess)

    async def drop(self, sess):
        self.sessions.discard(sess)
        if sess in self.waiting:
            self.waiting.remove(sess)
        if sess.match and not sess.match.state.game_over:
            # opponent wins by forfeit
            m = sess.match
            other = m.players[R.SIDE_BLACK if sess.side == R.SIDE_RED else R.SIDE_RED]
            m.state.surrender(sess.side)
            await other.send(P.game_over_frame(S.OVER_SURRENDER, other.side))
        await sess.close()
        log(f"- close session {sess.session_id}")

    async def dispatch(self, sess: Session, frame: P.Frame):
        t = frame.msg_type
        if t == P.C_HELLO:
            hello = P.Hello.decode(frame.payload)
            sess.name = hello.player_name
            sess.kind = hello.client_kind
            sess.hello_done = True
            welcome = P.Welcome(1, sess.session_id, 0, SERVER_NAME)
            await sess.send(P.welcome_frame(welcome, seq=sess.out_seq))
            sess.out_seq += 1
            log(f"session {sess.session_id}: HELLO {hello.player_name!r} "
                f"kind={hello.client_kind}")
        elif t == P.C_QUEUE_JOIN:
            if not sess.hello_done:
                await sess.send(P.error_frame(2, "hello first"))
                return
            join = P.QueueJoin.decode(frame.payload)
            await self.enqueue(sess, join.mode)
        elif t == P.C_PING:
            ping = P.Ping.decode(frame.payload)
            await sess.send(P.pong_frame(P.Pong(ping.nonce), seq=frame.seq))
        elif t in (P.C_MOVE, P.C_FIRE, P.C_END_TURN, P.C_SURRENDER):
            if sess.match:
                await sess.match.handle_action(sess, frame)
        else:
            await sess.send(P.error_frame(3, f"unexpected type 0x{t:02X}"))

    async def enqueue(self, sess: Session, mode: int):
        log(f"session {sess.session_id}: QUEUE mode={mode}")
        if mode == P.QUEUE_BOT:
            # spawn a bot client that connects back and is matched to this human
            self.waiting.append(sess)
            asyncio.create_task(self._spawn_bot())
            return
        self.waiting.append(sess)
        await self._try_match()

    async def _try_match(self):
        while len(self.waiting) >= 2:
            a = self.waiting.pop(0)
            b = self.waiting.pop(0)
            if a.closed or b.closed:
                continue
            match = Match(self, a, b, board=self.board)
            await match.start()

    async def _spawn_bot(self):
        # import lazily so the server runs even without the bot module. CC_BOT
        # selects the opponent (default random); "greedy" pairs the greedy bot.
        host = "127.0.0.1" if self.host in ("0.0.0.0", "::") else self.host
        if os.environ.get("CC_BOT", "random").lower().startswith("greedy"):
            from bots import greedy_bot
            asyncio.create_task(greedy_bot.run(host, self.port, name="GreedyBot"))
        else:
            from bots import random_bot
            asyncio.create_task(random_bot.run(host, self.port, name="RandomBot"))
        # give the bot a moment to connect+hello+queue, then match
        await asyncio.sleep(0.2)
        await self._try_match()

    async def serve(self):
        server = await asyncio.start_server(self.handle_conn, self.host, self.port)
        addrs = ", ".join(str(s.getsockname()) for s in server.sockets)
        log(f"match server listening on {addrs}")
        async with server:
            await server.serve_forever()


async def main():
    ap = argparse.ArgumentParser(description="Combat Chess match server (N3)")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=1984)
    a = ap.parse_args()
    await Server(a.host, a.port).serve()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
