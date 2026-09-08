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
  ldx #40
  ldy #20
  jsr draw_cstr

  lda #36
  sta line_y

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
  ldx #3
  jsr fmt_u16
  lda #7                    ; red
  ldx #0
  jsr set_colors
  lda #s_first_fail
  sta str_ptr
  ldx #40
  ldy line_y
  jsr draw_cstr
  lda #num_buf
  sta str_ptr
  ldx #200
  ldy line_y
  jsr draw_cstr
:no_fail
  lda #9
  ldx #0
  jsr set_colors
  lda #s_return
  sta str_ptr
  ldx #40
  ldy #180
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
* pattern (3). 48 checks.
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
 rts

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
* section_begin / section_end - Snapshot the tallies, then
* after the section's checks draw "NAME   passed/run" on
* the next line, green if nothing failed, red otherwise.
* Entered and left in 8-bit A/X/Y.
*----------------------------------------------------------
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
 ldx #3
 jsr fmt_u16
 lda #num_buf+4
 sta str_ptr
 lda num_total
 ldx #3
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
 ldx #40
 ldy line_y
 jsr draw_cstr
 lda #num_buf
 sta str_ptr
 ldx #200
 ldy line_y
 jsr draw_cstr
 lda line_y
 clc
 adc #10
 sta line_y
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
num_buf   asc '   /   '
          dfb 0

s_heading    asc 'COMBAT CHESS RULES SELF-TESTS'
             dfb 0
s_sec_class  asc 'CLASS TABLES'
             dfb 0
s_sec_fuel   asc 'FUEL TABLE'
             dfb 0
s_sec_range  asc 'MOVE RANGE BOUNDS'
             dfb 0
s_sec_hit    asc 'HIT TABLE'
             dfb 0
s_sec_fire   asc 'FIRE RANGE BOUNDS'
             dfb 0
s_sec_rng    asc 'RANDOM GENERATOR'
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
s_sec_total  asc 'TOTAL'
             dfb 0
s_first_fail asc 'FIRST FAILING CHECK ID'
             dfb 0
s_return     asc 'PRESS ANY KEY TO RETURN TO TITLE'
             dfb 0

  put tables
  put board
  put line
  put rng
  put common
