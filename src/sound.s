*----------------------------------------------------------
* sound.s - DOC sound effects through the Sound Tool Set
* (spec section 5, Milestone 5). PUT into game.s after the
* board art and before common.s. Native 16-bit like the rest
* of the display layer.
*
* toolbox_init has already run _SoundStartUp. The move, cannon
* and explosion waveforms are ripped from the Atari original
* (src/sound_samples.s, tools/gen_sound.py) as unsigned 8-bit
* DOC waveforms and played with _FFStartSound, each on its own
* generator and DOC RAM region so a cannon report and its
* explosion overlap. wave_size is one byte less than the DOC
* buffer, so the tool uses a single buffer (>= the buffer drops
* it into SWAP/streaming, whose interrupt-driven refill loop
* froze the machine for seconds). The tool still free-runs the
* oscillator past the waveform's end, so snd_tick stops each
* generator once the sample's own duration has elapsed - timed
* from the 60 Hz _GetTick counter, not a per-loop tick, so the
* stop lands on the sample's end however slow the game loop is
* running (a per-loop countdown lagged to ~4.5 s behind a full
* board redraw and left the oscillator screeching through DOC
* RAM). The UI-feedback buzz is a small square wave built at
* init. A missing DOC leaves the game mute rather than crashing.
*----------------------------------------------------------
FF_MODE = $01              ; free-form synthesiser mode byte

* Effect indices passed to snd_play.
SFX_MOVE    = 0
SFX_CANNON  = 1
SFX_EXPLODE = 2
SFX_UI      = 3
SFX_TICK    = 4            ; play-clock tick, once a second
SFX_BEEP    = 5            ; cursor-move click
SFX_TURN    = 6            ; turn-start fanfare (rising two-voice sweep)

* One logical generator each so effects can sound together.
GEN_MOVE    = 1
GEN_CANNON  = 2
GEN_EXPLODE = 3
GEN_UI      = 4
GEN_TICK    = 5
GEN_BEEP    = 6
GEN_TURN    = 7

*----------------------------------------------------------
* snd_load - point the parameter blocks at the ripped samples
* the launcher (cc.s) loaded into bank $02 at boot. Called by
* GAME each run (the param blocks reload with the part, but
* snd_blk / snd_loaded in page $11 persist). Native 16-bit.
*----------------------------------------------------------
snd_load
 MX %00
 lda snd_loaded
 and #$00FF
 beq :ret                  ; never loaded (mute)
 lda #snd_explode_wave_off
 ldx #snd_pb_explode
 jsr :one
 lda #snd_move_wave_off
 ldx #snd_pb_move
 jsr :one
 lda #snd_fire_wave_off
 ldx #snd_pb_cannon
 jsr :one
 lda #snd_tick_wave_off
 ldx #snd_pb_tick
 jsr :one
 lda #snd_beep_wave_off
 ldx #snd_pb_beep
 jsr :one
 lda #snd_turn_wave_off
 ldx #snd_pb_turn
 jsr :one
:ret
 rts
* :one - A = sample offset in the bank, X = parameter block.
* Writes wave_start (block base + offset) into the block.
:one
 clc
 adc snd_blk
 sta 0,x                   ; wave_start low word
 lda snd_blk+2
 sta 2,x                   ; wave_start bank
 rts

*----------------------------------------------------------
* snd_init - build the UI-feedback buzz, seed the tick clock
* and arm the per-frame stop. Call once, native 16-bit, after
* snd_load.
*----------------------------------------------------------
snd_init
 MX %00
 ldx #0
:buzz
 txa
 and #$0008
 bne :bhi
 lda #$3030
 bra :bst
:bhi
 lda #$D0D0
:bst
 sta snd_buzz,x
 inx
 inx
 cpx #SND_BUZZ_LEN
 bcc :buzz
* seed the last-seen tick so the first snd_tick delta is ~0
 jsr snd_gettick
 sta snd_last_tick
 lda #snd_tick
 sta snd_tick_vec               ; wait_vbl now stops finished effects
 rts

*----------------------------------------------------------
* snd_gettick - return (A) the low 16 bits of the 60 Hz
* _GetTick counter. Native 16-bit; clobbers A.
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
* snd_tick - called from wait_vbl every frame. Counts each
* playing effect down by the real ticks elapsed since the
* last call and stops its generator when the sample's own
* duration is up (the tool free-runs a one-shot forever
* otherwise). Native 16-bit; wait_vbl preserves the caller's
* registers.
*----------------------------------------------------------
snd_tick
 MX %00
 jsr snd_gettick           ; A = now, snd_now = now
 sec
 sbc snd_last_tick         ; delta = now - last
 cmp #$0100
 bcc :dok
 lda #$00FF                ; clamp a huge gap to 255 frames
:dok
 sta snd_delta
 lda snd_now
 sta snd_last_tick         ; remember for next time
 sep #$30
 MX %11
 ldx #0                    ; effect / generator index 0..3
:t
 lda snd_cd,x
 beq :next                 ; not playing
 cmp snd_delta
 bcc :stop                 ; countdown < elapsed -> done
 beq :stop
 sec
 sbc snd_delta
 sta snd_cd,x
 bra :next
:stop
 lda snd_loopf,x           ; looping effect (the flight trill)?
 beq :hardstop
* re-trigger: replay the one-shot and re-arm, keeping the trill going
 phx
 txa
 rep #$30
 MX %00
 and #$00FF
 jsr snd_play_loop
 sep #$30
 MX %11
 plx
 bra :next
:hardstop
 stz snd_cd,x
 phx                       ; save loop index (1 byte, 8-bit)
 lda snd_gen8,x            ; generator number
 rep #$30
 MX %00
 and #$00FF
 tay
 lda #$0001
:sh
 asl
 dey
 bne :sh
 pha                       ; 16-bit mask (1 << generator)
 ldx #$0F08
 jsl TOOLBOX               ; _FFStopSound
 sep #$30
 MX %11
 plx
:next
 inx
 cpx #7
 bne :t
 rep #$30
 MX %00
 rts

*----------------------------------------------------------
* snd_play - play effect A (SFX_*). Stops that effect's
* generator first so a re-trigger never hits gen-busy, then
* _FFStartSound with the effect's parameter block, and arms
* the stop countdown. Native 16-bit. Clobbers A, X, Y. Errors
* from a missing DOC are ignored (the game stays mute).
*----------------------------------------------------------
snd_play
 MX %00
 and #$00FF
 asl
 tax
 stx snd_fx                ; effect*2
 lda snd_gen_tab,x
 sta snd_gen
 lda snd_pb_tab,x
 sta snd_pbptr
* _FFStopSound(1 << generator)
 lda snd_gen
 tay
 lda #$0001
:sh
 asl
 dey
 bne :sh
 pha
 ldx #$0F08
 jsl TOOLBOX
* _FFStartSound((generator << 8) | FF_MODE, parmBlock)
 lda snd_gen
 xba
 ora #FF_MODE
 pha
 pea $0000                 ; parameter block bank ($00)
 lda snd_pbptr
 pha
 ldx #$0E08
 jsl TOOLBOX
* arm the stop countdown (in ticks): the tool free-runs the
* one-shot, so snd_tick halts the generator after the sample's
* own duration, timed off _GetTick.
 lda snd_fx
 lsr                       ; effect index
 tax
 sep #$20
 MX %10
 lda snd_frames,x
 sta snd_cd,x              ; one byte per effect (frames < 256)
 stz snd_loopf,x           ; one-shot by default
 rep #$20
 MX %00
 rts

*----------------------------------------------------------
* snd_play_loop - play effect A (SFX_*) and mark it looping, for
* the shot-in-flight trill: snd_tick re-triggers the one-shot
* each time its countdown expires (the tool cannot cleanly loop
* a waveform), giving a repeating beep until snd_stop cuts it on
* impact. Native 16-bit. Clobbers A, X, Y.
*----------------------------------------------------------
snd_play_loop
 MX %00
 pha                       ; save effect
 jsr snd_play              ; play once + arm countdown (clears loopf)
 pla
 and #$00FF
 tax
 sep #$20
 MX %10
 lda #1
 sta snd_loopf,x           ; mark looping so snd_tick re-triggers it
 rep #$20
 MX %00
 rts

*----------------------------------------------------------
* snd_stop - halt effect A (SFX_*): clear its loop flag and
* countdown, then _FFStopSound its generator. Native 16-bit.
* Clobbers A, X, Y.
*----------------------------------------------------------
snd_stop
 MX %00
 and #$00FF
 tax
 phx                       ; effect (2 bytes)
 asl
 tay
 lda snd_gen_tab,y
 tay                       ; generator
 lda #$0001
:sh
 asl
 dey
 bne :sh
 pha
 ldx #$0F08
 jsl TOOLBOX               ; _FFStopSound(1 << generator)
 plx                       ; effect
 sep #$20
 MX %10
 stz snd_cd,x
 stz snd_loopf,x
 rep #$20
 MX %00
 rts

*----------------------------------------------------------
* Free-form-synth parameter blocks (18 bytes each): wave
* start (long), wave size (word), frequency (word), DOC RAM
* address (word, page in the high byte), DOC buffer size code
* (word, 0=256 .. 7=32768 bytes), next wave (long, 0 = one
* shot), volume (word, 0-255 in the low byte). DOC regions do
* not overlap.
*----------------------------------------------------------
* Size, DOC size code and playback frequency come from the
* generator (sound_samples.s). wave_size is one less than the
* DOC buffer (256<<code), strictly smaller, so the tool copies
* the wave into a SINGLE buffer and plays it one-shot; wave_size
* >= the buffer needs a second buffer and drops the tool into
* SWAP/streaming, whose interrupt-driven DOC refill loop froze
* the whole machine for ~8 s on the 16 KB blast. wave_start is
* 0 here and patched by snd_load to the loaded sample bank plus
* each sound's offset.
snd_pb_explode
 adrl 0                     ; the four-channel blast (patched)
 dw snd_explode_wave_size
 dw snd_explode_wave_freq
 dw $0000                  ; DOC $0000 (16384 bytes)
 dw snd_explode_wave_code
 adrl 0
 dw $00FF
snd_pb_move
 adrl 0                     ; the poly5 engine buzz (patched)
 dw snd_move_wave_size
 dw snd_move_wave_freq
 dw $8000                  ; DOC $8000 (8192 bytes)
 dw snd_move_wave_code
 adrl 0
 dw $00B0
snd_pb_cannon
 adrl 0                     ; the shot-in-flight trill (patched)
 dw snd_fire_wave_size
 dw $03E6                  ; 2.5 x snd_fire_wave_freq ($018F): high-pitched trill
 dw $4000                  ; DOC $4000, in the 16 KB gap after the blast:
                           ; the loop's free-run runs out into silence
 dw snd_fire_wave_code
 adrl 0                    ; one-shot; snd_tick re-triggers it for the trill
 dw $00E0
snd_pb_ui
 adrl snd_buzz
 dw SND_BUZZ_LEN-1         ; < buffer -> single-buffer one-shot
 dw $02C0
 dw $C800                  ; DOC $C800 (512 bytes)
 dw 1
 adrl 0
 dw $00A0
snd_pb_tick
 adrl 0                     ; the play-clock tick (patched)
 dw snd_tick_wave_size
 dw snd_tick_wave_freq
 dw $A000                  ; DOC $A000 (256 bytes, run-out gap is $00)
 dw snd_tick_wave_code
 adrl 0
 dw $0090
snd_pb_beep
 adrl 0                     ; the cursor-move beep (patched)
 dw snd_beep_wave_size
 dw snd_beep_wave_freq
 dw $A800                  ; DOC $A800 (256 bytes, run-out gap is $00)
 dw snd_beep_wave_code
 adrl 0
 dw $0060                  ; quiet - it clicks on every cursor step
snd_pb_turn
 adrl 0                     ; the turn-start fanfare (patched)
 dw snd_turn_wave_size
 dw snd_turn_wave_freq
 dw $6000                  ; DOC $6000 (4096 bytes, run-out gap is $00)
 dw snd_turn_wave_code
 adrl 0
 dw $00FF

snd_pb_tab  da snd_pb_move,snd_pb_cannon,snd_pb_explode,snd_pb_ui
            da snd_pb_tick,snd_pb_beep,snd_pb_turn
snd_gen_tab dw GEN_MOVE,GEN_CANNON,GEN_EXPLODE,GEN_UI,GEN_TICK,GEN_BEEP,GEN_TURN
snd_gen8    dfb GEN_MOVE,GEN_CANNON,GEN_EXPLODE,GEN_UI,GEN_TICK,GEN_BEEP,GEN_TURN
* frames each effect plays before snd_tick stops it (its own
* duration; UI a short fixed buzz). All < 256.
snd_frames  dfb snd_move_wave_frames,snd_fire_wave_frames,snd_explode_wave_frames,10
            dfb snd_tick_wave_frames,snd_beep_wave_frames,snd_turn_wave_frames

SND_BUZZ_LEN  = 512

snd_gen   ds 2
snd_pbptr ds 2
snd_fx    ds 2
snd_now   ds 2
snd_last_tick ds 2
snd_delta ds 2
snd_cd    ds 7             ; one countdown byte per effect (ticks remaining)
snd_loopf ds 7             ; per-effect: nonzero = re-trigger on expiry (trill)
snd_buzz  ds SND_BUZZ_LEN+1
