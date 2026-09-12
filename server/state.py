#!/usr/bin/env python3
"""Authoritative game state + action resolution (server side) -- N3.

Holds the board, units and clocks, sets a match up from the shared board
maps (reference/maps/, the same data gen_boards.py feeds the client), and
validates/applies MOVE / FIRE / END_TURN / SURRENDER exactly as the 65816
engine does (move.s, fire.s, turn.s). Serializes to the spec-20 S_STATE
snapshot the client parses. Uses rules.py for the rule primitives.
"""
from __future__ import annotations

import os
import struct
from dataclasses import dataclass, field

import rules as R

MAPS_DIR = os.path.join(os.path.dirname(__file__), "..", "reference", "maps")

# Action reason codes (move.s / fire.s).
MV_OK, MV_NO_UNIT, MV_NOT_LINE, MV_TOO_FAR, MV_BLOCKED, MV_NO_FUEL = range(6)
FR_OK, FR_NO_UNIT, FR_NO_TARGET, FR_NOT_LINE, FR_OUT_OF_RANGE, \
    FR_BLOCKED, FR_NO_AMMO, FR_ALREADY = range(8)
FR_MISS, FR_HIT, FR_KILL = 0, 1, 2
FR_SQUARE = 0xFF          # C_FIRE target_id sentinel: a shot at a square (fire.s)

# Event types (spec 19) for the presentation layer.
EV_UNIT_MOVED = 1
EV_SHOT_FIRED = 2
EV_SHOT_HIT = 3
EV_SHOT_MISSED = 4
EV_UNIT_DAMAGED = 5
EV_UNIT_DESTROYED = 6
EV_TERRAIN_DAMAGED = 7
EV_TERRAIN_DESTROYED = 8
EV_TURN_CHANGED = 9

# Turn phases.
PHASE_MOVE = 0
PHASE_SHOOT = 1

# Unit flags (units.s: UF_ALIVE bit 7).
UF_ALIVE = 0x80

# Game-over reasons.
OVER_CRUISER = 0        # enemy Battle Cruiser destroyed
OVER_SURRENDER = 1
OVER_STALEMATE = 2
OVER_TIME = 3           # a side's clock ran out (server-authoritative time)


@dataclass
class Unit:
    id: int
    cls: int
    side: int
    x: int
    y: int
    hp: int
    fuel: int
    ammo: int
    terr_hp: int
    alive: bool = True
    fired_at: set = field(default_factory=set)   # target ids fired at this turn
    fired_sq: set = field(default_factory=set)   # (x,y) squares fired at this turn

    @property
    def flags(self) -> int:
        return UF_ALIVE if self.alive else 0


class RuleError(Exception):
    """An action the server rejects; carries the reason code."""
    def __init__(self, code: int):
        super().__init__(f"rule reason {code}")
        self.code = code


def _load_map(n: int):
    path = os.path.join(MAPS_DIR, f"board{n:02d}.txt")
    rows = [l.rstrip("\n") for l in open(path) if l.strip()]
    if len(rows) != R.BOARD_H or any(len(r) != R.BOARD_W for r in rows):
        raise ValueError(f"{path}: expected {R.BOARD_H} rows of {R.BOARD_W}")
    terrain = bytearray(R.BOARD_CELLS)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            terrain[y * R.BOARD_W + x] = R.MAP_LETTERS.index(ch)
    units = []
    upath = os.path.join(MAPS_DIR, f"board{n:02d}_units.txt")
    if os.path.exists(upath):
        side_map = {"SIDE_RED": R.SIDE_RED, "SIDE_BLACK": R.SIDE_BLACK}
        cls_map = {"CLASS_CRUISER": R.CLASS_CRUISER,
                   "CLASS_TANK": R.CLASS_TANK, "CLASS_CAR": R.CLASS_CAR}
        for line in open(upath):
            line = line.split("#")[0].strip()
            if not line:
                continue
            side, cls, x, y = line.split()
            units.append((side_map[side], cls_map[cls], int(x), int(y)))
    return terrain, units


class GameState:
    def __init__(self, board_number: int, moves_per_turn: int = 5,
                 shoot_option: int = 1, starting_side: int = R.SIDE_RED,
                 red_time_ms: int = 600000, black_time_ms: int = 600000,
                 rng: "random.Random | None" = None,
                 red_tanks: int = 3, red_cars: int = 5,
                 black_tanks: int = 3, black_cars: int = 5):
        import random
        self.board_number = board_number
        self.moves_per_turn = moves_per_turn
        self.shoot_option = shoot_option
        self.active_side = starting_side
        self.moves_used = 0
        self.turn_phase = PHASE_MOVE
        self.inactive_turn_count = 0
        self.red_remaining_ms = red_time_ms
        self.black_remaining_ms = black_time_ms
        self.state_serial = 0
        self.rng = rng or random.Random()
        self.game_over = False
        self.winner = None
        self.over_reason = None

        self.terrain, placed = _load_map(board_number)
        self.terr_hp = bytearray(R.TERR_MAX_HP[t] for t in self.terrain)
        self.units: dict[int, Unit] = {}
        self.occupant = [None] * R.BOARD_CELLS   # cell -> unit id or None

        # Assign stable ids in the spec-13 order: Red then Black, cruiser,
        # tanks, cars. The maps already list them roughly so; sort to be safe.
        limits = {(R.SIDE_RED, R.CLASS_TANK): red_tanks,
                  (R.SIDE_RED, R.CLASS_CAR): red_cars,
                  (R.SIDE_BLACK, R.CLASS_TANK): black_tanks,
                  (R.SIDE_BLACK, R.CLASS_CAR): black_cars}
        counts: dict[tuple, int] = {}
        order = sorted(placed, key=lambda u: (u[0], u[1]))
        next_id = 0
        for side, cls, x, y in order:
            if cls != R.CLASS_CRUISER:
                k = (side, cls)
                counts[k] = counts.get(k, 0) + 1
                if counts[k] > limits.get(k, 99):
                    continue                    # trimmed by the chosen army size
            self._add_unit(next_id, cls, side, x, y)
            next_id += 1

    def _add_unit(self, uid, cls, side, x, y):
        u = Unit(id=uid, cls=cls, side=side, x=x, y=y,
                 hp=R.CLASS_MAX_HP[cls], fuel=R.CLASS_MAX_FUEL[cls],
                 ammo=R.CLASS_MAX_AMMO[cls], terr_hp=R.CLASS_TERRAIN_HP[cls])
        self.units[uid] = u
        self.occupant[y * R.BOARD_W + x] = uid

    # ---- helpers ----
    def cell(self, x, y):
        return self.terrain[y * R.BOARD_W + x]

    def occupant_at(self, x, y):
        uid = self.occupant[y * R.BOARD_W + x]
        return self.units[uid] if uid is not None else None

    def cruiser_alive(self, side):
        return any(u.alive and u.side == side and u.cls == R.CLASS_CRUISER
                   for u in self.units.values())

    def _bump_serial(self):
        self.state_serial = (self.state_serial + 1) & 0xFFFFFFFF

    # ---- MOVE (move.s) ----
    def validate_move(self, side, unit_id, dx, dy):
        """Return (reason, cost, line). Raises nothing; reason==MV_OK if legal."""
        u = self.units.get(unit_id)
        if u is None or not u.alive or u.side != side:
            return MV_NO_UNIT, 0, None
        line = R.line_find(u.x, u.y, dx, dy)
        if line is None:
            return MV_NOT_LINE, 0, None
        # path: passability + occupancy, and accumulate tree penalty
        penalty = 0
        for (cx, cy) in R.cells_along(u.x, u.y, line):
            t = self.cell(cx, cy)
            if not R.terr_passable(t):
                return MV_BLOCKED, 0, None
            if self.occupant[cy * R.BOARD_W + cx] is not None:
                return MV_BLOCKED, 0, None
            penalty += R.TERRAIN_MOVE_PENALTY[t]
        # range: squares + trees <= class move range in this orientation
        if line.dist + penalty > R.move_range(u.cls, line.orient):
            return MV_TOO_FAR, 0, None
        eff = line.dist + penalty
        cost = R.fuel_cost(u.cls, line.orient, eff)
        if cost == R.FUEL_NONE or cost > u.fuel:
            return MV_NO_FUEL, 0, None
        return MV_OK, cost, line

    def apply_move(self, side, unit_id, dx, dy):
        reason, cost, line = self.validate_move(side, unit_id, dx, dy)
        if reason != MV_OK:
            raise RuleError(reason)
        u = self.units[unit_id]
        events = [(EV_UNIT_MOVED, unit_id, u.x, u.y, dx, dy)]
        self.occupant[u.y * R.BOARD_W + u.x] = None
        u.x, u.y = dx, dy
        self.occupant[dy * R.BOARD_W + dx] = unit_id
        u.fuel -= cost
        self.moves_used += 1
        self._bump_serial()
        return events

    # ---- FIRE (fire.s) ----
    def _los_clear(self, x0, y0, line, target_x, target_y):
        for (cx, cy) in R.cells_along(x0, y0, line):
            if cx == target_x and cy == target_y:
                break                            # the target cell itself is fine
            if not R.terr_fire_through(self.cell(cx, cy)):
                return False
            if self.occupant[cy * R.BOARD_W + cx] is not None:
                return False                     # units block line of fire
        return True

    def validate_fire(self, side, attacker_id, target_id):
        a = self.units.get(attacker_id)
        if a is None or not a.alive or a.side != side:
            return FR_NO_UNIT, 0, None
        t = self.units.get(target_id)
        if t is None or not t.alive or t.side == side:
            return FR_NO_TARGET, 0, None
        line = R.line_find(a.x, a.y, t.x, t.y)
        if line is None:
            return FR_NOT_LINE, 0, None
        pct = R.hit_chance(a.cls, line.orient, line.dist)
        if pct == 0:
            return FR_OUT_OF_RANGE, 0, None
        if not self._los_clear(a.x, a.y, line, t.x, t.y):
            return FR_BLOCKED, 0, None
        if a.ammo <= 0:
            return FR_NO_AMMO, 0, None
        if target_id in a.fired_at:
            return FR_ALREADY, 0, None
        return FR_OK, pct, line

    def apply_fire(self, side, attacker_id, target_id):
        reason, pct, line = self.validate_fire(side, attacker_id, target_id)
        if reason != FR_OK:
            raise RuleError(reason)
        a = self.units[attacker_id]
        t = self.units[target_id]
        a.ammo -= 1
        a.fired_at.add(target_id)
        events = [(EV_SHOT_FIRED, attacker_id, target_id, a.x, a.y, t.x, t.y)]
        roll = self.rng.randint(1, 100)
        if roll <= pct:                          # hit
            events.append((EV_SHOT_HIT, target_id, t.x, t.y))
            dmg = R.CLASS_DAMAGE[a.cls]
            t.hp -= dmg
            t.terr_hp -= dmg
            events.append((EV_UNIT_DAMAGED, target_id, max(t.hp, 0)))
            if t.hp <= 0:
                self._destroy_unit(t)
                events.append((EV_UNIT_DESTROYED, target_id))
                self._check_victory(t)
                outcome = FR_KILL
            else:
                outcome = FR_HIT
        else:                                    # miss (scatter left for later)
            events.append((EV_SHOT_MISSED, target_id, t.x, t.y))
            outcome = FR_MISS
        self._bump_serial()
        return outcome, events

    def validate_fire_square(self, side, attacker_id, tx, ty):
        """A shot at a destructible square (tree/bridge/grey) rather than a
        unit -- fire.s fire_validate_at when no unit stands there."""
        a = self.units.get(attacker_id)
        if a is None or not a.alive or a.side != side:
            return FR_NO_UNIT, 0, None
        if not (0 <= tx < R.BOARD_W and 0 <= ty < R.BOARD_H):
            return FR_NO_TARGET, 0, None
        if R.TERR_MAX_HP[self.cell(tx, ty)] <= 0:     # open/water/mountain: nothing to hit
            return FR_NO_TARGET, 0, None
        line = R.line_find(a.x, a.y, tx, ty)
        if line is None:
            return FR_NOT_LINE, 0, None
        pct = R.hit_chance(a.cls, line.orient, line.dist)
        if pct == 0:
            return FR_OUT_OF_RANGE, 0, None
        if not self._los_clear(a.x, a.y, line, tx, ty):
            return FR_BLOCKED, 0, None
        if a.ammo <= 0:
            return FR_NO_AMMO, 0, None
        if (tx, ty) in a.fired_sq:                     # spec 13: once per square per turn
            return FR_ALREADY, 0, None
        return FR_OK, pct, line

    def apply_fire_square(self, side, attacker_id, tx, ty):
        reason, pct, line = self.validate_fire_square(side, attacker_id, tx, ty)
        if reason != FR_OK:
            raise RuleError(reason)
        a = self.units[attacker_id]
        a.ammo -= 1
        a.fired_sq.add((tx, ty))
        # EV_SHOT_FIRED carries FR_SQUARE for the target so the client animates
        # a square shot; attacker + endpoints drive the projectile.
        events = [(EV_SHOT_FIRED, attacker_id, FR_SQUARE, a.x, a.y, tx, ty)]
        cell = ty * R.BOARD_W + tx
        roll = self.rng.randint(1, 100)
        if roll <= pct:                                # hit: wear the square down
            events.append((EV_SHOT_HIT, FR_SQUARE, tx, ty))
            self.terr_hp[cell] = max(0, self.terr_hp[cell] - R.CLASS_DAMAGE[a.cls])
            if self.terr_hp[cell] <= 0:                # destroyed -> terrain_after
                old = self.terrain[cell]
                new = R.TERRAIN_AFTER[old]
                self.terrain[cell] = new
                self.terr_hp[cell] = R.TERR_MAX_HP[new]
                events.append((EV_TERRAIN_DESTROYED, tx, ty, old, new))
                outcome = FR_KILL
            else:
                events.append((EV_TERRAIN_DAMAGED, tx, ty, self.terr_hp[cell]))
                outcome = FR_HIT
        else:
            events.append((EV_SHOT_MISSED, FR_SQUARE, tx, ty))
            outcome = FR_MISS
        self._bump_serial()
        return outcome, events

    def _destroy_unit(self, u: Unit):
        u.alive = False
        u.hp = 0
        self.occupant[u.y * R.BOARD_W + u.x] = None

    def _check_victory(self, destroyed: Unit):
        if destroyed.cls == R.CLASS_CRUISER:
            self.game_over = True
            self.winner = R.SIDE_RED if destroyed.side == R.SIDE_BLACK else R.SIDE_BLACK
            self.over_reason = OVER_CRUISER

    # ---- END TURN / SURRENDER (turn.s) ----
    def end_turn(self):
        prev = self.active_side
        moved_or_fired = self.moves_used > 0
        # inactivity / stalemate bookkeeping (spec: idle-turn draw)
        self.inactive_turn_count = 0 if moved_or_fired else self.inactive_turn_count + 1
        for u in self.units.values():
            u.fired_at.clear()
            u.fired_sq.clear()
        self.active_side = R.SIDE_BLACK if prev == R.SIDE_RED else R.SIDE_RED
        self.moves_used = 0
        self.turn_phase = PHASE_MOVE
        self._bump_serial()
        events = [(EV_TURN_CHANGED, self.active_side)]
        if self.inactive_turn_count >= 2:        # both sides idled a full round
            self.game_over = True
            self.winner = None                    # draw
            self.over_reason = OVER_STALEMATE
        return events

    def surrender(self, side):
        self.game_over = True
        self.winner = R.SIDE_BLACK if side == R.SIDE_RED else R.SIDE_RED
        self.over_reason = OVER_SURRENDER
        self._bump_serial()

    # ---- clock (server-authoritative time; the driver lives in match_server) ----
    def remaining_ms(self, side):
        return self.red_remaining_ms if side == R.SIDE_RED else self.black_remaining_ms

    def deduct_time(self, side, ms):
        """Charge `ms` of elapsed time to `side`, clamped at zero. Returns the
        new remaining. Does not bump the state serial (the clock ticks
        continuously; the serial tracks discrete state changes) nor end the game
        -- the caller checks for a flag."""
        ms = max(0, int(ms))
        if side == R.SIDE_RED:
            self.red_remaining_ms = max(0, self.red_remaining_ms - ms)
            return self.red_remaining_ms
        self.black_remaining_ms = max(0, self.black_remaining_ms - ms)
        return self.black_remaining_ms

    def timeout(self, side):
        """`side` ran out of time; the other side wins (spec: clock loss)."""
        self.game_over = True
        self.winner = R.SIDE_BLACK if side == R.SIDE_RED else R.SIDE_RED
        self.over_reason = OVER_TIME
        self._bump_serial()

    # ---- serialization (spec 20) ----
    def serialize(self) -> bytes:
        """S_STATE payload (spec 20)."""
        alive = [u for u in self.units.values()]      # destroyed units retain their id
        out = bytearray()
        out += struct.pack("<BBBB", self.active_side, self.turn_phase,
                           self.moves_used, self.inactive_turn_count)
        out += struct.pack("<II", self.red_remaining_ms, self.black_remaining_ms)
        out += struct.pack("<B", len(alive))
        for u in alive:
            out += struct.pack("<BBBBBBHBBB", u.id, u.cls, u.side, u.x, u.y,
                               max(u.hp, 0), max(u.fuel, 0) & 0xFFFF,
                               max(u.ammo, 0), max(u.terr_hp, 0), u.flags)
        out += bytes(self.terrain)
        out += struct.pack("<I", self.state_serial)
        return bytes(out)


def parse_snapshot(blob: bytes) -> dict:
    """Decode an S_STATE payload (spec 20) into a plain dict. Used by clients
    and bots that receive the authoritative snapshot."""
    active_side, turn_phase, moves_used, inactive = struct.unpack_from("<BBBB", blob, 0)
    red_ms, black_ms = struct.unpack_from("<II", blob, 4)
    n = blob[12]
    off = 13
    units = []
    for _ in range(n):
        uid, cls, side, x, y, hp, fuel, ammo, thp, flags = \
            struct.unpack_from("<BBBBBBHBBB", blob, off)
        off += 11
        units.append(dict(id=uid, cls=cls, side=side, x=x, y=y, hp=hp,
                          fuel=fuel, ammo=ammo, terr_hp=thp, flags=flags,
                          alive=bool(flags & UF_ALIVE)))
    terrain = bytes(blob[off:off + R.BOARD_CELLS]); off += R.BOARD_CELLS
    (serial,) = struct.unpack_from("<I", blob, off)
    return dict(active_side=active_side, turn_phase=turn_phase,
                moves_used=moves_used, inactive_turn_count=inactive,
                red_remaining_ms=red_ms, black_remaining_ms=black_ms,
                units=units, terrain=terrain, state_serial=serial)


class ClientView:
    """A client/bot's read-only rebuild of the authoritative snapshot,
    reusing GameState's validators to enumerate legal actions."""

    def __init__(self, snapshot: dict):
        self.snap = snapshot
        self.g = GameState.__new__(GameState)      # bypass __init__/setup
        g = self.g
        g.terrain = bytearray(snapshot["terrain"])
        g.terr_hp = bytearray(R.TERR_MAX_HP[t] for t in g.terrain)
        g.active_side = snapshot["active_side"]
        g.moves_used = snapshot["moves_used"]
        g.units = {}
        g.occupant = [None] * R.BOARD_CELLS
        for ud in snapshot["units"]:
            if not ud["alive"]:
                continue
            u = Unit(id=ud["id"], cls=ud["cls"], side=ud["side"], x=ud["x"],
                     y=ud["y"], hp=ud["hp"], fuel=ud["fuel"], ammo=ud["ammo"],
                     terr_hp=ud["terr_hp"], alive=True)
            g.units[u.id] = u
            g.occupant[u.y * R.BOARD_W + u.x] = u.id

    def legal_moves(self, side):
        """All (unit_id, dest_x, dest_y, cost) legal moves for side."""
        out = []
        for u in self.g.units.values():
            if u.side != side:
                continue
            for ty in range(R.BOARD_H):
                for tx in range(R.BOARD_W):
                    rsn, cost, _ = self.g.validate_move(side, u.id, tx, ty)
                    if rsn == MV_OK:
                        out.append((u.id, tx, ty, cost))
        return out

    def legal_fires(self, side):
        """All (attacker_id, target_id, pct) legal shots for side."""
        out = []
        for a in self.g.units.values():
            if a.side != side:
                continue
            for t in self.g.units.values():
                if t.side == side:
                    continue
                rsn, pct, _ = self.g.validate_fire(side, a.id, t.id)
                if rsn == FR_OK:
                    out.append((a.id, t.id, pct))
        return out
