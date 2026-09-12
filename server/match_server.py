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
# Reconnect grace: how long (seconds) a match survives a human's dropped
# connection before the opponent wins by abandonment (spec 24.2). Tests set
# CC_GRACE low; bots never get a grace (they cannot reconnect).
DEFAULT_GRACE = float(os.environ.get("CC_GRACE", "120"))
# Per-side time budget, server-authoritative (spec: the chess clock). CC_TIME is
# in seconds; tests set it small to force a clock loss. Default 600s = 10 min.
DEFAULT_TIME_MS = int(float(os.environ.get("CC_TIME", "600")) * 1000)
SIDE_NAME = {R.SIDE_RED: "RED", R.SIDE_BLACK: "BLACK"}
ERR_OPPONENT_LOST = 10        # S_ERROR code: your opponent dropped (grace running)


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
        # A dropped peer often leaves a half-sent frame in the transport; a
        # graceful close would try to flush it and raise BrokenPipeError, so
        # abort (discard the buffer, no flush) rather than close+wait_closed.
        self.closed = True
        try:
            self.writer.transport.abort()
        except Exception:
            pass
        try:
            self.writer.close()
        except Exception:
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
        self.state = S.GameState(board, moves_per_turn=moves,
                                 red_time_ms=DEFAULT_TIME_MS,
                                 black_time_ms=DEFAULT_TIME_MS)
        # Server-authoritative clock: the active side's time runs down in wall
        # time; turn_start marks when the current meter began, clock_task is the
        # pending flag-fall. Both None when the meter is stopped (paused/over).
        self.turn_start = None
        self.clock_task = None
        # Reconnect bookkeeping (spec 24): a per-player bearer token, whether
        # each side is currently connected, and any running grace timer.
        self.tokens = {R.SIDE_RED: secrets.token_bytes(16),
                       R.SIDE_BLACK: secrets.token_bytes(16)}
        self.connected = {R.SIDE_RED: True, R.SIDE_BLACK: True}
        self.grace_tasks = {}
        log(f"match {self.match_id}: {red.name!r}(RED) vs {black.name!r}(BLACK) "
            f"board {board}")

    async def start(self):
        self.server.register_match(self)
        blob = self.state.serialize()
        for side, sess in self.players.items():
            opp = self.players[R.SIDE_BLACK if side == R.SIDE_RED else R.SIDE_RED]
            frame = P.match_start_frame(
                self.match_id, side, self.state.board_number,
                self.state.moves_per_turn, self.state.shoot_option,
                self.state.active_side, 3, 5, 3, 5,
                self.state.red_remaining_ms, self.state.black_remaining_ms,
                self.tokens[side], blob, opponent_name=opp.name, seq=sess.out_seq)
            sess.out_seq += 1
            await sess.send(frame)
        self._arm_clock()                      # the starting side's clock begins

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
        self._charge_active()      # bank the active side's think time so the
                                   # snapshot we are about to send shows live clocks
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
                if msg.target_id == S.FR_SQUARE:        # shot at a tree/bridge square
                    outcome, events = self.state.apply_fire_square(
                        sess.side, msg.attacker_id, msg.target_x, msg.target_y)
                else:
                    outcome, events = self.state.apply_fire(
                        sess.side, msg.attacker_id, msg.target_id)
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
            await self._end_game()
        else:
            self._arm_clock()                       # re-arm for the current mover

    # ---- server-authoritative clock ---------------------------------------
    def _loop_time(self):
        return asyncio.get_event_loop().time()

    def _cancel_clock(self):
        if self.clock_task:
            self.clock_task.cancel()
            self.clock_task = None

    def _charge_active(self):
        """Bank the wall time spent since the meter started against the active
        side's remaining, and restart the meter. A no-op while it is stopped."""
        if self.turn_start is None or self.state.game_over:
            return
        now = self._loop_time()
        self.state.deduct_time(self.state.active_side,
                               int((now - self.turn_start) * 1000))
        self.turn_start = now

    def _arm_clock(self):
        """Start the active side's meter and schedule its flag fall. Skipped
        while that side is disconnected (the clock is paused during grace)."""
        self._cancel_clock()
        if self.state.game_over:
            return
        side = self.state.active_side
        if not self.connected.get(side, True):
            self.turn_start = None
            return
        self.turn_start = self._loop_time()
        remaining_s = max(0.0, self.state.remaining_ms(side) / 1000.0)
        self.clock_task = asyncio.create_task(self._flag_fall(remaining_s, side))

    def _pause_clock(self):
        """Stop the meter (a player dropped): bank what the active side has used
        so the grace window itself is not charged, and cancel the flag fall."""
        self._charge_active()
        self._cancel_clock()
        self.turn_start = None

    async def _flag_fall(self, secs, side):
        try:
            await asyncio.sleep(secs)
        except asyncio.CancelledError:
            return
        self.clock_task = None                      # we ARE the task: clear the
        if self.state.game_over or self.state.active_side != side:
            return                                   # handle so _end_game's
        self._charge_active()                       # _cancel_clock is a no-op and
        self.state.timeout(side)                    # cannot cancel us mid-await
        await self._end_game()

    async def _end_game(self):
        self._cancel_clock()
        winner = 0xFF if self.state.winner is None else self.state.winner
        for s2 in self.players.values():
            await s2.send(P.game_over_frame(self.state.over_reason, winner))
        log(f"match {self.match_id}: over reason={self.state.over_reason} "
            f"winner={self.state.winner}")
        self.server.unregister_match(self)          # tokens/grace no longer valid


class Server:
    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.sessions = set()
        self.waiting: list[Session] = []      # simple FIFO matchmaking queue
        self.board = int(os.environ.get("CC_BOARD", DEFAULT_BOARD))
        self.grace_s = DEFAULT_GRACE
        self.matches = {}                     # match_id -> Match (live matches)
        self.tokens = {}                      # reconnect token -> (Match, side)

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
        except (OSError, asyncio.IncompleteReadError, P.ProtocolError) as e:
            # OSError covers ConnectionReset/BrokenPipe -- a socket error on
            # this connection (read, or a pending write surfacing here) is a
            # disconnect; the finally drops the session.
            log(f"session {sess.session_id} error: {e}")
        finally:
            await self.drop(sess)

    def other_side(self, side):
        return R.SIDE_BLACK if side == R.SIDE_RED else R.SIDE_RED

    def register_match(self, m):
        self.matches[m.match_id] = m
        for side, tok in m.tokens.items():
            self.tokens[tok] = (m, side)

    def unregister_match(self, m):
        self.matches.pop(m.match_id, None)
        for tok in list(m.tokens.values()):
            self.tokens.pop(tok, None)
        for task in m.grace_tasks.values():
            task.cancel()
        m.grace_tasks.clear()
        m._cancel_clock()                            # stop any pending flag fall

    async def drop(self, sess):
        self.sessions.discard(sess)
        if sess in self.waiting:
            self.waiting.remove(sess)
        m = sess.match
        # Only the CURRENT session of a live match matters; a stale session
        # already replaced by a reconnect just goes away quietly.
        if m and not m.state.game_over and m.players.get(sess.side) is sess:
            if sess.kind == P.CLIENT_HUMAN:
                await self._enter_grace(m, sess.side)   # keep the match alive
            else:
                await self._forfeit(m, sess.side)       # bots cannot reconnect
        await sess.close()
        log(f"- close session {sess.session_id}")

    async def _forfeit(self, m, side):
        """Immediate loss for `side` -- a bot dropped, or grace is disabled."""
        m.state.surrender(side)
        other = m.players[self.other_side(side)]
        await other.send(P.game_over_frame(S.OVER_SURRENDER, other.side))
        self.unregister_match(m)

    async def _enter_grace(self, m, side):
        """A human dropped mid-match (spec 24.2): keep the match and its token,
        tell the opponent, and start the abandonment timer. The clock is paused
        for the grace window so nobody flags while disconnected; the restored
        S_STATE carries the banked time and _arm_clock resumes it on reconnect."""
        m.connected[side] = False
        m._pause_clock()
        log(f"match {m.match_id}: {SIDE_NAME[side]} disconnected; "
            f"grace {self.grace_s:g}s")
        other = m.players[self.other_side(side)]
        await other.send(P.error_frame(ERR_OPPONENT_LOST, "opponent disconnected"))
        m.grace_tasks[side] = asyncio.create_task(self._grace_expire(m, side))

    async def _grace_expire(self, m, side):
        try:
            await asyncio.sleep(self.grace_s)
        except asyncio.CancelledError:
            return                                       # reconnected in time
        if m.state.game_over or m.connected[side]:
            return
        log(f"match {m.match_id}: {SIDE_NAME[side]} grace expired -> abandonment")
        m.state.surrender(side)                          # loses by abandonment
        other = m.players[self.other_side(side)]
        await other.send(P.game_over_frame(S.OVER_SURRENDER, other.side))
        self.unregister_match(m)

    async def handle_reconnect(self, sess, frame):
        """C_RECONNECT (spec 24.3): a fresh connection presents a match token to
        take over a dropped player's slot; reply S_RECONNECT_RESULT + full state."""
        rc = P.Reconnect.decode(frame.payload)
        entry = self.tokens.get(bytes(rc.token))
        if entry is None:
            await sess.send(P.reconnect_result_frame(P.RC_BAD_TOKEN, 0))
            log(f"session {sess.session_id}: reconnect rejected (bad token)")
            return
        m, side = entry
        if m.match_id != rc.match_id:
            await sess.send(P.reconnect_result_frame(P.RC_BAD_TOKEN, 0))
            return
        if m.state.game_over:
            await sess.send(P.reconnect_result_frame(P.RC_GAME_OVER, side))
            return
        m.players[side] = sess                           # replace the dead link
        sess.match = m
        sess.side = side
        sess.hello_done = True
        m.connected[side] = True
        task = m.grace_tasks.pop(side, None)
        if task:
            task.cancel()
        m._arm_clock()                                   # resume the paused clock
        log(f"match {m.match_id}: {SIDE_NAME[side]} reconnected (session {sess.session_id})")
        await sess.send(P.reconnect_result_frame(P.RC_OK, side, m.state.serialize()))
        other = m.players[self.other_side(side)]
        if other is not sess:                            # nudge the opponent's view
            await other.send(P.state_frame(m.state.serialize()))

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
        elif t == P.C_RECONNECT:
            await self.handle_reconnect(sess, frame)
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
        # selects the opponent (default random): "greedy" pairs the greedy bot,
        # "chooser" the stronger search bot (spec 29.1).
        host = "127.0.0.1" if self.host in ("0.0.0.0", "::") else self.host
        pick = os.environ.get("CC_BOT", "random").lower()
        if pick.startswith("chooser"):
            from bots import chooser_bot
            asyncio.create_task(chooser_bot.run(host, self.port, name="Chooser"))
        elif pick.startswith("greedy"):
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
