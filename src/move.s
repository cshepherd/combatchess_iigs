*----------------------------------------------------------
* move.s - The movement action (spec sections 8, 9, 23
* and 25.1).
*
* PUT into any part that carries the rules engine, after
* events.s. Same convention: native mode, 8-bit A/X/Y,
* DBR $00, D $0000.
*
* move_validate answers "may this unit move there, and what
* would it cost" without changing anything, so the UI can
* show the projected fuel (spec 25.1) and say why a move is
* refused. move_execute validates, then performs spec 8.3
* steps 8-10 and queues EV_UNIT_MOVED. Neither knows about
* turns: whose turn it is, moves left this turn and the
* Shoot Option phase are the turn code's checks before it
* calls move_execute (spec 14, 15).
*
* Spec 8.3 order: line, distance against the allowance,
* every cell on the way, fuel. The tree penalties (spec 9.4)
* come out of line_trace, so the trace runs before the range
* check; both penalty tables are zero until measured.
*----------------------------------------------------------
MV_OK       = 0
MV_NO_UNIT  = 1   ; no living unit with that id
MV_NOT_LINE = 2   ; not on the unit's row, column or diagonal, or off the board
MV_TOO_FAR  = 3   ; beyond the class's allowance in that orientation
MV_BLOCKED  = 4   ; terrain or a unit in the way, or the square is taken
MV_NO_FUEL  = 5   ; the unit cannot pay for the move

*----------------------------------------------------------
* move_validate - Check a move and price it.
* In:  A = unit id, X = destination x, Y = destination y
* Out: carry set, A = MV_OK: legal. mv_cost = fuel it takes,
*        mv_fuel_after = fuel left afterwards, and the ln_*
*        results describe the line.
*      carry clear, A = MV_* reason.
* Changes no game state. Clobbers X, Y, rt0-rt3, mv_*, ln_*.
*----------------------------------------------------------
move_validate
 MX %11
 sta mv_unit
 stx ln_x1
 sty ln_y1
 cmp #MAX_UNITS
 bcs :no_unit
 tax
 lda unit_flags,x
 bpl :no_unit
 lda unit_x,x
 sta ln_x0
 lda unit_y,x
 sta ln_y0
 jsr line_find
 bcc :not_line
 jsr line_trace
* allowance, less any tree penalty on the way (spec 9.4)
 ldx mv_unit
 lda unit_class,x
 ldx ln_orient
 jsr move_range
 sec
 sbc ln_move_pen
 bcc :too_far              ; the penalty ate the whole allowance
 cmp ln_dist
 bcc :too_far
 jsr move_path_clear
 bcc :blocked
* fuel: the table cost plus any tree surcharge
 ldx mv_unit
 lda unit_class,x
 ldx ln_orient
 ldy ln_dist
 jsr fuel_cost             ; a legal distance, so never FUEL_NONE
 clc
 adc ln_fuel_pen
 bcs :no_fuel              ; past 255: nobody can pay
 sta mv_cost
 ldx mv_unit
 lda unit_fuel,x
 cmp mv_cost
 bcc :no_fuel
 sbc mv_cost               ; carry is set here
 sta mv_fuel_after
 lda #MV_OK
 sec
 rts
:no_unit
 lda #MV_NO_UNIT
 clc
 rts
:not_line
 lda #MV_NOT_LINE
 clc
 rts
:too_far
 lda #MV_TOO_FAR
 clc
 rts
:blocked
 lda #MV_BLOCKED
 clc
 rts
:no_fuel
 lda #MV_NO_FUEL
 clc
 rts

*----------------------------------------------------------
* move_execute - Validate and, if legal, make the move:
* relocate the unit, charge the fuel, reset its terrain HP
* to the class maximum (spec 8.3 steps 8-10, spec 23), flag
* it as moved this turn, and queue EV_UNIT_MOVED (unit,
* from x, from y, to x, to y).
* In and out as move_validate. Nothing changes on refusal.
* Clobbers X, Y, rt0-rt5, mv_*, ln_*, ev_*.
*----------------------------------------------------------
move_execute
 MX %11
 jsr move_validate
 bcc :done
 ldx mv_unit
 lda unit_x,x
 sta ev_p1                 ; from
 lda unit_y,x
 sta ev_p2
 lda mv_fuel_after
 sta unit_fuel,x
 lda unit_flags,x
 ora #UF_MOVED
 sta unit_flags,x
 ldy unit_class,x
 lda class_terrain_hp,y
 sta unit_terr_hp,x
 txa
 ldx ln_x1
 ldy ln_y1
 jsr unit_set_pos
 lda #EV_UNIT_MOVED
 sta ev_type
 lda mv_unit
 sta ev_p0
 lda ln_x1
 sta ev_p3                 ; to
 lda ln_y1
 sta ev_p4
 jsr event_push
 lda #1
 sta mv_moved              ; for the display's slide animation
 lda mv_unit
 sta mv_last_unit
 lda ev_p1
 sta mv_last_fx
 lda ev_p2
 sta mv_last_fy
 lda ev_p3
 sta mv_last_tx
 lda ev_p4
 sta mv_last_ty
 lda #MV_OK
 sec
:done
 rts

mv_unit       ds 1
mv_moved      ds 1         ; set by move_execute, cleared once the display animates it
mv_last_unit  ds 1
mv_last_fx    ds 1
mv_last_fy    ds 1
mv_last_tx    ds 1
mv_last_ty    ds 1
mv_cost       ds 1         ; fuel the validated move takes
mv_fuel_after ds 1         ; fuel the unit would have left
