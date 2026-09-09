# Combat Chess — Shoot Option 1 vs. Shoot Option 2
## Implementation note for the Apple IIGS port

**Original game:** *Combat Chess* — Avalon Hill, Atari 8-bit (1984)  
**Purpose:** Nail down the exact sequencing difference between the two shooting options.

---

# Executive Summary

The original manual calls this setting **Shoot Option**.

The two modes are:

- **Shoot Option 1:** firing and movement may be interleaved during a player's turn.
- **Shoot Option 2:** **all firing for the turn must be completed before the player makes the first movement action.**

The most important implementation consequence is:

> In Shoot Option 2, the player's **first successful movement ends the firing phase for the rest of that turn**.

This is a turn-wide rule. It does **not** mean "fire before each move."

---

# Rules Shared by Both Options

The Shoot Option setting changes **when firing is permitted**, not the basic movement or firing rules.

## Movement allowance

The game has a configurable **Moves Per Turn** value:

```text
1..20 movement actions per turn
```

A successful unit movement consumes one move.

The same unit may use more than one movement action during a turn.

## Firing does not consume the movement allowance

Firing is separate from the configurable movement-action count.

Observed play confirms that units may fire multiple times in a turn, while the player still has the configured number of movement actions available.

## How many times may you fire in a turn?

This is **not** a "one shot per friendly piece per turn" system.

The original printed manual fails to explain the total-shot rule clearly. However, observed Atari play documents the missing rule as:

> **You may shoot as many times as you want during your turn, but only once per enemy target.**

The important implementation consequence is that the restriction is best represented as a **target-used-this-turn** restriction, not a "has this firing unit already fired?" restriction.

### Example

Suppose the enemy currently has:

```text
Tank X
Tank Y
Armored Car Z
Battle Cruiser Q
```

A single friendly Tank A could potentially do:

```text
Tank A -> Tank X
Tank A -> Tank Y
Tank A -> Armored Car Z
Tank A -> Battle Cruiser Q
```

all in the same turn, if:

- every shot is legal for range and line-of-sight;
- Tank A has enough ammunition;
- the selected Shoot Option permits firing at that point in the turn.

So a piece is **not limited to one shot per turn**.

However, a given attacker may not fire twice at the same enemy target
during the same turn. The restriction is **per attacker, per target**.

Thus this is illegal:

```text
Tank A -> Tank X
Tank A -> Tank X        ; illegal: Tank A already fired at Tank X this turn
```

but this is perfectly legal, and common: several friendly units may
each fire once at the same enemy target in one turn.

```text
Tank A -> Tank X
Cruiser B -> Tank X     ; legal: a different attacker, once each
```

The restriction resets at the start of the player's next turn.

### Therefore there is no fixed global "number of shots"

The practical upper bound on firing during a turn is determined by:

```text
number of distinct enemy targets that can legally be fired upon
+ ammunition availability
+ Shoot Option sequencing
```

There is no army-wide cap tied to the number of enemy pieces: each of your units may fire at each enemy target once, so several units can pile fire onto one target (once each), and one unit can spread its fire across many targets.

A single friendly unit could theoretically account for several or even all of those shots if it has:

- sufficient ammo;
- sufficient range;
- clear lines of sight.

### Confidence note

This once-per-target rule is an observed behavior that the original Avalon Hill manual notoriously omits.

A contemporary playthrough/review summarizes it loosely as "shoot as
many times as you want, but once per target during your turn." That
phrasing is per **attacker**: one attacker may not repeat a target,
but different attackers may each fire once at the same target.

```text
Friendly Tank A fires at enemy Tank X.
Then friendly Tank B also fires at enemy Tank X
during the same turn.          ; legal: a different attacker
```

The correct implementation is an **attacker-target** restriction: a
unit may not fire twice at the same target in a turn, but two
different units may both fire at that target (once each).

This firing restriction applies identically under Shoot Option 1 and Shoot Option 2.

---

# Shoot Option 1

## Manual rule

The Avalon Hill manual states, in substance:

> Option #1 lets you shoot at any piece at any time.

The manual describes this as the more action-filled version of the game.

## Canonical interpretation

During an active turn, the player may freely interleave legal firing and legal movement actions.

For example:

```text
FIRE
FIRE
MOVE
FIRE
MOVE
MOVE
FIRE
```

is legal under Option 1, assuming every individual action is otherwise legal.

Another legal sequence:

```text
MOVE
FIRE
MOVE
FIRE
```

And another:

```text
FIRE
FIRE
FIRE
MOVE
MOVE
```

There is no permanent phase transition from firing to movement.

## State model

Conceptually:

```text
TURN_MODE = FIRE_OR_MOVE
```

Throughout the turn:

```text
if requested action == FIRE:
    validate and execute fire

if requested action == MOVE:
    validate and execute move
    moves_remaining--
```

A move does **not** disable subsequent firing.

## Important final-move nuance

The manual says that START ends a turn **before** all available moves have been used. This strongly implies that the normal Atari game ends the turn after the final allowed movement action is consumed.

Therefore:

- firing may occur after earlier movement actions;
- but the implementation should not invent a special "post-final-move firing phase" unless Atari executable testing proves one exists.

In other words, "at any time" means **at any time while the turn remains active**.

## Example with 3 Moves Per Turn

Legal:

```text
Shot
Move #1
Shot
Move #2
Shot
Move #3
TURN ENDS
```

Also legal:

```text
Move #1
Move #2
Shot
Shot
Move #3
TURN ENDS
```

The firing actions do not consume Move #1, #2, or #3.

---

# Shoot Option 2

## Manual rule

The Avalon Hill manual states:

> In Option #2, all your firing must be done before movement.

The manual describes this as the slower, more strategic version.

## Canonical interpretation

Every player's turn begins in a **FIRE phase**.

During that phase the player may:

- fire zero times;
- fire once;
- fire many legal shots;
- fire with one unit;
- fire with several units.

The player may continue firing until choosing to make a movement action.

### The first successful move permanently transitions the current turn into MOVE phase.

After that point:

```text
NO MORE FIRING THIS TURN
```

even if:

- movement actions remain;
- another unit has not fired yet;
- a newly moved unit now has a perfect target;
- the player moved only one square;
- the player would like to switch back to firing.

There is no transition back to FIRE phase until the opposing player finishes and this player's next turn begins.

## State model

At turn start:

```text
phase = FIRE
moves_used = 0
```

During FIRE phase:

```text
FIRE -> allowed
MOVE -> allowed
```

Upon the **first successful MOVE**:

```text
phase = MOVE
moves_used++
```

During MOVE phase:

```text
MOVE -> allowed while moves remain
FIRE -> illegal
```

At next turn:

```text
phase = FIRE
```

---

# What Does *Not* End the Firing Phase in Option 2

The rules say firing must precede **movement**.

Therefore the phase transition should occur on a **successful committed movement**, not merely because the user interacted with movement UI.

These should **not** by themselves end firing:

```text
selecting a unit
moving the cursor
entering Move cursor mode
previewing a destination
checking projected fuel
attempting an illegal move
cancelling Move mode
selecting a square and then cancelling
```

Only an actual executed movement should cause:

```text
FIRE -> MOVE
```

unless executable testing demonstrates an Atari UI quirk to the contrary.

This distinction is particularly important for a mouse-driven Enhanced version.

---

# Example: Shoot Option 2 with 3 Moves Per Turn

## Legal

```text
Fire Tank A at Car X
Fire Tank A at Tank Y
Fire Cruiser at Tank Y
Move Tank A       ; first movement: firing phase ends
Move Car B
Move Cruiser
TURN ENDS
```

## Legal: no firing at all

```text
Move Tank A       ; immediately forfeits all firing this turn
Move Car B
Move Tank A
TURN ENDS
```

## Illegal

```text
Fire Tank A
Move Tank A
Fire Cruiser      ; ILLEGAL: firing phase ended
```

## Also illegal

```text
Move Tank A
Fire Tank A       ; ILLEGAL
```

## Legal before the first move

```text
Fire Tank A
Fire Cruiser
Fire Car B
Fire Tank A at a different target
Move Car B
Move Tank A
Move Tank A
```

---

# Recommended Engine Representation

```c
typedef enum {
    SHOOT_OPTION_1,
    SHOOT_OPTION_2
} ShootOption;

typedef enum {
    TURN_FIRE_OR_MOVE,   // Option 1
    TURN_FIRE,           // Option 2, before first movement
    TURN_MOVE            // Option 2, after first movement
} TurnPhase;
```

At turn start:

```c
if (shootOption == SHOOT_OPTION_1)
    turnPhase = TURN_FIRE_OR_MOVE;
else
    turnPhase = TURN_FIRE;
```

On successful movement:

```c
execute_move(...);
movesUsed++;

if (shootOption == SHOOT_OPTION_2 &&
    turnPhase == TURN_FIRE) {
    turnPhase = TURN_MOVE;
}
```

When validating a shot:

```c
bool fire_phase_allows_shot(void)
{
    if (shootOption == SHOOT_OPTION_1)
        return true;

    return turnPhase == TURN_FIRE;
}
```

---

# Per-Turn Target Bookkeeping

Do **not** use a simple `hasFiredThisTurn` flag on each friendly unit: a friendly unit may fire several times (at different targets). And do **not** use a single global per-target flag: several friendly units may each fire once at the same enemy target.

The rule is an **attacker-target** restriction, per attacker per target per turn:

```c
bool firedThisTurn[MAX_ATTACKERS][MAX_TARGETS];   // or a per-attacker bitmask over targets
```

Before a shot:

```c
if (firedThisTurn[attackerID][targetID])
    reject_shot();
```

After a committed shot attempt:

```c
firedThisTurn[attackerID][targetID] = true;
```

The pair counts as used whether the shot:

```text
hits
misses
```

because the rule concerns having fired at that target, not whether damage was inflicted.

Clear the flags when the active player's turn begins.

This bookkeeping is independent of Shoot Option.

## Verification case (confirmed)

```text
Attacker A -> Target X            ; legal
Attacker A -> Target X            ; illegal: A already fired at X
Attacker B -> Target X            ; legal: a different attacker, once each
```

Confirmed behavior: a second **attacker** may fire at a target already
fired upon this turn; only a repeat by the **same** attacker at the
same target is rejected. The IIGS port implements the per-attacker
matrix (a per-attacker bitmask over enemy slots, plus a small
per-attacker list of squares fired at).

---

# Recommended Tests

## Shoot Option 1

```text
PASS: fire before any movement
PASS: move, then fire
PASS: fire, move, fire
PASS: move, move, fire
PASS: different units fire around movement actions
PASS: firing does not decrement moves remaining
PASS: same friendly unit may fire at multiple different targets
PASS: a second friendly unit fires at a target already fired upon this turn
FAIL: the same friendly unit fires twice at the same target in one turn
```

## Shoot Option 2

```text
PASS: multiple shots before first move
PASS: several different units fire before first move
PASS: player makes no shots and immediately moves
PASS: first successful move transitions phase FIRE -> MOVE
FAIL: shot after first successful move
FAIL: shot after second or later move
PASS: entering/cancelling Move UI without executing a move leaves FIRE phase intact
PASS: invalid attempted movement leaves FIRE phase intact
PASS: firing does not decrement moves remaining
PASS: one friendly unit may fire at several distinct targets before movement
PASS: a second unit fires at a target already fired upon that turn
FAIL: the same unit fires twice at the same target that turn
PASS: per-attacker target restrictions clear at the beginning of the player's next turn
PASS: firing permission resets to FIRE at beginning of player's next turn
```

## Turn-boundary test

Given:

```text
Shoot Option 2
Red turn: FIRE -> MOVE
Black turn occurs
Red turn begins again
```

Expected:

```text
Red may fire again before moving.
```

---

# AI Consequences

The distinction matters considerably for computer play.

## Option 1 AI

The AI may evaluate sequences such as:

```text
move -> fire -> move -> fire
```

Movement can create firing opportunities during the same turn.

## Option 2 AI

The AI must choose its complete firing plan from the **start-of-turn position** before executing movement.

Once it commits its first move:

```text
all remaining actions are movement-only
```

The manual specifically notes that increasing Moves Per Turn affects computer quality differently between the two modes:

- under Option 1, more moves per turn makes the game faster and the computer play better;
- under Option 2, more moves per turn makes the game faster but the computer play worse.

Avalon Hill recommends:

```text
Option 1: 3–5 moves per turn
Option 2: 1–3 moves per turn
```

That recommendation makes sense if Option 2 requires the AI to commit all fire before repositioning.

---

# Confidence / Source Notes

## Directly specified by the original Avalon Hill manual

High confidence:

```text
Option 1 permits shooting at any time.
Option 2 requires all firing before movement.
Moves Per Turn is configurable from 1 to 20.
START ends a turn before all moves have been used.
```

## Confirmed by observed Atari play

High confidence but poorly documented in the original manual:

```text
A unit may fire multiple times during a turn.
There is no once-per-firing-piece shot cap.
Observed play describes the restriction as once per enemy target per attacker: a unit may not repeat a target, but several units may each fire once at the same target.
The same unit may consume multiple movement actions in one turn.
```

## Implementation inference

Very strong rules-based inference:

```text
In Option 2, only a successful movement should close the firing phase;
merely entering or cancelling Move cursor mode should not.
```

If exact bug-for-bug Atari compatibility is desired, this last detail is worth one executable test.

---

# Bottom Line for the Port

Implement the two options as:

```text
FIRE COUNT:
    There is NO once-per-piece firing limit.
    A friendly piece may fire repeatedly at DIFFERENT enemy targets.
    A piece may NOT fire twice at the same target in a turn, but
    several pieces MAY each fire once at the same target (per
    attacker, per target). Ammo, range, LOS, and Shoot Option apply.

OPTION 1:
    FIRE and MOVE may be freely interleaved
    for as long as the player's turn is active.

OPTION 2:
    FIRE as much as desired first.
    FIRST SUCCESSFUL MOVE permanently disables FIRE
    for the remainder of that turn.
```

Do **not** implement Option 2 as:

```text
fire -> move -> fire -> move
```

and do **not** interpret it as:

```text
each individual unit must fire before that unit moves
```

The restriction is global to the player's turn.
