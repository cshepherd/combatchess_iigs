# Combat Chess — Apple IIGS Port
## Game Design and Rules Specification

**Target:** Apple IIGS  
**Original:** *Combat Chess* (Avalon Hill, Atari 8-bit, 1984)  
**Document status:** Draft 0.9 — faithful-port rules specification  
**Primary goal:** Reproduce the original game logic before adding IIGS-specific presentation improvements.

---

## 1. Design Goals

The Apple IIGS version should preserve the original *Combat Chess* simulation and tactical rules as faithfully as practical while modernizing presentation, controls, audiovisual feedback, and optional quality-of-life features.

The game engine should be logically independent from the display code so that:

1. the original rules can be tested without graphics;
2. deterministic test positions can be constructed;
3. AI can operate on the same rules API as human players;
4. alternate visual presentations can be added later without changing game logic;
5. compatibility modes can preserve original behavior, including quirks, where desirable.

Unless explicitly marked otherwise, rules in this document describe the **Original Rules** mode.

---

## 2. Core Concept

*Combat Chess* is a two-sided, turn-based tactical combat game played on a rectangular grid.

Each side controls:

- one **Battle Cruiser**;
- zero or more **Tanks**;
- zero or more **Armored Cars**.

The objective is to destroy the opposing Battle Cruiser before the opponent destroys yours.

Pieces move and fire only along the eight chess-like directions:

- north;
- northeast;
- east;
- southeast;
- south;
- southwest;
- west;
- northwest.

Movement distance, weapon range, ammunition, fuel, hit points, and firing damage depend on unit class.

Terrain can:

- block movement;
- block fire;
- increase movement cost;
- be destructible;
- permit fire but prohibit movement;
- permit movement but prohibit fire.

---

## 3. Board Geometry

### 3.1 Dimensions

Every game board is:

- **20 squares wide**
- **11 squares high**
- **220 total cells**

Use zero-based engine coordinates:

```text
x = 0..19
y = 0..10
```

Recommended convention:

```text
(0,0) = upper-left
x increases rightward
y increases downward
```

### 3.2 Directions

All movement and direct fire use one of eight vectors:

```text
N  = ( 0,-1)
NE = (+1,-1)
E  = (+1, 0)
SE = (+1,+1)
S  = ( 0,+1)
SW = (-1,+1)
W  = (-1, 0)
NW = (-1,-1)
```

A legal destination or target must therefore lie on the same:

- row;
- column; or
- exact 45-degree diagonal.

No knight-like, curved, arbitrary-vector, or pathfinding movement exists.

---

## 4. Sides

There are two armies:

- **Red**
- **Black**

One side moves first, chosen in game options.

Either side may be:

- human-controlled;
- computer-controlled.

Supported player configurations:

- Human Red vs Human Black
- Human Red vs Computer Black
- Computer Red vs Human Black
- Computer vs Computer demonstration game

---

## 5. Unit Classes

### 5.1 Master Unit Table

| Property | Battle Cruiser | Tank | Armored Car |
|---|---:|---:|---:|
| Unit HP | 30 | 24 | 18 |
| Terrain HP while stationary | 15 | 12 | 9 |
| Maximum ammo | 16 | 16 | 8 |
| Damage per hit | 5 | 4 | 4 |
| Orthogonal firing range | 11 | 7 | 4 |
| Diagonal firing range | 8 | 5 | 3 |
| Orthogonal movement range | 2 | 4 | 7 |
| Diagonal movement range | 1 | 3 | 5 |
| Maximum fuel | 240 | 240 | 160 |

### 5.2 Battle Cruiser

The Battle Cruiser is the game's king-equivalent and command center.

If a player's Battle Cruiser is destroyed, that player immediately loses.

Its characteristics are:

- extremely durable;
- longest firing range;
- highest damage per successful hit;
- very short movement range;
- exceptionally high fuel consumption.

### 5.3 Tank

The Tank is the middle-weight combat unit.

It combines:

- good durability;
- medium firing range;
- medium mobility;
- moderate fuel economy.

### 5.4 Armored Car

The Armored Car is the mobility unit.

It has:

- the least armor;
- the least ammunition;
- the shortest weapon range;
- the greatest movement allowance;
- the best fuel economy.

---

## 6. Army Composition

The original manual states the following maxima:

### Red Army

- 1 Battle Cruiser
- up to 3 Tanks
- up to 3 Armored Cars

### Black Army

- 1 Battle Cruiser
- up to 5 Tanks
- up to 5 Armored Cars

The exact user-interface behavior for selecting fewer than the maximum number of Tanks and Armored Cars should be verified against the original executable before final implementation.

### Compatibility requirement

The engine must not hard-code a fixed total piece count. Army composition must be data-driven.

Suggested maximum storage per side:

```text
1 cruiser + 5 tanks + 5 cars = 11 units
```

Maximum live units for both sides:

```text
22 units
```

---

## 7. Unit Runtime State

Each unit should maintain at least:

```c
struct Unit {
    UnitType type;
    Side side;

    int8_t x;
    int8_t y;

    uint8_t hp;
    uint16_t fuel;
    uint8_t ammo;

    uint8_t terrain_hp;

    bool alive;
};
```

Additional state will probably be needed for:

- per-turn firing restrictions;
- animation;
- AI evaluation;
- original-game compatibility quirks.

Recommended engine-only fields:

```text
fired_at_mask / fired_target_ids_this_turn
moved_this_turn
shots_this_turn
```

---

## 8. Movement

### 8.1 General Rule

A unit moves from its current square to another square on the same:

- horizontal line;
- vertical line; or
- 45-degree diagonal.

The destination must not exceed the unit's movement allowance for that orientation.

### 8.2 Movement Allowances

| Unit | Orthogonal | Diagonal |
|---|---:|---:|
| Battle Cruiser | 2 | 1 |
| Tank | 4 | 3 |
| Armored Car | 7 | 5 |

### 8.3 Path Traversal

Movement is line-based.

For a move from `A` to `B`:

1. determine direction;
2. determine distance in squares;
3. verify distance <= unit allowance;
4. inspect every intervening cell;
5. reject the move if any cell blocks movement;
6. calculate fuel cost;
7. reject the move if fuel is insufficient;
8. move the unit;
9. subtract fuel;
10. reset the unit's terrain HP to its class maximum.

### 8.4 Occupied Squares

A unit may not end movement on a square occupied by another unit.

Whether a unit may pass *through* another unit requires executable verification. The conservative implementation assumption is:

> **Units block movement through their square.**

This should remain tagged as a compatibility-test item until verified.

### 8.5 Multiple Moves by One Unit

A player's move allowance is a number of **moves per turn**, not a requirement that different pieces be moved.

The same unit may be moved more than once during the same turn, provided:

- moves remain;
- the piece has sufficient fuel;
- each individual move is otherwise legal.

---

## 9. Fuel

### 9.1 General Rule

Fuel is consumed when a unit moves.

A unit with insufficient fuel for a proposed move cannot execute that move.

A unit with no usable fuel may still fire if it has ammunition and a legal target.

### 9.2 Important Fuel Principle

Fuel usage is based on the distance of **each individual move**, and longer moves are disproportionately expensive.

Therefore:

```text
seven 1-square moves != one 7-square move
```

For an Armored Car moving orthogonally:

```text
7 × one-square moves = 7 fuel
one seven-square move = 28 fuel
```

This behavior is intentional and tactically significant.

### 9.3 Fuel Tables

#### Battle Cruiser

| Squares | Orthogonal | Diagonal |
|---:|---:|---:|
| 1 | 12 | 16 |
| 2 | 27 | — |

Maximum fuel: **240**

#### Tank

| Squares | Orthogonal | Diagonal |
|---:|---:|---:|
| 1 | 4 | 5 |
| 2 | 10 | 17 |
| 3 | 18 | 33 |
| 4 | 28 | — |

Maximum fuel: **240**

#### Armored Car

| Squares | Orthogonal | Diagonal |
|---:|---:|---:|
| 1 | 1 | 1 |
| 2 | 3 | 5 |
| 3 | 6 | 11 |
| 4 | 10 | 19 |
| 5 | 15 | 28 |
| 6 | 21 | — |
| 7 | 28 | — |

Maximum fuel: **160**

### 9.4 Forest / Tree Fuel Penalty

The original manual explicitly states that moving through tree squares:

- costs additional fuel;
- reduces movement allowance.

The manual does **not** provide sufficient numeric detail to reproduce this rule precisely.

Therefore this rule must be measured from the original executable.

Until measured, the engine should expose terrain modifiers rather than baking values into movement code:

```text
terrain.movement_allowed
terrain.movement_range_modifier
terrain.fuel_modifier
```

---

## 10. Firing

### 10.1 General Rule

A unit may fire at an enemy unit when:

1. the target lies on the same row, column, or 45-degree diagonal;
2. target range is within the weapon's range for that orientation;
3. line of sight is not blocked;
4. the firing unit has ammunition;
5. the current Shoot Option permits firing at this point in the turn;
6. the per-turn target restriction is satisfied.

### 10.2 Firing Ranges

| Unit | Orthogonal | Diagonal |
|---|---:|---:|
| Battle Cruiser | 11 | 8 |
| Tank | 7 | 5 |
| Armored Car | 4 | 3 |

### 10.3 Ammunition

| Unit | Maximum Ammo |
|---|---:|
| Battle Cruiser | 16 |
| Tank | 16 |
| Armored Car | 8 |

Each fired shot consumes:

```text
1 ammunition
```

A unit at zero ammo cannot fire.

### 10.4 Damage

A successful hit deals fixed damage based on the **attacker**:

| Attacker | Damage |
|---|---:|
| Battle Cruiser | 5 |
| Tank | 4 |
| Armored Car | 4 |

Damage does not vary by:

- range;
- target type;
- remaining HP.

Suggested implementation:

```text
target.hp = max(0, target.hp - attacker.damage)
```

If `target.hp == 0`, destroy the target.

---

## 11. Hit Probability

### 11.1 Orthogonal Fire

| Range | Hit Chance |
|---:|---:|
| 1 | 100% |
| 2 | 94% |
| 3 | 88% |
| 4 | 82% |
| 5 | 76% |
| 6 | 70% |
| 7 | 64% |
| 8 | 58% |
| 9 | 52% |
| 10 | 46% |
| 11 | 40% |

### 11.2 Diagonal Fire

| Range | Hit Chance |
|---:|---:|
| 1 | 98% |
| 2 | 89% |
| 3 | 81% |
| 4 | 72% |
| 5 | 64% |
| 6 | 56% |
| 7 | 47% |
| 8 | 39% |

### 11.3 Random Resolution

The original game uses percentage-based hit resolution.

For a faithful implementation:

```text
roll = random integer in a defined range
hit = roll < probability
```

The exact original PRNG and boundary behavior do not need to be preserved unless a "cycle-exact gameplay RNG" mode is later desired.

The IIGS version should make random-number generation injectable for testing.

Example:

```text
bool resolve_hit(uint8_t hit_percent, RNG *rng);
```

This allows unit tests to force hits and misses.

---

## 12. Misses and Stray Shots

The original manual states that a shot which misses its intended target may instead strike:

- a patch of ground; or
- another unit.

However, the manual does not specify:

- the scatter algorithm;
- eligible stray-hit squares;
- whether friendly units may be struck;
- whether the projectile continues along the firing line;
- whether terrain damage occurs on a miss;
- exact random probabilities for alternate impacts.

**This is a mandatory executable-verification item.**

The engine should therefore separate:

```text
1. determine intended target legality
2. roll hit/miss
3. resolve miss/scatter
4. apply resulting impact
```

Do not simply implement a miss as "nothing happens" unless original-game testing proves that appropriate for a particular case.

---

## 13. Per-Turn Firing Restriction

Observed original-game behavior indicates:

> A unit may fire multiple times during a turn, but may not fire twice at the same target during that turn.

This is a critical rule that is not clearly documented in the printed manual.

Tentative engine rule:

```text
for each attacker:
    attacker may fire at target T only if T has not already
    been fired upon by attacker during the current turn
```

This must be verified against the executable for:

- whether the restriction is per attacker or global to the army;
- whether destroyed targets still occupy the bookkeeping set;
- whether movement clears the restriction;
- whether target ID or square is tracked.

The likely interpretation, and recommended starting point, is **per attacker, per target, per turn**.

Firing does **not** appear to consume one of the player's movement actions.

---

## 14. Shoot Options

The game provides two fire-sequencing modes.

### 14.1 Shoot Option 1

> Fire may occur at any time.

The player may interleave:

```text
fire
move
fire
move
...
```

subject to all ordinary restrictions.

Recommended original settings:

```text
3–5 moves per turn
```

### 14.2 Shoot Option 2

> All firing must occur before movement.

Once the player performs the first movement action, firing is disabled for the remainder of that player's turn.

Recommended original settings:

```text
1–3 moves per turn
```

### 14.3 Engine State

Suggested turn state:

```text
phase = FIRE_OR_MOVE    // option 1

or

phase = FIRE            // option 2 initially
phase = MOVE            // option 2 after first move
```

For Option 2:

```text
first successful movement action:
    phase = MOVE
```

After this transition, no further shots may be initiated that turn.

---

## 15. Turn Structure

### 15.1 Start Turn

At the beginning of a player's turn:

1. set active side;
2. reset moves-used count;
3. clear per-turn firing bookkeeping;
4. establish firing phase according to Shoot Option;
5. start or resume that player's countdown clock.

### 15.2 During Turn

The player may:

- inspect units;
- move legal friendly units;
- fire legal friendly units;
- end the turn early;
- surrender;
- pause.

### 15.3 Moves Per Turn

Configuration range:

```text
1..20 moves per turn
```

Each successful piece movement consumes:

```text
1 move
```

Firing does not appear to consume a movement action.

### 15.4 End Turn

The turn ends when:

- all allowed movement actions have been used; or
- the player explicitly ends the turn; or
- the player's clock expires; or
- the player surrenders; or
- a Battle Cruiser is destroyed and the game ends immediately.

After a normal end:

```text
active_side = opposing_side
```

---

## 16. Time Control

Each army has its own countdown clock.

Allowed starting time:

```text
1..30 minutes per player
```

The clock is displayed as:

```text
MM:SS
```

If a player's clock reaches zero:

```text
that player immediately loses
```

The original manual says most games take less than thirty minutes.

### 16.1 Apple IIGS Timing Recommendation

The Apple IIGS port should use the system **tick counter / heartbeat counter** as the authoritative gameplay timer.

Do **not** use the battery-backed real-time clock as the primary chess clock.

Reasoning:

- the real-time clock is a wall clock and may be adjusted by the user or control panel;
- the real-time clock is only second-granular for ordinary Toolbox use;
- the tick counter measures elapsed time more naturally;
- the tick counter gives smoother and more exact turn accounting;
- the same timing source can also drive cursor blink, animation timing, and delays.

### 16.2 Internal Representation

Recommended engine state:

```c
uint32_t red_time_ticks;
uint32_t black_time_ticks;
uint32_t turn_start_tick;
```

Recommended semantics:

- `red_time_ticks` = Red remaining time in heartbeat ticks;
- `black_time_ticks` = Black remaining time in heartbeat ticks;
- `turn_start_tick` = tick count captured when the active turn begins.

Displayed `MM:SS` is derived from remaining ticks.

### 16.3 Turn Accounting

At the start of a player's turn:

```text
turn_start_tick = current_tick_count
```

At the end of that player's turn:

```text
elapsed = current_tick_count - turn_start_tick
active_side_remaining_time -= elapsed
```

Then switch sides and capture a new `turn_start_tick`.

The engine should also be able to compute a transient display value during the turn:

```text
displayed_remaining = stored_remaining - (current_tick_count - turn_start_tick)
```

### 16.4 RTC Usage

The Apple IIGS real-time clock remains useful for:

- save-game timestamps;
- replay/log timestamps;
- debugging metadata;
- user-facing save/load menus.

It should not be used as the authoritative source of elapsed gameplay time.

### 16.5 Pause

The original ESC command pauses play until another key is pressed.

A faithful IIGS implementation should stop gameplay clocks while paused.

Implementation note:

- when pause begins, first charge elapsed ticks to the active player;
- while paused, no gameplay time accrues;
- on unpause, set `turn_start_tick` to the current tick count.

---

## 17. Victory, Loss, Surrender, and Stalemate

### 17.1 Battle Cruiser Victory

Destroying the opposing Battle Cruiser immediately wins the game.

### 17.2 Time Loss

Running out of time immediately loses the game.

### 17.3 Surrender

A player may surrender.

Original Atari control:

```text
OPTION = surrender
```

The IIGS UI should request confirmation unless "strict original controls" is enabled.

### 17.4 Stalemate

If **neither side moves nor fires for four turns**, the game is declared a stalemate.

Implementation requires a clear definition of "turn."

Recommended interpretation:

```text
one player's complete action period = one turn
```

Maintain:

```text
inactive_turn_count
```

At turn end:

```text
if active side made >= 1 move OR fired >= 1 shot:
    inactive_turn_count = 0
else:
    inactive_turn_count++

if inactive_turn_count >= 4:
    stalemate
```

This interpretation should be verified against the original executable.

---

## 18. Terrain System

Terrain should be represented as behavior flags rather than hard-coded tile identities.

Recommended cell properties:

```text
can_move_into
blocks_movement_through
can_fire_through
destructible
terrain_hp / destruction state
movement_modifier
fuel_modifier
```

---

## 19. Natural Terrain — Boards 1–5 and 10

### 19.1 Trees

Trees:

- may be moved through;
- cost extra fuel;
- reduce movement allowance;
- block firing through the square.

Exact movement and fuel modifiers require original-game measurement.

Trees are destructible through the terrain-damage mechanism.

### 19.2 Water

Water:

- cannot be moved through directly;
- may be fired across.

Movement across water is only possible through bridges.

### 19.3 Bridges

Bridges:

- permit movement across water;
- may be destroyed.

A destroyed bridge should revert to non-traversable water or equivalent blocked-crossing state.

Exact bridge terrain HP and destruction interaction require executable verification.

### 19.4 Mountains

Mountains:

- block movement;
- block firing;
- cannot be destroyed.

---

## 20. Abstract Terrain — Boards 6–9

### 20.1 Board 6

The board is divided into a checkerboard:

- five blocks across;
- three blocks down.

Some blocks allow free movement.
Some do not.

Units:

- may pass diagonally between blocked regions;
- cannot move across a blocked region;
- may fire across the center block;
- cannot move across it.

The exact cell map must be captured from the original game data or screenshots.

### 20.2 Board 7

A black-and-yellow cross occupies the center.

Rules:

- units may move only through the yellow center;
- units may not move or fire through black cells.

### 20.3 Board 8

Same basic rule as Board 7, but the playable field is smaller.

### 20.4 Board 9

Checkerboard terrain with four relevant square colors/types:

**White**
- permits movement;
- permits fire.

**Grey**
- does not permit passage initially;
- may be destroyed;
- once destroyed, permits movement and fire.

**Purple**
- permits fire;
- prohibits movement.

**Black**
- blocks movement;
- blocks fire.

---

## 21. Board 10

Board 10 uses the same terrain layout as Board 1 with altered presentation:

- background is black;
- terrain and Red army are light grey.

The manual recommends playing Red against the computer.

Unless executable testing proves otherwise, Board 10 should be treated as mechanically identical to Board 1.

---

## 22. Original Board Descriptions

### Board 1

- river runs from upper-left to lower-right;
- mountains to the right of river;
- mountains in lower-left;
- three bridges cross the river;
- trees heavily forested.

### Board 2

- three heavily forested islands;
- islands connected by bridges.

### Board 3

- river separates two armies;
- river passes through a small valley.

### Board 4

- river runs diagonally;
- large island in center;
- bridges connect mountains/island to mainland.

### Board 5

- river runs top-to-bottom;
- bridges and mountains on both sides.

### Boards 6–9

Abstract boards as described above.

### Board 10

Night/dark presentation of Board 1.

---

## 23. Terrain Hit Points

Each unit has an associated **terrain HP** value while occupying a square.

| Unit | Terrain HP |
|---|---:|
| Battle Cruiser | 15 |
| Tank | 12 |
| Armored Car | 9 |

When a unit is hit:

```text
unit HP decreases by attack damage
terrain HP decreases by the same attack damage
```

When the unit moves:

```text
terrain HP resets to that unit class's maximum terrain HP
```

The manual explains this as representing the gunner's increasing ability to destroy a stationary target's underlying terrain.

Because terrain HP is lower than unit HP, destructible terrain can be destroyed before the unit standing on it.

### 23.1 Required Clarification

Executable testing must establish:

- what happens when destructible terrain reaches zero;
- whether the unit survives unchanged apart from normal unit damage;
- whether terrain replacement occurs immediately;
- behavior when a bridge is destroyed under a unit;
- behavior when trees are destroyed under a unit;
- behavior when Board 9 grey terrain is destroyed;
- whether non-destructible terrain still tracks/display terrain HP.

---

## 24. Line of Sight

### 24.1 Legal Fire Vector

A target must satisfy either:

```text
dx == 0
```

or

```text
dy == 0
```

or

```text
abs(dx) == abs(dy)
```

### 24.2 Range

For orthogonal fire:

```text
range = max(abs(dx), abs(dy))
```

For diagonal fire:

```text
range = abs(dx)
```

### 24.3 Intervening Cells

Trace all cells between attacker and target.

If any intervening cell has:

```text
blocks_fire = true
```

the shot is illegal.

### 24.4 Units and LOS

Whether units block fire to units behind them requires verification.

The game's tactical description suggests units may act as shields, implying occupied cells probably interact with line of fire.

Treat this as a high-priority compatibility test.

---

## 25. Status Information

The original interface presents two status lines:

- one for the unit under the selection cursor;
- one for the unit under the fire/move cursor.

Format:

```text
MM:SS  SQ=11, GM=11, AM=11, FL=111
```

Meanings:

| Field | Meaning |
|---|---|
| MM:SS | current player's remaining time |
| SQ | terrain hit points |
| GM | unit hit points |
| AM | remaining ammunition |
| FL | remaining fuel |

### 25.1 Projected Fuel

When the cursor is in Move mode, the destination status line shows the projected fuel remaining after the proposed move.

The IIGS version should preserve this feature.

---

## 26. Selection and Cursor Modes

The Atari original uses a joystick cursor with three states.

### Select Mode

No white box/cross.

Purpose:

- move cursor freely around board;
- choose a friendly unit.

### Move Mode

Represented by a white box.

Purpose:

- choose legal destination;
- preview fuel cost;
- execute movement.

### Fire Mode

Represented by a white cross.

Purpose:

- choose legal target;
- execute shot.

The IIGS version should preserve the conceptual state machine even if the actual UI is mouse-driven.

Recommended controls:

```text
single click friendly piece   -> select
drag/click legal destination  -> move
Fire command + target click   -> fire
right click / Esc             -> cancel current action
```

Keyboard and joystick support can be added after the mouse interface.

---

## 27. Original Keyboard Commands

Original Atari behavior:

| Key | Function |
|---|---|
| SELECT | cycle/view army status displays |
| OPTION | surrender |
| START | end turn early |
| ESC | pause |

On IIGS these should be mapped to native equivalents while remaining available through menus/hotkeys.

---

## 28. Army Status Screen

The original SELECT key cycles through:

1. status of the player's own units;
2. status of the opponent's units;
3. return to game.

The status display identifies:

- units remaining;
- unit types/shapes;
- corresponding status values.

The IIGS version may provide a continuously visible roster panel as an enhancement, but Original Rules mode should preserve all gameplay information that was available in the Atari version.

---

## 29. Game Options

There are seven configurable game options.

### 29.1 Game Board

```text
1..10
```

### 29.2 Units

Red:

```text
up to 3 Tanks
up to 3 Armored Cars
```

Black:

```text
up to 5 Tanks
up to 5 Armored Cars
```

Exact option-selection semantics need executable verification.

### 29.3 Starts First

```text
Red
Black
```

### 29.4 Computer Playing

Supported states:

```text
Computer plays both
Computer plays Red
Computer plays Black
Computer plays neither
```

### 29.5 Time Limit

```text
1..30 minutes per player
```

### 29.6 Moves Per Turn

```text
1..20
```

### 29.7 Shoot Option

```text
1 = fire at any time
2 = all firing before movement
```

---

## 30. Game State Model

Suggested top-level structure:

```c
struct GameState {
    Board board;

    Unit units[MAX_UNITS];
    uint8_t unit_count;

    Side active_side;

    uint8_t moves_per_turn;
    uint8_t moves_used;

    ShootOption shoot_option;
    TurnPhase turn_phase;

    uint32_t red_time_ticks;
    uint32_t black_time_ticks;
    uint32_t turn_start_tick;

    uint8_t inactive_turn_count;

    GameResult result;

    RNGState rng;
};
```

---

## 31. Board Cell Model

Suggested representation:

```c
struct Cell {
    TerrainType type;

    bool movement_allowed;
    bool blocks_movement;
    bool blocks_fire;

    bool destructible;

    uint8_t variant;
};
```

Destruction should preferably change the tile's terrain type rather than store generic HP permanently in every board square unless reverse engineering demonstrates that the original engine does otherwise.

Example:

```text
TREE -> CLEAR
BRIDGE -> WATER
GREY_BLOCK -> CLEAR
```

---

## 32. Suggested Engine API

```text
game_new(options)
game_tick(delta)

get_unit_at(x, y)
get_cell(x, y)

enumerate_legal_moves(unit)
enumerate_legal_targets(unit)

validate_move(unit, destination)
calculate_fuel_cost(unit, destination)
execute_move(unit, destination)

validate_shot(attacker, target)
calculate_hit_chance(attacker, target)
execute_shot(attacker, target)

end_turn()
surrender(side)

check_victory()
check_stalemate()
```

No rendering or sound routines should be called directly from the rules layer.

Instead, engine actions should emit events:

```text
UNIT_MOVED
SHOT_FIRED
SHOT_HIT
SHOT_MISSED
STRAY_HIT
UNIT_DAMAGED
UNIT_DESTROYED
TERRAIN_DAMAGED
TERRAIN_DESTROYED
TURN_CHANGED
GAME_OVER
```

This will make the IIGS animation layer substantially easier to write.

---

## 33. Deterministic Testing

The game engine should support fixed RNG seeds.

Examples:

```text
seed = $00000001
seed = $12345678
```

Unit tests should cover at minimum:

### Movement

- every unit's maximum orthogonal move;
- every unit's maximum diagonal move;
- one square beyond maximum rejected;
- insufficient fuel rejected;
- fuel deduction for every table entry;
- movement through blocked terrain rejected;
- movement resets terrain HP.

### Fire

- every range endpoint;
- one square beyond range rejected;
- orthogonal and diagonal probability table lookup;
- ammo decremented exactly once;
- zero-ammo shot rejected;
- damage application;
- destruction at zero HP;
- blocked LOS rejected.

### Turn Rules

- movement counter;
- early turn end;
- Shoot Option 1 interleaving;
- Shoot Option 2 fire-to-move transition;
- per-target firing restriction;
- timer loss;
- surrender;
- four inactive turns -> stalemate.

### Terrain

- tree behavior;
- water;
- bridge;
- mountain;
- Board 9 color rules;
- terrain destruction.

---

## 34. Original-Behavior Verification Checklist

The following behaviors are not fully specified by the surviving printed manual and should be measured against the Atari executable before declaring the engine complete.

### Critical

- [ ] Exact initial piece placement on all ten boards
- [ ] Exact selectable army compositions
- [ ] Whether units block movement paths
- [ ] Whether units block line of sight
- [ ] Exact miss/scatter algorithm
- [ ] Whether stray fire can hit friendly units
- [ ] Exact multiple-shot/per-target rule
- [ ] Whether firing consumes any hidden action allowance
- [ ] Exact tree movement-range penalty
- [ ] Exact tree fuel surcharge
- [ ] Exact destructible-terrain behavior
- [ ] Bridge destruction while occupied
- [ ] Board 9 grey-square destruction
- [ ] Exact stalemate counting semantics

### Important

- [ ] Cursor transition behavior
- [ ] Invalid move feedback
- [ ] Invalid shot feedback
- [ ] AI legal-action behavior
- [ ] Timer behavior during menus/status screens
- [ ] Pause behavior
- [ ] turn-ending behavior after final allowed move
- [ ] behavior when a unit has insufficient fuel for all moves
- [ ] behavior when all non-cruiser units are destroyed
- [ ] whether a Cruiser with no fuel/ammo remains fully valid for victory purposes

### Cosmetic / Compatibility

- [ ] exact board palette
- [ ] exact sound events
- [ ] original explosion timing
- [ ] original cursor animation
- [ ] status-screen sequencing
- [ ] title/demo timing

---

## 35. Compatibility Philosophy

Where the printed rules and executable disagree:

1. document both;
2. prefer executable behavior for **Original Rules** mode;
3. optionally provide a corrected behavior if the original appears to contain an obvious bug;
4. never silently "fix" behavior that affects tactics.

Suggested modes:

```text
Original
Enhanced
```

### Original

Replicates Atari gameplay behavior as closely as possible.

### Enhanced

May add:

- clearer LOS preview;
- movement-range highlighting;
- hit probability display;
- undo before commitment where no hidden/random information has been revealed;
- improved AI;
- configurable RNG;
- optional animation speed;
- visible unit roster;
- game replay;
- save/load.

No Enhanced feature should alter the core rules unless explicitly selected.

---

## 36. AI Requirements

AI is logically separate from rules.

The rules engine exposes legal actions and evaluates outcomes.

A first-pass AI can use:

```text
material value
cruiser safety
expected damage
ammo conservation
fuel conservation
mobility
number of enemy firing lines
number of friendly firing lines
terrain protection / LOS
distance to enemy cruiser
```

Expected damage:

```text
expected_damage =
    hit_probability * weapon_damage
```

A stronger AI can use shallow minimax or alpha-beta over movement/fire sequences.

Because there are at most roughly twenty-two units and the board contains only 220 cells, the IIGS has ample memory for sophisticated position evaluation, although sequence branching may require pruning.

AI design is outside the faithful-rules milestone.

---

## 37. Save Game Requirements

A saved game should contain only simulation state plus version metadata.

At minimum:

```text
file format version
board number
board destruction state
unit states
side to move
moves remaining
shoot option
turn phase
clock values
stalemate counter
per-turn target/fire bookkeeping
RNG state
```

Graphics and sound state should not be serialized.

---

## 38. Replay Support

Because *Combat Chess* is turn-based, a replay file can be a compact action log.

Example:

```text
MOVE unit=3 x=7 y=4
FIRE attacker=3 target=12 rng=...
ENDTURN
```

For exact replay, either:

- save RNG state before each random event; or
- store the resolved random result.

This is optional but architecturally cheap if planned early.

---

## 39. Internal Numeric Recommendations for Apple IIGS

The entire rules engine can comfortably use integer arithmetic.

Recommended:

```text
coordinates      8-bit
HP               8-bit
ammo             8-bit
fuel             16-bit
percentages      8-bit
unit IDs         8-bit
clock            32-bit ticks
```

No floating-point arithmetic is required.

Expected-damage AI calculations can use fixed-point arithmetic.

---

## 40. Rules Data Tables

The implementation should put all class-dependent behavior in data tables.

Example conceptual table:

```text
UnitClass {
    max_hp
    terrain_hp
    max_ammo
    max_fuel
    damage

    move_range_orth
    move_range_diag

    fire_range_orth
    fire_range_diag

    fuel_cost_orth[]
    fuel_cost_diag[]
}
```

Hit probabilities should also be tables.

This is preferable to embedded conditionals and closely matches the table-driven nature of the original rules.

---

## 41. Faithful-Port Milestones

### Milestone 1 — Headless Rules Engine

Complete:

- board;
- pieces;
- movement;
- fuel;
- firing;
- hit probability;
- damage;
- turn system;
- victory;
- clocks.

No graphics required.

### Milestone 2 — Atari Compatibility Tests

Run original executable and resolve every item in Section 34.

### Milestone 3 — IIGS Debug Board

Simple programmer-art board with:

- colored squares;
- piece letters/icons;
- legal move highlighting;
- fire lines;
- status display.

This proves the entire game before final artwork.

### Milestone 4 — Final 2D Artwork

Create:

- terrain tile set;
- Red vehicle sprites;
- Black vehicle sprites;
- cursors;
- muzzle flashes;
- projectile effects;
- explosions;
- damage states;
- UI chrome;
- title screen.

### Milestone 5 — Sound

Add:

- cannon reports;
- movement sounds;
- hit effects;
- explosions;
- UI feedback;
- title music if desired.

### Milestone 6 — AI

Implement and tune computer player.

---

## 42. Definition of Rules-Complete

The rules implementation is considered complete when:

1. all ten original boards can be loaded;
2. all original army configurations are reproducible;
3. every legal Atari move is legal on IIGS;
4. every illegal Atari move is rejected on IIGS;
5. fuel changes match the Atari game;
6. firing ranges and hit probabilities match;
7. miss/scatter behavior matches;
8. destructible terrain matches;
9. firing-sequence behavior matches;
10. win/loss/stalemate rules match;
11. a set of recorded Atari test games can be replayed action-for-action on the IIGS engine.

---

## 43. Essential Artwork Inventory

Artwork should not begin until board geometry and terrain types have been extracted, but the minimum asset inventory is already clear.

### Units

For each army:

- Battle Cruiser
- Tank
- Armored Car

Minimum:

```text
3 unit types × 2 sides = 6 base sprites
```

Possible enhanced states:

- selected;
- firing;
- damaged;
- critically damaged;
- destroyed.

### Terrain

Likely required:

- clear ground
- trees / forest
- water
- bridge
- mountain
- Board 6 abstract cells
- Board 7/8 yellow
- Board 7/8 black
- Board 9 white
- Board 9 grey
- Board 9 destroyed-grey
- Board 9 purple
- Board 9 black
- Board 10 dark variants

### Effects

- selection cursor
- move cursor
- fire cursor
- muzzle flash
- projectile / tracer
- hit spark
- ground impact
- explosion
- destroyed-terrain effect

### UI

- title/logo
- option screen
- unit roster icons
- status panel
- clocks
- ammo indicator
- fuel indicator
- HP indicator
- terrain HP indicator
- turn indicator
- victory/stalemate/surrender screens

---

## 44. Source Notes

Primary surviving rule source:

- Avalon Hill, *Combat Chess* instruction booklet, Atari 8-bit edition (1984/1985 printing), scans hosted by Atarimania.

Useful secondary behavioral source:

- The Wargaming Scribe, retrospective playthrough of *Combat Chess* (2024), particularly its observation that units can fire repeatedly in one turn but not repeatedly at the same target.

The printed manual itself leaves several implementation details unspecified. Those items are deliberately marked for executable verification rather than guessed.

---

## 45. Next Step

Before creating final artwork, capture the exact ten board maps and original unit starting positions into machine-readable data.

Suggested textual board format:

```text
....................
....TTTT............
....T..T....MMMM....
~~~~===~~~~.........
...
```

Or numeric tile IDs:

```text
00 clear
01 tree
02 water
03 bridge
04 mountain
...
```

Once every board is represented as a 20×11 array, the exact pixel dimensions and sprite scale for the IIGS presentation can be chosen with confidence.


## 46. Aesthetic Extraction Plan

> **Companion document:** `combat_chess_visual_capture_checklist.md` contains the detailed screen-by-screen and asset-by-asset harvest plan.


Before final artwork begins, create a reference archive from the Atari original.

### 46.1 Primary Extraction Targets

Capture or isolate:

- title screen;
- configuration/options screen;
- all ten board backgrounds;
- representative terrain tiles or terrain regions for each terrain type;
- unit sprites for both armies if distinct;
- cursor states;
- status-panel typography and layout;
- any emblem, border, or ornamental screen furniture;
- title-screen text treatments.

### 46.2 Practical Extraction Workflow

1. Acquire clean screenshots or manual images of:
   - title screen;
   - configuration screen;
   - in-game board views for each board.
2. Normalize each image to a common orientation and scale.
3. Crop reference regions for:
   - terrain;
   - units;
   - UI panels;
   - typography.
4. Store each crop with descriptive names.
5. Build a visual atlas / contact sheet for art direction.

### 46.3 Asset Bucket Recommendation

Suggested directory structure:

```text
reference/
  title/
  config/
  boards/
  terrain/
  units/
  ui/
  effects/
  manuals/
```

### 46.4 Music Direction Note

The original title music is a rendition of **"Over Hill, Over Dale."**

For the Apple IIGS port, a new arrangement may be authored for the Ensoniq sound hardware, for example in NinjaTracker Pro, while preserving the recognizable melodic identity of the title theme.

### 46.5 Deliverable of This Phase

The goal of the aesthetics-extraction phase is not final art.
It is a **reference package** that lets us answer:

- what the original visual language actually looked like;
- which terrain motifs recur;
- whether boards are tile-based, region-based, or hybrid;
- how much of the UI should be preserved literally versus reinterpreted.

