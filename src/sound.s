*----------------------------------------------------------
* sound.s - DOC sound effects, driven directly through the
* Ensoniq 5503 sound GLU (spec section 5, Milestone 5). PUT
* into game.s after the board art and before common.s. Native
* 16-bit like the rest of the display layer.
*
* toolbox_init has already run _SoundStartUp, which enables 32
* oscillators (so osc_rate ~26.3 kHz) and sets the master
* volume. Every effect is one waveform in DOC RAM played on a
* dedicated oscillator in ONE-SHOT mode (control $02): the
* oscillator halts itself when its accumulator strides onto a
* $00 sample, so each waveform ends in a 16-byte $00 run (a
* single zero can be stepped over at these resolutions). No
* per-frame stop is needed. The shot trill is the one looping
* voice (control $00, free-run) and is halted with snd_stop on
* impact. Waveforms are ripped from the Atari original
* (src/sound_samples.s, tools/gen_sound.py) and copied into
* DOC RAM once by snd_load. A missing DOC leaves the game mute
* rather than crashing.
*----------------------------------------------------------

* Effect indices passed to snd_play.
SFX_MOVE    = 0
SFX_CANNON  = 1
SFX_EXPLODE = 2
SFX_UI      = 3            ; invalid move/shot buzz
SFX_TICK    = 4            ; play-clock tick, once a second
SFX_BEEP    = 5            ; cursor-move click
SFX_TURN    = 6            ; turn-start fanfare
* SFX_PLACE is not in the tables; snd_place drives it directly.

*----------------------------------------------------------
* Sound GLU and Ensoniq DOC (modelled on the ROM's
* Set_doc_regs and ddiigs's libsound).
*----------------------------------------------------------
G_STAT  = $E1C03C          ; sound GLU control/status
G_DATA  = $E1C03D          ; sound GLU data
G_ADRL  = $E1C03E          ; GLU address low
G_ADRH  = $E1C03F          ; GLU address high (DOC RAM)
IRQVOL  = $E100CA          ; system 4-bit volume
E_FREQL = $00              ; per-oscillator DOC register offsets
E_FREQH = $20
E_VOL   = $40
E_WPAGE = $80
E_CTRL  = $A0
E_BTR   = $C0              ; table size (bits 3-5) + resolution (bits 0-2)
PLACE_OSC = $14            ; oscillator 20, the placement voice

*----------------------------------------------------------
* snd_load - copy every waveform from the SOUNDS bank (loaded
* into bank $02 at boot, snd_blk in page $11) into its DOC RAM
* region, once per game. Native 16-bit. A missing SOUNDS file
* leaves snd_loaded clear and the game mute.
*----------------------------------------------------------
snd_load
 MX %00
 lda snd_loaded
 and #$00FF
 beq :ret
 lda #$0000                ; explosion -> DOC $0000 (16 KB)
 ldx #snd_explode_wave_off
 ldy #16384
 jsr doc_load
 lda #$8000                ; move buzz -> DOC $8000 (8 KB)
 ldx #snd_move_wave_off
 ldy #8192
 jsr doc_load
 lda #$4000                ; cannon -> DOC $4000 (1 KB)
 ldx #snd_fire_wave_off
 ldy #1024
 jsr doc_load
 lda #$C800                ; UI buzz -> DOC $C800 (512 B)
 ldx #snd_ui_wave_off
 ldy #512
 jsr doc_load
 lda #$A000                ; tick -> DOC $A000
 ldx #snd_tick_wave_off
 ldy #256
 jsr doc_load
 lda #$A800                ; cursor beep -> DOC $A800
 ldx #snd_beep_wave_off
 ldy #256
 jsr doc_load
 lda #$6000                ; turn fanfare -> DOC $6000 (4 KB)
 ldx #snd_turn_wave_off
 ldy #4096
 jsr doc_load
 lda #$B000                ; placement beeps -> DOC $B000/$B100/$B200
 ldx #snd_place_cru_wave_off
 ldy #256
 jsr doc_load
 lda #$B100
 ldx #snd_place_tank_wave_off
 ldy #256
 jsr doc_load
 lda #$B200
 ldx #snd_place_car_wave_off
 ldy #256
 jsr doc_load
:ret
 rts

*----------------------------------------------------------
* snd_init - nothing to build now that the waveforms are all
* in DOC RAM and the oscillators halt themselves. Kept so
* game.s need not change. Native 16-bit.
*----------------------------------------------------------
snd_init
 MX %00
 rts

*----------------------------------------------------------
* snd_gettick - return (A) the low 16 bits of the 60 Hz
* _GetTick counter, for the placement animation's pacing.
* Native 16-bit; clobbers A.
*----------------------------------------------------------
snd_gettick
 MX %00
 pha                       ; room for the Long result
 pha
 ldx #$2503
 jsl TOOLBOX               ; _GetTick
 pla                       ; low word
 sta snd_now
 pla                       ; high word (discard)
 lda snd_now
 rts

*----------------------------------------------------------
* snd_play - play effect A (SFX_MOVE..SFX_TURN) on its
* oscillator: halt it, program table size/resolution,
* frequency, volume and waveform page, then start it. Most
* are one-shot (control $02, self-halting on the $00 tail);
* the cannon is free-run ($00) and loops until snd_stop.
* Native 16-bit. Clobbers A, X, Y. Mute if never loaded.
*----------------------------------------------------------
snd_play
 MX %00
 and #$00FF
 pha
 lda snd_loaded
 and #$00FF
 bne :ok
 pla
 rts
:ok
 pla
 sta snd_fx
 tax
 lda snd_osc,x
 and #$00FF
 sta snd_osc_cur
* halt the oscillator first, for a clean re-trigger
 clc
 adc #E_CTRL
 tax
 lda #$01
 jsr doc_setreg
* EBTR = (code<<3) | code   (table size = resolution = the buffer code)
 ldx snd_fx
 lda snd_codeT,x
 and #$00FF
 sta snd_tmp
 asl
 asl
 asl
 ora snd_tmp
 pha
 lda snd_osc_cur
 clc
 adc #E_BTR
 tax
 pla
 jsr doc_setreg
* frequency low then high
 lda snd_fx
 asl
 tax
 lda snd_freqT,x
 sta snd_tmp
 lda snd_osc_cur
 clc
 adc #E_FREQL
 tax
 lda snd_tmp
 jsr doc_setreg
 lda snd_osc_cur
 clc
 adc #E_FREQH
 tax
 lda snd_tmp
 xba
 jsr doc_setreg
* volume
 ldx snd_fx
 lda snd_volT,x
 and #$00FF
 pha
 lda snd_osc_cur
 clc
 adc #E_VOL
 tax
 pla
 jsr doc_setreg
* waveform start page
 ldx snd_fx
 lda snd_pageT,x
 and #$00FF
 pha
 lda snd_osc_cur
 clc
 adc #E_WPAGE
 tax
 pla
 jsr doc_setreg
* start it: one-shot ($02) or free-run loop ($00)
 ldx snd_fx
 lda snd_ctrlT,x
 and #$00FF
 pha
 lda snd_osc_cur
 clc
 adc #E_CTRL
 tax
 pla
 jmp doc_setreg

*----------------------------------------------------------
* snd_stop - halt effect A's oscillator (the trill on impact).
* Native 16-bit. Clobbers A, X.
*----------------------------------------------------------
snd_stop
 MX %00
 and #$00FF
 tax
 lda snd_osc,x
 and #$00FF
 clc
 adc #E_CTRL
 tax
 lda #$01                  ; halt
 jmp doc_setreg

*----------------------------------------------------------
* snd_place - the piece-placement beep for class A (0 cruiser,
* 1 tank, 2 car), pitched by class, on PLACE_OSC in one-shot
* mode. The three samples were copied into DOC RAM by
* snd_load. A no-op when the samples never loaded. Native
* 16-bit.
*----------------------------------------------------------
snd_place
 MX %00
 and #$00FF
 pha
 lda snd_loaded
 and #$00FF
 bne :ok
 pla
 rts
:ok
 pla
 tax
 lda place_page_tab,x
 and #$00FF
 sta snd_tmp               ; the sample's DOC RAM start page
 ldx #E_CTRL+PLACE_OSC
 lda #$01                  ; halt first
 jsr doc_setreg
 ldx #E_BTR+PLACE_OSC
 lda #$00                  ; code 0: 256-byte table, resolution 0
 jsr doc_setreg
 ldx #E_FREQL+PLACE_OSC    ; all three share the frequency
 lda #<snd_place_cru_wave_freq
 jsr doc_setreg
 ldx #E_FREQH+PLACE_OSC
 lda #>snd_place_cru_wave_freq
 jsr doc_setreg
 ldx #E_VOL+PLACE_OSC
 lda #$C0
 jsr doc_setreg
 ldx #E_WPAGE+PLACE_OSC
 lda snd_tmp
 jsr doc_setreg
 ldx #E_CTRL+PLACE_OSC     ; one-shot + GO; halts on the $00 tail
 lda #$02
 jmp doc_setreg

*----------------------------------------------------------
* doc_setreg - write value A (low byte) to DOC register X
* (low byte, e.g. E_CTRL+osc) through the sound GLU. Native
* 16-bit on entry/exit; waits for the GLU to be free.
*----------------------------------------------------------
doc_setreg
 MX %00
 sep #$20
 MX %10                    ; 8-bit A, 16-bit X
 pha                       ; save the value byte
:busy ldal G_STAT
 bmi :busy
 ldal IRQVOL
 and #$0F
 stal G_STAT               ; register access, no auto-inc, + system volume
 txa                       ; register number
 stal G_ADRL
 pla
 stal G_DATA               ; the value
 rep #$20
 MX %00
 rts

*----------------------------------------------------------
* doc_load - copy Y bytes from the SOUNDS bank (snd_blk)
* offset X into DOC RAM at address A, via the GLU with auto-
* increment. Uses rptr as a 24-bit source pointer. Native
* 16-bit. Called by snd_load, once per waveform.
*----------------------------------------------------------
doc_load
 MX %00
 sta snd_tmp               ; DOC destination address
 sty snd_len               ; byte count
 stx rptr                  ; source offset (low word)
 sep #$20
 MX %10                    ; 8-bit A, 16-bit X/Y
 lda snd_blk+2
 sta rptr+2                ; source bank -> [rptr] is a 24-bit pointer
:busy ldal G_STAT
 bmi :busy
 ldal IRQVOL
 and #$0F
 ora #$60                  ; DOC RAM ($40) + address auto-increment ($20)
 stal G_STAT
 lda snd_tmp
 stal G_ADRL               ; destination low byte
 lda snd_tmp+1
 stal G_ADRH               ; destination high byte
 ldy #$0000
:copy lda [rptr],y
 stal G_DATA               ; write; the GLU bumps the DOC address
 iny
 cpy snd_len
 bne :copy
 rep #$30
 MX %00
 rts

*----------------------------------------------------------
* Per-effect direct-DOC voice tables (index = SFX_MOVE..
* SFX_TURN): oscillator, DOC RAM start page, buffer-size code
* (table size + resolution), frequency register, volume and
* control mode ($02 one-shot, $00 free-run loop).
*----------------------------------------------------------
snd_osc   dfb 8,9,10,11,12,13,14
snd_pageT dfb $80,$40,$00,$C8,$A0,$A8,$60
snd_codeT dfb snd_move_wave_code,snd_fire_wave_code,snd_explode_wave_code
          dfb snd_ui_wave_code,snd_tick_wave_code,snd_beep_wave_code
          dfb snd_turn_wave_code
snd_freqT dw snd_move_wave_freq,$04B0,snd_explode_wave_freq,snd_ui_wave_freq
          dw snd_tick_wave_freq,snd_beep_wave_freq,snd_turn_wave_freq
snd_volT  dfb $B0,$E0,$FF,$A0,$90,$60,$FF
snd_ctrlT dfb $02,$00,$02,$02,$02,$02,$02
place_page_tab dfb $B0,$B1,$B2   ; DOC RAM pages: cruiser, tank, car

snd_fx      ds 2            ; current effect index
snd_osc_cur ds 2            ; its oscillator number
snd_tmp     ds 2            ; scratch: page / dest address / code
snd_len     ds 2            ; doc_load byte count
snd_now     ds 2            ; snd_gettick low word
