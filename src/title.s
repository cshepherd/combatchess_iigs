*----------------------------------------------------------
* TITLE - Combat Chess title screen and options page.
*
* SYS file loaded at $2000 by CC.SYSTEM. The upper half is
* the Atari original's tank plaque carried over as a bitmap
* (src/title_art.s, generated from the capture); the text
* under it and the whole options page are QuickDraw II text,
* laid out like the original's screens.
*
* Title keys: RETURN begins the game, O opens the options
* page, T runs the rules self-tests.
* Options page: O or the down arrow moves to the next field
* and the up arrow back; S or the right arrow steps the field
* to its next value, wrapping as the original does, and the
* left arrow steps back; RETURN or ESC returns to the title.
* The options live in page $11 (shared.s cfg_*) for GAME.
*
* Native mode, 16-bit A/X/Y throughout (like common.s).
*----------------------------------------------------------

  ORG $2000
  MX %11

  put shared

* NinjaTracker+ plays the title music. cc.s load_res copies the
* player into bank $03 at boot and the TITLENTP module into bank
* $04; the player's three-JMP entry table sits at its base.
NinjaTrackerPlus = $030000
NTPprepare       = NinjaTrackerPlus
NTPplay          = NinjaTrackerPlus+3
NTPstop          = NinjaTrackerPlus+6
NTP_MODULE_HI    = $0004          ; high word of the module pointer $04/0000

  lda tb_inited
  bne :ready
  jsr toolbox_init
  inc tb_inited
:ready
  lda cfg_valid
  cmp #CFG_MAGIC
  beq :cfg_ok
  jsr cfg_defaults
:cfg_ok
  clc
  xce
  rep $30
  MX %00
  jsr shr_init
  lda #TEXT_OPAQUE
  jsr set_text_mode         ; inverse fields need the cell painted
  jsr title_palette_load
  lda #10                   ; light gray border to match the grey plaque ground ($0AAA)
  jsr set_border
  jsr ntp_start             ; start the title music (silent if absent)
  lda ntp_playing           ; a failed network setup returns here with IRQs masked;
  beq :show                 ; once the NTP DOC handler is up it is safe to unmask
  cli                       ; (a no-op on the normal, already-enabled entry)
:show
  jsr draw_title
:key
  jsr wait_key
  jsr fold_upper
  cmp #KEY_RETURN
  beq :game
  cmp #'O'
  beq :options
  cmp #'N'
  beq :netbot
  cmp #'H'
  beq :nethuman
 do INCLUDE_TESTS
  cmp #'T'
  beq :tests
 fin
  bra :key
:options
  jsr options_page
  bra :show
:netbot
  ldx #0                    ; N: play the server's bot
  bra :netgame
:nethuman
  ldx #1                    ; H: wait for a second human
:netgame
  lda #1                    ; request a network game; GAME connects to the server
  sta net_mode              ; 16-bit A: this store also writes the adjacent byte
  stx net_human             ; ($1131), so set net_human AFTER it, not before
  bra :launch
:game
  stz net_mode              ; a local hot-seat game
:launch
  jsr ntp_stop              ; hand the DOC back to the Sound Tool
  sec
  xce
  MX %11
  jmp LAUNCH_GAME
 do INCLUDE_TESTS
:tests
  MX %00
  jsr ntp_stop
  sec
  xce
  MX %11
  jmp LAUNCH_TEST
 fin

*----------------------------------------------------------
* ntp_start / ntp_stop - title music via NinjaTracker+.
* Native 16-bit. ntp_start prepares the module in bank $04
* and loops it; a bad or absent module (NTPprepare returns
* carry) just leaves the title silent. ntp_stop, called on
* every exit to GAME or TEST, restores the sound interrupt
* the Sound Tool installed so in-game _FFStartSound works.
* ntp_playing gates the stop so it never runs without a
* matching prepare (which would restore a stale vector).
*----------------------------------------------------------
  MX %00
ntp_start
  ldx #$0000                ; module pointer low word
  ldy #NTP_MODULE_HI        ; module pointer high word -> $04/0000
  lda #$0000                ; normal: two oscillators per track
  jsl NTPprepare
  bcs :nomusic
  lda #$0000                ; loop the song
  jsl NTPplay
  lda #$0001
  sta ntp_playing
  rts
:nomusic
  stz ntp_playing
  rts

ntp_stop
  lda ntp_playing
  beq :done
  jsl NTPstop
  stz ntp_playing
:done
  rts

ntp_playing dw 0

KEY_LEFT   = $08
KEY_RIGHT  = $15
KEY_UP     = $0B
KEY_DOWN   = $0A
KEY_RETURN = $0D
KEY_ESC    = $1B
KEY_SPACE  = $20

* Palette slots: 0-4 from the plaque (0 = the grey ground it
* shares with the text area, 1 hull brown, 2-3 yellow, 4 the
* plaque's blue), 5 black ink, 15 white.
COL_BG     = 0
COL_YELLOW = 2
COL_BLUE   = 4
COL_INK    = 5

* Text styles for draw_line: fg, bg palette slots.
STYLE_NORMAL  = 0          ; black on grey
STYLE_INVERSE = 1          ; grey on black: the original's highlighted key names
STYLE_HEADING = 2          ; blue on grey
style_tab dw COL_INK,COL_BG, COL_BG,COL_INK, COL_BLUE,COL_BG

SCREEN_ROW = 160
SCREEN     = $2000

*----------------------------------------------------------
* fold_upper - A = key -> upper case for letters.
*----------------------------------------------------------
fold_upper
 MX %00
 cmp #'a'
 bcc :done
 cmp #'z'+1
 bcs :done
 and #$00DF
:done
 rts

*----------------------------------------------------------
* title_palette_load - plaque colours into slots 0-4, black
* into 5, white into 15 (shr_init loaded the standard set).
*----------------------------------------------------------
title_palette_load
 MX %00
 ldx #8
:pal
 lda title_palette,x
 stal $E19E00,x
 dex
 dex
 bpl :pal
 lda #$0000
 stal $E19E00+10
 lda #$0FFF
 stal $E19E00+30
 rts

*----------------------------------------------------------
* draw_title - the plaque, a yellow rule, and the text.
*----------------------------------------------------------
draw_title
 MX %00
 jsr clear_grey
 jsr blit_plaque
 lda #$2222                ; two rows of slot 2, the yellow rule
 ldx #DIVIDER_ROW*SCREEN_ROW+SCREEN
 ldy #2
 jsr fill_rows
 lda #seg_avalon
 ldx #$FFFF
 ldy #118
 jsr draw_line
 lda #seg_copy
 ldx #$FFFF
 ldy #134
 jsr draw_line
 lda #seg_port
 ldx #$FFFF
 ldy #144
 jsr draw_line
 lda #seg_push1
 ldx #$FFFF
 ldy #162
 jsr draw_line
 lda #seg_push2
 ldx #$FFFF
 ldy #172
 jsr draw_line
 do INCLUDE_TESTS
 lda #seg_push3
 ldx #$FFFF
 ldy #182
 jsr draw_line
 else
 lda #seg_push_net
 ldx #$FFFF
 ldy #182
 jsr draw_line
 fin
 lda #seg_by
 ldx #$FFFF
 ldy #196
 jmp draw_line

DIVIDER_ROW = 98

* blit_plaque - the 96-row bitmap to the top of the screen
* in one block move.
blit_plaque
 MX %00
 ldx #title_art
 ldy #SCREEN
 lda #TITLE_ART_ROWS*SCREEN_ROW-1
 mvn $00,$E1
 phk
 plb                       ; MVN left the data bank at $E1
 rts

* clear_grey - every pixel row to slot 0.
clear_grey
 MX %00
 lda #$0000
 ldx #SCREEN
 ldy #200
 jmp fill_rows

* fill_rows - A = word pattern, X = screen offset of the
* first row, Y = rows.
fill_rows
 MX %00
 sta fr_pat
 stx fr_off
 sty fr_rows
:row
 ldx fr_off
 ldy #80
 lda fr_pat
:word
 stal $E10000,x
 inx
 inx
 dey
 bne :word
 lda fr_off
 clc
 adc #SCREEN_ROW
 sta fr_off
 dec fr_rows
 bne :row
 rts

*----------------------------------------------------------
* draw_line - Draw a list of text segments on one baseline.
* In:  A = segment list, Y = baseline, X = left x, or $FFFF
*      to centre the whole line.
* A list is entries of "da string" then "dfb style", ended
* by a zero word. A style byte with bit 7 set is a STYLE_*
* value; otherwise it is an options field number, drawn
* inverse while that field is the current one.
*----------------------------------------------------------
draw_line
 MX %00
 sta rptr
 sty dl_y
 stx dl_x
 cpx #$FFFF
 bne draw_segs
 stz dl_w
 ldy #0
:measure
 lda (rptr),y
 beq :centre
 phy
 jsr cstr_width
 ply
 clc
 adc dl_w
 sta dl_w
 iny
 iny
 iny
 bra :measure
:centre
 lda #320
 sec
 sbc dl_w
 lsr
 sta dl_x
* draw_segs - draw the segment list at rptr from dl_x, dl_y.
draw_segs
 ldy #0
:seg
 lda (rptr),y
 beq :done
 sta dl_str
 iny
 iny
 lda (rptr),y
 and #$00FF
 iny
 phy
 jsr set_style
 lda dl_str
 sta str_ptr
 ldx dl_x
 ldy dl_y
 jsr draw_cstr
 lda dl_str
 jsr cstr_width
 clc
 adc dl_x
 sta dl_x
 ply
 bra :seg
:done
 rts

* set_style - A = style byte (see draw_line) -> pen colours.
set_style
 MX %00
 bit #$0080
 bne :literal
 cmp cur_field
 beq :inverse
 lda #STYLE_NORMAL
 bra :apply
:inverse
 lda #STYLE_INVERSE
 bra :apply
:literal
 and #$007F
:apply
 asl
 asl
 tax
 lda style_tab+2,x
 pha
 lda style_tab,x
 plx
 jmp set_colors

*----------------------------------------------------------
* options_page - Show and edit the options until RETURN or
* ESC. Layout follows the original's options screen.
*----------------------------------------------------------
options_page
 MX %00
 stz cur_field
:redraw
 jsr clear_grey
 jsr fmt_fields
 lda #seg_opt_head
 ldx #$FFFF
 ldy #20
 jsr draw_line
 lda #seg_board
 ldx #8
 ldy #44
 jsr draw_line
 lda #seg_tanks
 ldx #8
 ldy #64
 jsr draw_line
 lda #seg_cars
 ldx #8
 ldy #74
 jsr draw_line
 lda #seg_first
 ldx #8
 ldy #94
 jsr draw_line
 lda #seg_cpu
 ldx #8
 ldy #104
 jsr draw_line
 lda #seg_time
 ldx #8
 ldy #124
 jsr draw_line
 lda #seg_moves
 ldx #8
 ldy #144
 jsr draw_line
 lda #seg_botlevel
 ldx #8
 ldy #154
 jsr draw_line
 lda #seg_help1
 ldx #8
 ldy #168
 jsr draw_line
 lda #seg_help2
 ldx #8
 ldy #178
 jsr draw_line
 lda #seg_help3
 ldx #8
 ldy #188
 jsr draw_line
 lda #seg_help4
 ldx #8
 ldy #198
 jsr draw_line
:key
 jsr wait_key
 jsr fold_upper
 cmp #KEY_RETURN
 beq :leave
 cmp #KEY_ESC
 beq :leave
 cmp #'O'
 beq :next_field
 cmp #KEY_DOWN
 beq :next_field
 cmp #KEY_SPACE
 beq :next_field
 cmp #KEY_UP
 beq :prev_field
 cmp #'S'
 beq :next_value
 cmp #KEY_RIGHT
 beq :next_value
 cmp #KEY_LEFT
 beq :prev_value
 bra :key
:next_field
 lda cur_field
 sta df_old
 inc
 cmp #NUM_FIELDS
 bcc :set_field
 lda #0
:set_field
 sta cur_field
 lda df_old
 jsr draw_field           ; the old field un-highlights
 lda cur_field
 jsr draw_field           ; the new field highlights
 jmp :key
:prev_field
 lda cur_field
 sta df_old
 dec
 bpl :set_field
 lda #NUM_FIELDS-1
 bra :set_field
:next_value
 lda #1
 jsr step_field
 jsr fmt_fields           ; reformat the value buffers (no drawing)
 lda cur_field
 jsr draw_field           ; redraw just this field's value in place
 jmp :key
:prev_value
 lda #$FFFF
 jsr step_field
 jsr fmt_fields
 lda cur_field
 jsr draw_field
 jmp :key
:leave
 rts

*----------------------------------------------------------
* draw_field - redraw one option field's value in place: A =
* field number. Walks its line's segments to the value's
* pixel x, clears from there to the end of the line, and
* redraws the value and whatever follows it on the line (so a
* value that changes width, e.g. the time or the side name,
* shifts the rest correctly). Highlighted if it is cur_field.
* Native 16-bit.
*----------------------------------------------------------
draw_field
 MX %00
 and #$00FF
 sta df_field
 asl
 tax
 lda opt_field_seg,x
 sta rptr
 ldx df_field
 lda opt_field_y,x
 and #$00FF
 sta dl_y
 lda #8
 sta dl_x
 ldy #0
:walk
 lda (rptr),y
 sta dl_str
 iny
 iny
 lda (rptr),y
 and #$00FF
 cmp df_field
 beq :found
 iny
 phy
 lda dl_str
 jsr cstr_width
 clc
 adc dl_x
 sta dl_x
 ply
 bra :walk
:found
 dey
 dey
 tya
 clc
 adc rptr
 sta rptr                 ; point rptr at the value segment (Y still valid)
 jsr opt_clear            ; erase from the value's x to the line end (clobbers Y)
 jmp draw_segs

*----------------------------------------------------------
* opt_clear - erase dl_x..320 for the option line at dl_y,
* over the glyph rows, to the grey background (slot 0).
*----------------------------------------------------------
opt_clear
 MX %00
 lda dl_x
 lsr
 sta oc_byte              ; start byte (2 px each)
 lda #160
 sec
 sbc oc_byte
 sta oc_cnt               ; bytes to the row end
 lda dl_y
 sec
 sbc #8
 sta oc_row               ; top glyph row
 lda #10
 sta oc_rows
:row
 lda oc_row
 asl
 asl
 asl
 asl
 asl                      ; row * 32
 sta oc_tmp
 lda oc_row
 asl
 asl
 asl
 asl
 asl
 asl
 asl                      ; row * 128
 clc
 adc oc_tmp               ; row * 160
 clc
 adc #SCREEN
 clc
 adc oc_byte
 tax
 sep #$20
 MX %10
 ldy oc_cnt
 lda #0
:b
 stal $E10000,x
 inx
 dey
 bne :b
 rep #$20
 MX %00
 inc oc_row
 dec oc_rows
 bne :row
 rts

* step_field - add A (+1 or -1) to the current field's value,
* wrapping between its minimum and maximum.
step_field
 MX %00
 sta sf_delta
 lda cur_field
 asl
 asl
 tax
 lda field_tab,x
 sta rptr
 lda field_tab+2,x
 and #$00FF
 sta sf_min
 lda field_tab+3,x
 and #$00FF
 sta sf_max
 sep #$20
 MX %10
 lda (rptr)
 rep #$20
 MX %00
 and #$00FF
 clc
 adc sf_delta
 cmp sf_min
 bmi :wrap_high            ; went below the minimum (or negative)
 cmp sf_max
 beq :store
 bcc :store
 lda sf_min                ; past the maximum
 bra :store
:wrap_high
 lda sf_max
:store
 sep #$20
 MX %10
 sta (rptr)
 rep #$20
 MX %00
 rts

* cfg address, minimum, maximum, in the original's cursor order.
NUM_FIELDS = 12
* Per field (0..11): the segment list its value lives on, and
* the line's baseline y. Used by draw_field.
opt_field_seg
 da seg_board,seg_tanks,seg_tanks,seg_cars,seg_cars,seg_first
 da seg_cpu,seg_time,seg_time,seg_moves,seg_moves,seg_botlevel
opt_field_y
 dfb 44,64,64,74,74,94,104,124,124,144,144,154

field_tab
 da cfg_board
 dfb 1,10
 da cfg_tanks_black
 dfb 0,3
 da cfg_tanks_red
 dfb 0,3
 da cfg_cars_black
 dfb 0,5
 da cfg_cars_red
 dfb 0,5
 da cfg_first
 dfb 0,1
 da cfg_computer
 dfb 0,3
 da cfg_time_black
 dfb 1,30
 da cfg_time_red
 dfb 1,30
 da cfg_moves
 dfb 1,20
 da cfg_shoot
 dfb 1,2
 da cfg_bot_level
 dfb CFG_BOT_RANDOM,CFG_BOT_MAX

*----------------------------------------------------------
* fmt_fields - the numbers and names into the segment
* buffers before the page is drawn.
*----------------------------------------------------------
fmt_fields
 MX %00
 lda cfg_board
 and #$00FF
 ldx #nb_board
 jsr fmt_2z
 lda cfg_tanks_black
 and #$00FF
 ldx #nb_tanks_b
 jsr fmt_num
 lda cfg_tanks_red
 and #$00FF
 ldx #nb_tanks_r
 jsr fmt_num
 lda cfg_cars_black
 and #$00FF
 ldx #nb_cars_b
 jsr fmt_num
 lda cfg_cars_red
 and #$00FF
 ldx #nb_cars_r
 jsr fmt_num
 lda cfg_time_black
 and #$00FF
 ldx #nb_time_b
 jsr fmt_num
 lda cfg_time_red
 and #$00FF
 ldx #nb_time_r
 jsr fmt_num
 lda cfg_moves
 and #$00FF
 ldx #nb_moves
 jsr fmt_2z
 lda cfg_shoot
 and #$00FF
 ldx #nb_shoot
 jsr fmt_num
 lda cfg_first
 and #$00FF
 asl
 tax
 lda side_start_names,x
 sta seg_first             ; the list's first string pointer
 lda cfg_computer
 and #$00FF
 asl
 tax
 lda cpu_names,x
 sta seg_cpu
 lda cfg_bot_level
 and #$00FF
 asl
 tax
 lda bot_level_names,x
 sta seg_botlevel+3        ; the value word after the "NETWORK BOT: " prefix
 rts

* fmt_num - A = value (0-99) as 1 or 2 digits into the
* 3-byte buffer at X, terminated.
fmt_num
 MX %00
 stx fn_buf
 cmp #10
 bcs :two
 ldy #1
 bra :fmt
:two
 ldy #2
:fmt
 sty fn_len
 pha
 lda fn_buf
 sta str_ptr
 pla
 ldx fn_len
 jsr fmt_u16
 lda fn_buf
 clc
 adc fn_len
 tax
 sep #$20
 MX %10
 lda #0
 sta |0,x
 rep #$20
 MX %00
 rts

* fmt_2z - A = value (0-99) as two digits with a leading
* zero, as the original shows the board and moves.
fmt_2z
 MX %00
 cmp #10
 bcs fmt_num
 stx fn_buf
 pha
 sep #$20
 MX %10
 lda #'0'
 sta |0,x
 rep #$20
 MX %00
 pla
 inx
 jmp fmt_num

side_start_names da s_red5,s_black5
cpu_names        da s_cpu0,s_cpu1,s_cpu2,s_cpu3
bot_level_names  da s_bot_random,s_bot_greedy,s_bot_chooser

*----------------------------------------------------------
* Segment lists (da string, dfb style; zero word ends).
* Styles: $80+STYLE_* literal, or a field number.
*----------------------------------------------------------
seg_avalon
 da s_avalon
 dfb $80+STYLE_HEADING
 da 0
seg_copy
 da s_copy
 dfb $80+STYLE_NORMAL
 da 0
seg_port
 da s_port
 dfb $80+STYLE_NORMAL
 da 0
seg_push1
 da s_push
 dfb $80+STYLE_NORMAL
 da s_key_return
 dfb $80+STYLE_INVERSE
 da s_push1b
 dfb $80+STYLE_NORMAL
 da 0
seg_push2
 da s_push
 dfb $80+STYLE_NORMAL
 da s_key_o
 dfb $80+STYLE_INVERSE
 da s_push2b
 dfb $80+STYLE_NORMAL
 da 0
seg_push3
 da s_orpush
 dfb $80+STYLE_NORMAL
 da s_key_t
 dfb $80+STYLE_INVERSE
 da s_push3b
 dfb $80+STYLE_NORMAL
 da 0
seg_push_net
 da s_push
 dfb $80+STYLE_NORMAL
 da s_key_n
 dfb $80+STYLE_INVERSE
 da s_net_mid
 dfb $80+STYLE_NORMAL
 da s_key_h
 dfb $80+STYLE_INVERSE
 da s_net_b
 dfb $80+STYLE_NORMAL
 da 0
seg_by
 da s_by
 dfb $80+STYLE_NORMAL
 da 0

seg_opt_head
 da s_opt_head
 dfb $80+STYLE_HEADING
 da 0
seg_board
 da s_board
 dfb $80+STYLE_NORMAL
 da nb_board
 dfb 0
 da 0
seg_tanks
 da s_tanks
 dfb $80+STYLE_NORMAL
 da nb_tanks_b
 dfb 1
 da s_comma_red
 dfb $80+STYLE_NORMAL
 da nb_tanks_r
 dfb 2
 da 0
seg_cars
 da s_cars
 dfb $80+STYLE_NORMAL
 da nb_cars_b
 dfb 3
 da s_comma_red
 dfb $80+STYLE_NORMAL
 da nb_cars_r
 dfb 4
 da 0
seg_first
 da 0                      ; patched: s_red5 or s_black5
 dfb 5
 da s_start_first
 dfb $80+STYLE_NORMAL
 da 0
seg_cpu
 da 0                      ; patched: one of cpu_names
 dfb 6
 da 0
seg_time
 da s_time
 dfb $80+STYLE_NORMAL
 da nb_time_b
 dfb 7
 da s_comma_red
 dfb $80+STYLE_NORMAL
 da nb_time_r
 dfb 8
 da 0
seg_moves
 da s_moves
 dfb $80+STYLE_NORMAL
 da nb_moves
 dfb 9
 da s_shoot
 dfb $80+STYLE_NORMAL
 da nb_shoot
 dfb 10
 da 0
seg_botlevel
 da s_bot_pre
 dfb $80+STYLE_NORMAL
 da 0                      ; patched (seg_botlevel+3): the level name
 dfb 11
 da 0
seg_help1
 da s_help1
 dfb $80+STYLE_NORMAL
 da 0
seg_help2
 da s_help2
 dfb $80+STYLE_NORMAL
 da 0
seg_help3
 da s_help3
 dfb $80+STYLE_NORMAL
 da 0
seg_help4
 da s_help4
 dfb $80+STYLE_NORMAL
 da 0

s_avalon     asc 'AVALON HILL GAME COMPANY'
             dfb 0
s_copy       asc 'ORIGINAL ATARI GAME COPYRIGHT 1984'
             dfb 0
s_port       asc 'APPLE IIGS PORT 2026 [cCc]'
             dfb 0
s_push       asc 'PUSH '
             dfb 0
s_orpush     asc 'OR PUSH '
             dfb 0
s_key_return asc 'RETURN'
             dfb 0
s_key_o      asc 'O'
             dfb 0
s_key_t      asc 'T'
             dfb 0
s_push1b     asc ' TO BEGIN GAME, OR'
             dfb 0
s_push2b
             do INCLUDE_TESTS
             asc ' TO VIEW AND CHANGE OPTIONS,'
             else
             asc ' TO VIEW AND CHANGE OPTIONS.'
             fin
             dfb 0
s_push3b     asc ' FOR THE RULES SELF-TESTS.'
             dfb 0
s_key_n      asc 'N'
             dfb 0
s_net_mid    asc ' VS BOT OR '
             dfb 0
s_key_h      asc 'H'
             dfb 0
s_net_b      asc ' VS HUMAN (NET).'
             dfb 0
s_by         asc 'GAME BY LOU MATTSFIELD'
             dfb 0

s_opt_head   asc '*** CURRENT PLAY OPTIONS ***'
             dfb 0
s_board      asc 'GAME BOARD IS #'
             dfb 0
s_tanks      asc 'TANKS:          BLACK '
             dfb 0
s_cars       asc 'ARMORED CARS:   BLACK '
             dfb 0
s_comma_red  asc ', RED '
             dfb 0
s_red5       asc 'RED  '
             dfb 0
s_black5     asc 'BLACK'
             dfb 0
s_start_first asc ' WILL START FIRST'
             dfb 0
s_cpu0       asc 'COMPUTER WILL PLAY BLACK'
             dfb 0
s_cpu1       asc 'COMPUTER WILL PLAY RED'
             dfb 0
s_cpu2       asc 'COMPUTER WILL NOT PLAY'
             dfb 0
s_cpu3       asc 'COMPUTER WILL PLAY BOTH'
             dfb 0
s_time       asc 'TIME LIMITS (MINUTES): BLACK '
             dfb 0
s_moves      asc 'MOVES PER TURN IS '
             dfb 0
s_shoot      asc '; SHOOT OPTION #'
             dfb 0
s_bot_pre    asc 'NETWORK BOT: '
             dfb 0
s_bot_random asc 'RANDOM'
             dfb 0
s_bot_greedy asc 'GREEDY'
             dfb 0
s_bot_chooser asc 'CHOOSER'
             dfb 0
s_help1      asc 'O OR DOWN: NEXT FIELD     UP: PREVIOUS'
             dfb 0
s_help2      asc 'S OR RIGHT: NEXT VALUE    LEFT: PREVIOUS'
             dfb 0
s_help3      asc 'RETURN: BACK TO THE TITLE'
             dfb 0
s_help4      asc 'THE COMPUTER PLAYS THE CHOSEN SIDE(S)'
             dfb 0

* Number buffers: up to two digits and a terminator.
nb_board   ds 3
nb_tanks_b ds 3
nb_tanks_r ds 3
nb_cars_b  ds 3
nb_cars_r  ds 3
nb_time_b  ds 3
nb_time_r  ds 3
nb_moves   ds 3
nb_shoot   ds 3

cur_field ds 2
df_field  ds 2
df_old    ds 2
oc_byte   ds 2
oc_cnt    ds 2
oc_row    ds 2
oc_rows   ds 2
oc_tmp    ds 2
sf_delta  ds 2
sf_min    ds 2
sf_max    ds 2
fn_buf    ds 2
fn_len    ds 2
dl_x      ds 2
dl_y      ds 2
dl_w      ds 2
dl_str    ds 2
fr_pat    ds 2
fr_off    ds 2
fr_rows   ds 2

  put title_art
  put common
