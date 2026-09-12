#!/usr/bin/env python3
"""Combat Chess network bring-up: a trivial TCP echo server (milestone N1).

Before any Combat Chess protocol exists, the IIGS W5100 driver needs a
dead-simple peer to prove slot detection, DHCP, TCP connect, and a
send/receive round trip against. This server accepts connections and
echoes back whatever bytes it receives, logging each connection and the
bytes both ways so the driver bring-up is observable from the host.

The IIGS (real hardware or MAME's Uthernet II) connects OUT to this
server, so no port forwarding is needed on the IIGS side; run this on a
host the emulated/real machine can reach (often the same Mac).

Usage:
    python3 server/echo_server.py [--host 0.0.0.0] [--port 1984]
    python3 server/echo_server.py --hex          # log bytes as hex

The default port is 1984, the Combat Chess port from the network spec;
the echo server has no protocol of its own, so any port works.
"""
import argparse
import asyncio
import datetime


def _stamp():
    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]


def _fmt(data, as_hex):
    if as_hex:
        return data.hex(" ")
    # printable-ASCII with dots for the rest, so telnet-style text is legible
    return "".join(chr(b) if 32 <= b < 127 else "." for b in data)


async def handle(reader, writer, as_hex):
    peer = writer.get_extra_info("peername")
    print(f"[{_stamp()}] + connect {peer}", flush=True)
    total = 0
    try:
        while True:
            data = await reader.read(2048)
            if not data:                      # peer closed (FIN)
                break
            total += len(data)
            print(f"[{_stamp()}]   rx {len(data):4d}  {_fmt(data, as_hex)}", flush=True)
            writer.write(data)                # echo it straight back
            await writer.drain()
    except (ConnectionResetError, asyncio.IncompleteReadError):
        pass
    finally:
        print(f"[{_stamp()}] - close   {peer}  ({total} bytes echoed)", flush=True)
        writer.close()
        try:
            await writer.wait_closed()
        except (ConnectionResetError, OSError):
            pass


async def main():
    ap = argparse.ArgumentParser(description="Combat Chess N1 TCP echo server")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=1984)
    ap.add_argument("--hex", action="store_true", help="log bytes as hex, not ASCII")
    a = ap.parse_args()

    server = await asyncio.start_server(
        lambda r, w: handle(r, w, a.hex), a.host, a.port)
    addrs = ", ".join(str(s.getsockname()) for s in server.sockets)
    print(f"[{_stamp()}] echo server listening on {addrs}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
