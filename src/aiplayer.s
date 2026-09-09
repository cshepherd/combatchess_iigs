*----------------------------------------------------------
* aiplayer.s - The computer player (spec sections 29.4, 36; the
* Atari's COMPUTER WILL PLAY option). A greedy one-ply
* player that sits on top of the rules engine and drives it
* through the same validated actions a human uses, so it can
* never make an illegal move (spec 36: "AI is logically
* separate from rules; the rules engine exposes legal
* actions and evaluates outcomes").
*
* PUT into any part that carries the rules engine, after
* turn.s. Native mode, 8-bit A/X/Y, DBR $00, D $0000, like
* the engine; the scoring drops to 16-bit A inside ai_mul
* and the score compares and switches back.
*
* ai_step performs ONE action for the side to move (a shot,
* a move, or ending the turn) and returns, so the caller
* redraws between actions and the play is watchable, and a
* move that ends the turn by itself (rule_auto_end_turn)
* hands play over cleanly before the next step.
*
* The heuristic (spec 36): shots are scored by expected
* damage (hit_chance x damage) plus the target's value and a
* bonus for a killing shot, with a destroyed enemy Battle
* Cruiser dominating everything (it wins the game); moves are
* scored by how much closer they bring a unit to the enemy
* cruiser. Under Shoot Option 2 all firing comes before the
* first move (the turn layer enforces the phase; the AI
* fires first to use it). This is a first-pass player, not
* the spec 36 minimax; it advances and shoots.
*----------------------------------------------------------
FIRE_MIN = 120             ; a shot must score at least this to be worth the ammo
CRU_KILL = 20000           ; added when a shot would destroy the enemy cruiser: dominates
KILL_BONUS = 1000          ; added when a shot would destroy any target
MOVE_W    = 10             ; move score per square nearer the enemy cruiser
MOVE_W_CRU = 3             ; the cruiser advances more cautiously

* Value of a target by class, weighting expected damage
* toward the pieces worth killing (the Atari's own weights).
ai_class_value dfb 12,4,1  ; cruiser, tank, car

*----------------------------------------------------------
* side_is_cpu - X = side (SIDE_RED/SIDE_BLACK).
* Out: A = 1 if the computer plays that side, else 0; Z set
* when 0. cpu_side is filled by setup_game from cfg_computer.
*----------------------------------------------------------
side_is_cpu
 MX %11
 lda cpu_side,x
 rts

*----------------------------------------------------------
* ai_step - One action for the active side (which the caller
* has checked is a computer side, the game not over or
* paused): the best worthwhile shot, else the best advancing
* move, else end the turn. Clobbers A, X, Y, rt0-rt7, and
* the mv_*/fr_*/ln_*/ev_* the actions use.
*----------------------------------------------------------
ai_step
 MX %11
 jsr ai_enemy_cruiser      ; ai_ecru_x/y; carry clear if it is gone
 bcc :endturn
 jsr ai_find_shot          ; ai_have_shot, ai_best_atk/tgt, ai_best_score
 jsr ai_find_move          ; ai_have_move, ai_best_mu/mx/my, ai_best_mscore
 lda turn_phase
 cmp #PHASE_MOVE
 beq :trymove              ; Shoot Option 2 after the first move: no firing
 lda ai_have_shot
 beq :trymove
 rep #$20
 MX %01
 lda ai_best_score
 cmp #FIRE_MIN
 sep #$20
 MX %11
 bcc :trymove              ; no shot worth the ammo
 lda turn_phase
 cmp #PHASE_FIRE
 beq :dofire               ; Shoot Option 2: spend the fire phase first
 rep #$20
 MX %01
 lda ai_best_score
 cmp ai_best_mscore
 sep #$20
 MX %11
 bcc :trymove              ; a move scores higher: move instead
:dofire
 lda ai_best_atk
 ldx ai_best_tgt
 jmp turn_fire
:trymove
 lda ai_have_move
 beq :endturn
 lda moves_used
 cmp opt_moves_per_turn
 bcs :endturn
 lda ai_best_mu
 ldx ai_best_mx
 ldy ai_best_my
 jmp turn_move
:endturn
 jmp turn_end

*----------------------------------------------------------
* ai_enemy_cruiser - Find the Battle Cruiser of the side NOT
* to move. Out: carry set, ai_ecru_x/y set; carry clear if
* there is none (the game is already over). Clobbers A, X.
*----------------------------------------------------------
ai_enemy_cruiser
 MX %11
 lda active_side
 eor #1
 tax
 lda side_first_id,x
 sta rt0                   ; scan id
 lda side_units,x
 sta rt1                   ; slots to scan
:scan
 lda rt1
 beq :none
 dec rt1
 ldx rt0
 inc rt0
 lda unit_flags,x
 bpl :scan
 lda unit_class,x
 cmp #CLASS_CRUISER
 bne :scan
 lda unit_x,x
 sta ai_ecru_x
 lda unit_y,x
 sta ai_ecru_y
 sec
 rts
:none
 clc
 rts

*----------------------------------------------------------
* ai_find_shot - The active side's best shot at an enemy.
* Sets ai_have_shot, ai_best_atk, ai_best_tgt, ai_best_score
* (16-bit). Clobbers A, X, Y, rt0-rt7, fr_*, ln_*, ai_*.
*----------------------------------------------------------
ai_find_shot
 MX %11
 stz ai_have_shot
 rep #$20
 MX %01
 stz ai_best_score
 sep #$20
 MX %11
 ldx active_side
 lda side_first_id,x
 sta ai_a
 lda side_units,x
 sta ai_acount
:aloop
 lda ai_acount
 bne :alive
 rts
:alive
 dec ai_acount
 ldx ai_a
 lda unit_flags,x
 bmi :hasunit
 jmp :anext
:hasunit
 lda unit_ammo,x
 bne :haveammo
 jmp :anext
:haveammo
 lda active_side
 eor #1
 tax
 lda side_first_id,x
 sta ai_tg
 lda side_units,x
 sta ai_tcount
:tloop
 lda ai_tcount
 bne :tgo
 jmp :anext
:tgo
 dec ai_tcount
 ldx ai_tg
 lda unit_flags,x
 bmi :tlive
 jmp :tnext
:tlive
 lda ai_a
 ldx ai_tg
 jsr fire_validate         ; carry set = legal; fr_chance, fr_damage
 bcs :tok
 jmp :tnext
:tok
 jsr ai_score_shot         ; -> ai_score (16-bit)
 jsr ai_shot_keep
:tnext
 inc ai_tg
 jmp :tloop
:anext
 inc ai_a
 jmp :aloop

* ai_score_shot - fr_chance, fr_damage and target ai_tg into
* ai_score (16-bit): expected damage, the target's value
* weighted by the odds, and a kill bonus, cruiser-dominant.
ai_score_shot
 MX %11
 lda fr_chance
 sta ai_m1
 lda fr_damage
 sta ai_m2
 jsr ai_mul                ; ai_prod = chance * damage
 rep #$20
 MX %01
 lda ai_prod
 sta ai_score
 sep #$20
 MX %11
 ldx ai_tg
 lda unit_class,x
 tax
 lda ai_class_value,x
 sta ai_m1
 lda fr_chance
 sta ai_m2
 jsr ai_mul                ; ai_prod = value * chance
 rep #$20
 MX %01
 lda ai_score
 clc
 adc ai_prod
 sta ai_score
 sep #$20
 MX %11
 ldx ai_tg
 lda fr_damage
 cmp unit_hp,x
 bcc :done                 ; the shot would not destroy it
 rep #$20
 MX %01
 lda ai_score
 clc
 adc #KILL_BONUS
 sta ai_score
 sep #$20
 MX %11
 lda unit_class,x
 cmp #CLASS_CRUISER
 bne :done
 rep #$20
 MX %01
 lda ai_score
 clc
 adc #CRU_KILL
 sta ai_score
 sep #$20
 MX %11
:done
 rts

* ai_shot_keep - keep ai_a -> ai_tg if ai_score beats the
* best so far.
ai_shot_keep
 MX %11
 rep #$20
 MX %01
 lda ai_score
 cmp ai_best_score
 sep #$20
 MX %11
 bcc :no                   ; not strictly greater
 beq :no
 rep #$20
 MX %01
 lda ai_score
 sta ai_best_score
 sep #$20
 MX %11
 lda ai_a
 sta ai_best_atk
 lda ai_tg
 sta ai_best_tgt
 lda #1
 sta ai_have_shot
:no
 rts

*----------------------------------------------------------
* ai_find_move - The active side's best advancing move.
* Sets ai_have_move, ai_best_mu/mx/my, ai_best_mscore.
* Clobbers A, X, Y, rt0-rt7, mv_*, ln_*, ai_*.
*----------------------------------------------------------
ai_find_move
 MX %11
 stz ai_have_move
 rep #$20
 MX %01
 stz ai_best_mscore
 sep #$20
 MX %11
 ldx active_side
 lda side_first_id,x
 sta ai_a
 lda side_units,x
 sta ai_acount
:uloop
 lda ai_acount
 bne :alive
 rts
:alive
 dec ai_acount
 ldx ai_a
 lda unit_flags,x
 bmi :ulive
 jmp :unext
:ulive
 lda unit_x,x
 sta ai_qx
 lda unit_y,x
 sta ai_qy
 jsr ai_dist_ecru          ; A = Chebyshev distance to the enemy cruiser
 sta ai_db
 ldx ai_a
 lda unit_class,x
 cmp #CLASS_CRUISER
 bne :weight
 lda #MOVE_W_CRU
 bra :setw
:weight
 lda #MOVE_W
:setw
 sta ai_w
 stz ai_dir
:dloop
 ldx ai_a
 lda unit_x,x
 sta ai_hx
 lda unit_y,x
 sta ai_hy
:sloop
 ldx ai_dir
 lda ai_hx
 clc
 adc dir_dx,x              ; dir_dx/dir_dy carry $FF for -1; the low byte wraps
 sta ai_hx
 cmp #BOARD_W
 bcc :inx
 jmp :dnext                ; off the board (a negative wrap is >= BOARD_W too)
:inx
 lda ai_hy
 clc
 adc dir_dy,x
 sta ai_hy
 cmp #BOARD_H
 bcc :iny
 jmp :dnext
:iny
 lda ai_a
 ldx ai_hx
 ldy ai_hy
 jsr move_validate
 bcs :moveok
 jmp :dnext                ; blocked or too far: nothing farther on this ray
:moveok
 lda ai_hx
 sta ai_qx
 lda ai_hy
 sta ai_qy
 jsr ai_dist_ecru
 sta ai_da
 lda ai_db
 sec
 sbc ai_da                 ; squares nearer (signed; <=0 means no closer)
 bmi :stepon               ; farther: keep stepping, a later square may be nearer
 beq :stepon
 sta ai_m1                 ; improvement
 lda ai_w
 sta ai_m2
 jsr ai_mul                ; ai_prod = improvement * weight
 jsr ai_move_keep
:stepon
 jmp :sloop
:dnext
 inc ai_dir
 lda ai_dir
 cmp #NUM_DIRS
 bcc :dcont
 jmp :unext
:dcont
 jmp :dloop
:unext
 inc ai_a
 jmp :uloop

* ai_move_keep - keep ai_a -> (ai_hx, ai_hy) if ai_prod
* beats the best move score so far.
ai_move_keep
 MX %11
 rep #$20
 MX %01
 lda ai_prod
 cmp ai_best_mscore
 sep #$20
 MX %11
 bcc :no
 beq :no
 rep #$20
 MX %01
 lda ai_prod
 sta ai_best_mscore
 sep #$20
 MX %11
 lda ai_a
 sta ai_best_mu
 lda ai_hx
 sta ai_best_mx
 lda ai_hy
 sta ai_best_my
 lda #1
 sta ai_have_move
:no
 rts

* ai_dist_ecru - Chebyshev distance from (ai_qx, ai_qy) to
* the enemy cruiser (ai_ecru_x/y). Out: A. Clobbers rt0.
ai_dist_ecru
 MX %11
 lda ai_qx
 sec
 sbc ai_ecru_x
 bcs :dx
 eor #$FF
 inc                       ; negate: |dx|
:dx
 sta rt0
 lda ai_qy
 sec
 sbc ai_ecru_y
 bcs :dy
 eor #$FF
 inc                       ; |dy|
:dy
 cmp rt0
 bcs :done                 ; A = |dy| >= |dx|
 lda rt0
:done
 rts

*----------------------------------------------------------
* ai_mul - ai_m1 (byte) x ai_m2 (byte) -> ai_prod (16-bit),
* shift-and-add. Enters and leaves in 8-bit A/X/Y.
*----------------------------------------------------------
ai_mul
 MX %11
 rep #$30
 MX %00
 lda ai_m1
 and #$00FF
 sta ai_t1
 lda ai_m2
 and #$00FF
 sta ai_t2
 stz ai_prod
:loop
 lda ai_t2
 beq :done
 lsr
 sta ai_t2
 bcc :noadd
 lda ai_prod
 clc
 adc ai_t1
 sta ai_prod
:noadd
 asl ai_t1
 bra :loop
:done
 sep #$30
 MX %11
 rts

*----------------------------------------------------------
* Variables. cpu_side is set by setup_game; the rest are the
* AI's own scratch, live only within one ai_step.
*----------------------------------------------------------
cpu_side       ds 2        ; per side: 1 = the computer plays it
ai_ecru_x      ds 1
ai_ecru_y      ds 1
ai_have_shot   ds 1
ai_best_atk    ds 1
ai_best_tgt    ds 1
ai_best_score  ds 2
ai_have_move   ds 1
ai_best_mu     ds 1
ai_best_mx     ds 1
ai_best_my     ds 1
ai_best_mscore ds 2
ai_a           ds 1
ai_acount      ds 1
ai_tg          ds 1
ai_tcount      ds 1
ai_score       ds 2
ai_dir         ds 1
ai_hx          ds 1
ai_hy          ds 1
ai_qx          ds 1
ai_qy          ds 1
ai_da          ds 1
ai_db          ds 1
ai_w           ds 1
ai_m1          ds 1
ai_m2          ds 1
ai_prod        ds 2
ai_t1          ds 2
ai_t2          ds 2
