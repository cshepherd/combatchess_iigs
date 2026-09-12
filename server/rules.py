#!/usr/bin/env python3
"""Combat Chess rules engine (authoritative, server side) -- N3.

A faithful Python port of the 65816 engine (src/tables.s, board.s,
line.s, move.s, fire.s, turn.s). The server owns truth: it validates and
resolves every action, so this module must agree with the client's rules
for legal actions/outcomes. The hit/miss roll is the server's (spec 16),
so the RNG here need not byte-match src/rng.s -- only the validation
geometry, ranges, fuel and terrain behaviour must.

Board is 20 x 11 = 220 cells, row-major (index = y*20 + x).
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field

# --- sides / classes (src/shared.s, tables.s) ---
SIDE_RED = 0
SIDE_BLACK = 1

CLASS_CRUISER = 0
CLASS_TANK = 1
CLASS_CAR = 2

# Per-class stats (tables.s: class_*). Indexed by CLASS_*.
CLASS_MAX_HP = (30, 24, 18)
CLASS_TERRAIN_HP = (15, 12, 9)      # terrain HP while a unit stands on a cell
CLASS_MAX_AMMO = (16, 16, 8)
CLASS_MAX_FUEL = (240, 240, 160)
CLASS_DAMAGE = (5, 4, 4)            # damage dealt per hit, by attacker class
CLASS_FIRE_ORTH = (11, 7, 4)
CLASS_FIRE_DIAG = (8, 5, 3)
CLASS_MOVE_ORTH = (2, 4, 7)
CLASS_MOVE_DIAG = (1, 3, 5)
CLASS_NAME = ("BATTLE CRUISER", "TANK", "ARMORED CAR")

# --- board geometry ---
BOARD_W = 20
BOARD_H = 11
BOARD_CELLS = 220

# --- terrain types (board.s) ---
TERR_CLEAR = 0
TERR_TREE = 1
TERR_WATER = 2
TERR_BRIDGE = 3
TERR_MOUNTAIN = 4
TERR_WHITE = 5
TERR_YELLOW = 6
TERR_GREY = 7
TERR_PURPLE = 8
TERR_BLACK = 9

# Map from the checklist map letters to terrain type (tools/gen_boards.py).
MAP_LETTERS = ".T~=Mwygpb"

# terrain_flags (board.s): bit7 TF_FIRE, bit6 TF_MOVE, bit0 TF_DESTRUCT,
# bit1 TF_SLOW.
TF_FIRE = 0x80
TF_MOVE = 0x40
TF_DESTRUCT = 0x01
TF_SLOW = 0x02
TERRAIN_FLAGS = (
    TF_FIRE | TF_MOVE,                 # CLEAR
    TF_MOVE | TF_DESTRUCT | TF_SLOW,   # TREE
    TF_FIRE,                           # WATER
    TF_FIRE | TF_MOVE | TF_DESTRUCT,   # BRIDGE
    0x00,                              # MOUNTAIN (blocks everything)
    TF_FIRE | TF_MOVE,                 # WHITE
    TF_FIRE | TF_MOVE,                 # YELLOW
    TF_DESTRUCT,                       # GREY
    TF_FIRE,                           # PURPLE
    0x00,                              # BLACK
)
# terrain_after (board.s): what a destroyed cell becomes.
TERRAIN_AFTER = (
    TERR_CLEAR, TERR_CLEAR, TERR_WATER, TERR_WATER, TERR_MOUNTAIN,
    TERR_WHITE, TERR_YELLOW, TERR_WHITE, TERR_PURPLE, TERR_BLACK,
)
# terr_max_hp (board.s): empty-cell terrain HP by type.
TERR_MAX_HP = (0, 1, 0, 15, 0, 0, 0, 8, 0, 0)

# tree movement penalty: each tree square entered costs one extra square
# (src/board.s terrain_move_penalty; measured on the Atari original).
TERRAIN_MOVE_PENALTY = (0, 1, 0, 0, 0, 0, 0, 0, 0, 0)

# --- directions (line.s) ---
DIR_N, DIR_NE, DIR_E, DIR_SE, DIR_S, DIR_SW, DIR_W, DIR_NW = range(8)
ORIENT_ORTH = 0
ORIENT_DIAG = 1

# fuel_table (tables.s), indexed [class][orient][distance 0..7]; $FF=illegal.
FUEL_NONE = 0xFF
FUEL_TABLE = {
    (CLASS_CRUISER, ORIENT_ORTH): (FUEL_NONE, 12, 27, FUEL_NONE, FUEL_NONE, FUEL_NONE, FUEL_NONE, FUEL_NONE),
    (CLASS_CRUISER, ORIENT_DIAG): (FUEL_NONE, 16, FUEL_NONE, FUEL_NONE, FUEL_NONE, FUEL_NONE, FUEL_NONE, FUEL_NONE),
    (CLASS_TANK, ORIENT_ORTH): (FUEL_NONE, 4, 10, 18, 28, FUEL_NONE, FUEL_NONE, FUEL_NONE),
    (CLASS_TANK, ORIENT_DIAG): (FUEL_NONE, 5, 17, 33, FUEL_NONE, FUEL_NONE, FUEL_NONE, FUEL_NONE),
    (CLASS_CAR, ORIENT_ORTH): (FUEL_NONE, 1, 3, 6, 10, 15, 21, 28),
    (CLASS_CAR, ORIENT_DIAG): (FUEL_NONE, 1, 5, 11, 19, 28, FUEL_NONE, FUEL_NONE),
}

# hit_chance (tables.s), indexed [orient][range 0..15]; percent, 0 = no hit.
HIT_TABLE = {
    ORIENT_ORTH: (0, 100, 94, 88, 82, 76, 70, 64, 58, 52, 46, 40, 0, 0, 0, 0),
    ORIENT_DIAG: (0, 98, 89, 81, 72, 64, 56, 47, 39, 0, 0, 0, 0, 0, 0, 0),
}


def terr_flags(t: int) -> int:
    return TERRAIN_FLAGS[t]


def terr_passable(t: int) -> bool:
    return bool(TERRAIN_FLAGS[t] & TF_MOVE)


def terr_fire_through(t: int) -> bool:
    return bool(TERRAIN_FLAGS[t] & TF_FIRE)


def move_range(cls: int, orient: int) -> int:
    return CLASS_MOVE_DIAG[cls] if orient == ORIENT_DIAG else CLASS_MOVE_ORTH[cls]


def fire_range(cls: int, orient: int) -> int:
    return CLASS_FIRE_DIAG[cls] if orient == ORIENT_DIAG else CLASS_FIRE_ORTH[cls]


def fuel_cost(cls: int, orient: int, dist: int) -> int:
    """Fuel for one move; FUEL_NONE if the class can't move that far/orient."""
    if dist < 1 or dist > 7:
        return FUEL_NONE
    return FUEL_TABLE[(cls, orient)][dist]


def hit_chance(cls: int, orient: int, rng: int) -> int:
    """Percent to hit at range; 0 beyond the class's firing range."""
    if rng < 1 or rng > fire_range(cls, orient):
        return 0
    row = HIT_TABLE[orient]
    return row[rng] if rng < len(row) else 0


# --- line classification (line.s line_find) ---
_SIGN = lambda d: 0 if d == 0 else (1 if d > 0 else 2)
# dir_table indexed sign(dx)*3 + sign(dy); None = not a straight line.
_DIR_TABLE = (
    None,  DIR_S,  DIR_N,        # dx 0
    DIR_E, DIR_SE, DIR_NE,       # dx +
    DIR_W, DIR_SW, DIR_NW,       # dx -
)


@dataclass
class Line:
    direction: int
    dist: int
    orient: int


def line_find(x0: int, y0: int, x1: int, y1: int):
    """Classify the line. Returns a Line for a horizontal/vertical/exact-
    diagonal move within the board, else None (spec 24.1/24.2)."""
    for (x, y) in ((x0, y0), (x1, y1)):
        if not (0 <= x < BOARD_W and 0 <= y < BOARD_H):
            return None
    dx = x1 - x0
    dy = y1 - y0
    if dx == 0 and dy == 0:
        return None
    adx, ady = abs(dx), abs(dy)
    if dx != 0 and dy != 0 and adx != ady:
        return None                         # not orthogonal or exact diagonal
    direction = _DIR_TABLE[_SIGN(dx) * 3 + _SIGN(dy)]
    if direction is None:
        return None
    dist = max(adx, ady)
    orient = ORIENT_DIAG if (dx != 0 and dy != 0) else ORIENT_ORTH
    return Line(direction, dist, orient)


_STEP = {  # unit step (sx, sy) per direction
    DIR_N: (0, -1), DIR_NE: (1, -1), DIR_E: (1, 0), DIR_SE: (1, 1),
    DIR_S: (0, 1), DIR_SW: (-1, 1), DIR_W: (-1, 0), DIR_NW: (-1, -1),
}


def cells_along(x0, y0, line: Line):
    """Yield (x, y) for each of the dist cells after the origin, in order."""
    sx, sy = _STEP[line.direction]
    for i in range(1, line.dist + 1):
        yield x0 + sx * i, y0 + sy * i
