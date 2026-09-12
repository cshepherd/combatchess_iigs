#!/usr/bin/env python3
"""Generate byte-exact protocol fixtures (spec N2: "protocol fixtures").

Each fixture is one complete frame with fixed inputs, written as a raw
.bin under server/fixtures/ plus an entry in manifest.json describing its
decoded fields and hex. These golden files are the contract between the
Python protocol (server/protocol.py) and the IIGS encoder/parser
(src/proto.s): the Python test checks encode(inputs)==bytes and
decode(bytes)==inputs, and the IIGS test builds each frame with proto.s
and compares it to the same .bin, then parses the .bin back.

Run:  python3 tools/gen_fixtures.py           # (re)write fixtures
      python3 tools/gen_fixtures.py --check    # verify without writing
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "server"))
import protocol as P  # noqa: E402

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "server", "fixtures")

# Each fixture: (name, msg_type, seq, builder, decoder, fields-for-manifest).
# Inputs are fixed and deliberately exercise every field width.
FIXTURES = [
    (
        "hello_human",
        P.C_HELLO, 1,
        lambda: P.Hello(
            rules_version=1,
            client_build=0x00010203,
            capability_bits=P.CAP_ENHANCED_UI | P.CAP_RECONNECT,
            client_kind=P.CLIENT_HUMAN,
            player_name="cshepherd",
        ),
        P.Hello.decode,
    ),
    (
        "hello_bot",
        P.C_HELLO, 7,
        lambda: P.Hello(
            rules_version=1,
            client_build=0xAABBCCDD,
            capability_bits=P.CAP_BOT_CLIENT,
            client_kind=P.CLIENT_BOT,
            player_name="RandomBot",
        ),
        P.Hello.decode,
    ),
    (
        "welcome",
        P.S_WELCOME, 1,
        lambda: P.Welcome(
            accepted_rules_version=1,
            session_id=0xDEADBEEF,
            server_flags=0x0001,
            server_name="CombatChess",
        ),
        P.Welcome.decode,
    ),
    (
        "ping",
        P.C_PING, 0x1234,
        lambda: P.Ping(nonce=0x11223344),
        P.Ping.decode,
    ),
    (
        "pong",
        P.S_PONG, 0x1234,
        lambda: P.Pong(nonce=0x11223344),
        P.Pong.decode,
    ),
    (
        "queue_bot",
        P.C_QUEUE_JOIN, 3,
        lambda: P.QueueJoin(mode=P.QUEUE_BOT),
        P.QueueJoin.decode,
    ),
    (
        "move",
        P.C_MOVE, 0x0007,
        lambda: P.Move(match_id=0x01020304, action_id=0x0009,
                       unit_id=5, dest_x=9, dest_y=3),
        P.Move.decode,
    ),
    (
        "fire",
        P.C_FIRE, 0x0008,
        lambda: P.Fire(match_id=0x01020304, action_id=0x000A,
                       attacker_id=5, target_id=12),
        P.Fire.decode,
    ),
]

# Map message type -> the frame builder that adds the header.
FRAME_OF = {
    P.C_HELLO: P.hello_frame,
    P.S_WELCOME: P.welcome_frame,
    P.C_PING: P.ping_frame,
    P.S_PONG: P.pong_frame,
    P.C_QUEUE_JOIN: lambda m, seq=0: P.pack_frame(P.C_QUEUE_JOIN, m.encode(), seq),
    P.C_MOVE: lambda m, seq=0: P.pack_frame(P.C_MOVE, m.encode(), seq),
    P.C_FIRE: lambda m, seq=0: P.pack_frame(P.C_FIRE, m.encode(), seq),
}


def build(name, msg_type, seq, make, decode):
    msg = make()
    frame = FRAME_OF[msg_type](msg, seq=seq)
    # Self-check: re-parse the frame and re-decode the payload.
    (parsed,) = list(P.FrameParser().feed(frame))
    assert parsed.msg_type == msg_type, name
    assert parsed.seq == seq, name
    round_tripped = decode(parsed.payload)
    assert round_tripped == msg, f"{name}: {round_tripped} != {msg}"
    return frame, msg


def manifest_entry(name, msg_type, seq, frame, msg):
    fields = {k: v for k, v in vars(msg).items()}
    return {
        "name": name,
        "type": msg_type,
        "type_name": P.TYPE_NAMES.get(msg_type, hex(msg_type)),
        "seq": seq,
        "payload_len": len(frame) - P.HEADER_SIZE,
        "frame_len": len(frame),
        "fields": fields,
        "hex": frame.hex(),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate protocol fixtures")
    ap.add_argument("--check", action="store_true",
                    help="verify existing fixtures instead of writing")
    args = ap.parse_args()

    entries = []
    changed = False
    if not args.check:
        os.makedirs(OUT_DIR, exist_ok=True)

    for name, msg_type, seq, make, decode in FIXTURES:
        frame, msg = build(name, msg_type, seq, make, decode)
        path = os.path.join(OUT_DIR, name + ".bin")
        if args.check:
            with open(path, "rb") as f:
                on_disk = f.read()
            if on_disk != frame:
                print(f"MISMATCH: {name}.bin differs from protocol.py", file=sys.stderr)
                return 1
        else:
            old = None
            if os.path.exists(path):
                with open(path, "rb") as f:
                    old = f.read()
            if old != frame:
                with open(path, "wb") as f:
                    f.write(frame)
                changed = True
        entries.append(manifest_entry(name, msg_type, seq, frame, msg))
        print(f"{name:14s} {P.TYPE_NAMES.get(msg_type):14s} "
              f"{len(frame):3d}B  {frame.hex()}")

    # S_STATE fixture: the deterministic board-1 initial snapshot, wrapped in
    # a frame. Used to validate the IIGS S_STATE parser network-free.
    import state as ST
    g = ST.GameState(1, moves_per_turn=5)
    blob = g.serialize()
    sframe = P.state_frame(blob, seq=1)
    spath = os.path.join(OUT_DIR, "state_board1.bin")
    if args.check:
        with open(spath, "rb") as f:
            if f.read() != sframe:
                print("MISMATCH: state_board1.bin differs", file=sys.stderr)
                return 1
    else:
        old = open(spath, "rb").read() if os.path.exists(spath) else None
        if old != sframe:
            with open(spath, "wb") as f:
                f.write(sframe)
            changed = True
    snap = ST.parse_snapshot(blob)
    entries.append({
        "name": "state_board1", "type": P.S_STATE, "type_name": "S_STATE",
        "seq": 1, "payload_len": len(blob), "frame_len": len(sframe),
        "fields": {"active_side": snap["active_side"], "unit_count": len(snap["units"]),
                   "state_serial": snap["state_serial"],
                   "units": [[u["id"], u["cls"], u["side"], u["x"], u["y"], u["hp"],
                              u["fuel"], u["ammo"], u["terr_hp"], u["flags"]]
                             for u in snap["units"]]},
        "hex": sframe.hex(),
    })
    print(f"{'state_board1':14s} {'S_STATE':14s} {len(sframe):3d}B  "
          f"({len(snap['units'])} units, {ST.R.BOARD_CELLS}B terrain)")

    manifest = {
        "protocol_version": P.PROTOCOL_VERSION,
        "header_size": P.HEADER_SIZE,
        "max_payload": P.MAX_PAYLOAD,
        "fixtures": entries,
    }
    mpath = os.path.join(OUT_DIR, "manifest.json")
    if args.check:
        with open(mpath) as f:
            if json.load(f) != manifest:
                print("MISMATCH: manifest.json is stale", file=sys.stderr)
                return 1
        print("fixtures OK (match protocol.py)")
    else:
        with open(mpath, "w") as f:
            json.dump(manifest, f, indent=2)
        print(f"wrote {len(entries)} fixtures to {OUT_DIR}"
              + ("" if changed else " (no change)"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
