*----------------------------------------------------------
* sound.s - DOC sound effects through the Sound Tool Set
* (spec section 5, Milestone 5). PUT into game.s after the
* board art and before common.s. Native 16-bit like the rest
* of the display layer.
*
* toolbox_init has already run _SoundStartUp (common.s), which
* installs the free-form-synth interrupt handler. snd_init
* generates the effect waveforms once into bank-0 buffers.
* Each effect is a short 8-bit unsigned burst played one-shot
* with _FFStartSound on its own generator and its own DOC RAM
* region, so a cannon report and its explosion can overlap.
* next_wave_ptr = 0 makes the tool stop the generator at the
* end of the waveform (one-shot), and a $00 sample would halt
* it early, so the waveforms are kept to $01-$FF. Character
* comes from the playback frequency, length and volume, not
* pitch, so nothing needs tuning by ear.
*
* If the machine has no DOC, _SoundStartUp failed and the
* _FFStopSound/_FFStartSound calls just return an ignored
* error, so the game runs mute rather than crashing.
*----------------------------------------------------------
FF_MODE = $01              ; free-form synthesiser mode byte

* Effect indices passed to snd_play.
SFX_MOVE    = 0
SFX_CANNON  = 1
SFX_EXPLODE = 2
SFX_UI      = 3

* One logical generator each so effects can sound together.
GEN_MOVE    = 1
GEN_CANNON  = 2
GEN_EXPLODE = 3
GEN_UI      = 4

*----------------------------------------------------------
* snd_init - build the effect waveforms. Call once, native
* 16-bit, after toolbox_init.
*----------------------------------------------------------
snd_init
 MX %00
 lda #$A55A
 sta snd_seed
* Broadband noise for the cannon and explosion (and a soft,
* low-frequency version for movement). Two nonzero bytes at a
* time; a $00 sample would halt the oscillator early.
 ldx #0
:noise
 jsr snd_rand
 pha
 and #$00FF
 bne :lo_ok
 pla
 ora #$0001
 pha
:lo_ok
 pla
 pha
 and #$FF00
 bne :hi_ok
 pla
 ora #$0100
 pha
:hi_ok
 pla
 sta snd_noise,x
 inx
 inx
 cpx #SND_NOISE_LEN
 bcc :noise
* A square-wave buzz for UI feedback, period 16 samples, so
* it reads as a rough tone rather than noise.
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
 rts

*----------------------------------------------------------
* snd_rand - a 16-bit xorshift PRNG for the noise. State in
* snd_seed (nonzero). Returns A = next value. Native 16-bit.
*----------------------------------------------------------
snd_rand
 MX %00
 lda snd_seed
 sta snd_tmp
 asl
 asl
 asl
 asl
 asl
 asl
 asl                       ; x << 7
 eor snd_tmp               ; x ^= x << 7
 sta snd_tmp
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr
 lsr                       ; x >> 9
 eor snd_tmp               ; x ^= x >> 9
 sta snd_tmp
 xba                       ; x << 8 (byte swap)
 and #$FF00
 eor snd_tmp               ; x ^= x << 8
 sta snd_seed
 rts

*----------------------------------------------------------
* snd_play - play effect A (SFX_*). Stops that effect's
* generator first so a re-trigger never hits gen-busy, then
* _FFStartSound with the effect's parameter block. Native
* 16-bit. Clobbers A, X, Y. Errors from a missing DOC are
* ignored (the game stays mute).
*----------------------------------------------------------
snd_play
 MX %00
 and #$00FF
 asl
 tax
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
 rts

*----------------------------------------------------------
* Free-form-synth parameter blocks (18 bytes each): wave
* start (long), wave size (word), frequency (word), DOC RAM
* address (word, page in the high byte), DOC buffer size code
* (word, 0=256 .. 7=32768 bytes), next wave (long, 0 = one
* shot), volume (word, 0-255 in the low byte). DOC regions do
* not overlap, allowing for both oscillators of each pair.
*----------------------------------------------------------
snd_pb_move
 adrl snd_noise
 dw 512
 dw $0140                  ; low: a soft, deep tick
 dw $1000                  ; DOC $1000
 dw 1                      ; 512 bytes
 adrl 0
 dw $0070                  ; quiet, so moves do not nag
snd_pb_cannon
 adrl snd_noise
 dw 1024
 dw $0500                  ; high: a sharp crack
 dw $2000                  ; DOC $2000
 dw 2                      ; 1024 bytes
 adrl 0
 dw $00E0
snd_pb_explode
 adrl snd_noise
 dw 2048
 dw $0260                  ; mid: a longer boom
 dw $3000                  ; DOC $3000
 dw 3                      ; 2048 bytes
 adrl 0
 dw $00FF
snd_pb_ui
 adrl snd_buzz
 dw 512
 dw $02C0
 dw $5000                  ; DOC $5000
 dw 1                      ; 512 bytes
 adrl 0
 dw $00A0

snd_pb_tab  da snd_pb_move,snd_pb_cannon,snd_pb_explode,snd_pb_ui
snd_gen_tab dw GEN_MOVE,GEN_CANNON,GEN_EXPLODE,GEN_UI

SND_NOISE_LEN = 2048
SND_BUZZ_LEN  = 512

snd_seed  ds 2
snd_tmp   ds 2
snd_gen   ds 2
snd_pbptr ds 2
snd_noise ds SND_NOISE_LEN
snd_buzz  ds SND_BUZZ_LEN
