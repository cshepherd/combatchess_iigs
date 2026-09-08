*----------------------------------------------------------
* line.s - Straight lines across the board: the shared core
* of movement paths (spec 8.3, 8.4) and line of sight
* (spec 24).
*
* PUT into any part that carries the rules engine, after
* board.s. Same convention: native mode, 8-bit A/X/Y,
* DBR $00, D $0000.
*
* Use: put the endpoints in ln_x0..ln_y1, call line_find to
* classify the line (direction, distance, orientation), then
* line_trace to walk it once, then move_path_clear or
* los_clear to read the verdict. Movement code takes the
* fuel and range from fuel_cost / move_range with ln_orient
* and ln_dist; fire code takes hit_chance the same way.
*----------------------------------------------------------

*----------------------------------------------------------
* line_find - Classify the line from (ln_x0,ln_y0) to
* (ln_x1,ln_y1).
* Out: carry set: a legal move or fire vector (spec 3.2,
*        24.1). ln_dir = DIR_*, ln_dist = squares (>= 1),
*        ln_orient = ORIENT_*. Distance is the larger of
*        |dx| and |dy| (spec 24.2).
*      carry clear: the same square, not on one row, column
*        or exact diagonal, or an endpoint off the board.
*        ln_dist = 0, ln_dir = $FF, ln_orient = 0.
* Clobbers A, X, Y, rt0-rt3.
*----------------------------------------------------------
line_find
 MX %11
 ldx ln_x0
 ldy ln_y0
 jsr cell_in_bounds
 bcc :fail
 ldx ln_x1
 ldy ln_y1
 jsr cell_in_bounds
 bcc :fail
 sec
 lda ln_x1
 sbc ln_x0
 jsr sign_abs
 sta rt0                   ; |dx|
 stx rt2                   ; sign of dx: 0 zero, 1 +, 2 -
 sec
 lda ln_y1
 sbc ln_y0
 jsr sign_abs
 sta rt1                   ; |dy|
 stx rt3                   ; sign of dy
 lda rt2
 asl
 clc
 adc rt2                   ; sx*3
 clc
 adc rt3                   ; + sy
 tax
 lda dir_from_signs,x
 bmi :fail                 ; both zero: same square
 sta ln_dir
 lda rt0
 beq :use_dy               ; vertical
 ldy rt1
 beq :use_dx               ; horizontal
 cmp rt1
 bne :fail                 ; diagonal needs |dx| = |dy|
:use_dx
 sta ln_dist
 bra :orient
:use_dy
 lda rt1
 sta ln_dist
:orient
 lda ln_dir
 and #1
 sta ln_orient
 sec
 rts
:fail
 stz ln_dist
 stz ln_orient
 lda #$FF
 sta ln_dir
 clc
 rts

* sign_abs - A = signed byte -> A = |A|, X = 0 for zero,
* 1 for positive, 2 for negative.
sign_abs
 MX %11
 ldx #0
 cmp #0
 beq :done
 bmi :neg
 ldx #1
 rts
:neg
 eor #$FF
 inc
 ldx #2
:done
 rts

* Direction from the signs of dx and dy, indexed by
* sign(dx)*3 + sign(dy) with 0 zero, 1 positive, 2 negative.
dir_from_signs
 dfb $FF,DIR_S,DIR_N
 dfb DIR_E,DIR_SE,DIR_NE
 dfb DIR_W,DIR_SW,DIR_NW

*----------------------------------------------------------
* line_trace - Walk the line found by line_find and gather
* what movement and fire need to know about it. Cells are
* numbered 1..N from the start; cell N is the far end.
* Out: ln_mid_flags = terrain flags ANDed over cells 1..N-1
*                     ($FF when there are none)
*      ln_mid_occ   = how many of those cells hold a unit
*      ln_end_flags = terrain flags of cell N
*      ln_end_occ   = occupant of cell N (OCC_NONE if empty)
*      ln_move_pen, ln_fuel_pen = terrain penalties summed
*                     over cells 1..N (spec 9.4)
* Requires a successful line_find. Clobbers A, X, Y,
* rt0-rt3.
*----------------------------------------------------------
line_trace
 MX %11
 lda #$FF
 sta ln_mid_flags
 stz ln_mid_occ
 stz ln_move_pen
 stz ln_fuel_pen
 lda ln_dist
 sta rt2                   ; cells left to visit
 ldx ln_x0
 ldy ln_y0
:next
 lda ln_dir
 jsr cell_step             ; on the board by construction
 jsr get_cell
 phx
 tax
 lda terrain_move_penalty,x
 clc
 adc ln_move_pen
 sta ln_move_pen
 lda terrain_fuel_penalty,x
 clc
 adc ln_fuel_pen
 sta ln_fuel_pen
 lda terrain_flags,x
 plx
 dec rt2
 beq :last
 and ln_mid_flags
 sta ln_mid_flags
 jsr get_occupant
 beq :next
 inc ln_mid_occ
 bra :next
:last
 sta ln_end_flags
 jsr get_occupant
 sta ln_end_occ
 rts

*----------------------------------------------------------
* move_path_clear - After line_trace: may a unit travel the
* line? Every cell entered must allow movement, the far end
* must be empty (spec 8.4), and while rule_units_block_move
* is set so must every cell passed through.
* Out: carry set = clear. Clobbers A.
* Range and fuel are the caller's checks.
*----------------------------------------------------------
move_path_clear
 MX %11
 lda ln_mid_flags
 and ln_end_flags
 and #TF_MOVE
 beq :blocked
 lda ln_end_occ
 bne :blocked
 lda rule_units_block_move
 beq :clear
 lda ln_mid_occ
 bne :blocked
:clear
 sec
 rts
:blocked
 clc
 rts

*----------------------------------------------------------
* los_clear - After line_trace: can a shot reach the far end
* of the line? Every cell between must pass fire (spec 24.3)
* and, while rule_units_block_los is set, hold no unit. The
* far cell itself is not tested: trees block fire through a
* square, not at a unit standing in it.
* Out: carry set = clear. Clobbers A.
* Range, ammo and turn rules are the caller's checks.
*----------------------------------------------------------
los_clear
 MX %11
 lda ln_mid_flags
 and #TF_FIRE
 beq :blocked
 lda rule_units_block_los
 beq :clear
 lda ln_mid_occ
 bne :blocked
:clear
 sec
 rts
:blocked
 clc
 rts

* Compatibility rules (spec 8.4, 24.4, 35). UNVERIFIED: the
* manual does not say whether a unit blocks movement through
* its square or blocks line of fire. Both default to the
* spec's conservative reading (they do) until the Atari
* executable is measured; Original Rules mode will then pin
* them and Enhanced mode may expose them.
rule_units_block_move dfb 1
rule_units_block_los  dfb 1

* Endpoints in, results out.
ln_x0        ds 1
ln_y0        ds 1
ln_x1        ds 1
ln_y1        ds 1
ln_dir       ds 1
ln_dist      ds 1
ln_orient    ds 1
ln_mid_flags ds 1
ln_mid_occ   ds 1
ln_end_flags ds 1
ln_end_occ   ds 1
ln_move_pen  ds 1
ln_fuel_pen  ds 1
