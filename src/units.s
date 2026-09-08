*----------------------------------------------------------
* units.s - The unit list (spec sections 5-7 and 13) and its
* placement on the board.
*
* PUT into any part that carries the rules engine, after
* board.s. Same convention: native mode, 8-bit A/X/Y,
* DBR $00, D $0000.
*
* Units are parallel arrays indexed by unit id, so every
* field is one "lda unit_x,x" away. Ids are fixed by side:
* Red holds 0..10 and Black 11..21, UNITS_PER_SIDE slots
* each, the largest army the manual allows (a cruiser plus
* five tanks and five cars, spec 6). A side's slots fill in
* the order its units are added, so a unit's slot is id
* minus its side's first id. The per-turn "already fired at
* this target" rule (spec 13) is a 16-bit mask per attacker
* over the enemy's slots.
*
* The occupant map in board.s is kept current here: unit_add,
* unit_set_pos and unit_kill are the only writers.
*----------------------------------------------------------
SIDE_RED   = 0
SIDE_BLACK = 1
NUM_SIDES  = 2

UNITS_PER_SIDE = 11
MAX_UNITS      = 22
NO_UNIT        = $FF

* unit_flags bits. UF_ALIVE is bit 7 so "lda unit_flags,x"
* then bpl finds a dead unit, and asl puts it in carry.
UF_ALIVE = $80
UF_MOVED = $01           ; moved this turn (spec 7)

side_first_id dfb 0,UNITS_PER_SIDE

* Army limits by side and class (spec 6), indexed by
* side*3 + class. Data, not code: Enhanced mode may relax it.
side_class_max
 dfb 1,3,3               ; Red: cruiser, tanks, armored cars
 dfb 1,5,5               ; Black

*----------------------------------------------------------
* units_clear - No units on either side; empties the
* occupant map. Clobbers A, X.
*----------------------------------------------------------
units_clear
 MX %11
 ldx #MAX_UNITS-1
:loop
 stz unit_flags,x
 dex
 bpl :loop
 stz side_units
 stz side_units+1
 ldx #5
:cls
 stz side_class_used,x
 dex
 bpl :cls
 jmp occupant_clear

*----------------------------------------------------------
* unit_add - Put a new unit on the board at full strength.
* In:  un_side, un_class, un_x, un_y
* Out: carry set, A = the new unit's id
*      carry clear: the square is off the board, occupied,
*      or terrain a unit cannot stand on; or the side has no
*      slot left; or the army already has its limit of that
*      class (spec 6). Nothing changes on failure.
* Clobbers X, Y, rt0-rt2.
*----------------------------------------------------------
unit_add
 MX %11
 ldx un_x
 ldy un_y
 jsr cell_in_bounds
 bcc :fail
 jsr get_occupant
 bne :fail
 jsr get_cell
 jsr cell_flags
 and #TF_MOVE
 beq :fail
 ldx un_side
 lda side_units,x
 cmp #UNITS_PER_SIDE
 bcs :fail
 lda un_side
 asl
 clc
 adc un_side               ; side*3
 clc
 adc un_class
 tax
 lda side_class_used,x
 cmp side_class_max,x
 bcc :accept
:fail
 clc
 rts
:accept
 inc side_class_used,x
* id = the side's first id + slots used so far
 ldx un_side
 lda side_units,x
 inc side_units,x
 clc
 adc side_first_id,x
 sta rt2                   ; id
 tax
 lda un_class
 sta unit_class,x
 lda un_side
 sta unit_side,x
 lda un_x
 sta unit_x,x
 lda un_y
 sta unit_y,x
 ldy rt2
 ldx un_class
 lda class_max_hp,x
 sta unit_hp,y
 lda class_max_fuel,x
 sta unit_fuel,y
 lda class_max_ammo,x
 sta unit_ammo,y
 lda class_terrain_hp,x
 sta unit_terr_hp,y
 lda #UF_ALIVE
 sta unit_flags,y
 lda #0
 sta unit_fired_lo,y
 sta unit_fired_hi,y
 sta unit_shots,y
 tya
 inc                       ; occupant = id + 1
 ldx un_x
 ldy un_y
 jsr set_occupant
 lda rt2
 sec
 rts

*----------------------------------------------------------
* get_unit_at - Which unit stands on (X, Y)?
* In:  X = x, Y = y (on the board)
* Out: carry set, A = unit id; carry clear, A = NO_UNIT.
* Preserves X, Y. Clobbers rt0.
*----------------------------------------------------------
get_unit_at
 MX %11
 jsr get_occupant
 beq :none
 dec
 sec
 rts
:none
 lda #NO_UNIT
 clc
 rts

*----------------------------------------------------------
* unit_set_pos - Move a unit to a square, keeping the
* occupant map right. No legality checks: that is the
* movement code's job before it calls this.
* In:  A = id, X = x, Y = y
* Out: A = id, X, Y unchanged. Clobbers rt0-rt2, rt4, rt5.
*----------------------------------------------------------
unit_set_pos
 MX %11
 sta rt2                   ; id
 stx rt4                   ; new x
 sty rt5                   ; new y
 tax
 ldy unit_y,x
 lda unit_x,x
 tax                       ; old square
 lda #OCC_NONE
 jsr set_occupant
 ldx rt2
 lda rt4
 sta unit_x,x
 lda rt5
 sta unit_y,x
 lda rt2
 inc                       ; occupant = id + 1
 ldx rt4
 ldy rt5
 jsr set_occupant
 lda rt2
 rts

*----------------------------------------------------------
* unit_kill - Take a unit off the board. It keeps its slot
* and its last state for the status display.
* In:  A = id. Clobbers A, X, Y, rt0, rt1.
*----------------------------------------------------------
unit_kill
 MX %11
 tax
 lda unit_flags,x
 and #$7F                  ; clear UF_ALIVE
 sta unit_flags,x
 ldy unit_y,x
 lda unit_x,x
 tax
 lda #OCC_NONE
 jmp set_occupant

*----------------------------------------------------------
* unit_count_alive - How many of a side's units are alive.
* In:  X = side
* Out: A = count. Clobbers X, rt2, rt3.
*----------------------------------------------------------
unit_count_alive
 MX %11
 lda side_units,x
 sta rt2                   ; slots to look at
 stz rt3
 lda side_first_id,x
 tax
:loop
 lda rt2
 beq :done
 lda unit_flags,x
 bpl :dead
 inc rt3
:dead
 inx
 dec rt2
 bra :loop
:done
 lda rt3
 rts

*----------------------------------------------------------
* units_begin_turn - Clear a side's per-turn bookkeeping
* (spec 15.1): fired-at masks, shot counts, UF_MOVED.
* In:  X = side. Clobbers A, X, rt2.
*----------------------------------------------------------
units_begin_turn
 MX %11
 lda side_units,x
 sta rt2
 lda side_first_id,x
 tax
:loop
 lda rt2
 beq :done
 stz unit_fired_lo,x
 stz unit_fired_hi,x
 stz unit_shots,x
 lda unit_flags,x
 and #$FF-UF_MOVED
 sta unit_flags,x
 inx
 dec rt2
 bra :loop
:done
 rts

*----------------------------------------------------------
* unit_slot - A = id -> A = slot within its side (0..10).
*----------------------------------------------------------
unit_slot
 MX %11
 cmp #UNITS_PER_SIDE
 bcc :done
 sbc #UNITS_PER_SIDE       ; carry is set here
:done
 rts

*----------------------------------------------------------
* unit_has_fired_at - Has the attacker already fired at this
* target during the current turn (spec 13)?
* In:  A = attacker id, X = target id
* Out: carry set = yes. Clobbers A, X, Y, rt2.
*----------------------------------------------------------
unit_has_fired_at
 MX %11
 sta rt2                   ; attacker
 txa
 jsr unit_slot
 tay                       ; target slot
 ldx rt2
 cpy #8
 bcs :hi
 lda unit_fired_lo,x
 and bit_table,y
 bne :yes
 clc
 rts
:hi
 lda unit_fired_hi,x
 and bit_table-8,y
 bne :yes
 clc
 rts
:yes
 sec
 rts

*----------------------------------------------------------
* unit_mark_fired_at - Record that the attacker fired at the
* target this turn.
* In:  A = attacker id, X = target id. Clobbers A, X, Y, rt2.
*----------------------------------------------------------
unit_mark_fired_at
 MX %11
 sta rt2
 txa
 jsr unit_slot
 tay
 ldx rt2
 cpy #8
 bcs :hi
 lda unit_fired_lo,x
 ora bit_table,y
 sta unit_fired_lo,x
 rts
:hi
 lda unit_fired_hi,x
 ora bit_table-8,y
 sta unit_fired_hi,x
 rts

bit_table dfb $01,$02,$04,$08,$10,$20,$40,$80

* Parameters for unit_add.
un_side  ds 1
un_class ds 1
un_x     ds 1
un_y     ds 1

* The unit list. Part of the game state (spec 30); a save
* game stores these arrays plus side_units and
* side_class_used, and rebuilds the occupant map from them.
unit_class    ds MAX_UNITS
unit_side     ds MAX_UNITS
unit_x        ds MAX_UNITS
unit_y        ds MAX_UNITS
unit_hp       ds MAX_UNITS
unit_fuel     ds MAX_UNITS
unit_ammo     ds MAX_UNITS
unit_terr_hp  ds MAX_UNITS
unit_flags    ds MAX_UNITS
unit_fired_lo ds MAX_UNITS   ; enemy slots 0-7 fired at this turn
unit_fired_hi ds MAX_UNITS   ; enemy slots 8-10
unit_shots    ds MAX_UNITS   ; shots this turn
side_units      ds NUM_SIDES ; slots used per side
side_class_used ds 6         ; side*3 + class
