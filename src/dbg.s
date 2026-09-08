*----------------------------------------------------------
* dbg.s - The milestone 3 debug board: keyboard cursor, HUD
* and a hot-seat game loop over the rules engine (spec
* sections 25, 26, 41). The squares themselves are drawn by
* src/art.s with the original's glyphs (milestone 4).
*
* PUT into game.s after the engine includes. Runs in native
* mode with 16-bit A/X/Y (MX %00), like common.s, and drops
* to 8-bit only inside the eng_* wrappers that call the
* engine. Engine byte variables read from here are masked
* with #$00FF.
*
* Layout: 20 x 11 squares of 16 x 16 pixels fill the top 176
* rows, as on the Atari, then the original's two status lines
* (see HUD below) and, on the border under them, the debug
* board's own line: the last message, else the turn summary.
* The cursor is a white outline (select), thick box (move) or
* cross (fire). While a unit is selected, legal destinations
* get an orange dot and legal targets (enemy units, and
* trees, bridges or grey squares to destroy) a cyan outline,
* with the line of fire dotted to the target under the cursor.
*
* Keys: arrows or WASD move the cursor. RETURN selects a
* friendly unit, then confirms a move or a shot. M and F
* switch the selected unit between move and fire. ESC drops
* the selection. E ends the turn, P pauses, X surrenders,
* Q quits to the title; after the game ends any key quits.
*----------------------------------------------------------
CELL_WB    = 8             ; cell width in bytes (16 pixels)
CELL_H     = 16            ; cell height in rows
HUD_TOP    = 176           ; the original's two status lines start here
DBG_TOP    = 192           ; the debug board's line, on the border below them
SCREEN_ROW = 160           ; bytes per SHR row
SCREEN     = $2000         ; SHR pixels in bank $E1

MODE_SELECT = 0
MODE_MOVE   = 1
MODE_FIRE   = 2

* Palette 0 slots used here; 1-5 belong to the board (art.s).
COL_BLACK    = 0
COL_WHITE    = 6
COL_HUD_BG   = 7           ; the status lines' grey, Atari $08
COL_GREY     = 8
COL_PURPLE   = 9
COL_HUD_BORDER = 10        ; the border under them, Atari $36
COL_LTGREY   = 11
COL_ORANGE   = 12
COL_CYAN     = 13
COL_DKRED    = 14
COL_TEXT     = 15

KEY_LEFT   = $08
KEY_RIGHT  = $15
KEY_UP     = $0B
KEY_DOWN   = $0A
KEY_RETURN = $0D
KEY_ESC    = $1B
KEY_SPACE  = $20
KEY_TAB    = $09

dbg_palette
 dw $0000,$0555,$05C3,$0261,$026E,$0A63,$0EEE,$0666
 dw $0999,$093B,$0741,$0BBB,$0F92,$04DE,$0800,$0FFF

*----------------------------------------------------------
* dbg_init - Palette and display state. Native 16-bit.
*----------------------------------------------------------
dbg_init
 MX %00
 ldx #$001E
:pal
 lda dbg_palette,x
 stal $E19E00,x
 dex
 dex
 bpl :pal
 jsr art_set_board
 stz cur_x
 stz cur_y
 stz mode
 lda #$FF
 sta sel_unit
 stz quit
 stz over_shown
 lda #$FFFF
 sta last_sec
 stz msg_ptr
 stz status_view
 lda #HUD_TOP
 sta hud_top
 jsr hud_defaults
 lda #TEXT_FORE
 jsr set_text_mode         ; the status lines' descenders overlap the next strip
 lda #1
 sta dirty
 rts

*----------------------------------------------------------
* dbg_run - The loop: redraw when something changed, keep
* the clock line current, read keys. Returns when the
* player quits. Native 16-bit.
*----------------------------------------------------------
dbg_run
 MX %00
:loop
 lda dirty
 beq :clock
 stz dirty
 jsr draw_all
:clock
 jsr update_clock
 jsr wait_vbl
 lda inject_key            ; a debugger can poke a key here
 beq :keyboard
 stz inject_key
 bra :key
:keyboard
 sep #$20
 MX %10
 lda $C000
 bpl :nokey
 sta $C010
 and #$7F
 rep #$20
 MX %00
 and #$00FF
:key
 jsr handle_key
 lda quit
 beq :loop
 rts
:nokey
 rep #$20
 MX %00
 bra :loop

*----------------------------------------------------------
* update_clock - Once a frame: let the engine notice a
* timeout, then redraw the top line when the displayed
* second changes.
*----------------------------------------------------------
update_clock
 MX %00
 jsr eng_clock_check
 jsr note_game_over
 lda active_side
 and #$00FF
 tax
 jsr eng_clock_remaining   ; clk_min / clk_sec
 lda clk_sec
 cmp last_sec
 beq :same
 sta last_sec
 jmp draw_hud_lines
:same
 rts

* note_game_over - The first time game_result is set, show
* the result and mark the display dirty.
note_game_over
 MX %00
 lda game_result
 and #$00FF
 beq :done
 lda over_shown
 bne :done
 inc over_shown
 jsr build_result_msg
 lda #1
 sta dirty
:done
 rts

*----------------------------------------------------------
* handle_key - A = key. Native 16-bit.
*----------------------------------------------------------
handle_key
 MX %00
 sta key_code
 lda game_result
 and #$00FF
 beq :playing
 lda #1
 sta quit                  ; any key after the end
 rts
:playing
 lda key_code
 cmp #KEY_TAB
 bne :not_tab
 jmp status_toggle         ; board -> own status -> opponent's -> board
:not_tab
 lda status_view
 beq :board_keys
 lda key_code
 cmp #KEY_ESC
 bne :ignored
 jmp status_close
:ignored
 rts                       ; other keys wait for the board
:board_keys
 ldx #0
:scan
 lda key_table,x
 and #$00FF
 beq :unknown
 cmp key_code
 beq :found
 inx
 inx
 inx
 bra :scan
:found
 lda key_table+1,x         ; handler address (2 bytes)
 sta key_vec
 jmp (key_vec)
:unknown
 rts

* key, handler address. Zero key ends the table.
key_table
 dfb KEY_LEFT
 da k_left
 dfb 'A'
 da k_left
 dfb 'a'
 da k_left
 dfb KEY_RIGHT
 da k_right
 dfb 'D'
 da k_right
 dfb 'd'
 da k_right
 dfb KEY_UP
 da k_up
 dfb 'W'
 da k_up
 dfb 'w'
 da k_up
 dfb KEY_DOWN
 da k_down
 dfb 'S'
 da k_surrender_or_down
 dfb 's'
 da k_surrender_or_down
 dfb KEY_RETURN
 da k_confirm
 dfb KEY_SPACE
 da k_confirm
 dfb 'M'
 da k_move_mode
 dfb 'm'
 da k_move_mode
 dfb 'F'
 da k_fire_mode
 dfb 'f'
 da k_fire_mode
 dfb KEY_ESC
 da k_cancel
 dfb 'E'
 da k_end_turn
 dfb 'e'
 da k_end_turn
 dfb 'P'
 da k_pause
 dfb 'p'
 da k_pause
 dfb 'X'
 da k_surrender
 dfb 'x'
 da k_surrender
 dfb 'Q'
 da k_quit
 dfb 'q'
 da k_quit
 dfb '1'
 da k_board
 dfb '2'
 da k_board
 dfb '3'
 da k_board
 dfb '4'
 da k_board
 dfb '5'
 da k_board
 dfb '6'
 da k_board
 dfb '7'
 da k_board
 dfb '8'
 da k_board
 dfb '9'
 da k_board
 dfb '0'
 da k_board
 dfb 0

*----------------------------------------------------------
* k_board - a digit: restart on that board (0 = board 10).
* Boards not captured yet are refused with a message. Only
* the board changes; the other options keep their values.
*----------------------------------------------------------
k_board
 MX %00
 lda key_code
 sec
 sbc #'0'
 bne :num
 lda #10
:num
 sta tmp
 lda cfg_board
 and #$00FF
 sta tmp2                  ; to restore if the board is missing
 lda tmp
 sep #$20
 MX %10
 sta cfg_board
 rep #$20
 MX %00
 jsr eng_setup_game
 bcs :restarted
 lda tmp2
 sep #$20
 MX %10
 sta cfg_board
 rep #$20
 MX %00
 lda #s_no_board
 jmp set_msg
:restarted
 jsr dbg_init
 lda #s_new_board
 jmp set_msg

eng_setup_game
 MX %00
 sep #$30
 MX %11
 jsr setup_game
 rep #$30
 MX %00
 rts

k_left
 MX %00
 lda cur_x
 beq :edge
 dec cur_x
:edge
 jmp mark_dirty
k_right
 MX %00
 lda cur_x
 cmp #BOARD_W-1
 bcs :edge
 inc cur_x
:edge
 jmp mark_dirty
k_up
 MX %00
 lda cur_y
 beq :edge
 dec cur_y
:edge
 jmp mark_dirty
k_down
 MX %00
 lda cur_y
 cmp #BOARD_H-1
 bcs :edge
 inc cur_y
:edge
 jmp mark_dirty

* S doubles as "down" for WASD; surrender is X.
k_surrender_or_down
 MX %00
 jmp k_down

mark_dirty
 MX %00
 lda #1
 sta dirty
 rts

*----------------------------------------------------------
* k_confirm - RETURN: select, move or fire by mode.
*----------------------------------------------------------
k_confirm
 MX %00
 lda mode
 beq :select
 cmp #MODE_MOVE
 beq :move
 jmp do_fire
:select
 jmp do_select
:move
 jmp do_move

do_select
 MX %00
 ldx cur_x
 ldy cur_y
 jsr eng_get_unit_at
 bcs :unit
 lda #s_no_unit_here
 jmp set_msg
:unit
 sta sel_tmp
 tax
 lda unit_side,x
 and #$00FF
 sta tmp
 lda active_side
 and #$00FF
 cmp tmp
 beq :ours
 lda #s_not_yours
 jmp set_msg
:ours
 lda sel_tmp
 sta sel_unit
 lda active_side
 and #$00FF
 asl
 tax
 lda sel_tmp
 sta hud_shown,x           ; the side's line keeps showing it
 lda #MODE_MOVE
 sta mode
 lda #s_move_hint
 jmp set_msg

do_move
 MX %00
 lda sel_unit
 ldx cur_x
 ldy cur_y
 jsr eng_turn_move
 bcs :moved
 jsr reason_mv
 jmp set_msg
:moved
 lda #MODE_SELECT
 sta mode
 lda #$FF
 sta sel_unit
 lda #s_moved
 jsr set_msg
 jsr note_game_over
 jmp note_turn_change

do_fire
 MX %00
 lda sel_unit
 ldx cur_x
 ldy cur_y
 jsr eng_turn_fire_at      ; the unit there, else the square
 bcs :fired
 jsr reason_fr
 jmp set_msg
:fired
 jsr build_shot_msg
 jsr note_game_over
 lda #1
 sta dirty
 rts

* note_turn_change - after a move the engine may have ended
* the turn by itself; say so.
note_turn_change
 MX %00
 lda active_side
 and #$00FF
 cmp shown_side
 beq :same
 sta shown_side
 lda #s_turn_over
 jsr set_msg
:same
 rts

k_move_mode
 MX %00
 jsr need_selection
 bcc :done
 lda #MODE_MOVE
 sta mode
 lda #s_move_hint
 jmp set_msg
:done
 rts

k_fire_mode
 MX %00
 jsr need_selection
 bcc :done
 lda #MODE_FIRE
 sta mode
 lda #s_fire_hint
 jmp set_msg
:done
 rts

* need_selection - a unit must be selected; if none, try
* the one under the cursor. Carry set = there is one.
need_selection
 MX %00
 lda sel_unit
 cmp #$FF
 bne :have
 jsr do_select
 lda sel_unit
 cmp #$FF
 bne :have
 clc
 rts
:have
 sec
 rts

k_cancel
 MX %00
 lda #MODE_SELECT
 sta mode
 lda #$FF
 sta sel_unit
 stz msg_ptr
 jmp mark_dirty

k_end_turn
 MX %00
 jsr eng_turn_end
 lda #MODE_SELECT
 sta mode
 lda #$FF
 sta sel_unit
 lda active_side
 and #$00FF
 sta shown_side
 lda #s_turn_over
 jsr set_msg
 jmp note_game_over

k_pause
 MX %00
 lda paused
 and #$00FF
 bne :resume
 jsr eng_turn_pause
 lda #s_paused
 jmp set_msg
:resume
 jsr eng_turn_resume
 lda #s_resumed
 jmp set_msg

k_surrender
 MX %00
 lda active_side
 and #$00FF
 tax
 jsr eng_surrender
 jmp note_game_over

k_quit
 MX %00
 lda #1
 sta quit
 rts

* set_msg - A = C string for the bottom line; redraw.
set_msg
 MX %00
 sta msg_ptr
 lda #1
 sta dirty
 rts

*----------------------------------------------------------
* Messages
*----------------------------------------------------------

* reason_mv / reason_fr - A = MV_* / FR_* / TN_* code ->
* A = its text.
reason_mv
 MX %00
 cmp #$80
 bcs reason_tn
 asl
 tax
 lda mv_reasons,x
 rts
reason_fr
 MX %00
 cmp #$80
 bcs reason_tn
 asl
 tax
 lda fr_reasons,x
 rts
reason_tn
 MX %00
 and #$7F
 asl
 tax
 lda tn_reasons,x
 rts

mv_reasons da s_ok,s_r_no_unit,s_r_not_line,s_r_too_far,s_r_blocked,s_r_no_fuel
fr_reasons da s_ok,s_r_no_unit,s_r_no_target,s_r_not_line,s_r_range,s_r_blocked,s_r_no_ammo,s_r_already
tn_reasons da s_r_over,s_r_not_yours,s_r_no_moves,s_r_no_phase

* build_shot_msg - "HIT  63 < 64" / "MISS 70 >= 64" /
* "DESTROYED  12 < 64" into msg_buf from fr_*.
build_shot_msg
 MX %00
 jsr lb_reset
 lda fr_outcome
 and #$00FF
 beq :miss
 cmp #FR_KILL
 beq :kill
 lda #s_hit
 bra :word
:kill
 lda #s_destroyed
 bra :word
:miss
 lda #s_miss
:word
 jsr lb_str
 lda fr_roll
 and #$00FF
 ldx #3
 jsr lb_dec
 lda fr_outcome
 and #$00FF
 beq :ge
 lda #s_lt
 bra :cmp
:ge
 lda #s_ge
:cmp
 jsr lb_str
 lda fr_chance
 and #$00FF
 ldx #3
 jsr lb_dec
 jsr lb_end
 lda #line_buf
 jmp set_msg_copy

* build_result_msg - "RED WINS: CRUISER DESTROYED" etc.
build_result_msg
 MX %00
 jsr lb_reset
 lda game_result
 and #$00FF
 cmp #RESULT_STALEMATE
 bne :winner
 lda #s_stalemate
 jsr lb_str
 bra :end
:winner
 dec                       ; side that won
 asl
 tax
 lda side_names,x
 jsr lb_str
 lda #s_wins
 jsr lb_str
 lda result_reason
 and #$00FF
 asl
 tax
 lda reason_names,x
 jsr lb_str
:end
 lda #s_any_key
 jsr lb_str
 jsr lb_end
 lda #line_buf
 jmp set_msg_copy

* set_msg_copy - the line builder's buffer is reused by the
* HUD, so composed messages are copied to msg_buf first.
set_msg_copy
 MX %00
 ldx #0
:copy
 lda line_buf,x
 sta msg_buf,x
 and #$00FF
 beq :done
 inx
 bra :copy
:done
 lda #msg_buf
 jmp set_msg

side_names   da s_red,s_black
reason_names da s_ok,s_by_cruiser,s_by_time,s_by_surrender,s_by_stalemate

*----------------------------------------------------------
* Drawing
*----------------------------------------------------------
draw_all
 MX %00
 jsr eng_events_clear      ; the debug board reads state, not events
 lda status_view
 beq :board
 jmp status_draw
:board
 jsr art_draw_board
 jsr draw_highlights
 jsr draw_cursor
 jsr draw_hud
 rts

* draw_highlights - with a unit selected: legal destinations
* in move mode, legal targets and the line of fire in fire
* mode.
draw_highlights
 MX %00
 lda sel_unit
 cmp #$FF
 beq :done
 lda mode
 cmp #MODE_MOVE
 beq :moves
 cmp #MODE_FIRE
 beq :targets
:done
 rts
:moves
 jmp hl_moves
:targets
 jmp hl_targets

* hl_moves - walk the eight rays from the unit and dot every
* square move_validate accepts.
hl_moves
 MX %00
 stz dir
:dir
 ldx sel_unit
 lda unit_x,x
 and #$00FF
 sta hx
 lda unit_y,x
 and #$00FF
 sta hy
 stz dist
:step
 ldx dir
 lda dir_dx,x
 and #$00FF
 jsr sign_extend
 clc
 adc hx
 sta hx
 lda dir_dy,x
 and #$00FF
 jsr sign_extend
 clc
 adc hy
 sta hy
 lda hx
 cmp #BOARD_W
 bcs :off
 lda hy
 cmp #BOARD_H
 bcs :off
 lda sel_unit
 ldx hx
 ldy hy
 jsr eng_move_validate
 bcc :no
 lda hx
 sta cx
 lda hy
 sta cy
 lda #COL_ORANGE
 jsr draw_dot
:no
 inc dist
 lda dist
 cmp #MAX_MOVE_DIST
 bcs :off
 jmp :step
:off
 inc dir
 lda dir
 cmp #NUM_DIRS
 bcs :done
 jmp :dir
:done
 rts

* hl_targets - walk the eight rays from the selected unit and
* outline every square fire_validate_at accepts, an enemy
* unit or a square that can be destroyed; the line of fire
* is dotted to the target under the cursor.
hl_targets
 MX %00
 stz dir
:dir
 ldx sel_unit
 lda unit_x,x
 and #$00FF
 sta hx
 lda unit_y,x
 and #$00FF
 sta hy
:step
 ldx dir
 lda dir_dx,x
 and #$00FF
 jsr sign_extend
 clc
 adc hx
 sta hx
 lda dir_dy,x
 and #$00FF
 jsr sign_extend
 clc
 adc hy
 sta hy
 lda hx
 cmp #BOARD_W
 bcs :off
 lda hy
 cmp #BOARD_H
 bcs :off
 lda sel_unit
 ldx hx
 ldy hy
 jsr eng_fire_validate_at
 bcc :no
 lda hx
 sta cx
 lda hy
 sta cy
 lda #COL_CYAN
 jsr draw_box1
:no
 jmp :step
:off
 inc dir
 lda dir
 cmp #NUM_DIRS
 bcs :done
 jmp :dir
:done
* the line of fire to the cursor's square, if that is a
* target (draw_fire_line walks with hx, hy and dir itself)
 lda sel_unit
 ldx cur_x
 ldy cur_y
 jsr eng_fire_validate_at
 bcc :none
 jmp draw_fire_line
:none
 rts

* draw_fire_line - after a successful fire_validate, ln_*
* describe the line: dot cells 1..dist-1 from the attacker.
draw_fire_line
 MX %00
 lda ln_x0
 and #$00FF
 sta hx
 lda ln_y0
 and #$00FF
 sta hy
 lda ln_dist
 and #$00FF
 sta dist
 lda ln_dir
 and #$00FF
 sta dir
:step
 dec dist
 beq :done
 ldx dir
 lda dir_dx,x
 and #$00FF
 jsr sign_extend
 clc
 adc hx
 sta hx
 lda dir_dy,x
 and #$00FF
 jsr sign_extend
 clc
 adc hy
 sta hy
 lda hx
 sta cx
 lda hy
 sta cy
 lda #COL_CYAN
 jsr draw_dot
 bra :step
:done
 rts

* sign_extend - A = a byte -> A = the same value as a signed
* 16-bit number.
sign_extend
 MX %00
 cmp #$0080
 bcc :pos
 ora #$FF00
:pos
 rts

* draw_cursor - by mode: outline, thick box, or cross.
draw_cursor
 MX %00
 lda cur_x
 sta cx
 lda cur_y
 sta cy
 lda mode
 beq :select
 cmp #MODE_MOVE
 beq :move
 lda #COL_TEXT
 jmp draw_cross
:select
 lda #COL_TEXT
 jmp draw_box1
:move
 lda #COL_TEXT
 jmp draw_box2

* draw_box1 / draw_box2 - outline the cell at (cx, cy) in
* colour A, one or two bytes thick.
draw_box1
 MX %00
 ldx #1
 bra draw_box
draw_box2
 MX %00
 ldx #2
draw_box
 MX %00
 stx thick
 jsr set_fill_colour
 jsr cell_addr
 lda fr_addr
 sta box_addr
 lda #CELL_WB
 sta fr_w
 lda thick
 sta fr_h
 jsr fill_rect             ; top
 lda #CELL_H
 sec
 sbc thick
 jsr rows_to_offset
 clc
 adc box_addr
 sta fr_addr
 jsr fill_rect             ; bottom
 lda box_addr
 sta fr_addr
 lda thick
 sta fr_w
 lda #CELL_H
 sta fr_h
 jsr fill_rect             ; left
 lda box_addr
 clc
 adc #CELL_WB
 sec
 sbc thick
 sta fr_addr
 jmp fill_rect             ; right

* draw_cross - a + through the cell at (cx, cy) in colour A.
draw_cross
 MX %00
 jsr set_fill_colour
 jsr cell_addr
 lda fr_addr
 sta box_addr
 lda #7
 jsr rows_to_offset
 clc
 adc box_addr
 sta fr_addr
 lda #CELL_WB
 sta fr_w
 lda #1
 sta fr_h
 jsr fill_rect             ; horizontal bar
 lda box_addr
 clc
 adc #3
 sta fr_addr
 lda #2
 sta fr_w
 lda #CELL_H
 sta fr_h
 jmp fill_rect             ; vertical bar

* draw_dot - a small mark in the middle of (cx, cy) in
* colour A.
draw_dot
 MX %00
 jsr set_fill_colour
 jsr cell_addr
 lda fr_addr
 clc
 adc #6*SCREEN_ROW+3
 sta fr_addr
 lda #2
 sta fr_w
 lda #3
 sta fr_h
 jmp fill_rect

* rows_to_offset - A = rows -> A = rows * SCREEN_ROW.
rows_to_offset
 MX %00
 sta tmp
 asl
 asl
 asl
 asl
 asl                       ; *32
 sta tmp2
 lda tmp
 asl
 asl
 asl
 asl
 asl
 asl
 asl                       ; *128
 clc
 adc tmp2
 rts

* cell_addr - fr_addr = screen offset of the top-left byte
* of cell (cx, cy).
cell_addr
 MX %00
 lda cy
 asl
 asl
 asl
 asl                       ; cy*16 rows
 jsr rows_to_offset
 clc
 adc #SCREEN
 sta fr_addr
 lda cx
 asl
 asl
 asl                       ; cx*8 bytes
 clc
 adc fr_addr
 sta fr_addr
 rts

* set_fill_colour - A = palette index -> fr_col = the byte
* that paints two pixels of it.
set_fill_colour
 MX %00
 and #$000F
 sta tmp
 asl
 asl
 asl
 asl
 ora tmp
 sta fr_col
 rts

* fill_rect - paint fr_h rows of fr_w bytes from screen
* offset fr_addr in bank $E1 with fr_col.
fill_rect
 MX %00
 lda fr_h
 sta tmp_h
 lda fr_addr
 sta tmp_a
:row
 ldx tmp_a
 ldy fr_w
 sep #$20
 MX %10
 lda fr_col
:byte
 stal $E10000,x
 inx
 dey
 bne :byte
 rep #$20
 MX %00
 lda tmp_a
 clc
 adc #SCREEN_ROW
 sta tmp_a
 dec tmp_h
 bne :row
 rts

*----------------------------------------------------------
* HUD: the original's two status lines under the board (spec
* 25; captured in reference/raw/status/), one per side:
*
*   19:55 #  SQ=15, GM=30, AM=16, FL=240
*
* the side's remaining time, a marker (# on the side to move
* and _ on the other, as captured at the start of a game;
* UNVERIFIED meaning), then the square hit points, hit
* points, ammunition and fuel of the side's unit: for the
* side to move the selected unit, else the unit under the
* cursor if it is theirs; otherwise the last unit the side
* selected, its Battle Cruiser to begin with. (Spec 25 reads
* the manual as one line per cursor, but the capture shows
* one clock per side; which unit the waiting side's line
* follows is UNVERIFIED.) In move mode FL is the fuel left
* after the move under the cursor (spec 25.1). Black text on
* the grey strip the original's display list interrupt paints
* (Atari $08), 16 rows; below it the original shows its
* brown border ($36), where the debug board writes its
* message or turn summary. Fields sit at the original's
* 8-pixel columns; numbers are zero-padded like the status
* screen's (UNVERIFIED on the HUD itself, checklist H08-H13).
*----------------------------------------------------------
HUD_LINE_H = 8
HX_CLOCK   = 16            ; column 2
HX_MARK    = 64            ; column 8
HX_SQ      = 88            ; column 11
HX_GM      = 144           ; column 18
HX_AM      = 200           ; column 25
HX_FL      = 256           ; column 32
DBG_ADDR   = DBG_TOP*SCREEN_ROW+SCREEN ; Merlin: left to right
DBG_Y      = 199           ; the debug line's baseline

* draw_hud - both lines from hud_top and, on the board view,
* the debug line below them. Text is drawn foreground-only
* (TEXT_FORE) and every strip is cleared before any text:
* the font's comma and _ reach a row or two below the
* baseline, into the next strip.
draw_hud
 MX %00
 lda hud_top
 cmp #HUD_TOP
 bne :lines                ; the status view shows nothing below
 jsr dbg_clear
 jsr draw_hud_lines
 jmp dbg_text
:lines
 jmp draw_hud_lines

* draw_hud_lines - both status lines, cleared then drawn.
draw_hud_lines
 MX %00
 lda #0
 jsr hud_clear_line
 lda #1
 jsr hud_clear_line
 lda #0
 jsr hud_draw_line
 lda #1
 jmp hud_draw_line

* hud_clear_line - A = side: its 8-row strip in grey.
hud_clear_line
 MX %00
 asl
 asl
 asl                       ; side * 8 rows
 clc
 adc hud_top
 jsr rows_to_offset
 clc
 adc #SCREEN
 sta fr_addr
 lda #SCREEN_ROW
 sta fr_w
 lda #HUD_LINE_H
 sta fr_h
 lda #COL_HUD_BG
 jsr set_fill_colour
 jmp fill_rect

* hud_draw_line - A = side: that side's text.
hud_draw_line
 MX %00
 sta hud_side
 asl
 asl
 asl
 clc
 adc hud_top
 clc
 adc #7
 sta hud_y                 ; the baseline
 lda #COL_BLACK
 ldx #COL_HUD_BG
 jsr set_colors
* the clock
 ldx hud_side
 jsr eng_clock_remaining   ; clk_min / clk_sec
 jsr lb_reset
 lda clk_min
 jsr lb_dec2
 lda #s_colon
 jsr lb_str
 lda clk_sec
 jsr lb_dec2
 jsr lb_end
 ldx #HX_CLOCK
 jsr hud_text
* the marker
 lda active_side
 and #$00FF
 cmp hud_side
 bne :waiting
 lda #s_mark_move
 bra :mark
:waiting
 lda #s_mark_wait
:mark
 sta str_ptr
 ldx #HX_MARK
 ldy hud_y
 jsr draw_cstr
* the unit
 jsr hud_pick_unit
 sta hud_unit
 tax
 lda unit_terr_hp,x
 and #$00FF
 ldx #HX_SQ
 ldy #s_h_sq
 jsr hud_field
 ldx hud_unit
 lda unit_hp,x
 and #$00FF
 ldx #HX_GM
 ldy #s_h_gm
 jsr hud_field
 ldx hud_unit
 lda unit_ammo,x
 and #$00FF
 ldx #HX_AM
 ldy #s_h_am
 jsr hud_field
 ldx hud_unit
 lda unit_fuel,x
 and #$00FF
 sta hud_val
 lda mode
 cmp #MODE_MOVE
 bne :fuel
 lda active_side
 and #$00FF
 cmp hud_side
 bne :fuel
 lda sel_unit
 cmp #$FF
 beq :fuel
 ldx cur_x
 ldy cur_y
 jsr eng_move_validate
 bcc :fuel
 lda mv_fuel_after
 and #$00FF
 sta hud_val               ; spec 25.1: the fuel after that move
:fuel
 lda hud_val
 ldx #HX_FL
 ldy #s_h_fl
 jmp hud_field3

* hud_pick_unit - the unit hud_side's line shows (see above).
* Out: A = id.
hud_pick_unit
 MX %00
 lda active_side
 and #$00FF
 cmp hud_side
 bne :remembered
 lda sel_unit
 cmp #$FF
 bne :got
 ldx cur_x
 ldy cur_y
 jsr eng_get_unit_at
 bcc :remembered
 tax
 lda unit_side,x
 and #$00FF
 cmp hud_side
 bne :remembered
 txa
 rts
:remembered
 lda hud_side
 asl
 tax
 lda hud_shown,x
:got
 rts

* hud_defaults - each side's remembered unit starts as its
* Battle Cruiser (its first unit if it has none).
hud_defaults
 MX %00
 stz hud_side
:side
 ldx hud_side
 lda side_first_id,x
 and #$00FF
 sta tmp
 sta hud_val
 lda side_units,x
 and #$00FF
 sta tmp2
:scan
 lda tmp2
 beq :store
 ldx tmp
 lda unit_class,x
 and #$00FF
 cmp #CLASS_CRUISER
 bne :more
 lda tmp
 sta hud_val
 bra :store
:more
 inc tmp
 dec tmp2
 bra :scan
:store
 lda hud_side
 asl
 tax
 lda hud_val
 sta hud_shown,x
 inc hud_side
 lda hud_side
 cmp #2
 bcc :side
 rts

* hud_field - A = value, X = x, Y = label: "SQ=15," at x on
* the line; hud_field3 three digits and no comma.
hud_field
 MX %00
 sta hud_val
 stx hud_x
 jsr lb_reset
 tya
 jsr lb_str
 lda hud_val
 jsr lb_dec2
 lda #s_comma
 jsr lb_str
 bra hud_end
hud_field3
 MX %00
 sta hud_val
 stx hud_x
 jsr lb_reset
 tya
 jsr lb_str
 lda hud_val
 jsr lb_dec3z
hud_end
 MX %00
 jsr lb_end
 ldx hud_x
* hud_text - line_buf at (X, hud_y).
hud_text
 MX %00
 lda #line_buf
 sta str_ptr
 ldy hud_y
 jmp draw_cstr

* dbg_clear / dbg_text - the border strip under the HUD, then
* the last message on it, shown once, else "B 1  MOVES 0/3
* FIRE OR MOVE", PAUSED, or GAME OVER.
dbg_clear
 MX %00
 lda #DBG_ADDR
 sta fr_addr
 lda #SCREEN_ROW
 sta fr_w
 lda #200-DBG_TOP
 sta fr_h
 lda #COL_HUD_BORDER
 jsr set_fill_colour
 jmp fill_rect

dbg_text
 MX %00
 lda #COL_BLACK
 ldx #COL_HUD_BORDER
 jsr set_colors
 lda msg_ptr
 beq :summary
 sta str_ptr
 stz msg_ptr
 bra :draw
:summary
 jsr lb_reset
 lda game_result
 and #$00FF
 beq :playing
 lda #s_game_over
 jsr lb_str
 bra :end
:playing
 lda #s_board_tag
 jsr lb_str
 lda cfg_board
 and #$00FF
 ldx #2
 jsr lb_dec
 lda #s_moves
 jsr lb_str
 lda moves_used
 and #$00FF
 ldx #1
 jsr lb_dec
 lda #s_slash
 jsr lb_str
 lda opt_moves_per_turn
 and #$00FF
 ldx #1
 jsr lb_dec
 lda #s_two_spaces
 jsr lb_str
 lda paused
 and #$00FF
 beq :phase
 lda #s_paused_tag
 jsr lb_str
 bra :end
:phase
 lda turn_phase
 and #$00FF
 asl
 tax
 lda phase_names,x
 jsr lb_str
:end
 jsr lb_end
 lda #line_buf
 sta str_ptr
:draw
 ldx #2
 ldy #DBG_Y
 jmp draw_cstr

phase_names da s_ph_any,s_ph_fire,s_ph_move

*----------------------------------------------------------
* Engine wrappers: 16-bit in, 8-bit call, 16-bit out. A
* results come back masked; carry passes straight through.
*----------------------------------------------------------
eng_turn_move
 MX %00
 sep #$30
 MX %11
 jsr turn_move
 rep #$30
 MX %00
 and #$00FF
 rts

eng_turn_fire
 MX %00
 sep #$30
 MX %11
 jsr turn_fire
 rep #$30
 MX %00
 and #$00FF
 rts

eng_move_validate
 MX %00
 sep #$30
 MX %11
 jsr move_validate
 rep #$30
 MX %00
 and #$00FF
 rts

eng_fire_validate
 MX %00
 sep #$30
 MX %11
 jsr fire_validate
 rep #$30
 MX %00
 and #$00FF
 rts

eng_fire_validate_at
 MX %00
 sep #$30
 MX %11
 jsr fire_validate_at
 rep #$30
 MX %00
 and #$00FF
 rts

eng_turn_fire_at
 MX %00
 sep #$30
 MX %11
 jsr turn_fire_at
 rep #$30
 MX %00
 and #$00FF
 rts

eng_get_unit_at
 MX %00
 sep #$30
 MX %11
 jsr get_unit_at
 rep #$30
 MX %00
 and #$00FF
 rts

eng_turn_end
 MX %00
 sep #$30
 MX %11
 jsr turn_end
 rep #$30
 MX %00
 rts

eng_turn_pause
 MX %00
 sep #$30
 MX %11
 jsr turn_pause
 rep #$30
 MX %00
 rts

eng_turn_resume
 MX %00
 sep #$30
 MX %11
 jsr turn_resume
 rep #$30
 MX %00
 rts

eng_surrender
 MX %00
 sep #$30
 MX %11
 jsr game_surrender
 rep #$30
 MX %00
 rts

eng_clock_check
 MX %00
 sep #$30
 MX %11
 jsr clock_check
 rep #$30
 MX %00
 rts

eng_events_clear
 MX %00
 sep #$30
 MX %11
 jsr events_clear
 rep #$30
 MX %00
 rts

* eng_clock_remaining - X = side -> clk_min, clk_sec.
eng_clock_remaining
 MX %00
 sep #$30
 MX %11
 jsr clock_remaining
 jsr ticks_to_mmss
 rep #$30
 MX %00
 rts

*----------------------------------------------------------
* Strings
*----------------------------------------------------------
* Lines must stay under about 40 characters to fit 320
* pixels of Shaston 8.
s_cruiser       asc 'CRUISER'
                dfb 0
s_tank          asc 'TANK'
                dfb 0
s_car           asc 'CAR'
                dfb 0
                dfb 0
s_board_tag     asc 'B'
                dfb 0
s_no_board      asc 'THAT BOARD IS NOT CAPTURED YET'
                dfb 0
s_new_board     asc 'NEW GAME  (RETURN SELECT  E END  Q QUIT)'
                dfb 0
s_move_hint     asc 'MOVE: RETURN ON A SQUARE  F FIRE  ESC'
                dfb 0
s_fire_hint     asc 'FIRE: RETURN ON A TARGET  M MOVE  ESC'
                dfb 0
s_no_unit_here  asc 'NO UNIT THERE'
                dfb 0
s_not_yours     asc 'NOT YOUR UNIT'
                dfb 0
s_moved         asc 'MOVED'
                dfb 0
s_turn_over     asc 'TURN OVER'
                dfb 0
s_paused        asc 'PAUSED  (P TO RESUME)'
                dfb 0
s_resumed       asc 'RESUMED'
                dfb 0
s_ok            asc 'OK'
                dfb 0
s_r_no_unit     asc 'NO SUCH UNIT'
                dfb 0
s_r_not_line    asc 'NOT ON A LINE FROM THE UNIT'
                dfb 0
s_r_too_far     asc 'TOO FAR'
                dfb 0
s_r_blocked     asc 'BLOCKED'
                dfb 0
s_r_no_fuel     asc 'NOT ENOUGH FUEL'
                dfb 0
s_r_no_target   asc 'NOTHING TO SHOOT THERE'
                dfb 0
s_r_range       asc 'OUT OF RANGE'
                dfb 0
s_r_no_ammo     asc 'NO AMMUNITION'
                dfb 0
s_r_already     asc 'ALREADY FIRED AT THAT UNIT THIS TURN'
                dfb 0
s_r_over        asc 'THE GAME IS OVER'
                dfb 0
s_r_not_yours   asc 'NOT YOUR UNIT'
                dfb 0
s_r_no_moves    asc 'NO MOVES LEFT THIS TURN'
                dfb 0
s_r_no_phase    asc 'NO FIRING AFTER MOVING (OPTION 2)'
                dfb 0
s_hit           asc 'HIT  '
                dfb 0
s_miss          asc 'MISS '
                dfb 0
s_destroyed     asc 'DESTROYED  '
                dfb 0
s_lt            asc ' < '
                dfb 0
s_ge            asc ' >= '
                dfb 0
s_stalemate     asc 'STALEMATE'
                dfb 0
s_wins          asc ' WINS: '
                dfb 0
s_by_cruiser    asc 'CRUISER DESTROYED'
                dfb 0
s_by_time       asc 'OUT OF TIME'
                dfb 0
s_by_surrender  asc 'SURRENDER'
                dfb 0
s_by_stalemate  asc 'STALEMATE'
                dfb 0
s_any_key       asc ' (ANY KEY)'
                dfb 0
s_game_over     asc 'GAME OVER'
                dfb 0
s_red           asc 'RED'
                dfb 0
s_black         asc 'BLACK'
                dfb 0
s_colon         asc ':'
                dfb 0
s_comma         asc ','
                dfb 0
s_mark_move     asc '#'
                dfb 0
s_mark_wait     asc '_'
                dfb 0
s_h_sq          asc 'SQ='
                dfb 0
s_h_gm          asc 'GM='
                dfb 0
s_h_am          asc 'AM='
                dfb 0
s_h_fl          asc 'FL='
                dfb 0
s_zero          asc '0'
                dfb 0
s_moves         asc '  MOVES '
                dfb 0
s_slash         asc '/'
                dfb 0
s_two_spaces    asc '  '
                dfb 0
s_paused_tag    asc 'PAUSED'
                dfb 0
s_ph_any        asc 'FIRE OR MOVE'
                dfb 0
s_ph_fire       asc 'FIRE FIRST'
                dfb 0
s_ph_move       asc 'MOVE ONLY NOW'
                dfb 0

*----------------------------------------------------------
* State (words unless noted)
*----------------------------------------------------------
cur_x      ds 2
cur_y      ds 2
mode       ds 2
sel_unit   ds 2
sel_tmp    ds 2
dirty      ds 2
quit       ds 2
over_shown ds 2
shown_side ds 2
last_sec   ds 2
hud_top    ds 2            ; top row of the status lines: HUD_TOP, or STATUS_HUD_TOP
hud_side   ds 2
hud_y      ds 2
hud_x      ds 2
hud_val    ds 2
hud_shown  ds 4            ; each side's remembered unit, a word per side
msg_ptr    ds 2
key_code   ds 2
key_vec    ds 2
hud_unit   ds 2
cx         ds 2
cy         ds 2
hx         ds 2
hy         ds 2
dir        ds 2
dist       ds 2
uid        ds 2
side_tmp   ds 2
thick      ds 2
box_addr   ds 2
fr_addr    ds 2
fr_w       ds 2
fr_h       ds 2
fr_col     ds 2
tmp        ds 2
tmp2       ds 2
tmp_a      ds 2
tmp_h      ds 2
glyph_buf  ds 2
msg_buf    ds 64
