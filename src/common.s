*----------------------------------------------------------
* common.s - routines shared by every part (PUT at the END
* of each part, after its own code and data, so the part's
* entry point stays at $2000).
*
* Contents:
*   toolbox_init  start TL/MT, get an ID, reserve our RAM,
*                 start QuickDraw II (once per boot)
*   shr_init      SHR on, shadowing on, clear, palette 0
*   set_colors    QD II pen fore/back colour
*   draw_cstr     QD II _MoveTo + _DrawCString
*   wait_key      block until a key is pressed
*   wait_vbl      wait for the next vertical blank
*----------------------------------------------------------

*----------------------------------------------------------
* toolbox_init - Entered in emulation mode, returns in
* emulation mode. Called once per boot; the tb_inited flag
* in page $11 tells later parts to skip it.
*
* Under a raw ProDOS 8 boot the ROM Memory Manager believes
* all of bank $00 above the firmware area is free, so we
* reserve $0800-$BEFF as ours (fixed, locked) before starting
* any tool that might otherwise allocate bank-$00 memory on
* top of us. QD II's direct page is then carved out at QD_DP
* inside that reservation.
*----------------------------------------------------------
toolbox_init
 clc
 xce
 rep $30
 MX %00

 ldx #$0201
 jsl TOOLBOX               ; _TLStartUp

 ldx #$0203
 jsl TOOLBOX               ; _MTStartUp (tick counter, RTC)
 bcs tb_fail

 ldx #$020B
 jsl TOOLBOX               ; _IMStartUp (Int2Dec for on-screen numbers)
 bcs tb_fail

 pha                       ; result space
 pea $1000                 ; idTag: application
 ldx #$2003
 jsl TOOLBOX               ; _GetNewID
 pla
 sta myID
 bcs tb_fail

* Reserve $0800-$BEFF for ourselves.
 pha                       ; result space (handle high)
 pha                       ; result space (handle low)
 pea $0000                 ; size high word
 pea $B700                 ; size low word: $0800..$BEFF
 lda myID
 pha
 pea $C003                 ; locked | fixed | bank | addr
 pea $0000                 ; location high word
 pea $0800                 ; location low word
 ldx #$0902
 jsl TOOLBOX               ; _NewHandle
 bcs tb_fail
 pla
 pla                       ; block is fixed; handle not needed

 pea QD_DP                 ; dpAddress (3 pages)
 pea $0000                 ; master SCB: 320 mode, palette 0
 pea $00A0                 ; max scan-line width in bytes
 lda myID
 pha
 ldx #$0204
 jsl TOOLBOX               ; _QDStartUp
 bcs tb_fail

 sec
 xce
 MX %11
 rts

* A tool call failed. Park here with the error code saved
* so a KEGS debugger session shows PC inside tb_fail and the
* code in tb_error.
tb_fail
 MX %00
 sta tb_error
:spin bra :spin
tb_error dw 0

*----------------------------------------------------------
* shr_init - Turn on Super Hi-Res (320 mode), enable bank
* $01 -> $E1 shadowing, clear pixels + SCBs, load palette 0.
* Native mode, 16-bit M/X in and out.
*----------------------------------------------------------
shr_init
 MX %00
 sep $20
 MX %10
 lda #$C1
 stal $E0C029              ; SHR on, linear
 ldal $E0C035
 and #$F7
 stal $E0C035              ; bit 3 = 0: shadow $01/2000 into $E1
 rep $20
 MX %00

 lda #$0000
 ldx #$7DFE
:clr stal $E12000,x        ; pixels $2000-$9CFF, SCBs $9D00-$9DFF
 dex
 dex
 bpl :clr

 ldx #$001E
:pal lda palette0,x
 stal $E19E00,x            ; palette 0
 dex
 dex
 bpl :pal
 rts

* Standard Apple IIGS 320-mode palette, $0RGB per entry.
palette0
 dw $0000,$0777,$0841,$072C,$000F,$0080,$0F70,$0D00
 dw $0FA9,$0FF0,$00E0,$04DF,$0DAF,$078F,$0CCC,$0FFF

*----------------------------------------------------------
* set_colors - A = foreground colour, X = background colour
* (palette indices). Native, 16-bit M/X.
*----------------------------------------------------------
set_colors
 MX %00
 phx
 pha
 ldx #$A004
 jsl TOOLBOX               ; _SetForeColor (pops fg)
 ldx #$A204
 jsl TOOLBOX               ; _SetBackColor (pops bg)
 rts

*----------------------------------------------------------
* draw_cstr - Draw the C string at str_ptr with its baseline
* at (X, Y) in 320-mode pixels. Strings live in the part's
* own code, so bank $00. Native, 16-bit M/X.
*----------------------------------------------------------
draw_cstr
 MX %00
 phx
 phy
 ldx #$3A04
 jsl TOOLBOX               ; _MoveTo(x, y)
 pea $0000                 ; string pointer, high word (bank $00)
 lda str_ptr
 pha                       ; string pointer, low word
 ldx #$A604
 jsl TOOLBOX               ; _DrawCString
 rts
str_ptr dw 0

*----------------------------------------------------------
* fmt_u16 - Format A (unsigned 16-bit) as decimal, right-
* justified with leading spaces, into the X-byte buffer at
* str_ptr (bank $00). Native, 16-bit M/X.
*----------------------------------------------------------
fmt_u16
 MX %00
 pha                       ; intValue
 pea $0000                 ; strPtr, high word (bank $00)
 lda str_ptr
 pha                       ; strPtr, low word
 phx                       ; strLength
 pea $0000                 ; signedFlag: unsigned
 ldx #$260B
 jsl TOOLBOX               ; _Int2Dec
 rts

*----------------------------------------------------------
* wait_key - Clear the keyboard strobe, block until a key is
* pressed, clear it again. Returns the key's ASCII code in
* A (high bit stripped). Native, 16-bit M/X in and out.
*----------------------------------------------------------
wait_key
 MX %00
 sep $30
 MX %11
 sta $C010                 ; drop any key still latched
:wait lda $C000
 bpl :wait
 sta $C010
 and #$7F
 rep $30
 MX %00
 and #$00FF
 rts

*----------------------------------------------------------
* wait_vbl - Wait for the start of the next vertical blank.
* Native mode; preserves the caller's 16-bit M.
*----------------------------------------------------------
wait_vbl
 MX %00
 sep $20
 MX %10
:lp1 bit $C019
 bmi :lp1                  ; wait for current VBL to end
:lp2 bit $C019
 bpl :lp2                  ; wait for next VBL to start
 rep $20
 MX %00
 rts
