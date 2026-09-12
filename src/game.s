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
* Options come from the title screen's options page through
* page $11 (shared.s cfg_*); cfg_defaults fills in the
* original's defaults if GAME is entered directly.
*----------------------------------------------------------

  ORG $2000
  MX %11

  put shared

  lda tb_inited
  bne :ready
  jsr toolbox_init          ; only if GAME was launched directly
  inc tb_inited
:ready
  lda cfg_valid
  cmp #CFG_MAGIC
  beq :chosen
  jsr cfg_defaults          ; GAME launched without the title
:chosen
  clc
  xce
  rep $30
  MX %00
  jsr shr_init

  sep $30
  MX %11
  lda net_mode              ; network game? connect instead of local setup
  beq :local
  sei                       ; mask IRQs from here through snd_init: the connect
  jsr net_game_start        ; blocks for seconds before the game's sound handler
  bcc :haveboard            ; is up, and a stray DOC interrupt left by the title
  stz net_mode              ; music would otherwise crash the firmware
:local
  jsr setup_game            ; the board first: dbg_init reads it
:haveboard

  rep $30
  MX %00
  jsr dbg_init
  jsr snd_load
  jsr snd_init
  cli                       ; sound handler up: safe to take interrupts again
  sep #$20
  MX %10
  lda net_mode              ; local play sets the pieces down with beeps;
  bne :skipanim             ; a network board is the server's, already placed
  rep #$20
  MX %00
  jsr place_animation
  bra :runit
:skipanim
  rep #$20
  MX %00
:runit
  jsr dbg_run

  sec
  xce
  MX %11
  jmp LAUNCH_TITLE

*----------------------------------------------------------
* setup_game - Load board cfg_board with its starting units
* trimmed to the chosen army sizes, apply the options from
* page $11, seed the generator from the tick counter, and
* begin the first turn. 8-bit A/X/Y.
* Out: carry set = ready; carry clear = that board has not
*      been captured yet (nothing changed).
*
* The captured starting positions hold the original's
* default armies (Red 2 tanks 4 cars, Black 3 tanks 5 cars).
* Smaller armies drop the last-listed units of that class;
* UNVERIFIED whether the original drops the same ones. Larger
* armies cannot be placed until their positions are captured,
* so counts above the captured units are ignored.
* cfg_computer picks which sides the computer plays (ai.s).
*----------------------------------------------------------
setup_game
 MX %11
 lda cfg_board
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
* army limits for this game: index side*3 + class
 lda cfg_tanks_red
 sta side_class_max+1
 lda cfg_cars_red
 sta side_class_max+2
 lda cfg_tanks_black
 sta side_class_max+4
 lda cfg_cars_black
 sta side_class_max+5
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
 jsr unit_add              ; refused once a class is at its limit
 ply
 bra :unit
:placed
 lda cfg_first
 sta opt_first_side
 lda cfg_moves
 sta opt_moves_per_turn
 lda cfg_shoot
 sta opt_shoot_option
 lda cfg_time_red
 sta opt_time_minutes+SIDE_RED
 lda cfg_time_black
 sta opt_time_minutes+SIDE_BLACK
* who the computer plays (spec 29.4), from cfg_computer
 stz cpu_side+SIDE_RED
 stz cpu_side+SIDE_BLACK
 lda cfg_computer
 cmp #CFG_CPU_BOTH
 bne :notboth
 lda #1
 sta cpu_side+SIDE_RED
 sta cpu_side+SIDE_BLACK
 bra :cpudone
:notboth
 cmp #CFG_CPU_NONE
 beq :cpudone
 cmp #CFG_CPU_RED
 bne :cpublack
 lda #1
 sta cpu_side+SIDE_RED
 bra :cpudone
:cpublack
 lda #1
 sta cpu_side+SIDE_BLACK
:cpudone
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
  put aiplayer

* The captured boards (generated).
  put boards

* Debug board (milestone 3) and the status display.
  put dbg
  put status
  put status_art
 put art
  put board_art
  put sound_samples
  put sound

  put net
  put netdhcp
  put proto
  put netgame
  put netplay
  put netloop

  put common
