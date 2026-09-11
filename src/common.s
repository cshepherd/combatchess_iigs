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
 bcc *+5
 jmp tb_fail

 ldx #$020B
 jsl TOOLBOX               ; _IMStartUp (Int2Dec for on-screen numbers)
 bcc *+5
 jmp tb_fail

 pha                       ; result space
 pea $1000                 ; idTag: application
 ldx #$2003
 jsl TOOLBOX               ; _GetNewID
 pla
 sta myID
 bcc *+5
 jmp tb_fail

 jsr snd_reserve_bank      ; protect bank $02 (SOUNDS samples)

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
 bcc *+5
 jmp tb_fail
 pla
 pla                       ; block is fixed; handle not needed

 pea QD_DP                 ; dpAddress (3 pages)
 pea $0000                 ; master SCB: 320 mode, palette 0
 pea $00A0                 ; max scan-line width in bytes
 lda myID
 pha
 ldx #$0204
 jsl TOOLBOX               ; _QDStartUp
 bcc *+5
 jmp tb_fail

* The game clock (spec 16.1) reads the 60 Hz tick counter
* with _GetTick. That counter is only advanced by the Misc
* Tools heartbeat handler, which the firmware puts on the
* VBL vector when the first heartbeat task is registered,
* and the interrupt manager switches VBL interrupts off
* again whenever the heartbeat chain is empty. (Enabling
* VBL with _IntSource or INTEN alone lasts one frame.) So
* register a task that does nothing but reset its own
* count. It lives at HB_TASK, outside every part, because
* the firmware keeps a pointer to it for the rest of the
* session while TITLE, GAME and TEST replace each other
* at $2000.
 ldx #HB_TASK_LEN-2
:hb_copy
 lda hb_template,x
 sta HB_TASK,x
 dex
 dex
 bpl :hb_copy
 pea $0000
 pea HB_TASK               ; long pointer to the task record
 ldx #$1203
 jsl TOOLBOX               ; _SetHeartBeat
 bcc *+5
 jmp tb_fail
 pea $0002
 ldx #$2303
 jsl TOOLBOX               ; _IntSource: enable VBL interrupts
 bcc *+5
 jmp tb_fail

 jsr snd_toolstart

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

* Sound Tool Set (spec 5, Milestone 5): start it so the game
* can play DOC effects with _FFStartSound. It installs the
* free-form-synth interrupt handler and needs one direct
* page. A missing DOC is not fatal; the game just runs mute,
* so a failure here is ignored. Native 16-bit.
snd_toolstart
 MX %00
 pea SOUND_DP
 ldx #$0208
 jsl TOOLBOX               ; _SoundStartUp
 rts

* snd_reserve_bank - reserve bank $02, where the launcher loaded
* the SOUNDS samples, so no tool overwrites them. Ignored if it
* fails (no such bank -> the game runs mute). Native 16-bit.
snd_reserve_bank
 MX %00
 pha
 pha                       ; result space (handle)
 pea $0001
 pea $0000                 ; size $00010000 (whole bank)
 lda myID
 pha
 pea $C000                 ; locked | fixed
 pea $0002
 pea $0000                 ; location $02/0000
 ldx #$0902
 jsl TOOLBOX               ; _NewHandle
 pla
 pla                       ; discard handle (base is known: $02/0000)
 rts

* Heartbeat task record, copied to HB_TASK: link (filled by
* the firmware), count, signature, then code the firmware
* JSLs when the count reaches 0. The code puts the count
* back to 1 and returns, so it runs every frame and the
* chain is never empty. Hand-assembled because it runs at
* HB_TASK, not where it is assembled.
hb_template
 dfb 0,0,0,0               ; link
 dfb 1,0                   ; count: 1 tick
 dfb $5A,$A5               ; signature $A55A
 dfb $08                   ; php
 dfb $C2,$20               ; rep #$20
 dfb $A9,$01,$00           ; lda #$0001
 dfb $8D,$04,$12           ; sta HB_TASK+4 (the count)
 dfb $28                   ; plp
 dfb $6B                   ; rtl
HB_TASK_LEN = 20

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

* set_text_mode - A = QuickDraw text mode: TEXT_OPAQUE paints
* each glyph's cell in the background colour, TEXT_FORE only
* the glyph's own pixels. Native, 16-bit M/X.
*----------------------------------------------------------
TEXT_OPAQUE = $0000        ; modeCopy
TEXT_FORE   = $8000        ; modeForeCopy
set_text_mode
 MX %00
 pha
 ldx #$9C04
 jsl TOOLBOX               ; _SetTextMode (ROM listing: $9C04)
 rts

*----------------------------------------------------------
* set_border - A (low byte) = one of the IIGS's 16 fixed
* border colours (0-15). Sets the low nibble of the $C034
* border register, preserving the high nibble (the clock /
* battery-RAM data). Native, 16-bit M/X in and out.
*----------------------------------------------------------
set_border
 MX %00
 sep #$20
 MX %10
 and #$0F
 sta rt0
 ldal $E0C034
 and #$F0
 ora rt0
 stal $E0C034
 rep #$20
 MX %00
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
* cstr_width - Pixel width of the C string at A in the
* current font. Native, 16-bit M/X. Returns A.
*----------------------------------------------------------
cstr_width
 MX %00
 pea $0000                 ; result space
 pea $0000                 ; string pointer, high word (bank $00)
 pha                       ; string pointer, low word
 ldx #$AA04
 jsl TOOLBOX               ; _CStringWidth
 pla
 rts

*----------------------------------------------------------
* Line builder: composes a C string in line_buf for the
* status lines and option pages. Native, 16-bit M/X.
*----------------------------------------------------------
lb_reset
 MX %00
 stz lb_pos
 rts

* lb_str - append the C string at A. Uses rptr (direct page)
* for the indirect read; nothing in the engine runs while a
* line is built.
lb_str
 MX %00
 sta rptr
 ldy #0
 ldx lb_pos
 sep #$20
 MX %10
:copy
 lda (rptr),y
 beq :done
 sta line_buf,x
 inx
 iny
 bra :copy
:done
 rep #$20
 MX %00
 stx lb_pos
 rts

* lb_dec - append A as decimal, right-justified in X chars.
lb_dec
 MX %00
 stx lb_width
 pha
 lda #line_buf
 clc
 adc lb_pos
 sta str_ptr
 pla
 ldx lb_width
 jsr fmt_u16
 lda lb_pos
 clc
 adc lb_width
 sta lb_pos
 rts

* lb_dec2 - append A as two digits with a leading zero.
lb_dec2
 MX %00
 cmp #10
 bcs :two
 pha
 lda #s_lb_zero
 jsr lb_str
 pla
 ldx #1
 jmp lb_dec
:two
 ldx #2
 jmp lb_dec

* lb_dec3z - append A as three digits with leading zeros.
lb_dec3z
 MX %00
 cmp #100
 bcs :three
 pha
 lda #s_lb_zero
 jsr lb_str
 pla
 jmp lb_dec2
:three
 ldx #3
 jmp lb_dec

lb_end
 MX %00
 ldx lb_pos
 sep #$20
 MX %10
 lda #0
 sta line_buf,x
 rep #$20
 MX %00
 rts

s_lb_zero asc '0'
          dfb 0
lb_pos    ds 2
lb_width  ds 2
line_buf  ds 64

*----------------------------------------------------------
* cfg_defaults - The Atari original's default options into
* page $11 (reference/notes/options_ranges.md). Any mode in;
* the caller's M width is preserved.
*----------------------------------------------------------
cfg_defaults
 php
 sep #$20
 MX %10
 lda #1
 sta cfg_board
 lda #3
 sta cfg_tanks_black
 lda #2
 sta cfg_tanks_red
 lda #5
 sta cfg_cars_black
 lda #4
 sta cfg_cars_red
 lda #0
 sta cfg_first             ; Red starts
 sta cfg_computer          ; computer plays Black (no AI yet: both human)
 lda #20
 sta cfg_time_black
 sta cfg_time_red
 lda #3
 sta cfg_moves
 lda #1
 sta cfg_shoot
 lda #CFG_MAGIC
 sta cfg_valid
 plp
 rts

*----------------------------------------------------------
* wait_key - Block until a key is pressed (or one is poked
* into inject_key by a debugger), returning its ASCII code
* in A with the high bit stripped. Native, 16-bit M/X in
* and out.
*----------------------------------------------------------
wait_key
 MX %00
 sep $30
 MX %11
 sta $C010                 ; drop any key still latched
:wait
 lda inject_key
 bne :poked
 lda $C000
 bpl :wait
 sta $C010
 and #$7F
 bra :got
:poked
 stz inject_key
:got
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
* (Direct-DOC effects halt themselves in one-shot mode, so
* there is no longer any per-frame sound maintenance here.)
