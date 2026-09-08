*----------------------------------------------------------
* tables.s - Combat Chess rules data (spec sections 5, 8, 9,
* 10 and 40) and the lookups that define how it is indexed.
*
* PUT into any part that carries the rules engine, after
* shared.s (it uses the rt* direct-page scratch). Pure data
* plus stateless lookups; no game state lives here.
*
* Everything class-dependent is a table indexed by unit
* class, so movement and fire code never tests the class.
* All values fit in a byte: the largest is max fuel, 240.
*
* Rules-engine calling convention (all routines here):
*   native mode, 8-bit A/X/Y (MX %11), DBR = $00, D = $0000.
*----------------------------------------------------------

* Unit classes (spec 5.1). The order is the index into every
* class_* table and into the fuel table.
CLASS_CRUISER = 0
CLASS_TANK    = 1
CLASS_CAR     = 2
NUM_CLASSES   = 3

* Move / fire orientation (spec 3.2).
ORIENT_ORTH = 0
ORIENT_DIAG = 1

* Longest single move any class can make: the Armored Car's
* seven squares orthogonally. Fuel table rows hold this many
* entries plus the unused distance 0.
MAX_MOVE_DIST = 7

* Fuel-table marker for "cannot move that far". No unit can
* ever pay it (max fuel is 240), so comparing a unit's fuel
* against the cost rejects illegal distances for free.
FUEL_NONE = $FF

*----------------------------------------------------------
* Master unit table (spec 5.1). One byte per class, in
* CLASS_* order: Battle Cruiser, Tank, Armored Car.
*----------------------------------------------------------
class_max_hp      dfb 30,24,18     ; unit hit points
class_terrain_hp  dfb 15,12,9      ; terrain HP while stationary
class_max_ammo    dfb 16,16,8
class_max_fuel    dfb 240,240,160
class_damage      dfb 5,4,4        ; per hit, by attacker
class_fire_orth   dfb 11,7,4       ; firing range, squares
class_fire_diag   dfb 8,5,3
class_move_orth   dfb 2,4,7        ; movement range, squares
class_move_diag   dfb 1,3,5

* Display names, C strings, indexed by class*2.
class_name_ptrs   da name_cruiser,name_tank,name_car
name_cruiser      asc 'BATTLE CRUISER'
                  dfb 0
name_tank         asc 'TANK'
                  dfb 0
name_car          asc 'ARMORED CAR'
                  dfb 0

*----------------------------------------------------------
* Fuel cost of one move (spec 9.3). Each class has a 16-byte
* row: 8 orthogonal entries then 8 diagonal, indexed by the
* distance in squares (entry 0 is unused). Index =
* class*16 + orientation*8 + distance; fuel_cost does the
* arithmetic, so nothing else should index this directly.
*
* Costs grow faster than distance on purpose (spec 9.2):
* seven 1-square Car moves cost 7, one 7-square move 28.
*----------------------------------------------------------
fuel_table
* Battle Cruiser: orthogonal 1-2, diagonal 1
 dfb $FF,12,27,$FF,$FF,$FF,$FF,$FF
 dfb $FF,16,$FF,$FF,$FF,$FF,$FF,$FF
* Tank: orthogonal 1-4, diagonal 1-3
 dfb $FF,4,10,18,28,$FF,$FF,$FF
 dfb $FF,5,17,33,$FF,$FF,$FF,$FF
* Armored Car: orthogonal 1-7, diagonal 1-5
 dfb $FF,1,3,6,10,15,21,28
 dfb $FF,1,5,11,19,28,$FF,$FF

*----------------------------------------------------------
* fuel_cost - Fuel for one move.
* In:  A = class, X = orientation, Y = distance in squares
* Out: A = cost, carry set: a legal distance for this class
*      A = FUEL_NONE, carry clear: the class cannot move that
*      far in that orientation. Covers distance 0 and any
*      distance past MAX_MOVE_DIST as well.
* Preserves X and Y.
*----------------------------------------------------------
fuel_cost
 MX %11
 cpy #MAX_MOVE_DIST+1
 bcs :none
 asl
 asl
 asl
 asl                       ; class*16
 cpx #ORIENT_DIAG
 bne :orth
 ora #8                    ; + orientation*8
:orth
 sta rt0
 tya
 clc
 adc rt0                   ; + distance
 phx
 tax
 lda fuel_table,x
 plx
 cmp #FUEL_NONE
 beq :none
 sec
 rts
:none
 lda #FUEL_NONE
 clc
 rts

*----------------------------------------------------------
* move_range / fire_range - Range in squares for a class in
* one orientation.
* In:  A = class, X = orientation
* Out: A = squares. Clobbers X.
*----------------------------------------------------------
move_range
 MX %11
 cpx #ORIENT_DIAG
 beq :diag
 tax
 lda class_move_orth,x
 rts
:diag
 tax
 lda class_move_diag,x
 rts

fire_range
 MX %11
 cpx #ORIENT_DIAG
 beq :diag
 tax
 lda class_fire_orth,x
 rts
:diag
 tax
 lda class_fire_diag,x
 rts
