*----------------------------------------------------------
* TEST - Combat Chess rules self-tests (spec section 33).
*
* SYS part at $2000. Reached from the title screen with T,
* or from a KEGS debugger session with "00/1004g" while the
* title is waiting for a key. Runs every check, shows a
* per-section tally on screen, and leaves the totals in
* test_pass / test_fail plus the id of the first failing
* check in test_first_fail so a debugger can read the result
* without the screen. Any key returns to the title.
*
* Checks are numbered from 1 in the order they run, so a
* failing id can be traced by counting through the sections
* below. Adding a section: a section_begin, the checks, then
* section_end with sec_name pointing at its label.
*----------------------------------------------------------

  ORG $2000
  MX %11

  put shared

  lda tb_inited
  bne :ready
  jsr toolbox_init
  inc tb_inited
:ready
  clc
  xce
  rep $30
  MX %00
  jsr shr_init

  lda #15
  ldx #0
  jsr set_colors
  lda #s_heading
  sta str_ptr
  ldx #8
  ldy #20
  jsr draw_cstr

  lda #36
  sta line_y
  lda #8
  sta col_x

  sep $30
  MX %11
  stz test_pass
  stz test_pass+1
  stz test_fail
  stz test_fail+1
  stz test_id
  stz test_id+1
  stz test_first_fail
  stz test_first_fail+1

  jsr section_begin
  jsr test_class_tables
  lda #<s_sec_class
  sta sec_name
  lda #>s_sec_class
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_fuel_table
  lda #<s_sec_fuel
  sta sec_name
  lda #>s_sec_fuel
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_move_bounds
  lda #<s_sec_range
  sta sec_name
  lda #>s_sec_range
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_hit_table
  lda #<s_sec_hit
  sta sec_name
  lda #>s_sec_hit
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_fire_bounds
  lda #<s_sec_fire
  sta sec_name
  lda #>s_sec_fire
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_rng
  lda #<s_sec_rng
  sta sec_name
  lda #>s_sec_rng
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_resolve
  lda #<s_sec_resolve
  sta sec_name
  lda #>s_sec_resolve
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_board
  lda #<s_sec_board
  sta sec_name
  lda #>s_sec_board
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_terrain
  lda #<s_sec_terrain
  sta sec_name
  lda #>s_sec_terrain
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_line_find
  lda #<s_sec_lfind
  sta sec_name
  lda #>s_sec_lfind
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_line_trace
  lda #<s_sec_ltrace
  sta sec_name
  lda #>s_sec_ltrace
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_units
  lda #<s_sec_units
  sta sec_name
  lda #>s_sec_units
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_events
  lda #<s_sec_events
  sta sec_name
  lda #>s_sec_events
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_move
  lda #<s_sec_move
  sta sec_name
  lda #>s_sec_move
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_fire
  lda #<s_sec_fire_act
  sta sec_name
  lda #>s_sec_fire_act
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_turn
  lda #<s_sec_turn
  sta sec_name
  lda #>s_sec_turn
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_fire_at
  lda #<s_sec_fire_at
  sta sec_name
  lda #>s_sec_fire_at
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_ai
  lda #<s_sec_ai
  sta sec_name
  lda #>s_sec_ai
  sta sec_name+1
  jsr section_end

  jsr section_begin
  jsr test_miss
  lda #<s_sec_miss
  sta sec_name
  lda #>s_sec_miss
  sta sec_name+1
  jsr section_end

* Grand total: a "section" that started from zero.
  stz sec_pass
  stz sec_pass+1
  stz sec_fail
  stz sec_fail+1
  lda #<s_sec_total
  sta sec_name
  lda #>s_sec_total
  sta sec_name+1
  jsr section_end

  rep $30
  MX %00
  lda test_fail
  beq :no_fail
  lda #num_buf
  sta str_ptr
  lda test_first_fail
  ldx #4
  jsr fmt_u16
  lda #7                    ; red
  ldx #0
  jsr set_colors
  lda #s_first_fail
  sta str_ptr
  ldx col_x
  ldy line_y
  jsr draw_cstr
  lda #num_buf
  sta str_ptr
  lda col_x
  clc
  adc #NUM_COL
  tax
  ldy line_y
  jsr draw_cstr
:no_fail
  lda #9
  ldx #0
  jsr set_colors
  lda #s_return
  sta str_ptr
  ldx #8
  ldy #194
  jsr draw_cstr

  jsr wait_key

  sec
  xce
  MX %11
  jmp LAUNCH_TITLE

*----------------------------------------------------------
* Section 1 - every entry of every class_* table matches the
* master unit table in spec 5.1. 27 checks.
*----------------------------------------------------------
test_class_tables
 MX %11
 ldx #0                    ; 4 bytes per case
:case
 lda prop_cases,x
 ora prop_cases+1,x
 beq :done
 lda prop_cases,x
 sta rptr
 lda prop_cases+1,x
 sta rptr+1
 lda prop_cases+2,x
 sta rptr2
 lda prop_cases+3,x
 sta rptr2+1
 ldy #0
:cls
 lda (rptr2),y
 sta expect                   ; expected
 lda (rptr),y              ; actual
 phx
 phy
 jsr check_eq
 ply
 plx
 iny
 cpy #NUM_CLASSES
 bne :cls
 inx
 inx
 inx
 inx
 bra :case
:done
 rts

* (table, expected) pairs, terminated by a zero word.
prop_cases
 da class_max_hp,exp_max_hp
 da class_terrain_hp,exp_terrain_hp
 da class_max_ammo,exp_max_ammo
 da class_max_fuel,exp_max_fuel
 da class_damage,exp_damage
 da class_fire_orth,exp_fire_orth
 da class_fire_diag,exp_fire_diag
 da class_move_orth,exp_move_orth
 da class_move_diag,exp_move_diag
 da 0

* Spec 5.1, cruiser / tank / car.
exp_max_hp      dfb 30,24,18
exp_terrain_hp  dfb 15,12,9
exp_max_ammo    dfb 16,16,8
exp_max_fuel    dfb 240,240,160
exp_damage      dfb 5,4,4
exp_fire_orth   dfb 11,7,4
exp_fire_diag   dfb 8,5,3
exp_move_orth   dfb 2,4,7
exp_move_diag   dfb 1,3,5

*----------------------------------------------------------
* Section 2 - fuel_cost returns every legal entry of the
* spec 9.3 fuel tables with carry set. 2 checks per case,
* 22 cases: 44 checks.
*----------------------------------------------------------
test_fuel_table
 MX %11
 ldx #0                    ; 4 bytes per case
:case
 lda fuel_cases,x
 cmp #$FF
 beq :done
 lda fuel_cases+3,x
 sta expect                   ; expected cost
 lda fuel_cases+1,x
 sta rt2                   ; orientation
 lda fuel_cases+2,x
 tay                       ; distance
 lda fuel_cases,x          ; class
 phx
 ldx rt2
 jsr fuel_cost
 php
 jsr check_eq              ; cost matches the spec table
 plp
 lda #0
 rol                       ; A = carry from fuel_cost
 ldy #1
 sty expect
 jsr check_eq              ; and it was reported legal
 plx
 inx
 inx
 inx
 inx
 bra :case
:done
 rts

* class, orientation, distance, expected cost (spec 9.3).
fuel_cases
 dfb CLASS_CRUISER,ORIENT_ORTH,1,12
 dfb CLASS_CRUISER,ORIENT_ORTH,2,27
 dfb CLASS_CRUISER,ORIENT_DIAG,1,16
 dfb CLASS_TANK,ORIENT_ORTH,1,4
 dfb CLASS_TANK,ORIENT_ORTH,2,10
 dfb CLASS_TANK,ORIENT_ORTH,3,18
 dfb CLASS_TANK,ORIENT_ORTH,4,28
 dfb CLASS_TANK,ORIENT_DIAG,1,5
 dfb CLASS_TANK,ORIENT_DIAG,2,17
 dfb CLASS_TANK,ORIENT_DIAG,3,33
 dfb CLASS_CAR,ORIENT_ORTH,1,1
 dfb CLASS_CAR,ORIENT_ORTH,2,3
 dfb CLASS_CAR,ORIENT_ORTH,3,6
 dfb CLASS_CAR,ORIENT_ORTH,4,10
 dfb CLASS_CAR,ORIENT_ORTH,5,15
 dfb CLASS_CAR,ORIENT_ORTH,6,21
 dfb CLASS_CAR,ORIENT_ORTH,7,28
 dfb CLASS_CAR,ORIENT_DIAG,1,1
 dfb CLASS_CAR,ORIENT_DIAG,2,5
 dfb CLASS_CAR,ORIENT_DIAG,3,11
 dfb CLASS_CAR,ORIENT_DIAG,4,19
 dfb CLASS_CAR,ORIENT_DIAG,5,28
 dfb $FF

*----------------------------------------------------------
* Section 3 - for every class, orientation and distance 0..8
* (one past the table), fuel_cost reports legal exactly when
* 1 <= distance <= move_range, and returns FUEL_NONE exactly
* when illegal. 2 checks x 3 x 2 x 9 = 108 checks.
*----------------------------------------------------------
test_move_bounds
 MX %11
 lda #<fuel_cost
 sta lookup_vec
 lda #>fuel_cost
 sta lookup_vec+1
 lda #<move_range
 sta range_vec
 lda #>move_range
 sta range_vec+1
 lda #MAX_MOVE_DIST+2
 sta t_max
 lda #FUEL_NONE
 sta t_illegal
 jmp sweep_bounds

*----------------------------------------------------------
* Section 4 - hit_chance returns every entry of the spec 11
* tables with carry set, fired by the Battle Cruiser, whose
* ranges span both rows. 2 checks per case, 19 cases:
* 38 checks.
*----------------------------------------------------------
test_hit_table
 MX %11
 ldx #0                    ; 3 bytes per case
:case
 lda hit_cases,x
 cmp #$FF
 beq :done
 lda hit_cases+2,x
 sta expect                   ; expected percent
 lda hit_cases+1,x
 tay                       ; range
 lda hit_cases,x
 phx
 tax                       ; orientation
 lda #CLASS_CRUISER
 jsr hit_chance
 php
 jsr check_eq              ; percent matches the spec table
 plp
 lda #0
 rol                       ; A = carry from hit_chance
 ldy #1
 sty expect
 jsr check_eq              ; and it was reported in range
 plx
 inx
 inx
 inx
 bra :case
:done
 rts

* orientation, range, expected percent (spec 11.1 / 11.2).
hit_cases
 dfb ORIENT_ORTH,1,100
 dfb ORIENT_ORTH,2,94
 dfb ORIENT_ORTH,3,88
 dfb ORIENT_ORTH,4,82
 dfb ORIENT_ORTH,5,76
 dfb ORIENT_ORTH,6,70
 dfb ORIENT_ORTH,7,64
 dfb ORIENT_ORTH,8,58
 dfb ORIENT_ORTH,9,52
 dfb ORIENT_ORTH,10,46
 dfb ORIENT_ORTH,11,40
 dfb ORIENT_DIAG,1,98
 dfb ORIENT_DIAG,2,89
 dfb ORIENT_DIAG,3,81
 dfb ORIENT_DIAG,4,72
 dfb ORIENT_DIAG,5,64
 dfb ORIENT_DIAG,6,56
 dfb ORIENT_DIAG,7,47
 dfb ORIENT_DIAG,8,39
 dfb $FF

*----------------------------------------------------------
* Section 5 - for every class, orientation and range 0..12
* (one past the table), hit_chance reports in range exactly
* when 1 <= range <= fire_range, and returns 0 exactly when
* out of range. 2 checks x 3 x 2 x 13 = 156 checks.
*----------------------------------------------------------
test_fire_bounds
 MX %11
 lda #<hit_chance
 sta lookup_vec
 lda #>hit_chance
 sta lookup_vec+1
 lda #<fire_range
 sta range_vec
 lda #>fire_range
 sta range_vec+1
 lda #MAX_FIRE_DIST+2
 sta t_max
 lda #0
 sta t_illegal
 jmp sweep_bounds

*----------------------------------------------------------
* sweep_bounds - Shared body of the bounds sections. For
* every class and orientation, and every distance from 0 up
* to t_max exclusive, calls the lookup and checks that
*   carry is set exactly when 1 <= distance <= range, and
*   A equals t_illegal exactly when carry is clear.
* In: lookup_vec -> routine (A=class, X=orient, Y=distance)
*                   returning A and carry like fuel_cost
*     range_vec  -> routine (A=class, X=orient) returning
*                   A = range, like move_range
*     t_max, t_illegal as above
*----------------------------------------------------------
sweep_bounds
 MX %11
 stz t_class
:class
 stz t_orient
:orient
 lda t_class
 ldx t_orient
 jsr call_range
 sta t_range
 stz t_dist
:dist
 lda t_class
 ldx t_orient
 ldy t_dist
 jsr call_lookup
 sta t_cost
 lda #0
 rol
 sta t_legal               ; 1 if the lookup said legal
* expected: legal iff 1 <= dist <= range
 lda #0
 ldy t_dist
 beq :expect
 cpy t_range
 beq :legal
 bcs :expect               ; dist > range
:legal
 lda #1
:expect
 sta expect
 lda t_legal
 jsr check_eq              ; carry agrees with the range table
 lda t_cost
 cmp t_illegal
 beq :none
 lda #1
 bra :value
:none
 lda #0
:value
 jsr check_eq              ; illegal marker exactly when illegal
 inc t_dist
 lda t_dist
 cmp t_max
 bne :dist
 inc t_orient
 lda t_orient
 cmp #2
 bne :orient
 inc t_class
 lda t_class
 cmp #NUM_CLASSES
 bne :class
 rts

call_lookup jmp (lookup_vec)
call_range  jmp (range_vec)

*----------------------------------------------------------
* Section 6 - the generator matches tools/rng_ref.py byte
* for byte: state after 1 and 3 steps from seed $12345678
* (8 checks), a zero seed is replaced (1), and the first
* eight rng_roll100 values (8). 17 checks. If the generator
* changes deliberately, regenerate these with rng_ref.py.
*----------------------------------------------------------
test_rng
 MX %11
 jsr seed_test_rng
 jsr rng_next
 ldx #0
:state1
 lda kat_state1,x
 sta expect
 lda rng_state,x
 jsr check_eq
 inx
 cpx #4
 bne :state1
 jsr rng_next
 jsr rng_next
 ldx #0
:state3
 lda kat_state3,x
 sta expect
 lda rng_state,x
 jsr check_eq
 inx
 cpx #4
 bne :state3
* A zero seed must not leave the state at zero.
 stz rt0
 stz rt1
 stz rt2
 stz rt3
 jsr rng_seed
 lda rng_state
 ora rng_state+1
 ora rng_state+2
 ora rng_state+3
 beq :zero
 lda #1
:zero
 ldx #1
 stx expect
 jsr check_eq
* First eight rolls.
 jsr seed_test_rng
 ldx #0
:roll
 jsr rng_roll100
 sta t_cost
 lda kat_rolls,x
 sta expect
 lda t_cost
 jsr check_eq
 inx
 cpx #8
 bne :roll
 rts

* Seed $12345678, the spec 33 example seed.
seed_test_rng
 lda #$78
 sta rt0
 lda #$56
 sta rt1
 lda #$34
 sta rt2
 lda #$12
 sta rt3
 jmp rng_seed

* From: python3 tools/rng_ref.py
kat_state1 dfb 165,90,152,135
kat_state3 dfb 196,244,32,72
kat_rolls  dfb 35,21,72,29,12,41,37,97

*----------------------------------------------------------
* Section 7 - resolve_hit with injected rolls: hit exactly
* when roll < percent, and the roll is reported back
* (8 cases x 2 = 16 checks). Then with the real generator:
* 100% hits, 0% misses (2), and 255 trials at 50% give the
* exact count rng_ref.py predicts (1). 19 checks.
*----------------------------------------------------------
test_resolve
 MX %11
 lda #<stub_roll
 sta roll_vec
 lda #>stub_roll
 sta roll_vec+1
 ldx #0                    ; 3 bytes per case
:case
 lda rh_cases,x
 cmp #$FF
 beq :done
 lda rh_cases+1,x
 sta stub_value
 lda rh_cases,x            ; percent
 phx
 jsr resolve_hit
 sta t_cost                ; roll reported
 lda #0
 rol
 sta t_legal               ; 1 = hit
 plx
 lda rh_cases+2,x
 sta expect
 lda t_legal
 jsr check_eq              ; hit or miss as expected
 lda rh_cases+1,x
 sta expect
 lda t_cost
 jsr check_eq              ; the injected roll came back
 inx
 inx
 inx
 bra :case
:done
 lda #<rng_roll100
 sta roll_vec
 lda #>rng_roll100
 sta roll_vec+1
 jsr seed_test_rng
 lda #100
 jsr resolve_hit
 lda #0
 rol
 ldx #1
 stx expect
 jsr check_eq              ; 100% always hits
 lda #0
 jsr resolve_hit
 lda #0
 rol
 stz expect
 jsr check_eq              ; 0% never hits
 jsr seed_test_rng
 stz t_cost                ; hit counter
 ldx #255
:trial
 lda #50
 jsr resolve_hit
 bcc :miss
 inc t_cost
:miss
 dex
 bne :trial
 lda #138                  ; from rng_ref.py --trials 255 --percent 50
 sta expect
 lda t_cost
 jsr check_eq
 rts

stub_roll
 lda stub_value
 rts
stub_value ds 1

*----------------------------------------------------------
* Section 8 - board geometry and cells: cell_index at the
* corners and an interior square (5), fill then set one cell
* leaves its neighbours alone (7), cell_in_bounds on and off
* the edges (6), cell_step in all eight directions from
* (5,5) and off three edges (27), board_load copies a full
* pattern (3), board_load_text decodes every map letter
* (11). 59 checks.
*----------------------------------------------------------
test_board
 MX %11
* cell_index
 ldx #0                    ; 3 bytes per case
:idx
 lda idx_cases+2,x
 sta expect
 phx
 ldy idx_cases+1,x
 lda idx_cases,x
 tax
 jsr cell_index
 plx
 jsr check_eq
 inx
 inx
 inx
 cpx #15
 bne :idx
* fill, set one cell, count and look around it
 lda #TERR_CLEAR
 jsr board_fill
 lda #TERR_TREE
 ldx #3
 ldy #2
 jsr set_cell
 lda #TERR_TREE
 jsr count_type
 ldx #1
 stx expect
 jsr check_eq              ; exactly one tree
 lda #TERR_CLEAR
 jsr count_type
 ldx #219
 stx expect
 jsr check_eq              ; everything else clear
 ldx #3
 ldy #2
 jsr get_cell
 ldx #TERR_TREE
 stx expect
 jsr check_eq              ; the tree is where it was put
 ldx #TERR_CLEAR
 stx expect
 ldx #2
 ldy #2
 jsr get_cell
 jsr check_eq              ; west neighbour
 ldx #4
 ldy #2
 jsr get_cell
 jsr check_eq              ; east
 ldx #3
 ldy #1
 jsr get_cell
 jsr check_eq              ; north
 ldx #3
 ldy #3
 jsr get_cell
 jsr check_eq              ; south
* cell_in_bounds
 ldx #0                    ; 3 bytes per case
:inb
 lda inb_cases+2,x
 sta expect
 phx
 ldy inb_cases+1,x
 lda inb_cases,x
 tax
 jsr cell_in_bounds
 lda #0
 rol
 plx
 jsr check_eq
 inx
 inx
 inx
 cpx #18
 bne :inb
* cell_step from (5,5) in every direction
 ldx #0
:step
 stx t_class               ; direction
 txa
 asl
 sta t_orient              ; case offset, 2 bytes per direction
 lda t_class
 ldx #5
 ldy #5
 jsr cell_step
 stx t_cost                ; new x
 sty t_dist                ; new y
 lda #0
 rol
 sta t_legal               ; 1 = still on the board
 ldx t_orient
 lda step_cases,x
 sta expect
 lda t_cost
 jsr check_eq
 lda step_cases+1,x
 sta expect
 lda t_dist
 jsr check_eq
 lda #1
 sta expect
 lda t_legal
 jsr check_eq
 ldx t_class
 inx
 cpx #NUM_DIRS
 bne :step
* and off the edges
 stz expect
 lda #DIR_NW
 ldx #0
 ldy #0
 jsr cell_step
 lda #0
 rol
 jsr check_eq              ; off the top-left corner
 lda #DIR_SE
 ldx #19
 ldy #10
 jsr cell_step
 lda #0
 rol
 jsr check_eq              ; off the bottom-right corner
 lda #DIR_W
 ldx #0
 ldy #5
 jsr cell_step
 lda #0
 rol
 jsr check_eq              ; off the left edge
* board_load: pattern cell i = i AND 7
 ldx #0
 lda #0
:mk
 sta test_src,x
 inc
 and #7
 inx
 cpx #BOARD_CELLS
 bne :mk
 lda #<test_src
 sta rptr
 lda #>test_src
 sta rptr+1
 jsr board_load
 stz t_cost
 ldx #0
:cmp
 lda board,x
 cmp test_src,x
 beq :same
 inc t_cost
:same
 inx
 cpx #BOARD_CELLS
 bne :cmp
 stz expect
 lda t_cost
 jsr check_eq              ; no cell differs
 ldx #19
 ldy #10
 jsr get_cell
 ldx #3                    ; 219 AND 7
 stx expect
 jsr check_eq
 ldx #0
 ldy #1
 jsr get_cell
 ldx #4                    ; 20 AND 7
 stx expect
 jsr check_eq
* board_load_text: the ten map letters across row 0, dots
* elsewhere; every type decodes and a dot is clear (11).
 lda #<text_map
 sta rptr
 lda #>text_map
 sta rptr+1
 jsr board_load_text
 ldx #0
:letter
 stx expect                ; letter n is type n
 ldy #0
 jsr get_cell
 jsr check_eq
 inx
 cpx #NUM_TERRAIN
 bcc :letter
 ldx #5
 ldy #6
 jsr get_cell
 stz expect
 jsr check_eq
 rts

text_map
 asc '.T~=Mwygpb..........'
 asc '....................'
 asc '....................'
 asc '....................'
 asc '....................'
 asc '....................'
 asc '....................'
 asc '....................'
 asc '....................'
 asc '....................'
 asc '....................'

* count_type - A = terrain type -> A = how many cells hold
* it. Clobbers X, rt2, rt3.
count_type
 MX %11
 sta rt2
 stz rt3
 ldx #0
:loop
 lda board,x
 cmp rt2
 bne :next
 inc rt3
:next
 inx
 cpx #BOARD_CELLS
 bne :loop
 lda rt3
 rts

* x, y, expected index
idx_cases
 dfb 0,0,0
 dfb 19,0,19
 dfb 0,10,200
 dfb 19,10,219
 dfb 7,4,87

* x, y, expected on-board flag
inb_cases
 dfb 0,0,1
 dfb 19,10,1
 dfb 20,0,0
 dfb 0,11,0
 dfb $FF,0,0
 dfb 0,$FF,0

* expected (x, y) after one step from (5,5), in DIR_* order
step_cases
 dfb 5,4
 dfb 6,4
 dfb 6,5
 dfb 6,6
 dfb 5,6
 dfb 4,6
 dfb 4,5
 dfb 4,4

test_src ds BOARD_CELLS

*----------------------------------------------------------
* Section 9 - terrain: every type's flags and after-
* destruction type match spec 18-21 (20), destroy_cell on
* each kind of cell changes exactly what it should and
* reports it (12), and touches no other cell (1). 33 checks.
*----------------------------------------------------------
test_terrain
 MX %11
 ldx #0                    ; 3 bytes per case
:type
 lda terr_cases+1,x
 sta expect
 lda terr_cases,x
 jsr cell_flags
 jsr check_eq              ; flags
 lda terr_cases+2,x
 sta expect
 phx
 lda terr_cases,x
 tax
 lda terrain_after,x
 plx
 jsr check_eq              ; what it becomes
 inx
 inx
 inx
 cpx #30
 bne :type
* destroy_cell at (1,1) on an otherwise clear board
 lda #TERR_CLEAR
 jsr board_fill
 ldx #0                    ; 3 bytes per case
:des
 lda des_cases,x
 phx
 ldx #1
 ldy #1
 jsr set_cell
 jsr destroy_cell
 lda #0
 rol
 sta t_legal               ; 1 = reported destroyed
 ldx #1
 ldy #1
 jsr get_cell
 sta t_cost                ; type afterwards
 plx
 lda des_cases+1,x
 sta expect
 lda t_legal
 jsr check_eq
 lda des_cases+2,x
 sta expect
 lda t_cost
 jsr check_eq
 inx
 inx
 inx
 cpx #18
 bne :des
 lda #TERR_CLEAR
 jsr count_type
 ldx #220
 stx expect
 jsr check_eq              ; the board is all clear again
 rts

* type, expected flags, expected type after destruction
* (spec 19-20 in prose; the values here are composed from
* that prose, not copied from terrain_flags)
terr_cases
 dfb TERR_CLEAR,TF_MOVE+TF_FIRE,TERR_CLEAR
 dfb TERR_TREE,TF_MOVE+TF_DESTRUCT+TF_SLOW,TERR_CLEAR
 dfb TERR_WATER,TF_FIRE,TERR_WATER
 dfb TERR_BRIDGE,TF_MOVE+TF_FIRE+TF_DESTRUCT,TERR_WATER
 dfb TERR_MOUNTAIN,0,TERR_MOUNTAIN
 dfb TERR_WHITE,TF_MOVE+TF_FIRE,TERR_WHITE
 dfb TERR_YELLOW,TF_MOVE+TF_FIRE,TERR_YELLOW
 dfb TERR_GREY,TF_DESTRUCT,TERR_WHITE
 dfb TERR_PURPLE,TF_FIRE,TERR_PURPLE
 dfb TERR_BLACK,0,TERR_BLACK

* type placed, expected destroyed flag, expected type after
des_cases
 dfb TERR_TREE,1,TERR_CLEAR
 dfb TERR_BRIDGE,1,TERR_WATER
 dfb TERR_GREY,1,TERR_WHITE
 dfb TERR_MOUNTAIN,0,TERR_MOUNTAIN
 dfb TERR_WATER,0,TERR_WATER
 dfb TERR_CLEAR,0,TERR_CLEAR

*----------------------------------------------------------
* Section 10 - line_find: every direction from (5,5), long
* lines from a corner, and the rejections (same square, not
* a line, off the board). 4 checks per case (found, dir,
* dist, orient), 15 cases: 60 checks.
*----------------------------------------------------------
test_line_find
 MX %11
 ldx #0                    ; 7 bytes per case
:case
 lda lf_cases,x
 cmp #$FF
 beq :done
 stx t_class
 sta ln_x0
 lda lf_cases+1,x
 sta ln_y0
 lda lf_cases+2,x
 sta ln_x1
 lda lf_cases+3,x
 sta ln_y1
 jsr line_find
 lda #0
 rol
 sta t_legal
 ldx t_class
 lda lf_cases+4,x
 sta expect
 lda t_legal
 jsr check_eq              ; found or rejected as expected
 lda lf_cases+5,x
 sta expect
 lda ln_dir
 jsr check_eq              ; direction
 lda lf_cases+6,x
 sta expect
 lda ln_dist
 jsr check_eq              ; distance
 lda lf_cases+4,x
 beq :no_orient
 lda lf_cases+5,x
 and #1
:no_orient
 sta expect
 lda ln_orient
 jsr check_eq              ; orientation is the direction's low bit
 txa
 clc
 adc #7
 tax
 bra :case
:done
 rts

* x0, y0, x1, y1, expected found, dir, dist ($FF/0 when not found)
lf_cases
 dfb 5,5,5,2,1,DIR_N,3
 dfb 5,5,9,1,1,DIR_NE,4
 dfb 5,5,12,5,1,DIR_E,7
 dfb 5,5,8,8,1,DIR_SE,3
 dfb 5,5,5,10,1,DIR_S,5
 dfb 5,5,0,10,1,DIR_SW,5
 dfb 5,5,0,5,1,DIR_W,5
 dfb 5,5,4,4,1,DIR_NW,1
 dfb 0,0,10,10,1,DIR_SE,10
 dfb 0,0,19,0,1,DIR_E,19
 dfb 5,5,5,5,0,$FF,0
 dfb 5,5,7,6,0,$FF,0
 dfb 0,0,19,10,0,$FF,0
 dfb 20,0,0,0,0,$FF,0
 dfb 0,0,0,11,0,$FF,0
 dfb $FF

*----------------------------------------------------------
* Section 11 - line_trace, move_path_clear and los_clear on
* a built board: trees, water, mountain, bridge, purple and
* two units. 5 checks per case (found, move, los, mid units,
* end unit), 12 cases: 60. Then, each re-tracing a case (1
* found check per trace): the two rule switches (2+3), tree
* penalties summed over the cells entered (2+3), and a one-
* step line has no middle (1+2). 73 checks.
*
* Board for the section (all else clear, no other units):
*   TREE (7,3)  WATER (10,3)  MOUNTAIN (13,3)
*   BRIDGE (4,6)  PURPLE (4,8)
*   unit 1 at (2,5)  unit 2 at (9,9)
*----------------------------------------------------------
test_line_trace
 MX %11
 lda #TERR_CLEAR
 jsr board_fill
 jsr occupant_clear
 lda #TERR_TREE
 ldx #7
 ldy #3
 jsr set_cell
 lda #TERR_WATER
 ldx #10
 ldy #3
 jsr set_cell
 lda #TERR_MOUNTAIN
 ldx #13
 ldy #3
 jsr set_cell
 lda #TERR_BRIDGE
 ldx #4
 ldy #6
 jsr set_cell
 lda #TERR_PURPLE
 ldx #4
 ldy #8
 jsr set_cell
 lda #1
 ldx #2
 ldy #5
 jsr set_occupant
 lda #2
 ldx #9
 ldy #9
 jsr set_occupant
 ldx #0                    ; 8 bytes per case
:case
 lda tr_cases,x
 cmp #$FF
 beq :done
 stx t_class
 jsr trace_case            ; loads endpoints, finds, traces
 ldx t_class
 lda tr_cases+4,x
 sta expect
 lda t_legal
 jsr check_eq              ; move_path_clear
 lda tr_cases+5,x
 sta expect
 lda t_cost
 jsr check_eq              ; los_clear
 lda tr_cases+6,x
 sta expect
 lda ln_mid_occ
 jsr check_eq
 lda tr_cases+7,x
 sta expect
 lda ln_end_occ
 jsr check_eq
 txa
 clc
 adc #8
 tax
 bra :case
:done
* Rule switches: the unit at (2,5) on the line (0,5)-(4,5)
* stops blocking when the rules say units do not block.
 stz rule_units_block_move
 stz rule_units_block_los
 ldx #56                   ; case H: (0,5)-(4,5)
 stx t_class
 jsr trace_case
 lda #1
 sta expect
 lda t_legal
 jsr check_eq              ; may pass through the unit
 lda t_cost
 jsr check_eq              ; may fire past the unit
 ldx #64                   ; case I: (5,5)-(2,5), unit at the far end
 stx t_class
 jsr trace_case
 stz expect
 lda t_legal
 jsr check_eq              ; still may not end on a unit
 lda #1
 sta rule_units_block_move
 sta rule_units_block_los
* Tree penalties add up over the cells entered, far end
* included. Set them for the test, then put the zeros back.
 lda #3
 sta terrain_fuel_penalty+TERR_TREE
 lda #1
 sta terrain_move_penalty+TERR_TREE
 ldx #0                    ; case A: (5,3)-(9,3), one tree between
 stx t_class
 jsr trace_case
 lda #3
 sta expect
 lda ln_fuel_pen
 jsr check_eq
 lda #1
 sta expect
 lda ln_move_pen
 jsr check_eq
 ldx #8                    ; case B: (5,3)-(7,3), tree at the far end
 stx t_class
 jsr trace_case
 lda #3
 sta expect
 lda ln_fuel_pen
 jsr check_eq
 stz terrain_fuel_penalty+TERR_TREE
 stz terrain_move_penalty+TERR_TREE
* A one-step line has no cells between.
 ldx #80                   ; case K2: (0,0)-(1,0)
 stx t_class
 jsr trace_case
 lda #$FF
 sta expect
 lda ln_mid_flags
 jsr check_eq
 lda #TF_MOVE+TF_FIRE
 sta expect
 lda ln_end_flags
 jsr check_eq
 rts

* trace_case - Load the endpoints of case t_class, find and
* trace the line (checking it was found), and leave the
* verdicts in t_legal (move) and t_cost (los).
trace_case
 MX %11
 ldx t_class
 lda tr_cases,x
 sta ln_x0
 lda tr_cases+1,x
 sta ln_y0
 lda tr_cases+2,x
 sta ln_x1
 lda tr_cases+3,x
 sta ln_y1
 jsr line_find
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq              ; the case is a line
 jsr line_trace
 jsr move_path_clear
 lda #0
 rol
 sta t_legal
 jsr los_clear
 lda #0
 rol
 sta t_cost
 rts

* x0, y0, x1, y1, expected move clear, los clear, units
* between, unit at the far end
tr_cases
 dfb 5,3,9,3,1,0,0,0       ; A: through a tree: move yes, fire no
 dfb 5,3,7,3,1,1,0,0       ; B: onto a tree: both fine
 dfb 8,3,12,3,0,1,0,0      ; C: across water: fire only
 dfb 8,3,10,3,0,1,0,0      ; D: onto water: fire only
 dfb 11,3,15,3,0,0,0,0     ; E: through a mountain: neither
 dfb 4,4,4,7,1,1,0,0       ; F: over a bridge: both
 dfb 4,7,4,9,0,1,0,0       ; G: through purple: fire only
 dfb 0,5,4,5,0,0,1,0       ; H: through a unit: neither (rules on)
 dfb 5,5,2,5,0,1,0,1       ; I: onto a unit: no move, fire fine
 dfb 9,5,9,10,0,0,1,0      ; J: through a unit, southward
 dfb 0,0,1,0,1,1,0,0       ; K2: one step, nothing between
 dfb 0,0,3,3,1,1,0,0       ; K: clear diagonal: both
 dfb $FF

*----------------------------------------------------------
* Section 12 - the unit list: an empty list (2); a red
* cruiser added at full strength with every field right (14)
* and placement refused on an occupied square, off the board
* and on water (4); a tank, a car and the black cruiser with
* their class values (27); army limits: one cruiser, three
* red tanks and cars, five black, each add checked (35);
* get_unit_at (5); unit_set_pos and unit_kill keep the
* occupant map right (9); fired-at masks across both bytes
* and both sides, and units_begin_turn clearing only its own
* side (9); moved flag and shot count reset (3). 108 checks.
*----------------------------------------------------------
test_units
 MX %11
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 stz expect
 ldx #SIDE_RED
 jsr unit_count_alive
 jsr check_eq              ; nobody home
 ldx #SIDE_BLACK
 jsr unit_count_alive
 jsr check_eq
* red cruiser at (1,1)
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CRUISER
 ldx #1
 ldy #1
 jsr add_unit              ; expects id 0
 stz expect
 jsr check_eq
 stz t_class               ; id 0
 lda #<flds_red_cruiser
 sta rptr2
 lda #>flds_red_cruiser
 sta rptr2+1
 jsr check_fields
* placement refused: occupied, off board, water
 lda #CLASS_TANK
 ldx #1
 ldy #1
 jsr add_unit_fail
 lda #CLASS_TANK
 ldx #20
 ldy #0
 jsr add_unit_fail
 lda #TERR_WATER
 ldx #5
 ldy #5
 jsr set_cell
 lda #CLASS_TANK
 ldx #5
 ldy #5
 jsr add_unit_fail
 lda #1
 sta expect
 ldx #SIDE_RED
 jsr unit_count_alive
 jsr check_eq              ; still just the cruiser
* red tank (2,1) id 1, red car (3,1) id 2
 lda #CLASS_TANK
 ldx #2
 ldy #1
 jsr add_unit
 lda #1
 sta expect
 jsr check_eq
 lda #1
 sta t_class
 lda #<flds_red_tank
 sta rptr2
 lda #>flds_red_tank
 sta rptr2+1
 jsr check_fields
 lda #CLASS_CAR
 ldx #3
 ldy #1
 jsr add_unit
 lda #2
 sta expect
 jsr check_eq
 lda #2
 sta t_class
 lda #<flds_red_car
 sta rptr2
 lda #>flds_red_car
 sta rptr2+1
 jsr check_fields
* black cruiser (18,9) id 11
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_CRUISER
 ldx #18
 ldy #9
 jsr add_unit
 lda #11
 sta expect
 jsr check_eq
 lda #11
 sta t_class
 lda #<flds_black_cruiser
 sta rptr2
 lda #>flds_black_cruiser
 sta rptr2+1
 jsr check_fields
 lda #12
 sta expect
 ldx #18
 ldy #9
 jsr get_occupant
 jsr check_eq              ; occupant is id + 1
* army limits, red: a second cruiser, then tanks and cars to
* three each
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CRUISER
 ldx #4
 ldy #1
 jsr add_unit_fail
 lda #CLASS_TANK
 ldx #5
 ldy #1
 jsr add_unit
 lda #3
 sta expect
 jsr check_eq
 lda #CLASS_TANK
 ldx #6
 ldy #1
 jsr add_unit
 lda #4
 sta expect
 jsr check_eq
 lda #CLASS_TANK
 ldx #7
 ldy #1
 jsr add_unit_fail         ; fourth red tank
 lda #CLASS_CAR
 ldx #8
 ldy #1
 jsr add_unit
 lda #5
 sta expect
 jsr check_eq
 lda #CLASS_CAR
 ldx #9
 ldy #1
 jsr add_unit
 lda #6
 sta expect
 jsr check_eq
 lda #CLASS_CAR
 ldx #10
 ldy #1
 jsr add_unit_fail         ; fourth red car
 lda #7
 sta expect
 ldx #SIDE_RED
 jsr unit_count_alive
 jsr check_eq
* army limits, black: five tanks along row 9, five cars
* along row 8, a sixth of each refused
 lda #SIDE_BLACK
 sta un_side
 ldx #1
:btank
 stx t_dist
 lda #CLASS_TANK
 ldy #9
 jsr add_unit
 lda t_dist                ; x, so ids 12..16
 clc
 adc #11
 sta expect
 jsr check_eq
 ldx t_dist
 inx
 cpx #6
 bne :btank
 lda #CLASS_TANK
 ldx #6
 ldy #9
 jsr add_unit_fail
 ldx #1
:bcar
 stx t_dist
 lda #CLASS_CAR
 ldy #8
 jsr add_unit
 lda t_dist                ; x, so ids 17..21
 clc
 adc #16
 sta expect
 jsr check_eq
 ldx t_dist
 inx
 cpx #6
 bne :bcar
 lda #CLASS_CAR
 ldx #6
 ldy #8
 jsr add_unit_fail
 lda #11
 sta expect
 ldx #SIDE_BLACK
 jsr unit_count_alive
 jsr check_eq
* get_unit_at
 ldx #1
 ldy #1
 jsr get_unit_at
 sta t_cost
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq              ; found
 stz expect
 lda t_cost
 jsr check_eq              ; the red cruiser
 ldx #18
 ldy #9
 jsr get_unit_at
 ldy #11
 sty expect
 jsr check_eq              ; the black cruiser
 ldx #0
 ldy #0
 jsr get_unit_at
 sta t_cost
 lda #0
 rol
 stz expect
 jsr check_eq              ; nothing there
 lda #NO_UNIT
 sta expect
 lda t_cost
 jsr check_eq
* unit_set_pos: red cruiser (1,1) -> (4,4)
 lda #0
 ldx #4
 ldy #4
 jsr unit_set_pos
 stz expect
 ldx #1
 ldy #1
 jsr get_occupant
 jsr check_eq              ; old square empty
 lda #1
 sta expect
 ldx #4
 ldy #4
 jsr get_occupant
 jsr check_eq              ; new square holds id 0
 lda #4
 sta expect
 lda unit_x
 jsr check_eq
 lda unit_y
 jsr check_eq
 stz expect
 ldx #4
 ldy #4
 jsr get_unit_at
 jsr check_eq
* unit_kill id 0
 lda #0
 jsr unit_kill
 stz expect
 lda unit_flags
 and #UF_ALIVE
 jsr check_eq              ; dead
 ldx #4
 ldy #4
 jsr get_occupant
 jsr check_eq              ; square empty
 jsr get_unit_at
 lda #0
 rol
 jsr check_eq              ; nobody found there
 lda #6
 sta expect
 ldx #SIDE_RED
 jsr unit_count_alive
 jsr check_eq
* fired-at masks
 stz expect
 lda #1                    ; red tank
 ldx #11                   ; black cruiser, slot 0
 jsr unit_has_fired_at
 lda #0
 rol
 jsr check_eq              ; not yet
 lda #1
 ldx #11
 jsr unit_mark_fired_at
 lda #1
 ldx #11
 jsr unit_has_fired_at
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq              ; now yes
 stz expect
 lda #1
 ldx #12                   ; slot 1 untouched
 jsr unit_has_fired_at
 lda #0
 rol
 jsr check_eq
 lda #1
 ldx #21                   ; slot 10, high byte
 jsr unit_mark_fired_at
 lda #1
 ldx #21
 jsr unit_has_fired_at
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq
 lda #12                   ; black tank fires at red tank
 ldx #1
 jsr unit_mark_fired_at
 lda #12
 ldx #1
 jsr unit_has_fired_at
 lda #0
 rol
 jsr check_eq
* red's new turn clears red's masks only
 ldx #SIDE_RED
 jsr units_begin_turn
 stz expect
 lda #1
 ldx #11
 jsr unit_has_fired_at
 lda #0
 rol
 jsr check_eq
 lda #1
 ldx #21
 jsr unit_has_fired_at
 lda #0
 rol
 jsr check_eq
 lda #1
 sta expect
 lda #12
 ldx #1
 jsr unit_has_fired_at
 lda #0
 rol
 jsr check_eq              ; black's mask survives
 ldx #SIDE_BLACK
 jsr units_begin_turn
 stz expect
 lda #12
 ldx #1
 jsr unit_has_fired_at
 lda #0
 rol
 jsr check_eq
* moved flag and shots reset with the turn, alive untouched
 lda unit_flags+1
 ora #UF_MOVED
 sta unit_flags+1
 lda #2
 sta unit_shots+1
 ldx #SIDE_RED
 jsr units_begin_turn
 stz expect
 lda unit_flags+1
 and #UF_MOVED
 jsr check_eq
 lda unit_shots+1
 jsr check_eq
 lda #UF_ALIVE
 sta expect
 lda unit_flags+1
 and #UF_ALIVE
 jsr check_eq
 rts

* add_unit - A = class, X = x, Y = y, un_side already set.
* Adds and checks that it succeeded; returns A = id.
add_unit
 MX %11
 sta un_class
 stx un_x
 sty un_y
 jsr unit_add
 sta t_cost
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq
 lda t_cost
 rts

* add_unit_fail - same inputs; checks that it was refused.
add_unit_fail
 MX %11
 sta un_class
 stx un_x
 sty un_y
 jsr unit_add
 lda #0
 rol
 stz expect
 jmp check_eq

* check_fields - For unit id t_class, compare each (array,
* expected) entry in the list at rptr2 (da array, dfb value;
* terminated by da 0).
check_fields
 MX %11
 ldy #0
:field
 lda (rptr2),y
 sta rptr
 iny
 lda (rptr2),y
 sta rptr+1
 iny
 lda rptr
 ora rptr+1
 beq :done
 lda (rptr2),y
 sta expect
 iny
 phy
 ldy t_class
 lda (rptr),y
 ply
 jsr check_eq
 bra :field
:done
 rts

flds_red_cruiser
 da unit_class
 dfb CLASS_CRUISER
 da unit_side
 dfb SIDE_RED
 da unit_x
 dfb 1
 da unit_y
 dfb 1
 da unit_hp
 dfb 30
 da unit_fuel
 dfb 240
 da unit_ammo
 dfb 16
 da unit_terr_hp
 dfb 15
 da unit_flags
 dfb UF_ALIVE
 da unit_fired_lo
 dfb 0
 da unit_fired_hi
 dfb 0
 da unit_shots
 dfb 0
 da 0

flds_red_tank
 da unit_class
 dfb CLASS_TANK
 da unit_side
 dfb SIDE_RED
 da unit_x
 dfb 2
 da unit_y
 dfb 1
 da unit_hp
 dfb 24
 da unit_fuel
 dfb 240
 da unit_ammo
 dfb 16
 da unit_terr_hp
 dfb 12
 da unit_flags
 dfb UF_ALIVE
 da 0

flds_red_car
 da unit_class
 dfb CLASS_CAR
 da unit_x
 dfb 3
 da unit_hp
 dfb 18
 da unit_fuel
 dfb 160
 da unit_ammo
 dfb 8
 da unit_terr_hp
 dfb 9
 da 0

flds_black_cruiser
 da unit_class
 dfb CLASS_CRUISER
 da unit_side
 dfb SIDE_BLACK
 da unit_x
 dfb 18
 da unit_y
 dfb 9
 da unit_hp
 dfb 30
 da 0

*----------------------------------------------------------
* Section 13 - the event queue: empty at first (1), two
* records queued (2) come back in order with every field
* (10), then empty again and reset (2), a full queue drops
* the extra push and drains completely (4). 19 checks.
*----------------------------------------------------------
test_events
 MX %11
 jsr events_clear
 jsr event_pop
 lda #0
 rol
 stz expect
 jsr check_eq              ; nothing queued
 ldy #0
:fill1
 tya
 clc
 adc #5                    ; type 5, params 6..10
 sta ev_rec,y
 iny
 cpy #EV_SIZE
 bne :fill1
 jsr event_push
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq              ; queued
 ldy #0
:fill2
 tya
 clc
 adc #20                   ; type 20, params 21..25
 sta ev_rec,y
 iny
 cpy #EV_SIZE
 bne :fill2
 jsr event_push
 lda #0
 rol
 jsr check_eq              ; queued
 jsr event_pop
 lda #0
 rol
 jsr check_eq              ; got one
 ldy #0
:rec1
 tya
 clc
 adc #5
 sta expect
 lda ev_rec,y
 phy
 jsr check_eq              ; each field of the first record
 ply
 iny
 cpy #EV_SIZE
 bne :rec1
 jsr event_pop
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq              ; got the second
 lda #20
 sta expect
 lda ev_type
 jsr check_eq
 lda #25
 sta expect
 lda ev_p4
 jsr check_eq
 jsr event_pop
 lda #0
 rol
 stz expect
 jsr check_eq              ; empty again
 lda ev_count
 jsr check_eq              ; and reset to the start
* fill it up
 stz t_cost
 ldx #0
:fillq
 stx t_dist
 lda #EV_UNIT_MOVED
 sta ev_type
 jsr event_push
 bcc :dropped
 inc t_cost
:dropped
 ldx t_dist
 inx
 cpx #EV_MAX
 bne :fillq
 lda #EV_MAX
 sta expect
 lda t_cost
 jsr check_eq              ; all EV_MAX pushes queued
 jsr event_push
 lda #0
 rol
 stz expect
 jsr check_eq              ; one more is dropped
 stz t_cost
:drain
 jsr event_pop
 bcc :drained
 inc t_cost
 bra :drain
:drained
 lda #EV_MAX
 sta expect
 lda t_cost
 jsr check_eq              ; and all EV_MAX come back
 stz expect
 lda ev_count
 jsr check_eq
 rts

*----------------------------------------------------------
* Section 14 - the movement action on a built board.
*
*   red cruiser (1,1) id 0, red tank (5,5) id 1,
*   red car (10,5) id 2, black cruiser (18,9) id 11,
*   black tank (5,3) id 12, added once the red tank has
*   moved north past that square
*   MOUNTAIN (3,1)  WATER (4,2)  TREE (8,1)
* Row 1 east of the tank stays clear for the tree and fuel
* cases; the water and mountain sit west and south-west.
*
* Placing the units (4, then 1 more, then 1); validation
* prices a legal move and changes nothing (6); execute moves
* the tank, charges fuel, resets terrain HP, flags it, fixes
* the occupant map and queues one event with the right
* fields (16); range beats path in the refusal order,
* diagonals, non-lines, off board (7); units in the way,
* with and without the rule (4); water and mountain (3);
* trees passable, then with penalties (5); fuel exactly
* enough, then none, and no event on refusal (10); a dead
* unit (1); the car's reach (7); the cruiser's (6); a black
* unit (2). 73 checks.
*----------------------------------------------------------
test_move
 MX %11
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #TERR_MOUNTAIN
 ldx #3
 ldy #1
 jsr set_cell
 lda #TERR_WATER
 ldx #4
 ldy #2
 jsr set_cell
 lda #TERR_TREE
 ldx #8
 ldy #1
 jsr set_cell
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CRUISER
 ldx #1
 ldy #1
 jsr add_unit              ; id 0
 lda #CLASS_TANK
 ldx #5
 ldy #5
 jsr add_unit              ; id 1
 lda #CLASS_CAR
 ldx #10
 ldy #5
 jsr add_unit              ; id 2
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_CRUISER
 ldx #18
 ldy #9
 jsr add_unit              ; id 11
* validate the tank north 4: legal, priced, nothing changed
 lda #MV_OK
 sta expect
 lda #1
 ldx #5
 ldy #1
 jsr mv_case
 lda #28
 sta expect
 lda mv_cost
 jsr check_eq
 lda #212
 sta expect
 lda mv_fuel_after
 jsr check_eq
 lda #5
 sta expect
 lda unit_x+1
 jsr check_eq
 lda unit_y+1
 jsr check_eq
 lda #240
 sta expect
 lda unit_fuel+1
 jsr check_eq
* execute it, with the tank's terrain HP worn down first
 lda #3
 sta unit_terr_hp+1
 lda #MV_OK
 sta expect
 lda #1
 ldx #5
 ldy #1
 jsr move_execute
 jsr check_eq
 lda #5
 sta expect
 lda unit_x+1
 jsr check_eq
 lda #1
 sta expect
 lda unit_y+1
 jsr check_eq
 lda #212
 sta expect
 lda unit_fuel+1
 jsr check_eq
 lda #12
 sta expect
 lda unit_terr_hp+1
 jsr check_eq              ; back to the class maximum
 lda #UF_MOVED
 sta expect
 lda unit_flags+1
 and #UF_MOVED
 jsr check_eq
 stz expect
 ldx #5
 ldy #5
 jsr get_occupant
 jsr check_eq              ; left the old square
 lda #2
 sta expect
 ldx #5
 ldy #1
 jsr get_occupant
 jsr check_eq              ; id 1 on the new one
 jsr event_pop
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq              ; one event
 lda #EV_UNIT_MOVED
 sta expect
 lda ev_type
 jsr check_eq
 lda #1
 sta expect
 lda ev_p0
 jsr check_eq              ; unit
 lda #5
 sta expect
 lda ev_p1
 jsr check_eq              ; from (5,5)
 lda ev_p2
 jsr check_eq
 lda ev_p3
 jsr check_eq              ; to (5,1)
 lda #1
 sta expect
 lda ev_p4
 jsr check_eq
 jsr event_pop
 lda #0
 rol
 stz expect
 jsr check_eq              ; and no more
* now the black tank, two squares south of the red tank
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_TANK
 ldx #5
 ldy #3
 jsr add_unit              ; id 12
* refusals: too far comes before the unit in the way
 lda #MV_TOO_FAR
 sta expect
 lda #1
 ldx #5
 ldy #6
 jsr mv_case               ; south 5
 lda #MV_OK
 sta expect
 lda #1
 ldx #8
 ldy #4
 jsr mv_case               ; diagonal 3
 lda #33
 sta expect
 lda mv_cost
 jsr check_eq
 lda #MV_TOO_FAR
 sta expect
 lda #1
 ldx #9
 ldy #5
 jsr mv_case               ; diagonal 4
 lda #MV_NOT_LINE
 sta expect
 lda #1
 ldx #7
 ldy #2
 jsr mv_case               ; knight's move
 lda #1
 ldx #5
 ldy #1
 jsr mv_case               ; same square
 lda #1
 ldx #5
 ldy #255
 jsr mv_case               ; off the board
* units in the way
 lda #MV_BLOCKED
 sta expect
 lda #1
 ldx #5
 ldy #3
 jsr mv_case               ; onto the black tank
 lda #1
 ldx #5
 ldy #4
 jsr mv_case               ; through it
 stz rule_units_block_move
 lda #MV_OK
 sta expect
 lda #1
 ldx #5
 ldy #4
 jsr mv_case               ; allowed when the rule is off
 lda #18
 sta expect
 lda mv_cost
 jsr check_eq
 lda #1
 sta rule_units_block_move
* water and mountain
 lda #MV_BLOCKED
 sta expect
 lda #1
 ldx #3
 ldy #3
 jsr mv_case               ; south-west 2, across the water at (4,2)
 lda #1
 ldx #4
 ldy #2
 jsr mv_case               ; into the water
 lda #1
 ldx #2
 ldy #1
 jsr mv_case               ; west 3, through the mountain at (3,1)
* trees: passable, then with the penalty tables set
 lda #MV_OK
 sta expect
 lda #1
 ldx #9
 ldy #1
 jsr mv_case               ; east 4 through the tree
 lda #28
 sta expect
 lda mv_cost
 jsr check_eq
 lda #5
 sta terrain_fuel_penalty+TERR_TREE
 lda #1
 sta terrain_move_penalty+TERR_TREE
 lda #MV_TOO_FAR
 sta expect
 lda #1
 ldx #9
 ldy #1
 jsr mv_case               ; allowance 4 - 1 < 4
 lda #MV_OK
 sta expect
 lda #1
 ldx #8
 ldy #1
 jsr mv_case               ; east 3 onto the tree
 lda #23
 sta expect
 lda mv_cost
 jsr check_eq              ; 18 + 5
 stz terrain_fuel_penalty+TERR_TREE
 stz terrain_move_penalty+TERR_TREE
* fuel
 lda #27
 sta unit_fuel+1
 lda #MV_NO_FUEL
 sta expect
 lda #1
 ldx #9
 ldy #1
 jsr mv_case               ; costs 28
 lda #MV_OK
 sta expect
 lda #1
 ldx #8
 ldy #1
 jsr mv_case               ; costs 18
 lda #18
 sta expect
 lda mv_cost
 jsr check_eq
 lda #28
 sta unit_fuel+1
 lda #MV_OK
 sta expect
 lda #1
 ldx #9
 ldy #1
 jsr move_execute          ; exactly enough
 jsr check_eq
 stz expect
 lda unit_fuel+1
 jsr check_eq              ; and now dry
 lda #9
 sta expect
 lda unit_x+1
 jsr check_eq
 jsr event_pop
 lda #EV_UNIT_MOVED
 sta expect
 lda ev_type
 jsr check_eq
 lda #MV_NO_FUEL
 sta expect
 lda #1
 ldx #9
 ldy #2
 jsr move_execute          ; one square costs 4
 jsr check_eq
 lda #9
 sta expect
 lda unit_x+1
 jsr check_eq              ; did not move
 jsr event_pop
 lda #0
 rol
 stz expect
 jsr check_eq              ; and queued nothing
* a dead unit cannot move
 lda #2
 jsr unit_kill
 lda #MV_NO_UNIT
 sta expect
 lda #2
 ldx #11
 ldy #5
 jsr mv_case
* the armored car's reach: a new one where the dead one stood
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CAR
 ldx #10
 ldy #5
 jsr add_unit              ; id 3
 lda #MV_OK
 sta expect
 lda #3
 ldx #17
 ldy #5
 jsr mv_case               ; east 7
 lda #28
 sta expect
 lda mv_cost
 jsr check_eq
 lda #MV_TOO_FAR
 sta expect
 lda #3
 ldx #18
 ldy #5
 jsr mv_case               ; east 8
 lda #MV_OK
 sta expect
 lda #3
 ldx #15
 ldy #10
 jsr mv_case               ; diagonal 5
 lda #28
 sta expect
 lda mv_cost
 jsr check_eq
 lda #MV_OK
 sta expect
 lda #3
 ldx #4
 ldy #5
 jsr mv_case               ; west 6
 lda #21
 sta expect
 lda mv_cost
 jsr check_eq
* the cruiser's
 lda #MV_OK
 sta expect
 lda #0
 ldx #1
 ldy #3
 jsr mv_case               ; south 2
 lda #27
 sta expect
 lda mv_cost
 jsr check_eq
 lda #MV_TOO_FAR
 sta expect
 lda #0
 ldx #1
 ldy #4
 jsr mv_case               ; south 3
 lda #MV_OK
 sta expect
 lda #0
 ldx #2
 ldy #2
 jsr mv_case               ; diagonal 1
 lda #16
 sta expect
 lda mv_cost
 jsr check_eq
 lda #MV_TOO_FAR
 sta expect
 lda #0
 ldx #3
 ldy #3
 jsr mv_case               ; diagonal 2
* a black unit
 lda #MV_OK
 sta expect
 lda #12
 ldx #5
 ldy #1
 jsr mv_case               ; north 2 into the square the red tank left
 lda #10
 sta expect
 lda mv_cost
 jsr check_eq
 rts

* mv_case - A = unit, X = x, Y = y, expect = the MV_* reason
* wanted. Validates and checks the reason; mv_* stay for
* further checks.
mv_case
 MX %11
 jsr move_validate
 jmp check_eq

*----------------------------------------------------------
* Section 15 - the fire action on a built board, rolls
* injected through roll_vec.
*
*   red cruiser (1,5) id 0, red tank (5,5) id 1,
*   red car (5,8) id 2, black cruiser (12,5) id 11,
*   black tank (5,1) id 12, black car (9,9) id 13
*   all clear; a tree and then water at (8,5) for one case
*
* Placing the units (6); legal shots priced for the tank in
* three directions (7); non-lines and the car's short reach
* (3); the cruiser's long shot blocked by its own tank, then
* allowed by the rule (4); friendly, self and nonsense
* targets (3); trees block, water does not (2); no ammo (1);
* the per-turn target rule and its reset (2); a hit with
* every side effect and event (26); the same target again
* (1); a miss (10); a bridge destroyed under a unit (21); a
* kill, then the dead can neither be shot nor shoot (21);
* damage floors at 0 (3); the cruiser's damage (2).
* 112 checks.
*----------------------------------------------------------
test_fire
 MX %11
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #<stub_roll
 sta roll_vec
 lda #>stub_roll
 sta roll_vec+1
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CRUISER
 ldx #1
 ldy #5
 jsr add_unit              ; id 0
 lda #CLASS_TANK
 ldx #5
 ldy #5
 jsr add_unit              ; id 1
 lda #CLASS_CAR
 ldx #5
 ldy #8
 jsr add_unit              ; id 2
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_CRUISER
 ldx #12
 ldy #5
 jsr add_unit              ; id 11
 lda #CLASS_TANK
 ldx #5
 ldy #1
 jsr add_unit              ; id 12
 lda #CLASS_CAR
 ldx #9
 ldy #9
 jsr add_unit              ; id 13
* legal shots for the tank
 lda #FR_OK
 sta expect
 lda #1
 ldx #11
 jsr fr_case               ; east 7: the tank's full reach
 lda #64
 sta expect
 lda fr_chance
 jsr check_eq
 lda #4
 sta expect
 lda fr_damage
 jsr check_eq
 lda #FR_OK
 sta expect
 lda #1
 ldx #12
 jsr fr_case               ; north 4
 lda #82
 sta expect
 lda fr_chance
 jsr check_eq
 lda #FR_OK
 sta expect
 lda #1
 ldx #13
 jsr fr_case               ; diagonal 4
 lda #72
 sta expect
 lda fr_chance
 jsr check_eq
* non-lines and the car's reach
 lda #FR_NOT_LINE
 sta expect
 lda #2
 ldx #13
 jsr fr_case
 lda #2
 ldx #11
 jsr fr_case
 lda #FR_OUT_OF_RANGE
 sta expect
 lda #2
 ldx #12
 jsr fr_case               ; north 7, the car reaches 4
* the cruiser's long shot: its own tank stands at (5,5)
 lda #FR_BLOCKED
 sta expect
 lda #0
 ldx #11
 jsr fr_case
 stz rule_units_block_los
 lda #FR_OK
 sta expect
 lda #0
 ldx #11
 jsr fr_case
 lda #40
 sta expect
 lda fr_chance
 jsr check_eq              ; orthogonal 11
 lda #5
 sta expect
 lda fr_damage
 jsr check_eq
 lda #1
 sta rule_units_block_los
* targets that are not enemies
 lda #FR_NO_TARGET
 sta expect
 lda #1
 ldx #2
 jsr fr_case               ; friendly
 lda #1
 ldx #1
 jsr fr_case               ; itself
 lda #1
 ldx #22
 jsr fr_case               ; no such unit
* terrain in the line of fire
 lda #TERR_TREE
 ldx #8
 ldy #5
 jsr set_cell
 lda #FR_BLOCKED
 sta expect
 lda #1
 ldx #11
 jsr fr_case
 lda #TERR_WATER
 ldx #8
 ldy #5
 jsr set_cell
 lda #FR_OK
 sta expect
 lda #1
 ldx #11
 jsr fr_case
 lda #TERR_CLEAR
 ldx #8
 ldy #5
 jsr set_cell
* ammunition
 stz unit_ammo+1
 lda #FR_NO_AMMO
 sta expect
 lda #1
 ldx #11
 jsr fr_case
 lda #16
 sta unit_ammo+1
* the per-turn target rule
 lda #1
 ldx #11
 jsr unit_mark_fired_at
 lda #FR_ALREADY
 sta expect
 lda #1
 ldx #11
 jsr fr_case
 ldx #SIDE_RED
 jsr units_begin_turn
 lda #FR_OK
 sta expect
 lda #1
 ldx #11
 jsr fr_case
* a hit: roll 63 against 64
 lda #63
 sta stub_value
 lda #FR_OK
 sta expect
 lda #1
 ldx #11
 jsr fire_execute
 jsr check_eq
 lda #FR_HIT
 sta expect
 lda fr_outcome
 jsr check_eq
 lda #63
 sta expect
 lda fr_roll
 jsr check_eq
 lda #15
 sta expect
 lda unit_ammo+1
 jsr check_eq
 lda #1
 sta expect
 lda unit_shots+1
 jsr check_eq
 lda #1
 ldx #11
 jsr unit_has_fired_at
 lda #0
 rol
 jsr check_eq              ; remembered
 lda #26
 sta expect
 lda unit_hp+11
 jsr check_eq              ; 30 - 4
 lda #11
 sta expect
 lda unit_terr_hp+11
 jsr check_eq              ; 15 - 4
 lda #EV_SHOT_FIRED
 jsr pop_type
 lda #1
 sta expect
 lda ev_p0
 jsr check_eq
 lda #11
 sta expect
 lda ev_p1
 jsr check_eq
 lda #EV_SHOT_HIT
 jsr pop_type
 lda #63
 sta expect
 lda ev_p2
 jsr check_eq
 lda #EV_UNIT_DAMAGED
 jsr pop_type
 lda #11
 sta expect
 lda ev_p0
 jsr check_eq
 lda #4
 sta expect
 lda ev_p1
 jsr check_eq
 lda #26
 sta expect
 lda ev_p2
 jsr check_eq
 lda #EV_TERRAIN_DAMAGED
 jsr pop_type
 lda #12
 sta expect
 lda ev_p0
 jsr check_eq
 lda #5
 sta expect
 lda ev_p1
 jsr check_eq
 lda #11
 sta expect
 lda ev_p2
 jsr check_eq
 jsr pop_none
* the same target again this turn
 lda #FR_ALREADY
 sta expect
 lda #1
 ldx #11
 jsr fr_case
* a miss: roll 64 against 64
 ldx #SIDE_RED
 jsr units_begin_turn
 lda #64
 sta stub_value
 lda #FR_OK
 sta expect
 lda #1
 ldx #11
 jsr fire_execute
 jsr check_eq
 lda #FR_MISS
 sta expect
 lda fr_outcome
 jsr check_eq
 lda #14
 sta expect
 lda unit_ammo+1
 jsr check_eq
 lda #26
 sta expect
 lda unit_hp+11
 jsr check_eq              ; untouched
 lda #EV_SHOT_FIRED
 jsr pop_type
 lda #EV_SHOT_MISSED
 jsr pop_type
 lda #64
 sta expect
 lda ev_p2
 jsr check_eq
 jsr pop_none
* a bridge destroyed under the black tank
 lda #TERR_BRIDGE
 ldx #5
 ldy #1
 jsr set_cell
 lda #4
 sta unit_terr_hp+12
 ldx #SIDE_RED
 jsr units_begin_turn
 stz stub_value
 lda #FR_OK
 sta expect
 lda #1
 ldx #12
 jsr fire_execute
 jsr check_eq
 lda #FR_HIT
 sta expect
 lda fr_outcome
 jsr check_eq
 lda #20
 sta expect
 lda unit_hp+12
 jsr check_eq
 stz expect
 lda unit_terr_hp+12
 jsr check_eq
 lda #TERR_WATER
 sta expect
 ldx #5
 ldy #1
 jsr get_cell
 jsr check_eq              ; the felled bridge is a water gap
 lda #UF_ALIVE
 sta expect
 lda unit_flags+12
 and #UF_ALIVE
 jsr check_eq              ; still there (UNVERIFIED)
 lda #EV_SHOT_FIRED
 jsr pop_type
 lda #EV_SHOT_HIT
 jsr pop_type
 lda #EV_UNIT_DAMAGED
 jsr pop_type
 lda #EV_TERRAIN_DAMAGED
 jsr pop_type
 lda #EV_TERRAIN_DESTROYED
 jsr pop_type
 lda #5
 sta expect
 lda ev_p0
 jsr check_eq
 lda #1
 sta expect
 lda ev_p1
 jsr check_eq
 lda #TERR_BRIDGE
 sta expect
 lda ev_p2
 jsr check_eq
 lda #TERR_WATER
 sta expect
 lda ev_p3
 jsr check_eq              ; destroyed to a water gap, not clear
 jsr pop_none
* a kill: the black car down to 4
 lda #4
 sta unit_hp+13
 ldx #SIDE_RED
 jsr units_begin_turn
 lda #FR_OK
 sta expect
 lda #1
 ldx #13
 jsr fire_execute
 jsr check_eq
 lda #FR_KILL
 sta expect
 lda fr_outcome
 jsr check_eq
 stz expect
 lda unit_hp+13
 jsr check_eq
 lda unit_flags+13
 and #UF_ALIVE
 jsr check_eq
 ldx #9
 ldy #9
 jsr get_occupant
 jsr check_eq              ; square emptied
 lda #EV_SHOT_FIRED
 jsr pop_type
 lda #EV_SHOT_HIT
 jsr pop_type
 lda #EV_UNIT_DAMAGED
 jsr pop_type
 lda #EV_TERRAIN_DAMAGED
 jsr pop_type
 lda #EV_UNIT_DESTROYED
 jsr pop_type
 lda #13
 sta expect
 lda ev_p0
 jsr check_eq
 lda #9
 sta expect
 lda ev_p1
 jsr check_eq
 lda ev_p2
 jsr check_eq
 jsr pop_none
 lda #FR_NO_TARGET
 sta expect
 lda #1
 ldx #13
 jsr fr_case               ; the dead cannot be shot
 lda #FR_NO_UNIT
 sta expect
 lda #13
 ldx #1
 jsr fr_case               ; nor shoot
* damage floors at zero
 lda #2
 sta unit_hp+11
 lda #1
 sta unit_terr_hp+11
 ldx #SIDE_RED
 jsr units_begin_turn
 lda #1
 ldx #11
 jsr fire_execute
 lda #FR_KILL
 sta expect
 lda fr_outcome
 jsr check_eq
 stz expect
 lda unit_hp+11
 jsr check_eq
 lda unit_terr_hp+11
 jsr check_eq
 jsr events_clear
* the cruiser hits for 5: north-east 4 at the black tank
 lda #0
 ldx #12
 jsr fire_execute
 lda #5
 sta expect
 lda fr_damage
 jsr check_eq
 lda #15
 sta expect
 lda unit_hp+12
 jsr check_eq              ; 20 - 5
 jsr events_clear
 lda #<rng_roll100
 sta roll_vec
 lda #>rng_roll100
 sta roll_vec+1
 rts

* fr_case - A = attacker, X = target, expect = the FR_*
* reason wanted. Validates and checks the reason; fr_* stay
* for further checks.
fr_case
 MX %11
 jsr fire_validate
 jmp check_eq

* pop_type - A = the event type wanted. Pops and checks that
* a record came (1) and its type (1); ev_p* stay for more.
pop_type
 MX %11
 sta t_max
 jsr event_pop
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq
 lda t_max
 sta expect
 lda ev_type
 jmp check_eq

* pop_none - checks that the queue is empty (1).
pop_none
 MX %11
 jsr event_pop
 lda #0
 rol
 stz expect
 jmp check_eq

*----------------------------------------------------------
* Section 16 - the turn system, ticks injected through
* tick_vec and rolls through roll_vec (always a hit).
*
*   red cruiser (1,5) id 0, red tank (5,5) id 1,
*   black cruiser (18,5) id 11, black tank (11,5) id 12
*   options: Red first, 2 moves, Shoot Option 1, 1 minute
*
* Placing the units (4); game_start sets everything and
* announces the turn (15); the wrong side is refused (2);
* a move, a refused move, a shot and a repeat shot with the
* bookkeeping (14); the last move ends the turn by itself
* with the clock charged (14); four idle turns are a
* stalemate and nothing works afterwards (20); Shoot Option
* 2 phases (6); time runs out (4); killing the cruiser wins
* (5); pause stops the clock (10); MM:SS (10); surrender
* (2). 106 checks.
*----------------------------------------------------------
test_turn
 MX %11
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #<stub_roll
 sta roll_vec
 lda #>stub_roll
 sta roll_vec+1
 stz stub_value
 lda #<stub_tick
 sta tick_vec
 lda #>stub_tick
 sta tick_vec+1
 stz stub_tick_value+2
 stz stub_tick_value+3
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CRUISER
 ldx #1
 ldy #5
 jsr add_unit              ; id 0
 lda #CLASS_TANK
 ldx #5
 ldy #5
 jsr add_unit              ; id 1
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_CRUISER
 ldx #18
 ldy #5
 jsr add_unit              ; id 11
 lda #CLASS_TANK
 ldx #11
 ldy #5
 jsr add_unit              ; id 12
 lda #SIDE_RED
 sta opt_first_side
 lda #2
 sta opt_moves_per_turn
 lda #SHOOT_ANY
 sta opt_shoot_option
 lda #1
 sta opt_time_minutes
 sta opt_time_minutes+1
* game_start at tick 1000
 lda #<1000
 ldx #>1000
 jsr tick_set
 jsr game_start
 stz expect
 lda active_side
 jsr check_eq              ; Red
 lda moves_used
 jsr check_eq
 lda turn_phase
 jsr check_eq              ; PHASE_FIRE_OR_MOVE
 lda game_result
 jsr check_eq
 lda #<3600
 sta rt4
 lda #>3600
 sta rt5
 ldx #SIDE_RED
 jsr check_time            ; a full minute each
 ldx #SIDE_BLACK
 jsr check_time
 lda #<1000
 sta rt4
 lda #>1000
 sta rt5
 lda #<turn_start_tick
 sta rptr
 lda #>turn_start_tick
 sta rptr+1
 jsr check_word
 lda #EV_TURN_CHANGED
 jsr pop_type
 stz expect
 lda ev_p0
 jsr check_eq
 jsr pop_none
* the wrong side
 lda #TN_NOT_YOURS
 sta expect
 lda #12
 ldx #11
 ldy #4
 jsr turn_move
 jsr check_eq
 lda #12
 ldx #1
 jsr turn_fire
 jsr check_eq
* the red tank steps west, then fires east 7 at the black tank
 lda #TN_OK
 sta expect
 lda #1
 ldx #4
 ldy #5
 jsr turn_move
 jsr check_eq
 lda #1
 sta expect
 lda moves_used
 jsr check_eq
 stz expect
 lda turn_phase
 jsr check_eq              ; option 1 never changes phase
 lda #EV_UNIT_MOVED
 jsr pop_type
 jsr pop_none
 lda #MV_NOT_LINE
 sta expect
 lda #1
 ldx #4
 ldy #255
 jsr turn_move
 jsr check_eq              ; the move's own reason comes through
 lda #1
 sta expect
 lda moves_used
 jsr check_eq              ; and cost nothing
 lda #TN_OK
 sta expect
 lda #1
 ldx #12
 jsr turn_fire
 jsr check_eq
 lda #1
 sta expect
 lda turn_shots
 jsr check_eq
 lda #20
 sta expect
 lda unit_hp+12
 jsr check_eq
 jsr drain_count
 lda #4
 sta expect
 lda t_cost
 jsr check_eq              ; fired, hit, unit damaged, terrain damaged
 lda #FR_ALREADY
 sta expect
 lda #1
 ldx #12
 jsr turn_fire
 jsr check_eq
* the second move is the last: the turn ends at tick 1600
 lda #<1600
 ldx #>1600
 jsr tick_set
 lda #TN_OK
 sta expect
 lda #1
 ldx #5
 ldy #5
 jsr turn_move
 jsr check_eq
 lda #SIDE_BLACK
 sta expect
 lda active_side
 jsr check_eq
 stz expect
 lda moves_used
 jsr check_eq
 lda inactive_turns
 jsr check_eq
 lda #<3000
 sta rt4
 lda #>3000
 sta rt5
 ldx #SIDE_RED
 jsr check_time            ; 600 ticks charged
 lda #<1600
 sta rt4
 lda #>1600
 sta rt5
 lda #<turn_start_tick
 sta rptr
 lda #>turn_start_tick
 sta rptr+1
 jsr check_word
 lda #EV_UNIT_MOVED
 jsr pop_type
 lda #EV_TURN_CHANGED
 jsr pop_type
 lda #SIDE_BLACK
 sta expect
 lda ev_p0
 jsr check_eq
 jsr pop_none
* four idle turns in a row: a stalemate
 lda #<2600
 ldx #>2600
 jsr tick_set
 jsr turn_end
 stz expect
 jsr check_eq              ; TN_OK
 lda #<2600
 sta rt4
 lda #>2600
 sta rt5
 ldx #SIDE_BLACK
 jsr check_time            ; 1000 ticks charged
 lda #1
 sta expect
 lda inactive_turns
 jsr check_eq
 stz expect
 lda active_side
 jsr check_eq              ; Red again
 jsr events_clear
 lda #<3000
 ldx #>3000
 jsr tick_set
 jsr turn_end
 stz expect
 jsr check_eq
 lda #2
 sta expect
 lda inactive_turns
 jsr check_eq
 lda #<2600
 sta rt4
 lda #>2600
 sta rt5
 ldx #SIDE_RED
 jsr check_time            ; 400 more off Red
 lda #<3100
 ldx #>3100
 jsr tick_set
 jsr turn_end
 lda #3
 sta expect
 lda inactive_turns
 jsr check_eq
 jsr events_clear
 lda #<3200
 ldx #>3200
 jsr tick_set
 jsr turn_end
 lda #TN_GAME_OVER
 sta expect
 jsr check_eq
 lda #RESULT_STALEMATE
 sta expect
 lda game_result
 jsr check_eq
 lda #REASON_STALEMATE
 sta expect
 lda result_reason
 jsr check_eq
 lda #EV_GAME_OVER
 jsr pop_type
 lda #RESULT_STALEMATE
 sta expect
 lda ev_p0
 jsr check_eq
 lda #REASON_STALEMATE
 sta expect
 lda ev_p1
 jsr check_eq
 jsr pop_none
 lda #TN_GAME_OVER
 sta expect
 lda #1
 ldx #5
 ldy #4
 jsr turn_move
 jsr check_eq
 lda #1
 ldx #12
 jsr turn_fire
 jsr check_eq
 jsr turn_end
 jsr check_eq
* Shoot Option 2: a shot, then a move closes the door
 lda #SHOOT_FIRST
 sta opt_shoot_option
 lda #3
 sta opt_moves_per_turn
 lda #<4000
 ldx #>4000
 jsr tick_set
 jsr game_start
 jsr events_clear
 lda #PHASE_FIRE
 sta expect
 lda turn_phase
 jsr check_eq
 lda #TN_OK
 sta expect
 lda #1
 ldx #12
 jsr turn_fire
 jsr check_eq              ; east 6, before moving
 lda #1
 ldx #5
 ldy #4
 jsr turn_move
 jsr check_eq
 lda #PHASE_MOVE
 sta expect
 lda turn_phase
 jsr check_eq
 lda #TN_NO_FIRE_PHASE
 sta expect
 lda #1
 ldx #12
 jsr turn_fire
 jsr check_eq
 jsr turn_end
 lda #SIDE_BLACK
 sta expect
 lda active_side
 jsr check_eq
 lda #PHASE_FIRE
 sta expect
 lda turn_phase
 jsr check_eq              ; Black starts in the fire phase
* Black's minute runs out
 lda #<7600
 ldx #>7600
 jsr tick_set
 jsr clock_check
 lda #RESULT_RED_WINS
 sta expect
 lda game_result
 jsr check_eq
 lda #REASON_TIME
 sta expect
 lda result_reason
 jsr check_eq
 ldx #SIDE_BLACK
 jsr clock_remaining
 stz rt4
 stz rt5
 lda #<clk_out
 sta rptr
 lda #>clk_out
 sta rptr+1
 jsr check_word            ; nothing left
* the cruiser falls: Black fires first at a 4-HP cruiser
 lda #SIDE_BLACK
 sta opt_first_side
 lda #<8000
 ldx #>8000
 jsr tick_set
 jsr game_start
 jsr events_clear
 lda #4
 sta unit_hp
 lda #12
 ldx #8
 ldy #5
 jsr unit_set_pos          ; west 7 to (1,5)
 lda #TN_OK
 sta expect
 lda #12
 ldx #0
 jsr turn_fire
 jsr check_eq
 lda #RESULT_BLACK_WINS
 sta expect
 lda game_result
 jsr check_eq
 lda #REASON_CRUISER
 sta expect
 lda result_reason
 jsr check_eq
 jsr drain_count
 lda #EV_GAME_OVER
 sta expect
 lda t_legal
 jsr check_eq              ; the last event
 lda #TN_GAME_OVER
 sta expect
 lda #12
 ldx #0
 jsr turn_fire
 jsr check_eq
* pause stops the clock
 lda #SIDE_RED
 sta opt_first_side
 lda #<100
 ldx #>100
 jsr tick_set
 jsr game_start
 jsr events_clear
 lda #<400
 ldx #>400
 jsr tick_set
 jsr turn_pause
 lda #<3300
 sta rt4
 lda #>3300
 sta rt5
 ldx #SIDE_RED
 jsr check_time            ; 300 charged
 lda #<900
 ldx #>900
 jsr tick_set
 ldx #SIDE_RED
 jsr clock_remaining
 lda #<clk_out
 sta rptr
 lda #>clk_out
 sta rptr+1
 jsr check_word            ; still 3300 while paused
 jsr turn_resume
 lda #<900
 sta rt4
 lda #>900
 sta rt5
 lda #<turn_start_tick
 sta rptr
 lda #>turn_start_tick
 sta rptr+1
 jsr check_word
 lda #<1000
 ldx #>1000
 jsr tick_set
 ldx #SIDE_RED
 jsr clock_remaining
 lda #<3200
 sta rt4
 lda #>3200
 sta rt5
 lda #<clk_out
 sta rptr
 lda #>clk_out
 sta rptr+1
 jsr check_word            ; running again
 ldx #SIDE_BLACK
 jsr clock_remaining
 lda #<3600
 sta rt4
 lda #>3600
 sta rt5
 jsr check_word            ; the idle side is untouched
* minutes and seconds
 ldx #0                    ; 5 bytes per case
:mmss
 lda mmss_cases,x
 sta clk_out
 lda mmss_cases+1,x
 sta clk_out+1
 lda mmss_cases+2,x
 sta clk_out+2
 stz clk_out+3
 stx t_class
 jsr ticks_to_mmss
 ldx t_class
 lda mmss_cases+3,x
 sta expect
 lda clk_min
 jsr check_eq
 lda mmss_cases+4,x
 sta expect
 lda clk_sec
 jsr check_eq
 txa
 clc
 adc #5
 tax
 cpx #25
 bne :mmss
* surrender
 ldx #SIDE_RED
 jsr game_surrender
 lda #RESULT_BLACK_WINS
 sta expect
 lda game_result
 jsr check_eq
 lda #REASON_SURRENDER
 sta expect
 lda result_reason
 jsr check_eq
 jsr events_clear
 lda #<sys_tick
 sta tick_vec
 lda #>sys_tick
 sta tick_vec+1
 lda #<rng_roll100
 sta roll_vec
 lda #>rng_roll100
 sta roll_vec+1
 rts

* ticks (3 bytes, little-endian), expected minutes, seconds
mmss_cases
 dfb $10,$0E,$00,1,0       ; 3600
 dfb $0F,$0E,$00,0,59      ; 3599
 dfb $E0,$A5,$01,30,0      ; 108000
 dfb $00,$00,$00,0,0
 dfb $3D,$00,$00,0,1       ; 61

* stub_tick - the injected tick source.
stub_tick
 MX %11
 ldx #3
:copy
 lda stub_tick_value,x
 sta now_tick,x
 dex
 bpl :copy
 rts
stub_tick_value ds 4

* tick_set - A = low byte, X = high byte of the next tick
* value (upper word stays 0).
tick_set
 MX %11
 sta stub_tick_value
 stx stub_tick_value+1
 rts

* check_time - X = side; rt4/rt5 = expected low word of its
* stored time. 2 checks.
check_time
 MX %11
 txa
 asl
 asl
 clc
 adc #<side_time
 sta rptr
 lda #>side_time
 adc #0
 sta rptr+1
 jmp check_word

* check_word - rptr -> a 16-bit value, rt4/rt5 = expected
* low/high byte. 2 checks.
check_word
 MX %11
 lda rt4
 sta expect
 ldy #0
 lda (rptr),y
 jsr check_eq
 lda rt5
 sta expect
 ldy #1
 lda (rptr),y
 jmp check_eq

* drain_count - pops every queued event; t_cost = how many,
* t_legal = the type of the last one.
drain_count
 MX %11
 stz t_cost
 stz t_legal
:pop
 jsr event_pop
 bcc :done
 inc t_cost
 lda ev_type
 sta t_legal
 bra :pop
:done
 rts

* percent, injected roll, expected (1 hit / 0 miss)
rh_cases
 dfb 100,99,1
 dfb 100,0,1
 dfb 0,0,0
 dfb 40,39,1
 dfb 40,40,0
 dfb 40,41,0
 dfb 98,97,1
 dfb 98,98,0
 dfb $FF

lookup_vec ds 2
range_vec  ds 2
t_class    ds 1
t_orient   ds 1
t_range    ds 1
t_dist     ds 1
t_cost     ds 1
t_legal    ds 1
t_max      ds 1
t_illegal  ds 1

*----------------------------------------------------------
* Section 17 - shots at squares (fire_validate_at,
* fire_execute_at, turn_fire_at): a red tank at (5,5) id 0
* and a black car at (5,2) id 11 on clear ground; a tree at
* (7,5), a bridge at (5,7), a mountain at (3,5), a tree off
* any line at (8,6), a tree far along the row at (19,5).
*
* Placing the units (2); the square with the enemy car
* resolves to the unit (3); a tree in range is a target with the tank's odds at distance
* 2 (5); clear ground and a mountain are not (2); off-line,
* out of range (2); a tree in the way blocks (2); a hit
* destroys the tree, costs a round, and queues FIRED, HIT
* and TERRAIN_DESTROYED with the square (21); another square
* is not refused as already shot at (1); a miss leaves the
* bridge (9); no ammo (1); through the turn layer: not the
* black car's turn, then the tank's shot counts and the
* a bridge: one hit a turn (spec 13 refuses a repeat), worn to
* a water gap over four turns (8). 56 checks.
*----------------------------------------------------------
test_fire_at
 MX %11
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #<stub_roll
 sta roll_vec
 lda #>stub_roll
 sta roll_vec+1
 lda #SIDE_RED
 sta un_side
 lda #CLASS_TANK
 ldx #5
 ldy #5
 jsr add_unit              ; id 0
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_CAR
 ldx #5
 ldy #2
 jsr add_unit              ; id 11
 lda #TERR_TREE
 ldx #7
 ldy #5
 jsr set_cell
 lda #TERR_BRIDGE
 ldx #5
 ldy #7
 jsr set_cell
 lda #TERR_MOUNTAIN
 ldx #3
 ldy #5
 jsr set_cell
 lda #TERR_TREE
 ldx #8
 ldy #6
 jsr set_cell
 lda #TERR_TREE
 ldx #19
 ldy #5
 jsr set_cell
* the enemy car's square is the car
 lda #FR_OK
 sta expect
 lda #0
 ldx #5
 ldy #2
 jsr fire_validate_at
 jsr check_eq
 lda #11
 sta expect
 lda fr_target
 jsr check_eq
 lda #CLASS_TANK
 ldx #ORIENT_ORTH
 ldy #3
 jsr hit_chance
 sta expect
 lda fr_chance
 jsr check_eq
* the tree at distance 2
 lda #FR_OK
 sta expect
 lda #0
 ldx #7
 ldy #5
 jsr fire_validate_at
 jsr check_eq
 lda #FR_SQUARE
 sta expect
 lda fr_target
 jsr check_eq
 lda #7
 sta expect
 lda fr_tx
 jsr check_eq
 lda #5
 sta expect
 lda fr_ty
 jsr check_eq
 lda #CLASS_TANK
 ldx #ORIENT_ORTH
 ldy #2
 jsr hit_chance
 sta expect
 lda fr_chance
 jsr check_eq
* clear ground and a mountain are not targets
 lda #FR_NO_TARGET
 sta expect
 lda #0
 ldx #5
 ldy #3
 jsr fire_validate_at
 jsr check_eq
 lda #0
 ldx #3
 ldy #5
 jsr fire_validate_at
 jsr check_eq
* off any line; out of range
 lda #FR_NOT_LINE
 sta expect
 lda #0
 ldx #8
 ldy #6
 jsr fire_validate_at
 jsr check_eq
 lda #FR_OUT_OF_RANGE
 sta expect
 lda #0
 ldx #19
 ldy #5
 jsr fire_validate_at
 jsr check_eq
* a tree in the way
 lda #TERR_TREE
 ldx #6
 ldy #5
 jsr set_cell
 lda #FR_BLOCKED
 sta expect
 lda #0
 ldx #7
 ldy #5
 jsr fire_validate_at
 jsr check_eq
 lda #TERR_CLEAR
 ldx #6
 ldy #5
 jsr set_cell
 lda #FR_OK
 sta expect
 lda #0
 ldx #7
 ldy #5
 jsr fire_validate_at
 jsr check_eq
* a hit destroys the tree
 lda #0
 sta stub_value
 lda #FR_OK
 sta expect
 lda #0
 ldx #7
 ldy #5
 jsr fire_execute_at
 jsr check_eq
 lda #FR_HIT
 sta expect
 lda fr_outcome
 jsr check_eq
 lda #0
 sta expect
 lda fr_roll
 jsr check_eq
 lda #TERR_CLEAR
 sta expect
 ldx #7
 ldy #5
 jsr get_cell
 jsr check_eq
 lda #15
 sta expect
 lda unit_ammo
 jsr check_eq
 lda #1
 sta expect
 lda unit_shots
 jsr check_eq
 lda #EV_SHOT_FIRED
 jsr pop_type
 lda #0
 sta expect
 lda ev_p0
 jsr check_eq
 lda #FR_SQUARE
 sta expect
 lda ev_p1
 jsr check_eq
 lda #7
 sta expect
 lda ev_p3
 jsr check_eq
 lda #5
 sta expect
 lda ev_p4
 jsr check_eq
 lda #EV_SHOT_HIT
 jsr pop_type
 lda #0
 sta expect
 lda ev_p2
 jsr check_eq
 lda #EV_TERRAIN_DESTROYED
 jsr pop_type
 lda #7
 sta expect
 lda ev_p0
 jsr check_eq
 lda #5
 sta expect
 lda ev_p1
 jsr check_eq
 lda #TERR_TREE
 sta expect
 lda ev_p2
 jsr check_eq
 lda #TERR_CLEAR
 sta expect
 lda ev_p3
 jsr check_eq
* another square is not "already"
 lda #FR_OK
 sta expect
 lda #0
 ldx #5
 ldy #7
 jsr fire_validate_at
 jsr check_eq
* a miss leaves the bridge
 lda #99
 sta stub_value
 lda #FR_OK
 sta expect
 lda #0
 ldx #5
 ldy #7
 jsr fire_execute_at
 jsr check_eq
 lda #FR_MISS
 sta expect
 lda fr_outcome
 jsr check_eq
 lda #TERR_BRIDGE
 sta expect
 ldx #5
 ldy #7
 jsr get_cell
 jsr check_eq
 lda #14
 sta expect
 lda unit_ammo
 jsr check_eq
 lda #EV_SHOT_FIRED
 jsr pop_type
 lda #EV_SHOT_MISSED
 jsr pop_type
 lda #99
 sta expect
 lda ev_p2
 jsr check_eq
* no ammo
 stz unit_ammo
 lda #FR_NO_AMMO
 sta expect
 lda #0
 ldx #5
 ldy #7
 jsr fire_validate_at
 jsr check_eq
 lda #14
 sta unit_ammo
* through the turn layer
 jsr game_start
 lda #TN_NOT_YOURS
 sta expect
 lda #11
 ldx #5
 ldy #5
 jsr turn_fire_at
 jsr check_eq
 lda #0
 sta stub_value
* one shot damages the 15-HP bridge (4) but does not fell it
 lda #TN_OK
 sta expect
 lda #0
 ldx #5
 ldy #7
 jsr turn_fire_at
 jsr check_eq
 lda #TERR_BRIDGE
 sta expect
 ldx #5
 ldy #7
 jsr get_cell
 jsr check_eq              ; still a bridge after one shot
* a second shot at the same square this turn is refused (spec 13)
 lda #FR_ALREADY
 sta expect
 lda #0
 ldx #5
 ldy #7
 jsr turn_fire_at
 jsr check_eq
 lda #TERR_BRIDGE
 sta expect
 ldx #5
 ldy #7
 jsr get_cell
 jsr check_eq              ; unchanged: the repeat did nothing
* three more shots, each a fresh turn, wear it down to a water gap
 ldx #SIDE_RED
 jsr units_begin_turn
 lda #0
 ldx #5
 ldy #7
 jsr turn_fire_at
 ldx #SIDE_RED
 jsr units_begin_turn
 lda #0
 ldx #5
 ldy #7
 jsr turn_fire_at
 ldx #SIDE_RED
 jsr units_begin_turn
 lda #0
 ldx #5
 ldy #7
 jsr turn_fire_at
 lda #TERR_WATER
 sta expect
 ldx #5
 ldy #7
 jsr get_cell
 jsr check_eq              ; four hits over four turns: felled to a water gap
 rts

*----------------------------------------------------------
* Section 18 - the computer player's decision core (ai.s):
* a red tank at (5,5) and a red car at (2,5) with the black
* cruiser, killable in one tank hit, at (6,5), Red to move.
* side_is_cpu reads cpu_side (2); ai_enemy_cruiser finds the
* black cruiser (3); ai_find_shot picks the tank's shot at it
* (3); ai_find_move advances the car, the only unit that can
* get nearer (2). 10 checks.
*----------------------------------------------------------
test_ai
 MX %11
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #SIDE_RED
 sta un_side
 lda #CLASS_TANK
 ldx #5
 ldy #5
 jsr add_unit              ; id 0
 lda #CLASS_CAR
 ldx #2
 ldy #5
 jsr add_unit              ; id 1
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_CRUISER
 ldx #6
 ldy #5
 jsr add_unit              ; id 11
 lda #3
 sta unit_hp+11            ; the tank's 4 damage destroys it
 lda #SIDE_RED
 sta active_side
* side_is_cpu
 lda #1
 sta cpu_side+SIDE_BLACK
 stz cpu_side+SIDE_RED
 lda #0
 sta expect
 ldx #SIDE_RED
 jsr side_is_cpu
 jsr check_eq
 lda #1
 sta expect
 ldx #SIDE_BLACK
 jsr side_is_cpu
 jsr check_eq
 stz cpu_side+SIDE_BLACK
* ai_enemy_cruiser
 jsr ai_enemy_cruiser
 lda #0
 rol
 ldy #1
 sty expect
 jsr check_eq              ; carry set: found
 lda #6
 sta expect
 lda ai_ecru_x
 jsr check_eq
 lda #5
 sta expect
 lda ai_ecru_y
 jsr check_eq
* ai_find_shot: the tank (id 0) at the cruiser (id 11)
 jsr ai_find_shot
 lda #1
 sta expect
 lda ai_have_shot
 jsr check_eq
 lda #0
 sta expect
 lda ai_best_atk
 jsr check_eq
 lda #11
 sta expect
 lda ai_best_tgt
 jsr check_eq
* ai_find_move: the car (id 1) is the only unit that can close in
 jsr ai_find_move
 lda #1
 sta expect
 lda ai_have_move
 jsr check_eq
 lda #1
 sta expect
 lda ai_best_mu
 jsr check_eq
 rts

*----------------------------------------------------------
* check_eq - One check: A must equal expect. Numbers the check,
* tallies it, and remembers the first failing id.
* 8-bit A/X/Y. Preserves X, Y and expect.
*----------------------------------------------------------
check_eq
 MX %11
 inc test_id
 bne :id_ok
 inc test_id+1
:id_ok
 cmp expect
 bne :fail
 inc test_pass
 bne :done
 inc test_pass+1
 rts
:fail
 inc test_fail
 bne :first
 inc test_fail+1
:first
 lda test_first_fail
 ora test_first_fail+1
 bne :done
 lda test_id
 sta test_first_fail
 lda test_id+1
 sta test_first_fail+1
:done
 rts

test_pass       ds 2
test_fail       ds 2
test_id         ds 2
test_first_fail ds 2
expect          ds 1     ; expected value for check_eq; engine code never touches it

*----------------------------------------------------------
* Section - a missed shot (miss_resolve, spec 12) still lands
* and explodes: it carries one square past the target and a
* tile up in y, and strikes whatever sits there. An enemy
* unit takes the shot's damage, a friendly or open ground is
* spared, felling the enemy Battle Cruiser counts as a kill,
* and the landing square is clamped to the board.
* miss_setup lays a clear board with a RED cruiser at (5,5)
* firing a doomed-to-miss shot at a BLACK tank at (8,5); the
* stray then lands on (9,5+dy-1) = (9,4).
*----------------------------------------------------------
miss_setup
 MX %11
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #<stub_roll
 sta roll_vec
 lda #>stub_roll
 sta roll_vec+1
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CRUISER
 ldx #5
 ldy #5
 jsr add_unit             ; id 0, the shooter
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_TANK
 ldx #8
 ldy #5
 jsr add_unit             ; id 11, the intended target
 ldx #SIDE_RED
 jmp units_begin_turn     ; ready RED to fire; rts through here

test_miss
 MX %11
* --- an enemy on the landing square takes the stray ---
 jsr miss_setup
 lda #CLASS_TANK
 ldx #9
 ldy #4
 jsr add_unit             ; id 12, BLACK, sitting where the miss lands
 lda unit_hp+12
 sta t_cost               ; victim HP before the shot
 lda unit_hp+11
 sta t_legal              ; intended target HP before the shot
 lda #100
 sta stub_value           ; roll 100 >= any hit chance -> always a miss
 lda #FR_OK
 sta expect
 lda #0
 ldx #11
 jsr fire_execute
 jsr check_eq
 lda #FR_MISS
 sta expect
 lda fr_outcome
 jsr check_eq             ; a stray on a tank is still a miss
 lda #9
 sta expect
 lda fr_shot_land_x
 jsr check_eq
 lda #4
 sta expect
 lda fr_shot_land_y
 jsr check_eq             ; landed one past the target, a tile up
 lda t_legal
 sta expect
 lda unit_hp+11
 jsr check_eq             ; the intended target is untouched
 lda t_cost
 sec
 sbc fr_damage
 sta expect
 lda unit_hp+12
 jsr check_eq             ; the unit under the stray took the damage
* --- a friendly on the landing square is hit too ---
 jsr miss_setup
 lda #SIDE_RED
 sta un_side
 lda #CLASS_TANK
 ldx #9
 ldy #4
 jsr add_unit             ; id 1, RED, friendly to the shooter
 lda unit_hp+1
 sta t_cost
 lda #100
 sta stub_value
 lda #FR_OK
 sta expect
 lda #0
 ldx #11
 jsr fire_execute
 jsr check_eq
 lda #FR_MISS
 sta expect
 lda fr_outcome
 jsr check_eq
 lda t_cost
 sec
 sbc fr_damage
 sta expect
 lda unit_hp+1
 jsr check_eq             ; strays are blind: the friendly takes it too
* --- destructible terrain on the landing square is worn ---
 jsr miss_setup
 lda #TERR_BRIDGE
 ldx #9
 ldy #4
 jsr set_cell             ; a bridge (15 HP) where the miss lands
 ldx #9
 ldy #4
 jsr cell_index
 tax
 lda terr_hp,x
 sta t_cost               ; the fresh bridge's hit points
 lda #100
 sta stub_value
 lda #FR_OK
 sta expect
 lda #0
 ldx #11
 jsr fire_execute
 jsr check_eq
 lda #FR_MISS
 sta expect
 lda fr_outcome
 jsr check_eq
 ldx #9
 ldy #4
 jsr cell_index
 tax
 lda t_cost
 sec
 sbc fr_damage
 sta expect
 lda terr_hp,x
 jsr check_eq             ; the bridge took the stray's damage
 lda #TERR_BRIDGE
 sta expect
 ldx #9
 ldy #4
 jsr get_cell
 jsr check_eq             ; and still stands (15 HP outlasts one shot)
* --- a stray that fells the enemy cruiser counts as a kill ---
 jsr miss_setup
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_CRUISER
 ldx #9
 ldy #4
 jsr add_unit             ; id 12, BLACK cruiser
 lda #1
 sta unit_hp+12           ; on its last hit point
 lda #100
 sta stub_value
 lda #FR_OK
 sta expect
 lda #0
 ldx #11
 jsr fire_execute
 jsr check_eq
 lda #FR_KILL
 sta expect
 lda fr_outcome
 jsr check_eq             ; a stray cruiser kill wins the game
 lda #12
 sta expect
 lda fr_target
 jsr check_eq             ; fr_target redirected to the felled cruiser
* --- the landing square is clamped to the board ---
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CRUISER
 ldx #16
 ldy #5
 jsr add_unit             ; id 0
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_TANK
 ldx #19
 ldy #5
 jsr add_unit             ; id 11, at the right edge
 ldx #SIDE_RED
 jsr units_begin_turn
 lda #100
 sta stub_value
 lda #FR_OK
 sta expect
 lda #0
 ldx #11
 jsr fire_execute
 jsr check_eq
 lda #19
 sta expect
 lda fr_shot_land_x
 jsr check_eq             ; tx+1 = 20 clamped back onto the board
* --- turn layer: a stray that fells the enemy cruiser wins ---
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #<stub_roll
 sta roll_vec
 lda #>stub_roll
 sta roll_vec+1
 lda #<stub_tick
 sta tick_vec
 lda #>stub_tick
 sta tick_vec+1
 stz stub_tick_value+2
 stz stub_tick_value+3
 lda #SIDE_RED
 sta un_side
 lda #CLASS_TANK
 ldx #7
 ldy #5
 jsr add_unit             ; id 0, RED tank shooter
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_TANK
 ldx #8
 ldy #5
 jsr add_unit             ; id 11, BLACK tank, the aimed-at target
 lda #CLASS_CRUISER
 ldx #9
 ldy #4
 jsr add_unit             ; id 12, BLACK cruiser on the landing square
 lda #SIDE_RED
 sta opt_first_side
 lda #2
 sta opt_moves_per_turn
 lda #SHOOT_ANY
 sta opt_shoot_option
 lda #1
 sta opt_time_minutes
 sta opt_time_minutes+1
 lda #<1000
 ldx #>1000
 jsr tick_set
 jsr game_start
 lda #1
 sta unit_hp+12           ; the cruiser is one shot from gone
 lda #100
 sta stub_value           ; force the miss
 lda #0
 ldx #11
 jsr turn_fire
 lda #RESULT_RED_WINS
 sta expect
 lda game_result
 jsr check_eq             ; Red's stray felled Black's cruiser
 lda #REASON_CRUISER
 sta expect
 lda result_reason
 jsr check_eq
* --- turn layer: a stray onto your OWN cruiser loses ---
 lda #TERR_CLEAR
 jsr board_fill
 jsr units_clear
 jsr events_clear
 lda #SIDE_RED
 sta un_side
 lda #CLASS_CRUISER
 ldx #9
 ldy #4
 jsr add_unit             ; id 0, RED cruiser on the landing square
 lda #CLASS_TANK
 ldx #7
 ldy #5
 jsr add_unit             ; id 1, RED tank shooter
 lda #SIDE_BLACK
 sta un_side
 lda #CLASS_TANK
 ldx #8
 ldy #5
 jsr add_unit             ; id 11, BLACK tank target
 lda #SIDE_RED
 sta opt_first_side
 lda #<1000
 ldx #>1000
 jsr tick_set
 jsr game_start
 lda #1
 sta unit_hp+0            ; Red's own cruiser one shot from gone
 lda #100
 sta stub_value
 lda #1
 ldx #11
 jsr turn_fire
 lda #RESULT_BLACK_WINS
 sta expect
 lda game_result
 jsr check_eq             ; Red destroyed its own cruiser; Black wins
 lda #REASON_CRUISER
 sta expect
 lda result_reason
 jsr check_eq
 rts

*----------------------------------------------------------
* section_begin / section_end - Snapshot the tallies, then
* after the section's checks draw "NAME   passed/run" on
* the next line, green if nothing failed, red otherwise.
* Rows run down the left column and continue in a second
* column once the first is full. Entered and left in 8-bit
* A/X/Y.
*----------------------------------------------------------
NUM_COL  = 88              ; numbers this far right of the name
COL_STEP = 152             ; second column starts here
ROW_STEP = 10
ROW_TOP  = 36
ROW_LAST = 176             ; last baseline before the footer
section_begin
 MX %11
 lda test_pass
 sta sec_pass
 lda test_pass+1
 sta sec_pass+1
 lda test_fail
 sta sec_fail
 lda test_fail+1
 sta sec_fail+1
 rts

section_end
 MX %11
 rep $30
 MX %00
 lda test_pass
 sec
 sbc sec_pass
 sta num_pass
 lda test_fail
 sec
 sbc sec_fail
 sta num_fail
 clc
 adc num_pass
 sta num_total
 lda #num_buf
 sta str_ptr
 lda num_pass
 ldx #4
 jsr fmt_u16
 lda #num_buf+5
 sta str_ptr
 lda num_total
 ldx #4
 jsr fmt_u16
 lda num_fail
 beq :green
 lda #7                    ; red
 bra :colour
:green
 lda #10                   ; green
:colour
 ldx #0
 jsr set_colors
 lda sec_name
 sta str_ptr
 ldx col_x
 ldy line_y
 jsr draw_cstr
 lda #num_buf
 sta str_ptr
 lda col_x
 clc
 adc #NUM_COL
 tax
 ldy line_y
 jsr draw_cstr
 lda line_y
 clc
 adc #ROW_STEP
 sta line_y
 cmp #ROW_LAST+1
 bcc :fits
 lda #ROW_TOP
 sta line_y
 lda col_x
 clc
 adc #COL_STEP
 sta col_x
:fits
 sep $30
 MX %11
 rts

sec_pass  ds 2
sec_fail  ds 2
sec_name  ds 2
num_pass  ds 2
num_fail  ds 2
num_total ds 2
line_y    ds 2
col_x     ds 2
num_buf   asc '    /    '
          dfb 0

s_heading    asc 'COMBAT CHESS RULES SELF-TESTS'
             dfb 0
s_sec_class  asc 'CLASS TABLE'
             dfb 0
s_sec_fuel   asc 'FUEL TABLE'
             dfb 0
s_sec_range  asc 'MOVE BOUNDS'
             dfb 0
s_sec_hit    asc 'HIT TABLE'
             dfb 0
s_sec_fire   asc 'FIRE BOUNDS'
             dfb 0
s_sec_rng    asc 'GENERATOR'
             dfb 0
s_sec_resolve asc 'RESOLVE HIT'
             dfb 0
s_sec_board  asc 'BOARD CELLS'
             dfb 0
s_sec_terrain asc 'TERRAIN'
             dfb 0
s_sec_lfind  asc 'LINE FIND'
             dfb 0
s_sec_ltrace asc 'LINE TRACE'
             dfb 0
s_sec_units  asc 'UNIT LIST'
             dfb 0
s_sec_events asc 'EVENT QUEUE'
             dfb 0
s_sec_move   asc 'MOVEMENT'
             dfb 0
s_sec_fire_act asc 'FIRE'
             dfb 0
s_sec_turn   asc 'TURN SYSTEM'
             dfb 0
s_sec_fire_at asc 'SQUARE FIRE'
             dfb 0
s_sec_ai     asc 'COMPUTER'
s_sec_miss   asc 'STRAY SHOT'
             dfb 0
s_sec_total  asc 'TOTAL'
             dfb 0
s_first_fail asc 'FIRST FAIL'
             dfb 0
s_return     asc 'PRESS ANY KEY TO RETURN TO TITLE'
             dfb 0

  put tables
  put board
  put line
  put units
  put events
  put move
  put rng
  put fire
  put turn
  put aiplayer
  put common
