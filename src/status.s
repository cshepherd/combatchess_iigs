*----------------------------------------------------------
* status.s - The army status display (spec section 28, the
* original's SELECT screen), for the debug board in GAME.
*
* PUT into game.s after dbg.s (it uses its fill_rect, key
* codes and HUD) and before common.s. Native 16-bit like
* dbg.s.
*
* The original: SELECT shows the side to move's roster,
* SELECT again the opponent's, SELECT again the board, and
* the clock keeps running throughout (measured on the Atari).
* Here TAB does what SELECT did and ESC goes straight back.
*
* Layout follows the captured screen: the STATUS plaque (the
* original's picture, src/status_art.s, its tank painted red
* or black by side through palette slot STATUS_SLOT_TANK),
* then "**STATUS FOR RED" with column heads FUEL AMMO GAME
* SQR / DMG DMG, then nine fixed rows in class order, a
* cruiser, three tanks and five armoured cars: a unit's
* fuel, ammo, hit points and terrain hit points, or the name
* alone when the army never had that unit (captured: Red's
* third TANK and fifth ARMOURED CAR rows). A destroyed unit
* is the same: the original deletes its record and closes the
* gap, so the survivors of a class fill the first rows and the
* bare names follow (captured, tools/atari_destroyed_capture.py).
*----------------------------------------------------------
STATUS_SLOT_TANK = 14      ; repainted per side; the board itself never uses it
STATUS_TANK_PAL  = STATUS_SLOT_TANK*2+$E19E00 ; its palette entry (Merlin: left to right)
STATUS_TANK_RED  = $0520   ; Atari $34, the hull brown measured from the capture
STATUS_TANK_BLK  = $0000
STATUS_SLOT_BG   = 8       ; grey, the bitmap's background slot
STATUS_INK       = COL_BLACK
STATUS_ART_ROWS  = 80      ; plaque height (was in status_art.s, now bank-loaded)
STATUS_HEAD_Y    = 90
STATUS_NET_Y     = 100     ; the net opponent line, between the header and the roster
STATUS_ROW_Y     = 110
STATUS_ROW_STEP  = 9
STATUS_HUD_TOP   = 184     ; the two status lines sit at the very bottom here

VIEW_BOARD = 0
VIEW_OWN   = 1
VIEW_OTHER = 2

* Columns from the original's 40-column text (8 pixels a
* column; reference/raw/status/): the name at column 1, the
* heads FUEL AMMO GAME SQR at 21 26 31 36 with DMG DMG under
* the last two at 32 and 36, and the numbers right-aligned at
* 22 27 33 37: fuel three digits, the rest two with a leading
* zero ("08", "09"). Fuel below 100 is UNVERIFIED; padded the
* same way here.
X_NAME   = 8
X_H_FUEL = 168
X_H_AMMO = 208
X_H_GAME = 248
X_H_SQR  = 288
X_H_DMG1 = 256
X_N_FUEL = 176
X_N_AMMO = 216
X_N_GAME = 264
X_N_SQR  = 296

*----------------------------------------------------------
* status_toggle - TAB: board -> own -> other -> board.
*----------------------------------------------------------
status_toggle
 MX %00
 lda status_view
 inc
 cmp #VIEW_OTHER+1
 bcc :set
 lda #VIEW_BOARD
:set
 jmp status_set_view

* status_close - ESC: back to the board.
status_close
 MX %00
 lda #VIEW_BOARD
* status_set_view - A = VIEW_*; picks the side shown and
* where the status lines live, and asks for a redraw.
status_set_view
 MX %00
 sta status_view
 lda #HUD_TOP
 sta hud_top
 lda status_view
 beq :board
 lda #STATUS_HUD_TOP
 sta hud_top
 lda active_side
 and #$00FF
 ldx status_view
 cpx #VIEW_OWN
 beq :side
 eor #1
:side
 sta status_side
:board
 lda STATUS_SLOT_TANK*2+dbg_palette ; the board's own slot back
 stal STATUS_TANK_PAL
 lda #1
 sta dirty
 rts

*----------------------------------------------------------
* status_draw - The whole status screen for status_side.
*----------------------------------------------------------
status_draw
 MX %00
* the tank's colour by side: red or black
 lda status_side
 beq :red
 lda #STATUS_TANK_BLK
 bra :paint
:red
 lda #STATUS_TANK_RED
:paint
 stal STATUS_TANK_PAL
* grey below the picture, then the picture itself
 lda #STATUS_ART_ROWS*SCREEN_ROW+SCREEN
 sta fr_addr
 lda #SCREEN_ROW
 sta fr_w
 lda #200-STATUS_ART_ROWS
 sta fr_h
 lda #STATUS_SLOT_BG
 jsr set_fill_colour
 jsr fill_rect
 ldx #0                    ; the plaque sits at STATUS_ART_BANK/0000 (cc.s loaded it
 ldy #SCREEN               ; there at boot); block-move it straight to the screen
 lda #STATUS_ART_ROWS*SCREEN_ROW-1
 mvn STATUS_ART_BANK,$E1
 phk
 plb
* header
 lda #STATUS_INK
 ldx #STATUS_SLOT_BG
 jsr set_colors
 jsr lb_reset
 lda #s_st_for
 jsr lb_str
 lda status_side
 asl
 tax
 lda side_names,x
 jsr lb_str
 jsr lb_end
 lda #line_buf
 sta str_ptr
 ldx #X_NAME
 ldy #STATUS_HEAD_Y
 jsr draw_cstr
 jsr st_net_line           ; in a net game: VS <opponent>  (CONNECTED / RECONNECTING)
 ldx #0
:head
 lda st_heads,x            ; string, x, y; a zero string ends
 beq :rows
 sta str_ptr
 phx
 lda st_heads+4,x
 tay
 lda st_heads+2,x
 tax
 jsr draw_cstr
 plx
 inx
 inx
 inx
 inx
 inx
 inx
 bra :head
:rows
* nine rows: which class each row wants, and its ordinal
 stz st_row
:row
 ldx st_row
 lda st_row_class,x
 and #$00FF
 sta st_class
 lda st_row_nth,x
 and #$00FF
 sta st_nth
 lda #STATUS_ROW_Y
 ldx st_row
:ystep
 beq :ygot
 clc
 adc #STATUS_ROW_STEP
 dex
 bra :ystep
:ygot
 sta st_y
 lda st_class
 asl
 tax
 lda st_class_names,x
 sta str_ptr
 ldx #X_NAME
 ldy st_y
 jsr draw_cstr
 jsr st_find_unit          ; carry set, A = id of the nth living unit of that class
 bcc :next
 sta st_unit
 tax
 lda unit_fuel,x
 and #$00FF
 ldx #X_N_FUEL
 ldy #3
 jsr st_num
 ldx st_unit
 lda unit_ammo,x
 and #$00FF
 ldx #X_N_AMMO
 ldy #2
 jsr st_num
 ldx st_unit
 lda unit_hp,x
 and #$00FF
 ldx #X_N_GAME
 ldy #2
 jsr st_num
 ldx st_unit
 lda unit_terr_hp,x
 and #$00FF
 ldx #X_N_SQR
 ldy #2
 jsr st_num
:next
 inc st_row
 lda st_row
 cmp #9
 bcs :rows_done
 jmp :row
:rows_done
 jmp draw_hud              ; both status lines at the bottom, as the original

*----------------------------------------------------------
* st_net_line - in a network game, one line under the header:
* the opponent's name and whether the link is live or the
* opponent has dropped and we are waiting for them. Nothing in
* a local hot-seat game. Native 16-bit.
*----------------------------------------------------------
st_net_line
 MX %00
 jsr is_net_mode
 bcc :out                  ; local game: no opponent
 lda #STATUS_INK
 ldx #STATUS_SLOT_BG
 jsr set_colors
 jsr lb_reset
 lda #s_st_vs
 jsr lb_str
 lda #nm_name              ; opponent name, NUL-padded from MATCH_START
 jsr lb_str
 lda #s_st_sp2
 jsr lb_str
 lda nl_opp_lost
 and #$00FF
 beq :live
 lda #s_st_recon
 bra :state
:live
 lda #s_st_live
:state
 jsr lb_str
 jsr lb_end
 lda #line_buf
 sta str_ptr
 ldx #X_NAME
 ldy #STATUS_NET_Y
 jmp draw_cstr
:out
 rts

* st_num - A = value, X = x, Y = width: the number in that
* many digits with leading zeros, on the current row.
st_num
 MX %00
 stx st_x
 sty st_w
 pha
 lda #line_buf
 sta str_ptr
 pla
 ldx st_w
 jsr fmt_u16               ; right-justified, space padded
 ldx st_w
 sep #$20
 MX %10
 lda #0
 sta line_buf,x
 ldx #0
:pad
 lda line_buf,x
 cmp #' '
 bne :padded
 lda #'0'
 sta line_buf,x
 inx
 bra :pad
:padded
 rep #$20
 MX %00
 lda #line_buf
 sta str_ptr
 ldx st_x
 ldy st_y
 jmp draw_cstr

* st_find_unit - the st_nth living unit (1-based) of class
* st_class on status_side, in id order, so the survivors fill
* the first rows of their class as the original's compacted
* unit table does. Carry set, A = id.
st_find_unit
 MX %00
 lda status_side
 and #$00FF
 sta st_left               ; our side (0/1), reused as the side filter
 lda st_nth
 sta st_count
 stz st_id                 ; slot index; scan every slot so the roster works
:scan                      ; whatever id order the units use (local: RED 0-10,
 lda st_id                 ; BLACK 11-21; net: packed by the server), filtering
 cmp #MAX_UNITS            ; by side rather than a fixed per-side id range
 bcs :none
 tax
 inc st_id
 lda unit_flags,x
 and #$0080
 beq :scan                 ; empty / destroyed slot
 lda unit_side,x
 and #$00FF
 cmp st_left
 bne :scan                 ; the other side
 lda unit_class,x
 and #$00FF
 cmp st_class
 bne :scan                 ; a different class
 dec st_count
 bne :scan
 txa
 sec
 rts
:none
 clc
 rts

st_row_class dfb CLASS_CRUISER,CLASS_TANK,CLASS_TANK,CLASS_TANK
             dfb CLASS_CAR,CLASS_CAR,CLASS_CAR,CLASS_CAR,CLASS_CAR
st_row_nth   dfb 1,1,2,3,1,2,3,4,5
st_class_names da s_st_cruiser,s_st_tank,s_st_car

s_st_for     asc '**STATUS FOR '
             dfb 0
s_st_fuel    asc 'FUEL'
             dfb 0
s_st_ammo    asc 'AMMO'
             dfb 0
s_st_game    asc 'GAME'
             dfb 0
s_st_sqr     asc 'SQR'
             dfb 0
s_st_dmg     asc 'DMG'
             dfb 0
s_st_vs      asc 'VS '
             dfb 0
s_st_sp2     asc '  '
             dfb 0
s_st_live    asc '(CONNECTED)'
             dfb 0
s_st_recon   asc '(RECONNECTING)'
             dfb 0

* Column heads: string, x, y.
st_heads da s_st_fuel,X_H_FUEL,STATUS_HEAD_Y
         da s_st_ammo,X_H_AMMO,STATUS_HEAD_Y
         da s_st_game,X_H_GAME,STATUS_HEAD_Y
         da s_st_sqr,X_H_SQR,STATUS_HEAD_Y
         da s_st_dmg,X_H_DMG1,STATUS_HEAD_Y+STATUS_ROW_STEP
         da s_st_dmg,X_H_SQR,STATUS_HEAD_Y+STATUS_ROW_STEP
         da 0
s_st_cruiser asc 'BATTLE CRUISER'
             dfb 0
s_st_tank    asc 'TANK'
             dfb 0
s_st_car     asc 'ARMOURED CAR'
             dfb 0

status_view ds 2
status_side ds 2
st_row      ds 2
st_class    ds 2
st_nth      ds 2
st_y        ds 2
st_x        ds 2
st_w        ds 2
st_unit     ds 2
st_id       ds 2
st_left     ds 2
st_count    ds 2
