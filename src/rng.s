*----------------------------------------------------------
* rng.s - Seedable random numbers and shot resolution
* (spec 11.3, 30, 33, 37, 38).
*
* PUT into any part that carries the rules engine, after
* shared.s and tables.s. Same calling convention as
* tables.s: native mode, 8-bit A/X/Y, DBR $00, D $0000.
*
* Generator: xorshift32 (shifts 13, 17, 5). 32-bit state,
* period 2^32-1, cheap in 16-bit 65816 arithmetic. The
* whole state is the 4 bytes at rng_state: save games store
* them verbatim (spec 37) and replays either restore them or
* log the roll resolve_hit returns (spec 38). Changing the
* generator, the byte drawn, or the roll mapping changes
* every replay, so tools/rng_ref.py mirrors this exactly and
* the self-tests hold known answers from it.
*
* Injection: resolve_hit gets its roll through roll_vec,
* which normally points at rng_roll100. Tests point it at a
* stub to force hits and misses, then restore it.
*----------------------------------------------------------

* xorshift32 cannot leave state zero, so a zero seed becomes
* this instead.
RNG_DEFAULT_SEED = $2545F491

*----------------------------------------------------------
* rng_seed - Seed the generator.
* In: rt0..rt3 = 32-bit seed, little-endian. Zero is
*     replaced by RNG_DEFAULT_SEED.
*----------------------------------------------------------
rng_seed
 MX %11
 lda rt0
 sta rng_state
 lda rt1
 sta rng_state+1
 lda rt2
 sta rng_state+2
 lda rt3
 sta rng_state+3
 ora rt0
 ora rt1
 ora rt2
 bne :done
 lda #<RNG_DEFAULT_SEED
 sta rng_state
 lda #>RNG_DEFAULT_SEED
 sta rng_state+1
 lda #^RNG_DEFAULT_SEED
 sta rng_state+2
 lda #RNG_DEFAULT_SEED/$1000000
 sta rng_state+3
:done
 rts

*----------------------------------------------------------
* rng_next - Advance the state one step.
* Out: A = the new state's top byte (bits 24-31).
* Clobbers rt0-rt3. Preserves X and Y.
*
* With the state as two 16-bit words lo:hi,
*   x ^= x << 13   hi ^= (hi<<13)|(lo>>3);  lo ^= lo<<13
*   x ^= x >> 17   lo ^= hi>>1
*   x ^= x << 5    hi ^= (hi<<5)|(lo>>11);  lo ^= lo<<5
* Each step computes the new hi from the old lo first.
*----------------------------------------------------------
rng_next
 MX %11
 rep #$20
 MX %01
* x ^= x << 13
 lda rng_state+2
 xba
 and #$FF00
 asl
 asl
 asl
 asl
 asl                       ; hi << 13
 sta rt0
 lda rng_state
 lsr
 lsr
 lsr                       ; lo >> 3
 ora rt0
 eor rng_state+2
 sta rt2                   ; new hi, pending
 lda rng_state
 xba
 and #$FF00
 asl
 asl
 asl
 asl
 asl                       ; lo << 13
 eor rng_state
 sta rng_state
 lda rt2
 sta rng_state+2
* x ^= x >> 17
 lda rng_state+2
 lsr                       ; hi >> 1
 eor rng_state
 sta rng_state
* x ^= x << 5
 lda rng_state+2
 asl
 asl
 asl
 asl
 asl                       ; hi << 5
 sta rt0
 lda rng_state
 xba
 and #$00FF
 lsr
 lsr
 lsr                       ; lo >> 11
 ora rt0
 eor rng_state+2
 sta rt2                   ; new hi, pending
 lda rng_state
 asl
 asl
 asl
 asl
 asl                       ; lo << 5
 eor rng_state
 sta rng_state
 lda rt2
 sta rng_state+2
 sep #$20
 MX %11
 lda rng_state+3
 rts

*----------------------------------------------------------
* rng_roll100 - Uniform roll 0-99 by rejection: draw bytes
* until one is below 200, then fold 100-199 down.
* Out: A = 0..99. Clobbers rt0-rt3. Preserves X and Y.
*----------------------------------------------------------
rng_roll100
 MX %11
:again
 jsr rng_next
 cmp #200
 bcs :again
 cmp #100
 bcc :done
 sbc #100                  ; carry is set here
:done
 rts

*----------------------------------------------------------
* resolve_hit - Roll against a hit percentage (spec 11.3).
* In:  A = hit percent, 0..100 (from hit_chance)
* Out: carry set = hit, clear = miss
*      A = the roll used (0..99), for replay logs
* Hit when roll < percent, so 100 always hits and 0 never.
* Draws the roll through roll_vec. Clobbers rt0-rt3.
*----------------------------------------------------------
resolve_hit
 MX %11
 pha                       ; percent
 jsr call_roll             ; A = 0..99
 sta rt1
 pla
 sta rt0
 lda rt1
 cmp rt0                   ; carry clear iff roll < percent
 bcc :hit
 clc
 rts
:hit
 sec
 rts

call_roll jmp (roll_vec)

roll_vec  da rng_roll100
rng_state ds 4
