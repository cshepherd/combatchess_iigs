#!/usr/bin/env python3
"""Combat Chess network protocol (spec sections 7-10, 25) -- the N2 layer.

This module is the AUTHORITATIVE definition of the wire format. The Python
server, the Python bots, and the IIGS client (src/proto.s) must all agree
with it byte for byte; tools/gen_fixtures.py emits golden frames from here
that the 65816 encoder/parser are checked against.

Framing (spec 7): every message is an 8-byte header + payload.

    off size field
    0   1    0x43 'C'
    1   1    0x43 'C'
    2   1    protocol version
    3   1    message type
    4   2    payload length   (u16, little-endian)
    6   2    sequence number  (u16, little-endian)

All multibyte protocol integers are little-endian (cheap on the 65816).
Version-1 payloads are at most 1024 bytes; a larger advertised length is a
protocol error. TCP guarantees integrity, so there is no app checksum.
"""
from __future__ import annotations

import struct
from dataclasses import dataclass, field

MAGIC0 = 0x43            # 'C'
MAGIC1 = 0x43            # 'C'
PROTOCOL_VERSION = 1
HEADER_SIZE = 8
MAX_PAYLOAD = 1024

# Message type IDs (spec 9). Client->server names start C_, server->client S_.
C_HELLO = 0x01
S_WELCOME = 0x02
C_QUEUE_JOIN = 0x03
C_QUEUE_LEAVE = 0x04
S_QUEUE_STATUS = 0x05
S_MATCH_START = 0x10
C_MOVE = 0x11
C_FIRE = 0x12
C_END_TURN = 0x13
C_SURRENDER = 0x14
S_ACTION_RESULT = 0x15
S_STATE = 0x16
S_GAME_OVER = 0x17
C_PING = 0x20
S_PONG = 0x21
C_RECONNECT = 0x30
S_RECONNECT_RESULT = 0x31
S_ERROR = 0x7F

TYPE_NAMES = {v: k for k, v in globals().items()
              if isinstance(v, int) and (k.startswith("C_") or k.startswith("S_"))
              and k not in ("C_", "S_")}

# Client kinds (spec 10.1) and capability bits.
CLIENT_HUMAN = 0
CLIENT_BOT = 1
CAP_ENHANCED_UI = 1 << 0
CAP_MOUSE_UI = 1 << 1
CAP_RECONNECT = 1 << 2
CAP_BOT_CLIENT = 1 << 3

MAX_NAME = 15            # player/server names: ASCII, <= 15 bytes (spec 10.1)


class ProtocolError(Exception):
    """Malformed frame or payload: the peer should disconnect."""


# --------------------------------------------------------------------------
# Frame header
# --------------------------------------------------------------------------

def pack_frame(msg_type: int, payload: bytes = b"", seq: int = 0,
               version: int = PROTOCOL_VERSION) -> bytes:
    """Wrap a payload in the 8-byte header and return the full frame bytes."""
    if not 0 <= msg_type <= 0xFF:
        raise ProtocolError(f"message type out of range: {msg_type}")
    if len(payload) > MAX_PAYLOAD:
        raise ProtocolError(f"payload too large: {len(payload)} > {MAX_PAYLOAD}")
    if not 0 <= seq <= 0xFFFF:
        raise ProtocolError(f"sequence out of range: {seq}")
    header = struct.pack("<BBBBHH", MAGIC0, MAGIC1, version, msg_type,
                         len(payload), seq)
    return header + payload


@dataclass
class Frame:
    version: int
    msg_type: int
    seq: int
    payload: bytes

    @property
    def type_name(self) -> str:
        return TYPE_NAMES.get(self.msg_type, f"0x{self.msg_type:02X}")

    def __repr__(self) -> str:
        return (f"Frame({self.type_name} v{self.version} seq={self.seq} "
                f"len={len(self.payload)})")


class FrameParser:
    """Streaming frame parser (spec 34).

    TCP is a byte stream: one SEND does not map to one RECV. Feed whatever
    bytes arrive with feed(); it yields each complete Frame as it becomes
    available and keeps any partial frame staged for the next call.
    """

    def __init__(self) -> None:
        self._buf = bytearray()

    def feed(self, data: bytes):
        """Add received bytes; yield every complete Frame now available."""
        self._buf.extend(data)
        while True:
            if len(self._buf) < HEADER_SIZE:
                return
            if self._buf[0] != MAGIC0 or self._buf[1] != MAGIC1:
                raise ProtocolError("bad frame magic")
            version = self._buf[2]
            msg_type = self._buf[3]
            length = self._buf[4] | (self._buf[5] << 8)
            seq = self._buf[6] | (self._buf[7] << 8)
            if length > MAX_PAYLOAD:
                raise ProtocolError(f"payload length {length} > {MAX_PAYLOAD}")
            if len(self._buf) < HEADER_SIZE + length:
                return                      # frame not complete yet
            payload = bytes(self._buf[HEADER_SIZE:HEADER_SIZE + length])
            del self._buf[:HEADER_SIZE + length]
            yield Frame(version, msg_type, seq, payload)


# --------------------------------------------------------------------------
# Message payloads (N2 subset: HELLO / WELCOME / PING / PONG)
# --------------------------------------------------------------------------

def _encode_name(name: str) -> bytes:
    raw = name.encode("ascii")
    if len(raw) > MAX_NAME:
        raise ProtocolError(f"name too long: {len(raw)} > {MAX_NAME}")
    if any(b < 0x20 or b == 0x7F for b in raw):
        raise ProtocolError("name contains control characters")
    return bytes([len(raw)]) + raw


def _decode_name(payload: bytes, off: int):
    n = payload[off]
    off += 1
    raw = payload[off:off + n]
    if len(raw) != n:
        raise ProtocolError("truncated name")
    return raw.decode("ascii"), off + n


@dataclass
class Hello:
    rules_version: int = 1
    client_build: int = 0
    capability_bits: int = 0
    client_kind: int = CLIENT_HUMAN
    player_name: str = ""

    def encode(self) -> bytes:
        return (struct.pack("<HIHB", self.rules_version, self.client_build,
                            self.capability_bits, self.client_kind)
                + _encode_name(self.player_name))

    @classmethod
    def decode(cls, payload: bytes) -> "Hello":
        rules_version, client_build, capability_bits, client_kind = \
            struct.unpack_from("<HIHB", payload, 0)
        name, off = _decode_name(payload, 9)
        if off != len(payload):
            raise ProtocolError("trailing bytes in C_HELLO")
        return cls(rules_version, client_build, capability_bits, client_kind, name)


@dataclass
class Welcome:
    accepted_rules_version: int = 1
    session_id: int = 0
    server_flags: int = 0
    server_name: str = ""

    def encode(self) -> bytes:
        return (struct.pack("<HIH", self.accepted_rules_version, self.session_id,
                            self.server_flags)
                + _encode_name(self.server_name))

    @classmethod
    def decode(cls, payload: bytes) -> "Welcome":
        accepted_rules_version, session_id, server_flags = \
            struct.unpack_from("<HIH", payload, 0)
        name, off = _decode_name(payload, 8)
        if off != len(payload):
            raise ProtocolError("trailing bytes in S_WELCOME")
        return cls(accepted_rules_version, session_id, server_flags, name)


@dataclass
class Ping:
    """Keepalive (spec 25). A nonce the peer echoes back in S_PONG."""
    nonce: int = 0

    def encode(self) -> bytes:
        return struct.pack("<I", self.nonce)

    @classmethod
    def decode(cls, payload: bytes) -> "Ping":
        (nonce,) = struct.unpack("<I", payload)
        return cls(nonce)


@dataclass
class Pong:
    nonce: int = 0

    def encode(self) -> bytes:
        return struct.pack("<I", self.nonce)

    @classmethod
    def decode(cls, payload: bytes) -> "Pong":
        (nonce,) = struct.unpack("<I", payload)
        return cls(nonce)


# Convenience frame builders (payload + header in one step).
def hello_frame(hello: Hello, seq: int = 0) -> bytes:
    return pack_frame(C_HELLO, hello.encode(), seq)


def welcome_frame(welcome: Welcome, seq: int = 0) -> bytes:
    return pack_frame(S_WELCOME, welcome.encode(), seq)


def ping_frame(ping: Ping, seq: int = 0) -> bytes:
    return pack_frame(C_PING, ping.encode(), seq)


def pong_frame(pong: Pong, seq: int = 0) -> bytes:
    return pack_frame(S_PONG, pong.encode(), seq)


if __name__ == "__main__":
    # Smoke test: round-trip each message and re-parse a concatenated stream.
    frames = [
        hello_frame(Hello(1, 0x00010203, CAP_ENHANCED_UI | CAP_RECONNECT,
                          CLIENT_HUMAN, "cshepherd"), seq=1),
        welcome_frame(Welcome(1, 0xDEADBEEF, 0, "CombatChess"), seq=1),
        ping_frame(Ping(0x11223344), seq=2),
        pong_frame(Pong(0x11223344), seq=2),
    ]
    stream = b"".join(frames)
    parser = FrameParser()
    # feed the stream one byte at a time to exercise the staging buffer
    got = []
    for b in stream:
        got.extend(parser.feed(bytes([b])))
    assert len(got) == 4, got
    assert Hello.decode(got[0].payload).player_name == "cshepherd"
    assert Welcome.decode(got[1].payload).server_name == "CombatChess"
    assert Ping.decode(got[2].payload).nonce == 0x11223344
    assert Pong.decode(got[3].payload).nonce == 0x11223344
    print("protocol.py smoke test OK:", [f.type_name for f in got])


# --------------------------------------------------------------------------
# N3 messages: matchmaking, actions, results, state (spec 11-21)
# --------------------------------------------------------------------------

# Matchmaking mode for C_QUEUE_JOIN (spec 11).
QUEUE_QUICK = 0
QUEUE_HUMAN = 1
QUEUE_BOT = 2

# Bot difficulty a client may request with a QUEUE_BOT join (the player picks it
# on the options screen). BOT_DEFAULT leaves the choice to the server's CC_BOT.
BOT_RANDOM = 0
BOT_GREEDY = 1
BOT_CHOOSER = 2
BOT_DEFAULT = 0xFF


@dataclass
class QueueJoin:
    mode: int = QUEUE_QUICK
    bot_level: int = BOT_DEFAULT

    def encode(self) -> bytes:
        return struct.pack("<BB", self.mode, self.bot_level)

    @classmethod
    def decode(cls, payload: bytes) -> "QueueJoin":
        # tolerate a legacy 1-byte join (no level -> server default)
        level = payload[1] if len(payload) > 1 else BOT_DEFAULT
        return cls(payload[0], level)


@dataclass
class Move:
    match_id: int
    action_id: int
    unit_id: int
    dest_x: int
    dest_y: int

    def encode(self) -> bytes:
        return struct.pack("<IHBBB", self.match_id, self.action_id,
                           self.unit_id, self.dest_x, self.dest_y)

    @classmethod
    def decode(cls, p: bytes) -> "Move":
        return cls(*struct.unpack("<IHBBB", p))


@dataclass
class Fire:
    """C_FIRE: attacker fires at target_id, or at square (target_x,target_y)
    when target_id == 0xFF (a shot at destructible terrain)."""
    match_id: int
    action_id: int
    attacker_id: int
    target_id: int
    target_x: int = 0
    target_y: int = 0

    def encode(self) -> bytes:
        return struct.pack("<IHBBBB", self.match_id, self.action_id,
                           self.attacker_id, self.target_id,
                           self.target_x, self.target_y)

    @classmethod
    def decode(cls, p: bytes) -> "Fire":
        return cls(*struct.unpack("<IHBBBB", p))


@dataclass
class SimpleAction:
    """C_END_TURN / C_SURRENDER: match_id + action_id only."""
    match_id: int
    action_id: int

    def encode(self) -> bytes:
        return struct.pack("<IH", self.match_id, self.action_id)

    @classmethod
    def decode(cls, p: bytes) -> "SimpleAction":
        return cls(*struct.unpack("<IH", p))


# S_RECONNECT_RESULT result codes.
RC_OK = 0
RC_BAD_TOKEN = 1        # unknown / wrong token
RC_NO_MATCH = 2         # match_id not found (expired / never existed)
RC_GAME_OVER = 3        # the match already ended


@dataclass
class Reconnect:
    """C_RECONNECT (spec 24.3): resume a match after a dropped connection.
    The token is a per-match, per-player bearer credential from S_MATCH_START.
    last_action_id / last_state_serial let the server tell how far behind the
    client is (it always re-sends the full state, so they are advisory)."""
    match_id: int
    token: bytes                       # exactly 16 bytes
    last_action_id: int = 0
    last_state_serial: int = 0

    def encode(self) -> bytes:
        assert len(self.token) == 16
        return (struct.pack("<I", self.match_id) + self.token +
                struct.pack("<HI", self.last_action_id, self.last_state_serial))

    @classmethod
    def decode(cls, p: bytes) -> "Reconnect":
        (match_id,) = struct.unpack_from("<I", p, 0)
        token = bytes(p[4:20])
        last_action_id, last_serial = struct.unpack_from("<HI", p, 20)
        return cls(match_id, token, last_action_id, last_serial)


MATCH_NAME_LEN = 16       # opponent-name field in S_MATCH_START: MAX_NAME + NUL


def match_start_frame(match_id, assigned_side, board_number, moves_per_turn,
                      shoot_option, starting_side, red_tanks, red_cars,
                      black_tanks, black_cars, red_time_ms, black_time_ms,
                      reconnect_token: bytes, state_blob: bytes,
                      opponent_name: str = "", seq: int = 0) -> bytes:
    """S_MATCH_START (spec 12): fixed header + reconnect token + a fixed
    16-byte NUL-padded opponent name + the serialized state."""
    assert len(reconnect_token) == 16
    hdr = struct.pack("<IBBBBBBBBBII", match_id, assigned_side, board_number,
                      moves_per_turn, shoot_option, starting_side,
                      red_tanks, red_cars, black_tanks, black_cars,
                      red_time_ms, black_time_ms)
    name = opponent_name.encode("ascii", "ignore")[:MAX_NAME]
    name = name + b"\x00" * (MATCH_NAME_LEN - len(name))
    return pack_frame(S_MATCH_START,
                      hdr + reconnect_token + name + state_blob, seq)


def encode_events(events) -> bytes:
    """Self-describing event list: for each, u8 type, u8 nargs, u8 args[]."""
    out = bytearray([len(events)])
    for ev in events:
        etype = ev[0]
        args = ev[1:]
        out.append(etype)
        out.append(len(args))
        for a in args:
            out.append(a & 0xFF)
    return bytes(out)


def action_result_frame(match_id, action_id, action_type, result_code,
                        events, state_blob: bytes, seq: int = 0) -> bytes:
    """S_ACTION_RESULT (spec 19): result header + events + state snapshot."""
    hdr = struct.pack("<IHBB", match_id, action_id, action_type, result_code)
    return pack_frame(S_ACTION_RESULT, hdr + encode_events(events) + state_blob, seq)


def state_frame(state_blob: bytes, seq: int = 0) -> bytes:
    """S_STATE (spec 20): the canonical snapshot alone."""
    return pack_frame(S_STATE, state_blob, seq)


def game_over_frame(reason, winner, seq: int = 0) -> bytes:
    """S_GAME_OVER: reason + winner (0xFF winner = draw)."""
    return pack_frame(S_GAME_OVER, struct.pack("<BB", reason, winner & 0xFF), seq)


def error_frame(code, message: str = "", seq: int = 0) -> bytes:
    raw = message.encode("ascii")[:255]
    return pack_frame(S_ERROR, struct.pack("<BB", code, len(raw)) + raw, seq)


def reconnect_frame(rc: Reconnect, seq: int = 0) -> bytes:
    return pack_frame(C_RECONNECT, rc.encode(), seq)


def reconnect_result_frame(result_code, assigned_side, state_blob: bytes = b"",
                           seq: int = 0) -> bytes:
    """S_RECONNECT_RESULT: u8 result_code, u8 assigned_side, then (on RC_OK)
    the full snapshot so the client re-syncs the board and clocks."""
    hdr = struct.pack("<BB", result_code, assigned_side & 0xFF)
    return pack_frame(S_RECONNECT_RESULT, hdr + state_blob, seq)
