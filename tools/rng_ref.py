#!/usr/bin/env python3
"""Host-side reference for src/rng.s: the same xorshift32 generator,
byte draw, roll mapping and hit rule, so replay tools can reproduce
the IIGS engine's random events and the self-tests can hold exact
known answers.

Keep this in lockstep with rng.s. If either changes, every saved
replay changes with it.

Usage:
    python3 tools/rng_ref.py                # print the test.s known answers
    python3 tools/rng_ref.py --seed 0x1 --steps 5 --rolls 10
"""
import argparse

MASK = 0xFFFFFFFF
DEFAULT_SEED = 0x2545F491      # RNG_DEFAULT_SEED in rng.s


def xorshift32(x):
    x ^= (x << 13) & MASK
    x ^= x >> 17
    x ^= (x << 5) & MASK
    return x


class Rng:
    def __init__(self, seed):
        self.seed(seed)

    def seed(self, seed):
        self.state = (seed & MASK) or DEFAULT_SEED

    def state_bytes(self):
        return [(self.state >> (8 * i)) & 0xFF for i in range(4)]

    def next(self):
        """rng_next: advance and return the top byte."""
        self.state = xorshift32(self.state)
        return (self.state >> 24) & 0xFF

    def roll100(self):
        """rng_roll100: rejection-sample a uniform 0..99."""
        while True:
            r = self.next()
            if r < 200:
                return r if r < 100 else r - 100

    def resolve_hit(self, percent):
        """resolve_hit: (hit, roll)."""
        roll = self.roll100()
        return roll < percent, roll


def dfb(values):
    return " dfb " + ",".join(str(v) for v in values)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=lambda s: int(s, 0), default=0x12345678)
    ap.add_argument("--steps", type=int, default=3,
                    help="print the state after step 1 and after this many")
    ap.add_argument("--rolls", type=int, default=8)
    ap.add_argument("--trials", type=int, default=255)
    ap.add_argument("--percent", type=int, default=50)
    a = ap.parse_args()

    r = Rng(a.seed)
    print(f"* seed ${a.seed:08X}")
    r.next()
    print("* state after 1 step (little-endian)")
    print(dfb(r.state_bytes()))
    for _ in range(a.steps - 1):
        r.next()
    print(f"* state after {a.steps} steps")
    print(dfb(r.state_bytes()))

    r.seed(a.seed)
    print(f"* first {a.rolls} rng_roll100 values")
    print(dfb([r.roll100() for _ in range(a.rolls)]))

    r.seed(a.seed)
    hits = sum(r.resolve_hit(a.percent)[0] for _ in range(a.trials))
    print(f"* hits in {a.trials} resolve_hit({a.percent}) trials: {hits}")


if __name__ == "__main__":
    main()
