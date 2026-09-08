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
 jsr fire_check_line
 bcc :fail
 lda #FR_OK
 sec
 rts
:no_unit
 lda #FR_NO_UNIT
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
 bcc :done
 ldx fr_attacker
 dec unit_ammo,x
 inc unit_shots,x
 lda fr_attacker
 ldx fr_target
 jsr unit_mark_fired_at
 lda #EV_SHOT_FIRED
 jsr fr_event              ; attacker, target
 lda fr_chance
 jsr resolve_hit
 sta fr_roll
 bcc :miss
 lda #EV_SHOT_HIT
 jsr fr_event
 lda fr_roll
 sta ev_p2
 jsr event_push
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
 jsr miss_resolve
 stz fr_outcome            ; FR_MISS
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
 bcc :done
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
 lda #EV_SHOT_FIRED
 jsr fr_event
 lda fr_chance
 jsr resolve_hit
 sta fr_roll
 bcc :miss
 lda #EV_SHOT_HIT
 jsr fr_event
 lda fr_roll
 sta ev_p2
 jsr event_push
 ldx fr_tx
 ldy fr_ty
 jsr get_cell
 sta fr_terr_type
 jsr destroy_cell          ; validated destructible
 sta ev_p3                 ; the new type
 lda #EV_TERRAIN_DESTROYED
 sta ev_type
 stx ev_p0
 sty ev_p1
 lda fr_terr_type
 sta ev_p2
 stz ev_p4
 jsr event_push
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
 jsr miss_resolve
 stz fr_outcome            ; FR_MISS
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
* miss_resolve - What a missed shot does instead (spec 12).
* UNVERIFIED (spec 34, critical): the manual says a miss may
* strike ground or another unit but gives no scatter
* algorithm, eligible squares, friendly-fire rule, terrain
* effect or probabilities, and does not say whether the
* projectile carries on down the line. Until the Atari
* executable is measured, a miss does nothing further.
* Called after EV_SHOT_MISSED with fr_* and ln_* describing
* the shot, so scatter code has everything when it arrives.
*----------------------------------------------------------
miss_resolve
 MX %11
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
