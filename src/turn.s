*----------------------------------------------------------
* turn.s - Turns, clocks and the end of the game (spec
* sections 14-17, 29 and 30).
*
* PUT into any part that carries the rules engine, after
* fire.s. Same convention: native mode, 8-bit A/X/Y,
* DBR $00, D $0000. The clock routines switch to 16-bit
* arithmetic inside and switch back.
*
* The turn layer wraps the actions: turn_move and turn_fire
* check whose turn it is, the moves left and the Shoot
* Option phase, then call move_execute / fire_execute and do
* the turn bookkeeping. turn_end charges the clock, counts
* idle turns for the stalemate rule and hands play over.
* game_over records the result and freezes the clocks.
*
* Time (spec 16) is counted in heartbeat ticks (60 per
* second) from get_tick, which goes through tick_vec so
* tests can supply exact values; the real source is the
* Misc Tools tick counter, never the battery clock. Each
* side has a stored remaining time; the active side's live
* time is the stored value less the ticks since
* turn_start_tick, charged at turn end, pause and game over.
*----------------------------------------------------------
SHOOT_ANY   = 1            ; Shoot Option 1: fire at any time
SHOOT_FIRST = 2            ; Shoot Option 2: all firing before movement

PHASE_FIRE_OR_MOVE = 0     ; option 1, all turn long
PHASE_FIRE         = 1     ; option 2, until the first move
PHASE_MOVE         = 2     ; option 2, after it: no more shots

RESULT_NONE       = 0
RESULT_RED_WINS   = 1      ; RESULT_RED_WINS + side = that side wins
RESULT_BLACK_WINS = 2
RESULT_STALEMATE  = 3

REASON_NONE      = 0
REASON_CRUISER   = 1       ; the other side's Battle Cruiser was destroyed
REASON_TIME      = 2       ; the other side's clock ran out
REASON_SURRENDER = 3
REASON_STALEMATE = 4

* turn_move / turn_fire / turn_end results. MV_* and FR_*
* reasons pass through unchanged; these sit above them.
TN_OK            = 0
TN_GAME_OVER     = $80
TN_NOT_YOURS     = $81     ; that unit is not the active side's
TN_NO_MOVES      = $82     ; no moves left this turn
TN_NO_FIRE_PHASE = $83     ; Shoot Option 2 and the side has moved

TICKS_PER_SEC   = 60
TICKS_PER_MIN   = 3600
STALEMATE_TURNS = 4        ; idle turns in a row (spec 17.4)

* Options (spec 29) the turn system reads. The options
* screen sets them before game_start.
opt_first_side     dfb SIDE_RED
opt_moves_per_turn dfb 3   ; 1..20
opt_shoot_option   dfb SHOOT_ANY
opt_time_minutes   dfb 10  ; 1..30 per player

* UNVERIFIED (spec 15.4, 34): whether the turn ends by itself
* after the last allowed move or waits for the player, who
* under Shoot Option 1 might still want to fire. Ends by
* itself, as spec 15.4 reads, until measured.
rule_auto_end_turn dfb 1

*----------------------------------------------------------
* game_start - Begin a game with the board and units already
* placed: first mover from the options, clocks full, no
* result, then the first turn. Clobbers A, X, Y, rt2, ev_*.
*----------------------------------------------------------
game_start
 MX %11
 lda opt_first_side
 sta active_side
 stz inactive_turns
 stz game_result
 stz result_reason
 stz paused
 ldx #SIDE_RED
 jsr clock_set
 ldx #SIDE_BLACK
 jsr clock_set
 jmp turn_begin

*----------------------------------------------------------
* turn_begin - Start the active side's turn (spec 15.1):
* moves and shots to zero, the phase from the Shoot Option,
* per-unit bookkeeping cleared, the clock running from now,
* EV_TURN_CHANGED (side). Clobbers A, X, Y, rt2, ev_*.
*----------------------------------------------------------
turn_begin
 MX %11
 stz moves_used
 stz turn_shots
 lda #PHASE_FIRE_OR_MOVE
 ldx opt_shoot_option
 cpx #SHOOT_FIRST
 bne :phase
 lda #PHASE_FIRE
:phase
 sta turn_phase
 ldx active_side
 jsr units_begin_turn
 jsr get_tick
 jsr clock_restart
 stz paused
 lda #EV_TURN_CHANGED
 sta ev_type
 lda active_side
 sta ev_p0
 stz ev_p1
 stz ev_p2
 stz ev_p3
 stz ev_p4
 jmp event_push

*----------------------------------------------------------
* turn_move - The active side moves a unit (spec 15.3).
* In:  A = unit id, X = destination x, Y = destination y
* Out: carry set, A = TN_OK: moved; one move used, Shoot
*        Option 2 goes to its move phase, and if that was
*        the last move the turn ends by itself
*        (rule_auto_end_turn).
*      carry clear, A = TN_* or the MV_* reason.
* Clobbers X, Y, rt0-rt5, mv_*, ln_*, ev_*.
*----------------------------------------------------------
turn_move
 MX %11
 sta tn_unit
 stx tn_x
 sty tn_y
 lda game_result
 bne :over
 ldx tn_unit
 cpx #MAX_UNITS
 bcs :try                  ; let move_validate refuse it
 lda unit_side,x
 cmp active_side
 bne :not_yours
:try
 lda moves_used
 cmp opt_moves_per_turn
 bcs :no_moves
 lda tn_unit
 ldx tn_x
 ldy tn_y
 jsr move_execute
 bcc :refused
 inc moves_used
 lda opt_shoot_option
 cmp #SHOOT_FIRST
 bne :count
 lda #PHASE_MOVE
 sta turn_phase
:count
 lda rule_auto_end_turn
 beq :ok
 lda moves_used
 cmp opt_moves_per_turn
 bcc :ok
 jsr turn_end
:ok
 lda #TN_OK
 sec
 rts
:refused
 clc
 rts
:over
 lda #TN_GAME_OVER
 clc
 rts
:not_yours
 lda #TN_NOT_YOURS
 clc
 rts
:no_moves
 lda #TN_NO_MOVES
 clc
 rts

*----------------------------------------------------------
* turn_fire - The active side fires (spec 14, 15.2).
* In:  A = attacker id, X = target id
* Out: carry set, A = TN_OK: the shot was taken (see
*        fr_outcome); if it destroyed the enemy Battle
*        Cruiser the game is over (spec 17.1).
*      carry clear, A = TN_* or the FR_* reason.
* Firing uses no move (spec 15.3). Clobbers X, Y, rt0-rt3,
* fr_*, ln_*, ev_*.
*----------------------------------------------------------
turn_fire
 MX %11
 sta tn_unit
 stx tn_target
 lda game_result
 bne :over
 ldx tn_unit
 cpx #MAX_UNITS
 bcs :try
 lda unit_side,x
 cmp active_side
 bne :not_yours
:try
 lda turn_phase
 cmp #PHASE_MOVE
 beq :no_phase
 lda tn_unit
 ldx tn_target
 jsr fire_execute
 bcc :refused
 inc turn_shots
 lda fr_outcome
 cmp #FR_KILL
 bne :ok
 ldx fr_target
 lda unit_class,x
 cmp #CLASS_CRUISER
 bne :ok
 lda active_side
 inc                       ; RESULT_RED_WINS + side
 ldx #REASON_CRUISER
 jsr game_over
:ok
 lda #TN_OK
 sec
 rts
:refused
 clc
 rts
:over
 lda #TN_GAME_OVER
 clc
 rts
:not_yours
 lda #TN_NOT_YOURS
 clc
 rts
:no_phase
 lda #TN_NO_FIRE_PHASE
 clc
 rts

*----------------------------------------------------------
* turn_end - The active side's turn is over (spec 15.4):
* charge its clock, lose on time if it ran out, count an
* idle turn towards the stalemate (spec 17.4), hand play to
* the other side and begin its turn.
* Out: carry set, A = TN_OK: play goes on.
*      carry clear, A = TN_GAME_OVER: the game is over (now,
*        or already was).
* Clobbers A, X, Y, rt2, clk_*, ev_*.
*----------------------------------------------------------
turn_end
 MX %11
 lda game_result
 bne :over
 jsr get_tick
 jsr clock_charge
 lda active_side
 asl
 asl
 tax
 lda side_time,x
 ora side_time+1,x
 ora side_time+2,x
 ora side_time+3,x
 bne :in_time
 jsr time_loss
 bra :over
:in_time
 lda moves_used
 ora turn_shots
 bne :was_active
 inc inactive_turns
 lda inactive_turns
 cmp #STALEMATE_TURNS
 bcc :hand_over
 lda #RESULT_STALEMATE
 ldx #REASON_STALEMATE
 jsr game_over
 bra :over
:was_active
 stz inactive_turns
:hand_over
 lda active_side
 eor #1
 sta active_side
 jsr turn_begin
 lda #TN_OK
 sec
 rts
:over
 lda #TN_GAME_OVER
 clc
 rts

*----------------------------------------------------------
* clock_check - Has the active side run out of time (spec
* 16, 17.2)? For the game loop to call every frame.
* Out: A = game_result (RESULT_NONE while play goes on).
* Clobbers A, X, Y, clk_*, ev_*.
*----------------------------------------------------------
clock_check
 MX %11
 lda game_result
 bne :done
 ldx active_side
 jsr clock_remaining
 lda clk_out
 ora clk_out+1
 ora clk_out+2
 ora clk_out+3
 bne :running
 jsr time_loss
:running
 lda game_result
:done
 rts

* time_loss - the active side's clock ran out: the other
* side wins.
time_loss
 MX %11
 lda active_side
 eor #1
 inc                       ; RESULT_RED_WINS + other side
 ldx #REASON_TIME
 jmp game_over

*----------------------------------------------------------
* game_surrender - A side gives up (spec 17.3).
* In:  X = the side surrendering. Nothing happens if the
*      game is already over.
*----------------------------------------------------------
game_surrender
 MX %11
 lda game_result
 bne :done
 txa
 eor #1
 inc                       ; the other side wins
 ldx #REASON_SURRENDER
 jmp game_over
:done
 rts

*----------------------------------------------------------
* game_over - Record the result, freeze the clock where it
* stands, and queue EV_GAME_OVER (result, reason).
* In:  A = RESULT_*, X = REASON_*. Clobbers A, X, Y, clk_*,
*      ev_*.
*----------------------------------------------------------
game_over
 MX %11
 sta game_result
 stx result_reason
 jsr get_tick
 jsr clock_charge
 lda #1
 sta paused
 lda #EV_GAME_OVER
 sta ev_type
 lda game_result
 sta ev_p0
 lda result_reason
 sta ev_p1
 stz ev_p2
 stz ev_p3
 stz ev_p4
 jmp event_push

*----------------------------------------------------------
* turn_pause / turn_resume - The ESC pause (spec 16.5). On
* pause the ticks so far are charged and time stops
* accruing; on resume the turn's clock restarts from now.
*----------------------------------------------------------
turn_pause
 MX %11
 lda paused
 ora game_result
 bne :done
 jsr get_tick
 jsr clock_charge
 lda #1
 sta paused
:done
 rts

turn_resume
 MX %11
 lda paused
 beq :done
 lda game_result
 bne :done
 jsr get_tick
 jsr clock_restart
 stz paused
:done
 rts

*----------------------------------------------------------
* clock_remaining - A side's time left, live.
* In:  X = side
* Out: clk_out = ticks remaining (32-bit). For the active
*      side while play runs and is not paused, the ticks
*      since turn_start_tick are taken off; otherwise it is
*      the stored value.
* Clobbers A, X, Y, clk_*.
*----------------------------------------------------------
clock_remaining
 MX %11
 stx clk_side
 txa
 asl
 asl
 tax
 rep #$20
 MX %01
 lda side_time,x
 sta clk_out
 lda side_time+2,x
 sta clk_out+2
 sep #$20
 MX %11
 lda clk_side
 cmp active_side
 bne :done
 lda paused
 ora game_result
 bne :done
 jsr get_tick
 jsr clock_elapsed
 rep #$20
 MX %01
 sec
 lda clk_out
 sbc clk_elapsed
 sta clk_out
 lda clk_out+2
 sbc clk_elapsed+2
 sta clk_out+2
 bcs :floored
 stz clk_out
 stz clk_out+2
:floored
 sep #$20
 MX %11
:done
 rts

*----------------------------------------------------------
* ticks_to_mmss - clk_out (ticks) -> clk_min, clk_sec for
* the MM:SS display (spec 16, 25).
*----------------------------------------------------------
ticks_to_mmss
 MX %11
 rep #$20
 MX %01
 stz clk_min
 stz clk_sec
 lda clk_out
 sta clk_tmp
 lda clk_out+2
 sta clk_tmp+2
:minutes
 lda clk_tmp+2
 bne :take_minute
 lda clk_tmp
 cmp #TICKS_PER_MIN
 bcc :seconds
:take_minute
 sec
 lda clk_tmp
 sbc #TICKS_PER_MIN
 sta clk_tmp
 lda clk_tmp+2
 sbc #0
 sta clk_tmp+2
 inc clk_min
 bra :minutes
:seconds
 lda clk_tmp                ; below 3600 now
:take_second
 cmp #TICKS_PER_SEC
 bcc :done
 sbc #TICKS_PER_SEC         ; carry is set here
 inc clk_sec
 bra :take_second
:done
 sep #$20
 MX %11
 rts

*----------------------------------------------------------
* Clock internals. All expect get_tick to have filled
* now_tick first.
*----------------------------------------------------------

* clock_set - X = side: stored time = opt_time_minutes.
clock_set
 MX %11
 txa
 asl
 asl
 tax
 lda opt_time_minutes
 sta clk_tmp
 stz clk_tmp+1
 rep #$30
 MX %00
 stz side_time,x
 stz side_time+2,x
:add
 lda clk_tmp
 beq :done
 dec clk_tmp
 lda side_time,x
 clc
 adc #TICKS_PER_MIN
 sta side_time,x
 lda side_time+2,x
 adc #0
 sta side_time+2,x
 bra :add
:done
 sep #$30
 MX %11
 rts

* clock_restart - the active turn's clock starts now.
clock_restart
 MX %11
 rep #$20
 MX %01
 lda now_tick
 sta turn_start_tick
 lda now_tick+2
 sta turn_start_tick+2
 sep #$20
 MX %11
 rts

* clock_elapsed - clk_elapsed = now_tick - turn_start_tick.
clock_elapsed
 MX %11
 rep #$20
 MX %01
 sec
 lda now_tick
 sbc turn_start_tick
 sta clk_elapsed
 lda now_tick+2
 sbc turn_start_tick+2
 sta clk_elapsed+2
 sep #$20
 MX %11
 rts

* clock_charge - take the ticks since turn_start_tick off
* the active side's stored time (floored at 0) and restart
* the turn clock from now. Nothing while paused.
clock_charge
 MX %11
 lda paused
 bne :done
 jsr clock_elapsed
 lda active_side
 asl
 asl
 tax
 rep #$20
 MX %01
 sec
 lda side_time,x
 sbc clk_elapsed
 sta side_time,x
 lda side_time+2,x
 sbc clk_elapsed+2
 sta side_time+2,x
 bcs :charged
 stz side_time,x
 stz side_time+2,x
:charged
 sep #$20
 MX %11
 jsr clock_restart
:done
 rts

* get_tick - now_tick = the current tick count, through
* tick_vec so tests can inject one.
get_tick jmp (tick_vec)

* sys_tick - the Misc Tools tick counter (_GetTick), 60 Hz
* since power-on. The authoritative game timer (spec 16.1).
sys_tick
 MX %11
 rep #$30
 MX %00
 pha
 pha
 ldx #$2503
 jsl TOOLBOX               ; _GetTick
 pla
 sta now_tick
 pla
 sta now_tick+2
 sep #$30
 MX %11
 rts

tick_vec da sys_tick

* Turn state. Part of the game state (spec 30); a save game
* stores all of it, with the clocks charged first.
active_side     ds 1
moves_used      ds 1
turn_phase      ds 1
turn_shots      ds 1       ; shots this turn, for the stalemate rule
inactive_turns  ds 1
game_result     ds 1
result_reason   ds 1
paused          ds 1
side_time       ds 8       ; remaining ticks, 32-bit per side
turn_start_tick ds 4

now_tick        ds 4
clk_elapsed     ds 4
clk_out         ds 4
clk_tmp         ds 4
clk_min         ds 2
clk_sec         ds 2
clk_side        ds 1
tn_unit         ds 1
tn_x            ds 1
tn_y            ds 1
tn_target       ds 1
