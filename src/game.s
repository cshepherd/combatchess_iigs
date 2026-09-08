*----------------------------------------------------------
* GAME - Combat Chess game part.
*
* SYS file loaded at $2000 by CC.SYSTEM after TITLE. Carries
* the rules engine (milestone 1), the ten captured boards
* (src/boards.s, generated from reference/maps/) and, for
* now, the debug board (milestone 3): the hot-seat loop in
* dbg.s. Number keys on the board restart on another board;
* Q returns to the title.
*
* Options other than the board are fixed here until the
* title screen has an options page (spec 29): Red first,
* 3 moves a turn, Shoot Option 1, 10 minutes each. Army
* sizes are whatever the captured starting positions hold
* (the original's defaults: Red 2 tanks 4 cars, Black 3
* tanks 5 cars).
*----------------------------------------------------------

  ORG $2000
  MX %11

  put shared

  lda tb_inited
  bne :ready
  jsr toolbox_init          ; only if GAME was launched directly
  inc tb_inited
:ready
  lda opt_board
  bne :chosen
  lda #1
  sta opt_board             ; board 1 until the title offers a choice
:chosen
  clc
  xce
  rep $30
  MX %00
  jsr shr_init
  jsr dbg_init

  sep $30
  MX %11
  jsr setup_game

  rep $30
  MX %00
  jsr dbg_run

  sec
  xce
  MX %11
  jmp LAUNCH_TITLE

*----------------------------------------------------------
* setup_game - Load board opt_board with its starting units,
* apply the fixed options, seed the generator from the tick
* counter, and begin the first turn. 8-bit A/X/Y.
* Out: carry set = ready; carry clear = that board has not
*      been captured yet (nothing changed).
*----------------------------------------------------------
setup_game
 MX %11
 lda opt_board
 beq :missing
 cmp #NUM_BOARDS+1
 bcs :missing
 dec
 asl
 tax
 lda board_map_ptrs,x
 sta rptr
 lda board_map_ptrs+1,x
 sta rptr+1
 ora rptr
 bne :have
:missing
 clc
 rts
:have
 lda board_units_ptrs,x
 sta rptr2
 lda board_units_ptrs+1,x
 sta rptr2+1
 jsr board_load_text
 jsr units_clear
 jsr events_clear
 ldy #0
:unit
 lda (rptr2),y
 cmp #$FF
 beq :placed
 sta un_side
 iny
 lda (rptr2),y
 sta un_class
 iny
 lda (rptr2),y
 sta un_x
 iny
 lda (rptr2),y
 sta un_y
 iny
 phy
 jsr unit_add
 ply
 bra :unit
:placed
 lda #SIDE_RED
 sta opt_first_side
 lda #3
 sta opt_moves_per_turn
 lda #SHOOT_ANY
 sta opt_shoot_option
 lda #10
 sta opt_time_minutes
 jsr sys_tick
 lda now_tick
 sta rt0
 lda now_tick+1
 sta rt1
 lda now_tick+2
 sta rt2
 lda now_tick+3
 sta rt3
 jsr rng_seed
 jsr game_start
 sec
 rts

* Rules engine (milestone 1).
  put tables
  put board
  put line
  put units
  put events
  put move
  put rng
  put fire
  put turn

* The captured boards (generated).
  put boards

* Debug board (milestone 3).
  put dbg

  put common
