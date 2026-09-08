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

  lda #40
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
  jsr test_ranges
  lda #<s_sec_range
  sta sec_name
  lda #>s_sec_range
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
 sta rt1                   ; expected
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
 sta rt1                   ; expected cost
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
 sty rt1
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
test_ranges
 MX %11
 stz t_class
:class
 stz t_orient
:orient
 lda t_class
 ldx t_orient
 jsr move_range
 sta t_range
 stz t_dist
:dist
 lda t_class
 ldx t_orient
 ldy t_dist
 jsr fuel_cost
 sta t_cost
 lda #0
 rol
 sta t_legal               ; 1 if fuel_cost said legal
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
 sta rt1
 lda t_legal
 jsr check_eq              ; carry agrees with move_range
 lda t_cost
 cmp #FUEL_NONE
 beq :none
 lda #1
 bra :value
:none
 lda #0
:value
 jsr check_eq              ; FUEL_NONE exactly when illegal
 inc t_dist
 lda t_dist
 cmp #MAX_MOVE_DIST+2
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

t_class  ds 1
t_orient ds 1
t_range  ds 1
t_dist   ds 1
t_cost   ds 1
t_legal  ds 1

*----------------------------------------------------------
* check_eq - One check: A must equal rt1. Numbers the check,
* tallies it, and remembers the first failing id.
* 8-bit A/X/Y. Preserves X, Y and rt1.
*----------------------------------------------------------
check_eq
 MX %11
 inc test_id
 bne :id_ok
 inc test_id+1
:id_ok
 cmp rt1
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
 adc #12
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
s_sec_total  asc 'TOTAL'
             dfb 0
s_first_fail asc 'FIRST FAILING CHECK ID'
             dfb 0
s_return     asc 'PRESS ANY KEY TO RETURN TO TITLE'
             dfb 0

  put tables
  put common
