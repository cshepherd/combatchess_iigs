*----------------------------------------------------------
* fire.s - The fire action (spec sections 10-13, 23, 24).
*
* PUT into any part that carries the rules engine, after
* move.s and rng.s. Same convention: native mode, 8-bit
* A/X/Y, DBR $00, D $0000.
*
* fire_validate answers "may this unit shoot that one, and
* with what odds" without changing anything, so the UI can
* show the hit chance (Enhanced mode) and say why a shot is
* refused. fire_execute validates, spends the ammunition,
* rolls, applies the hit or hands a miss to miss_resolve,
* and queues the events. fire_validate_at / fire_execute_at
* take a square instead: the enemy unit on it, else the
* square itself if it can be destroyed. Neither knows about turns: whose
* turn it is and the Shoot Option phase (spec 14) are the
* turn code's checks before it calls fire_execute. Victory
* (spec 17.1) is the game layer's check afterwards, using
* fr_outcome.
*
* Spec 10.1 order: living attacker and enemy target, line,
* range, line of sight, ammunition, then the per-turn
* target rule (spec 13).
*----------------------------------------------------------
FR_OK           = 0
FR_NO_UNIT      = 1   ; no living attacker with that id
FR_NO_TARGET    = 2   ; target is not a living enemy unit, or not a square that can be destroyed
FR_NOT_LINE     = 3   ; not on the attacker's row, column or diagonal
FR_OUT_OF_RANGE = 4   ; beyond the class's range in that orientation
FR_BLOCKED      = 5   ; terrain, or a unit while the rule says so, in the way
FR_NO_AMMO      = 6
FR_ALREADY      = 7   ; already fired at that target this turn (spec 13)
FR_SQUARE       = $FF ; fr_target of a shot at a square rather than a unit

* fr_outcome after a successful fire_execute
FR_MISS = 0
FR_HIT  = 1
FR_KILL = 2           ; hit, and the target was destroyed

*----------------------------------------------------------
* fire_validate - Check a shot and give its odds.
* In:  A = attacker id, X = target id
* Out: carry set, A = FR_OK: legal. fr_chance = hit percent,
*        fr_damage = damage on a hit, and the ln_* results
*        describe the line.
*      carry clear, A = FR_* reason.
* Changes no game state. Clobbers X, Y, rt0-rt3, fr_*, ln_*.
*----------------------------------------------------------
fire_validate
 MX %11
 sta fr_attacker
 stx fr_target
 cmp #MAX_UNITS
 bcs :no_unit
 tax
 lda unit_flags,x
 bpl :no_unit
 ldx fr_target
 cpx #MAX_UNITS
 bcs :no_target
 lda unit_flags,x
 bpl :no_target
 lda unit_side,x
 ldx fr_attacker
 cmp unit_side,x
 beq :no_target            ; own side, or itself
 lda unit_x,x
 sta ln_x0
 lda unit_y,x
 sta ln_y0
 ldx fr_target
 lda unit_x,x
 sta ln_x1
 lda unit_y,x
 sta ln_y1
 jsr fire_check_line
 bcc :fail
 lda fr_attacker
 ldx fr_target
 jsr unit_has_fired_at
 bcs :already
 lda #FR_OK
 sec
 rts
:no_unit
 lda #FR_NO_UNIT
 clc
 rts
:no_target
 lda #FR_NO_TARGET
 clc
 rts
:already
 lda #FR_ALREADY
:fail
 clc
 rts

*----------------------------------------------------------
* fire_validate_at - Check a shot at square (X, Y): at the
* enemy unit standing there, else at the square itself when
* it can be destroyed (trees, bridges, board 9's grey). The
* original lets a unit shoot such squares. UNVERIFIED
* whether its odds differ from a shot at a unit: the same
* hit table applies here, and one hit destroys an empty
* square, which carries no hit points (spec 23 gives them
* only under a unit).
* In:  A = attacker id, X = x, Y = y (on the board)
* Out: as fire_validate. fr_target = the unit's id, or
*      FR_SQUARE with fr_tx/fr_ty the square.
* Clobbers X, Y, rt0-rt3, fr_*, ln_*.
*----------------------------------------------------------
fire_validate_at
 MX %11
 sta fr_attacker
 stx fr_tx
 sty fr_ty
 jsr get_unit_at
 bcc :square
 tax
 lda fr_attacker
 jmp fire_validate
:square
 lda #FR_SQUARE
 sta fr_target
 lda fr_attacker
 cmp #MAX_UNITS
 bcs :no_unit
 tax
 lda unit_flags,x
 bpl :no_unit
 lda unit_x,x
 sta ln_x0
 lda unit_y,x
 sta ln_y0
 ldx fr_tx
 stx ln_x1
 ldy fr_ty
 sty ln_y1
 jsr get_cell
 jsr cell_flags
 and #TF_DESTRUCT
 beq :no_target
 jsr fire_check_line       ; line, range, sight, ammunition
 bcc :fail
 ldx fr_tx
 ldy fr_ty
 jsr cell_index
 tax                       ; X = cell index
 lda fr_attacker
 jsr square_has_fired_at   ; spec 13: not twice at the same target per turn (checked last, like units)
 bcs :already
 lda #FR_OK
 sec
 rts
:no_unit
 lda #FR_NO_UNIT
 clc
 rts
:already
 lda #FR_ALREADY
 clc
 rts
:no_target
 lda #FR_NO_TARGET
:fail
 clc
 rts

* fire_check_line - The checks both validates share once
* ln_x0..ln_y1 hold the endpoints and fr_attacker the
* shooter: a line, the range (fr_chance), line of sight and
* ammunition; sets fr_damage.
* Out: carry set: fine. Carry clear, A = the FR_* reason.
fire_check_line
 MX %11
 jsr line_find
 bcc :not_line
 ldx fr_attacker
 lda unit_class,x
 ldx ln_orient
 ldy ln_dist
 jsr hit_chance            ; carry clear past the class's range
 bcc :out_of_range
 sta fr_chance
 jsr line_trace
 jsr los_clear
 bcc :blocked
 ldx fr_attacker
 lda unit_ammo,x
 beq :no_ammo
 ldy unit_class,x
 lda class_damage,y
 sta fr_damage
 sec
 rts
:not_line
 lda #FR_NOT_LINE
 clc
 rts
:out_of_range
 lda #FR_OUT_OF_RANGE
 clc
 rts
:blocked
 lda #FR_BLOCKED
 clc
 rts
:no_ammo
 lda #FR_NO_AMMO
 clc
 rts

*----------------------------------------------------------
* fire_execute - Validate and, if legal, take the shot: one
* round of ammunition, the shot counted and the target
* remembered for the rest of the turn (spec 10.3, 13), then
* the roll (spec 11.3). A hit damages the target and its
* square (unit_take_hit); a miss goes to miss_resolve.
* Events, in order: EV_SHOT_FIRED, then EV_SHOT_HIT or
* EV_SHOT_MISSED, then whatever the hit caused.
* In and out as fire_validate; fr_outcome = FR_MISS / FR_HIT
* / FR_KILL and fr_roll = the roll on success. Nothing
* changes on refusal.
* Clobbers X, Y, rt0-rt3, fr_*, ln_*, ev_*.
*----------------------------------------------------------
fire_execute
 MX %11
 jsr fire_validate
 bcs :ok
 rts                       ; invalid: carry clear, A = reason
:ok
 ldx fr_attacker
 dec unit_ammo,x
 inc unit_shots,x
 lda fr_attacker
 ldx fr_target
 jsr unit_mark_fired_at
 lda #EV_SHOT_FIRED
 jsr fr_event              ; attacker, target
 lda #1
 sta fr_shot               ; the display flies a shot, then explodes on a hit
 stz fr_shot_hit
 ldx fr_attacker
 lda unit_x,x
 sta fr_shot_fx
 lda unit_y,x
 sta fr_shot_fy
 lda unit_class,x
 sta fr_shot_class
 ldx fr_target
 lda unit_x,x
 sta fr_shot_tx
 lda unit_y,x
 sta fr_shot_ty
 lda fr_chance
 jsr resolve_hit
 sta fr_roll
 bcc :miss
 lda #EV_SHOT_HIT
 jsr fr_event
 lda fr_roll
 sta ev_p2
 jsr event_push
 lda #1
 sta fr_shot_hit
 ldx fr_target
 lda fr_damage
 jsr unit_take_hit
 lda #FR_HIT
 bcc :outcome
 lda #FR_KILL
:outcome
 sta fr_outcome
 lda #FR_OK
 sec
 rts
:miss
 lda #EV_SHOT_MISSED
 jsr fr_event
 lda fr_roll
 sta ev_p2
 jsr event_push
 jsr miss_resolve          ; sets fr_outcome (FR_MISS, or FR_KILL on a stray cruiser kill)
 lda #FR_OK
 sec
:done
 rts

*----------------------------------------------------------
* fire_execute_at - Validate and take a shot at square (X,
* Y): at the unit there through fire_execute, else at the
* square: a round spent, the roll, and on a hit the square
* destroyed (EV_TERRAIN_DESTROYED after EV_SHOT_HIT); a miss
* goes to miss_resolve. The shot events of a square shot
* carry FR_SQUARE as the target and the square in p3, p4.
* In and out as fire_validate_at; fr_outcome = FR_MISS or
* FR_HIT. Clobbers X, Y, rt0-rt3, fr_*, ln_*, ev_*.
*----------------------------------------------------------
fire_execute_at
 MX %11
 jsr fire_validate_at
 bcs :ok
 rts                       ; invalid: carry clear, A = reason
:ok
 lda fr_target
 cmp #FR_SQUARE
 beq :square
 tax
 lda fr_attacker
 jmp fire_execute
:square
 ldx fr_attacker
 dec unit_ammo,x
 inc unit_shots,x
 ldx fr_tx
 ldy fr_ty
 jsr cell_index
 tax                       ; X = cell index
 lda fr_attacker
 jsr square_mark_fired     ; spec 13: remember this square for the turn
 lda #EV_SHOT_FIRED
 jsr fr_event
 lda #1
 sta fr_shot
 stz fr_shot_hit
 ldx fr_attacker
 lda unit_x,x
 sta fr_shot_fx
 lda unit_y,x
 sta fr_shot_fy
 lda unit_class,x
 sta fr_shot_class
 lda fr_tx
 sta fr_shot_tx
 lda fr_ty
 sta fr_shot_ty
 lda fr_chance
 jsr resolve_hit
 sta fr_roll
 bcs :hit
 jmp :miss
:hit
 lda #EV_SHOT_HIT
 jsr fr_event
 lda fr_roll
 sta ev_p2
 jsr event_push
 lda #1
 sta fr_shot_hit
* wear down the square's terrain hit points; destroy it only
* when they reach zero (spec 23), so a bridge takes several
* shots while a tree (1 HP) still falls to one
 ldx fr_tx
 ldy fr_ty
 jsr cell_index
 tax                       ; X = cell index
 lda terr_hp,x
 sec
 sbc fr_damage
 bcs :hpok
 lda #0
:hpok
 sta terr_hp,x
 bne :stands
* destroyed
 ldx fr_tx
 ldy fr_ty
 jsr get_cell
 sta fr_terr_type
 jsr destroy_cell
 sta ev_p3                 ; the new type
 lda #EV_TERRAIN_DESTROYED
 sta ev_type
 stx ev_p0
 sty ev_p1
 lda fr_terr_type
 sta ev_p2
 stz ev_p4
 jsr event_push
 bra :sqdone
:stands
 lda #EV_TERRAIN_DAMAGED
 sta ev_type
 lda fr_tx
 sta ev_p0
 lda fr_ty
 sta ev_p1
 ldx fr_tx
 ldy fr_ty
 jsr cell_index
 tax
 lda terr_hp,x
 sta ev_p2                 ; terrain hit points left
 stz ev_p3
 stz ev_p4
 jsr event_push
:sqdone
 lda #FR_HIT
 sta fr_outcome
 lda #FR_OK
 sec
 rts
:miss
 lda #EV_SHOT_MISSED
 jsr fr_event
 lda fr_roll
 sta ev_p2
 jsr event_push
 jsr miss_resolve          ; sets fr_outcome (FR_MISS, or FR_KILL on a stray cruiser kill)
 lda #FR_OK
 sec
:done
 rts

* fr_event - Fill ev_type = A, ev_p0 = attacker, ev_p1 =
* target, the rest zero, except that a square shot puts its
* square in p3, p4. EV_SHOT_FIRED is pushed here; the others
* add a parameter first.
fr_event
 MX %11
 sta ev_type
 lda fr_attacker
 sta ev_p0
 lda fr_target
 sta ev_p1
 stz ev_p2
 stz ev_p3
 stz ev_p4
 lda fr_target
 cmp #FR_SQUARE
 bne :unit
 lda fr_tx
 sta ev_p3
 lda fr_ty
 sta ev_p4
:unit
 lda ev_type
 cmp #EV_SHOT_FIRED
 bne :later
 jmp event_push
:later
 rts

*----------------------------------------------------------
* unit_take_hit - A hit of A damage lands on unit X (spec
* 10.4, 23): unit HP and terrain HP both drop by the damage,
* floored at 0. Queues EV_UNIT_DAMAGED (unit, damage, hp
* left) and EV_TERRAIN_DAMAGED (x, y, terrain hp left). If
* terrain HP has just reached 0 on a destructible square,
* the square is destroyed: EV_TERRAIN_DESTROYED (x, y, old
* type, new type). If unit HP reached 0, the unit is
* destroyed: EV_UNIT_DESTROYED (unit, x, y).
* Out: carry set = the unit was destroyed.
* Clobbers A, X, Y, rt0-rt3, ev_*.
*
* UNVERIFIED (spec 23.1, 34): what happens to a unit whose
* square is destroyed beneath it, a bridge in particular.
* Here it stays where it is on the new terrain with terrain
* HP 0, and terrain HP keeps counting down on any terrain
* since the status line always shows it.
*----------------------------------------------------------
unit_take_hit
 MX %11
 sta fr_dmg_tmp
 stx fr_victim
 lda unit_hp,x
 sec
 sbc fr_dmg_tmp
 bcs :hp_ok
 lda #0
:hp_ok
 sta unit_hp,x
 lda #EV_UNIT_DAMAGED
 sta ev_type
 stx ev_p0
 lda fr_dmg_tmp
 sta ev_p1
 lda unit_hp,x
 sta ev_p2
 stz ev_p3
 stz ev_p4
 jsr event_push
* terrain HP
 ldx fr_victim
 lda unit_terr_hp,x
 sta fr_terr_old
 sec
 sbc fr_dmg_tmp
 bcs :terr_ok
 lda #0
:terr_ok
 sta unit_terr_hp,x
 lda #EV_TERRAIN_DAMAGED
 sta ev_type
 lda unit_x,x
 sta ev_p0
 lda unit_y,x
 sta ev_p1
 lda unit_terr_hp,x
 sta ev_p2
 stz ev_p3
 stz ev_p4
 jsr event_push
 ldx fr_victim
 lda unit_terr_hp,x
 bne :terrain_stands
 lda fr_terr_old
 beq :terrain_stands       ; was already 0: nothing new
 ldy unit_y,x
 lda unit_x,x
 tax
 jsr get_cell
 sta fr_terr_type
 jsr destroy_cell
 bcc :terrain_stands
 sta ev_p3                 ; new type
 lda #EV_TERRAIN_DESTROYED
 sta ev_type
 stx ev_p0
 sty ev_p1
 lda fr_terr_type
 sta ev_p2
 stz ev_p4
 jsr event_push
:terrain_stands
* the unit itself
 ldx fr_victim
 lda unit_hp,x
 bne :survives
 lda #EV_UNIT_DESTROYED
 sta ev_type
 stx ev_p0
 lda unit_x,x
 sta ev_p1
 lda unit_y,x
 sta ev_p2
 stz ev_p3
 stz ev_p4
 jsr event_push
 lda fr_victim
 jsr unit_kill
 sec
 rts
:survives
 clc
 rts

*----------------------------------------------------------
* miss_resolve - A missed shot still lands somewhere and
* explodes (spec 12). The projectile carries one square past
* the intended target along the line of fire, shifted a
* square in y the way the display flies a miss (up, or down
* when up would leave the top of the board), and strikes
* whatever sits on that square. Strays are blind: any unit
* there takes fr_damage (friend or foe), destructible terrain
* on an empty square is worn down and destroyed at 0 HP, and
* open ground just takes the blast. The clamped landing
* square goes to the display in fr_shot_land_x/y so the blast
* lands where the shot came to rest. miss_resolve owns
* fr_outcome for the miss: FR_MISS, or FR_KILL with fr_target
* = the victim when a stray fells a Battle Cruiser, so the
* turn layer ends the game (spec 17.1); with friendly fire on
* that cruiser may be the attacker's own.
* In:  fr_shot_fx/fy, fr_shot_tx/ty, fr_attacker, fr_damage.
* Clobbers A, X, Y, rt0-rt7, ev_*.
* Called after EV_SHOT_MISSED.
*
* UNVERIFIED (spec 12, 34): the manual says a miss may strike
* ground or another unit but gives no scatter algorithm,
* eligible squares, friendly-fire rule or terrain effect.
* This carries the shot one square past the target and lets
* it hit anything there; measure the Atari executable to
* confirm.
*----------------------------------------------------------
miss_resolve
 MX %11
 lda #FR_MISS
 sta fr_outcome
* direction of fire: dx, dy in {-1, 0, +1}
 lda fr_shot_tx
 sec
 sbc fr_shot_fx
 jsr ms_sgn
 sta rt0                   ; dx
 lda fr_shot_ty
 sec
 sbc fr_shot_fy
 jsr ms_sgn
 sta rt1                   ; dy
* y shift: down (+1) when the higher endpoint is the top row,
* else up (-1); matches the display's miss flight
 lda fr_shot_fy
 cmp fr_shot_ty
 bcc :miny                 ; fy < ty: min is fy, already in A
 lda fr_shot_ty
:miny
 cmp #1
 bcs :up                   ; min >= 1: shift up
 lda #1                    ; top-row endpoint: shift down
 bra :yadd
:up
 lda #$FF                  ; -1
:yadd
 clc
 adc rt1
 sta rt1                   ; dy + y shift
* landing square, clamped to the board
 lda fr_shot_tx
 clc
 adc rt0
 ldx #BOARD_W
 jsr ms_clamp
 sta fr_shot_land_x
 sta rt2
 lda fr_shot_ty
 clc
 adc rt1
 ldx #BOARD_H
 jsr ms_clamp
 sta fr_shot_land_y
 sta rt3
* what is on the landing square?
 ldx rt2
 ldy rt3
 jsr get_occupant          ; A = 0 empty, else id + 1
 beq :terrain              ; open square: wear the terrain instead
 sec
 sbc #1
 tax                       ; victim id (friend or foe: strays are blind)
 stx rt4
 lda fr_damage
 jsr unit_take_hit         ; the unit and its terrain both take it
 bcc :done
 ldx rt4
 lda unit_class,x
 cmp #CLASS_CRUISER
 bne :done
* a Battle Cruiser fell to the stray: count it as a kill so the
* turn layer ends the game, losing for fr_target's side
 lda rt4
 sta fr_target
 lda #FR_KILL
 sta fr_outcome
 bra :done
:terrain
 ldx rt2
 ldy rt3
 jsr cell_index
 tax                       ; X = cell index of the landing square
 lda terr_hp,x
 beq :done                 ; open / indestructible ground: just explode
 sec
 sbc fr_damage
 bcs :hpok
 lda #0
:hpok
 sta terr_hp,x
 bne :terr_dmg
* worn to nothing: the square is destroyed (spec 23)
 ldx rt2
 ldy rt3
 jsr get_cell
 sta fr_terr_type
 jsr destroy_cell          ; A = new type; X, Y preserved
 sta ev_p3
 lda #EV_TERRAIN_DESTROYED
 sta ev_type
 stx ev_p0
 sty ev_p1
 lda fr_terr_type
 sta ev_p2
 stz ev_p4
 jsr event_push
 bra :done
:terr_dmg
 lda #EV_TERRAIN_DAMAGED
 sta ev_type
 lda rt2
 sta ev_p0
 lda rt3
 sta ev_p1
 lda terr_hp,x             ; X still the cell index
 sta ev_p2
 stz ev_p3
 stz ev_p4
 jsr event_push
:done
 rts

* ms_sgn - signed byte in A -> -1 / 0 / +1
ms_sgn
 MX %11
 cmp #0
 beq :z
 bmi :neg
 lda #1
 rts
:neg
 lda #$FF
:z
 rts

* ms_clamp - clamp signed byte A to 0..X-1 (X a board size,
* 1..127); values >= $80 read as negative and clamp to 0
ms_clamp
 MX %11
 cmp #$80
 bcs :zero
 stx rt6
 cmp rt6
 bcc :ok                   ; A < dimension
 lda rt6
 dec                       ; dimension - 1
 rts
:zero
 lda #0
:ok
 rts

fr_attacker  ds 1
fr_target    ds 1
fr_chance    ds 1          ; hit percent of the validated shot
fr_damage    ds 1          ; damage it would do
fr_roll      ds 1          ; the roll, for replay logs
fr_outcome   ds 1          ; FR_MISS / FR_HIT / FR_KILL
fr_victim    ds 1
fr_dmg_tmp   ds 1
fr_terr_old  ds 1
fr_terr_type ds 1
fr_tx        ds 1          ; the square of a square shot
fr_ty        ds 1
fr_shot      ds 1          ; a shot was fired; the display flies it and explodes on a hit, then clears this
fr_shot_hit  ds 1          ; the shot hit (draw an explosion at the target)
fr_shot_fx   ds 1          ; the attacker's square
fr_shot_fy   ds 1
fr_shot_tx   ds 1          ; the target square
fr_shot_ty   ds 1
fr_shot_class ds 1         ; the attacker's class, for the shot's size
fr_shot_land_x ds 1        ; where a miss came to rest (miss_resolve); the
fr_shot_land_y ds 1        ; display explodes here on a miss
