*----------------------------------------------------------
* art.s - The board drawn with the original's character set
* (milestone 4). Every square is one of the 64 glyphs in
* board_charset, 8 x 8 Atari pixels each shown 2 x 2, in one
* of the board's four colours on its background colour, as
* ANTIC mode 7 showed it. A unit replaces its square's glyph:
* glyph 1-3 by class, in colour 3 for Red and colour 0 for
* Black (board 10 has both colour 0 and the background black,
* so Black's units are unseen there, as in the original).
*
* The look of a square is its captured screen code
* (board_look_N in src/board_art.s): the terrain type alone
* does not say which river piece or mountain edge it shows.
* A square whose terrain type has changed since the board was
* loaded (destroyed) shows terr_default_code for its new type
* instead.
*
* Palette slots ART_SLOT_BK..ART_SLOT_PF0+3 (1-5) carry the
* board's colours, set by art_set_board; the other slots stay
* the debug palette's for the HUD, cursor, highlights and the
* status screen.
*
* PUT into game.s after dbg.s (uses its cx, cy, tmp, cell_addr
* and fr_addr). Native 16-bit like dbg.s.
*----------------------------------------------------------

ART_PAL = ART_SLOT_BK*2+$E19E00 ; the board's first palette entry (Merlin: left to right)

* art_set_board - Board cfg_board (1-10) has been loaded into
* the engine: set its palette and look table, and keep a copy
* of its terrain to tell destroyed squares from later.
art_set_board
 MX %00
 lda cfg_board
 and #$00FF
 dec
 sta tmp                   ; board index 0-9
 asl
 tax
 lda board_look_ptrs,x
 sta look_ptr
 lda tmp
 asl
 sta tmp2
 asl
 asl
 clc
 adc tmp2                  ; index * 10: five colour words
 tay
 ldx #0
:pal
 lda board_palettes,y
 stal ART_PAL,x
 iny
 iny
 inx
 inx
 cpx #10
 bcc :pal
 ldx #0
:copy
 lda board,x
 sta orig_terrain,x
 inx
 inx
 cpx #BOARD_CELLS
 bcc :copy
 rts

* art_draw_board - every square, units included.
art_draw_board
 MX %00
 stz cy
:row
 stz cx
:col
 jsr art_draw_cell
 inc cx
 lda cx
 cmp #BOARD_W
 bcc :col
 inc cy
 lda cy
 cmp #BOARD_H
 bcc :row
 rts

* art_draw_cell - the square (cx, cy): its unit if one stands
* there, else its terrain.
art_draw_cell
 MX %00
 lda cy
 asl
 asl
 sta tmp
 asl
 asl
 clc
 adc tmp                   ; cy*20
 clc
 adc cx
 sta cell
 tax
 lda occupant,x
 and #$00FF
 beq :terrain
 dec                       ; unit id
 tax
 lda unit_class,x
 and #$00FF
 inc                       ; glyphs 1-3
 sta glyph
 lda unit_side,x
 and #$00FF
 tax
 lda side_glyph_reg,x
 and #$00FF
 bra :colour
:terrain
 ldx cell
 lda board,x
 and #$00FF
 sta tmp2
 lda orig_terrain,x
 and #$00FF
 cmp tmp2
 bne :changed
 lda look_ptr
 sta rptr
 ldy cell
 lda (rptr),y
 and #$00FF
 bra :code
:changed
 ldx tmp2
 lda terr_default_code,x
 and #$00FF
:code
 sta tmp2
 and #$003F
 sta glyph
 lda tmp2
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr                       ; colour register 0-3
:colour
 asl
 asl
 asl
 asl
 asl
 asl
 sta art_fgoff             ; register * 64 into art_tbl
 lda glyph
 asl
 asl
 asl
 sta art_gi                ; the glyph's first row in board_charset
 jsr cell_addr
 ldx fr_addr
 lda #8
 sta art_row
:line
 ldy art_gi
 lda board_charset,y
 and #$00FF
 sta art_bits
 lsr
 lsr
 and #$003C                ; high nibble * 4
 ora art_fgoff
 tay
 lda art_tbl,y
 stal $E10000,x            ; this row and the one below it
 stal $E100A0,x
 inx
 inx
 lda art_tbl+2,y
 stal $E10000,x
 stal $E100A0,x
 inx
 inx
 lda art_bits
 and #$000F
 asl
 asl                       ; low nibble * 4
 ora art_fgoff
 tay
 lda art_tbl,y
 stal $E10000,x
 stal $E100A0,x
 inx
 inx
 lda art_tbl+2,y
 stal $E10000,x
 stal $E100A0,x
 txa
 clc
 adc #SCREEN_ROW*2-6       ; two rows down, back to the left edge
 tax
 inc art_gi
 dec art_row
 bne :line
 rts

* Colour register of each side's unit glyphs: Red 3, Black 0.
side_glyph_reg dfb 3,0

* Screen code for a square whose terrain type changed after
* loading, by TERR_*: clear, tree, water (solid, colour 1),
* bridge, mountain, white, yellow, grey (stripe glyph, colour
* 2), purple, black.
terr_default_code dfb $00,$88,$68,$C6,$28,$00,$68,$8D,$68,$28

look_ptr     ds 2
cell         ds 2
glyph        ds 2
art_gi       ds 2
art_bits     ds 2
art_fgoff    ds 2
art_row      ds 2
orig_terrain ds BOARD_CELLS
