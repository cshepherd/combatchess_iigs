#!/usr/bin/env python3
"""
PackBytes - Apple IIgs compatible RLE compressor/decompressor.

Implements the PackBytes/UnPackBytes format used by the Apple IIgs ROM Toolbox.

Encoding format:
  00xxxxxx  1-64 literal bytes follow            (xxxxxx + 1 bytes)
  01xxxxxx  3,5,6,7 repeats of next byte          (xxxxxx = 2,4,5,6)
  10xxxxxx  1-64 repeats of next 4 bytes           (xxxxxx + 1 repeats)
  11xxxxxx  1-64 repeats of next byte as 4 bytes   (xxxxxx + 1 repeats of 4)

Usage:
  python packbytes.py pack   input.bin output.pak
  python packbytes.py unpack input.pak output.bin
  python packbytes.py pack   --verify input.bin output.pak
"""

import sys
import argparse


def find_byte_run(data, pos):
    """Count consecutive identical bytes starting at pos."""
    if pos >= len(data):
        return 0
    val = data[pos]
    end = pos + 1
    while end < len(data) and data[end] == val:
        end += 1
    return end - pos


def find_4byte_pattern(data, pos):
    """Count consecutive repeats of a 4-byte pattern starting at pos.
    Returns 0 if fewer than 2 repeats or pattern is all one byte value."""
    if pos + 7 > len(data):
        return 0
    pat = data[pos:pos + 4]
    # All-same-byte patterns are handled more efficiently as byte runs
    if pat[0] == pat[1] == pat[2] == pat[3]:
        return 0
    count = 1
    while pos + (count + 1) * 4 <= len(data):
        if data[pos + count * 4:pos + (count + 1) * 4] == pat:
            count += 1
        else:
            break
    return count if count >= 2 else 0


def flush_literals(out, literals):
    """Emit literal bytes using 00xxxxxx encoding (up to 64 per chunk)."""
    i = 0
    while i < len(literals):
        n = min(len(literals) - i, 64)
        out.append(n - 1)  # 00xxxxxx
        out.extend(literals[i:i + n])
        i += n


def emit_byte_run(out, val, count):
    """Encode a run of identical bytes.

    Uses 11xxxxxx for groups of 4 (max 64 groups = 256 bytes per chunk)
    and 01xxxxxx for remainders of 3, 5, 6, or 7.

    Returns leftover count (0-2) to be handled as literals by the caller.
    """
    # Handle large runs in groups of 4 using 11xxxxxx
    while count >= 8:
        q = count // 4
        r = count % 4
        # If remainder would be 1 or 2, hold back one group so the
        # combined remainder (5 or 6) fits a 01xxxxxx encoding
        if r in (1, 2) and q > 1:
            groups = min(q - 1, 64)
        else:
            groups = min(q, 64)
        out.append(0xC0 | (groups - 1))
        out.append(val)
        count -= groups * 4

    # Handle small remainders (0-7)
    if count == 7:
        out.append(0x46)
        out.append(val)
        return 0
    if count == 6:
        out.append(0x45)
        out.append(val)
        return 0
    if count == 5:
        out.append(0x44)
        out.append(val)
        return 0
    if count == 4:
        out.append(0xC0)
        out.append(val)
        return 0
    if count == 3:
        out.append(0x42)
        out.append(val)
        return 0
    # 0, 1, or 2 leftover — caller adds them to the literal buffer
    return count


def emit_4byte_pattern(out, pattern, count):
    """Encode repeats of a 4-byte pattern using 10xxxxxx (max 64 per chunk)."""
    while count > 0:
        n = min(count, 64)
        out.append(0x80 | (n - 1))
        out.extend(pattern)
        count -= n


def pack_bytes(data):
    """Compress data using Apple IIgs PackBytes format."""
    data = bytes(data)
    out = bytearray()
    literals = bytearray()
    pos = 0

    while pos < len(data):
        byte_run = find_byte_run(data, pos)
        four_run = find_4byte_pattern(data, pos)
        four_coverage = four_run * 4

        if byte_run >= 3 and byte_run >= four_coverage:
            flush_literals(out, literals)
            literals = bytearray()
            leftover = emit_byte_run(out, data[pos], byte_run)
            pos += byte_run - leftover
            for _ in range(leftover):
                literals.append(data[pos])
                pos += 1

        elif four_coverage >= 8:
            flush_literals(out, literals)
            literals = bytearray()
            emit_4byte_pattern(out, data[pos:pos + 4], four_run)
            pos += four_coverage

        else:
            literals.append(data[pos])
            pos += 1
            if len(literals) == 64:
                flush_literals(out, literals)
                literals = bytearray()

    flush_literals(out, literals)
    return bytes(out)


def unpack_bytes(data):
    """Decompress Apple IIgs PackBytes format."""
    out = bytearray()
    pos = 0

    while pos < len(data):
        flag = data[pos]
        pos += 1
        kind = (flag >> 6) & 3
        count = flag & 0x3F

        if kind == 0:
            # 00xxxxxx: count+1 literal bytes follow
            n = count + 1
            out.extend(data[pos:pos + n])
            pos += n

        elif kind == 1:
            # 01xxxxxx: count+1 repeats of next byte
            n = count + 1
            out.extend(bytes([data[pos]]) * n)
            pos += 1

        elif kind == 2:
            # 10xxxxxx: count+1 repeats of next 4 bytes
            n = count + 1
            pat = data[pos:pos + 4]
            pos += 4
            out.extend(pat * n)

        elif kind == 3:
            # 11xxxxxx: count+1 repeats of next byte taken as 4 bytes
            n = count + 1
            out.extend(bytes([data[pos]]) * (n * 4))
            pos += 1

    return bytes(out)


def main():
    parser = argparse.ArgumentParser(
        description='Apple IIgs PackBytes compressor/decompressor')
    parser.add_argument('mode', choices=['pack', 'unpack'],
                        help='Compress or decompress')
    parser.add_argument('input', help='Input file (- for stdin)')
    parser.add_argument('output', help='Output file (- for stdout)')
    parser.add_argument('--verify', action='store_true',
                        help='Round-trip verify after packing')
    parser.add_argument('--length', type=int, default=None,
                        help='Number of bytes to read from input file')

    args = parser.parse_args()

    # Read input
    if args.input == '-':
        data = sys.stdin.buffer.read()
    else:
        with open(args.input, 'rb') as f:
            data = f.read()

    if args.length is not None:
        if args.length > len(data):
            print(f'ERROR: --length {args.length} exceeds file size {len(data)}',
                  file=sys.stderr)
            sys.exit(1)
        data = data[:args.length]

    if args.mode == 'pack':
        result = pack_bytes(data)

        if args.verify:
            unpacked = unpack_bytes(result)
            if unpacked != data:
                print(f'ERROR: round-trip verification failed! '
                      f'original={len(data)} unpacked={len(unpacked)}',
                      file=sys.stderr)
                for i in range(min(len(data), len(unpacked))):
                    if data[i] != unpacked[i]:
                        print(f'  First mismatch at offset {i}: '
                              f'expected 0x{data[i]:02X}, '
                              f'got 0x{unpacked[i]:02X}',
                              file=sys.stderr)
                        break
                sys.exit(1)

            ratio = len(result) / len(data) * 100 if data else 0
            print(f'OK: {len(data)} -> {len(result)} bytes ({ratio:.1f}%)',
                  file=sys.stderr)
    else:
        result = unpack_bytes(data)

    # Write output
    if args.output == '-':
        sys.stdout.buffer.write(result)
    else:
        with open(args.output, 'wb') as f:
            f.write(result)


if __name__ == '__main__':
    main()
