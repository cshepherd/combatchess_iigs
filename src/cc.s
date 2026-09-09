*----------------------------------------------------------
* CC.SYSTEM - Combat Chess launcher.
*
* ProDOS 8 loads every SYS file at $2000. This launcher
* relocates itself to $1000 on first entry so it can stay
* resident underneath the parts it chains between (TITLE
* and GAME, both ORG $2000). Public jump table at the top
* of the relocated launcher:
*
*   $1000  load TITLE   (also the boot / post-relocation entry)
*   $1002  load GAME
*   $1004  load TEST    (rules self-tests)
*
* Each entry is a 2-byte BRA into its loader stub. A part
* that finishes JMPs to one of these to chain to the next
* part. Every stub switches to emulation mode itself, so
* callers may arrive in any mode: a KEGS debugger session
* can enter with "00/1004g" from wherever the machine is
* parked. Nothing else is left resident between parts.
*
* Bank-$00 layout owned by the launcher:
*   $0C00-$0FFF  ProDOS 8 I/O buffer (1 KB, page-aligned)
*   $1000-$10FF  launcher code, MLI parameter blocks, paths
*   $1100-$11FF  cross-part globals (src/shared.s). Zeroed
*                once by the bootstrap; parts keep state
*                here that must survive chaining.
*----------------------------------------------------------

  ORG $1000
  MX %11

* Public jump table.
br_title     bra load_title            ; $1000
br_game      bra load_game             ; $1002
br_test      bra load_test             ; $1004

*----------------------------------------------------------
* load_title - Boot OR reload-TITLE entry.
*
* On the very first call ProDOS has just loaded us at $2000.
* Detect that from the runtime program counter rather than
* from memory contents: PER pushes the PC-relative address
* of :here, so its high byte is $10 once relocated and $20
* when still running from the load address. Checking the
* PC (instead of looking for BRA opcodes at $1000 as ddiigs
* does) means a stale launcher left in RAM by a warm reboot
* can never masquerade as the current one.
*----------------------------------------------------------
load_title
 sec
 xce                       ; emulation mode, whatever the caller had
 per :here
:here
 pla                       ; low byte of runtime address
 pla                       ; high byte: $10 relocated, $20 not
 cmp #$20
 bcs :do_bootstrap
 jmp :set_title_path

:do_bootstrap
* Copy one page ($2000-$20FF) down to $1000-$10FF, then zero
* the globals page. Uses only fixed absolute addresses plus
* a relative BNE, so it runs correctly while still executing
* from $2xxx (its own labels resolve to $1xxx but none are
* used here). ERR at the end of the file guarantees the
* launcher fits in that one page.
 ldx #$00
:cp_loop
 lda $2000,x
 sta $1000,x
 inx
 bne :cp_loop
:zero_loop
 stz $1100,x
 inx
 bne :zero_loop
* Continue in the relocated copy at $1000 before load_sounds
* reads the SOUNDS file into $2000 (which would clobber this
* bootstrap if we were still running from the load address).
 jmp :set_title_path

:set_title_path
 jsr load_sounds
 ldx #>title_path
 lda #<title_path
 jmp load_and_run


load_game
 sec
 xce
 ldx #>game_path
 lda #<game_path
 jmp load_and_run

load_test
 sec
 xce
 ldx #>test_path
 lda #<test_path
 jmp load_and_run

*----------------------------------------------------------
* load_and_run - OPEN the file at <path>, READ it to $2000,
* CLOSE, and JMP $2000. Runs in emulation mode with 8-bit
* M/X as ProDOS 8 requires. Any MLI error quits to ProDOS
* instead of hanging silently.
* Inputs: A = path low byte, X = path high byte.
*----------------------------------------------------------
load_and_run
 sta open_path
 stx open_path+1

 jsr $BF00
 dfb $C8                   ; OPEN
 da open_pblock
 bcs mli_error
 lda open_ref
 sta read_ref
 sta close_ref

 jsr $BF00
 dfb $CA                   ; READ
 da read_pblock
 bcs mli_error

 jsr $BF00
 dfb $CC                   ; CLOSE
 da close_pblock
 bcs mli_error

 jmp $2000

*----------------------------------------------------------
* load_sounds - once per boot, read the SOUNDS file (ripped
* effect samples) into $2000 and block-move it to bank $02,
* where GAME reads it. Done here, in ProDOS 8's clean boot
* state, because the MLI crashes once the toolbox is up.
* snd_blk / snd_loaded (page $11) tell GAME it is there. A
* missing file just leaves the game mute. Reuses the OPEN /
* READ / CLOSE parameter blocks below.
*----------------------------------------------------------
load_sounds
 lda $1124                 ; snd_loaded
 bne :done
 lda #<snd_path
 sta open_path
 lda #>snd_path
 sta open_path+1
 jsr $BF00
 dfb $C8                   ; OPEN
 da open_pblock
 bcs :done
 lda open_ref
 sta read_ref
 sta close_ref
 jsr $BF00
 dfb $CA                   ; READ into $2000 (up to read_count, i.e. to EOF)
 da read_pblock
 jsr $BF00
 dfb $CC                   ; CLOSE
 da close_pblock
 clc
 xce                       ; native for the block move
 rep #$30
 ldx #$2000
 ldy #$0000
 lda read_xfer
 dec
 mvn $00,$02               ; $00/2000 -> $02/0000
 phk
 plb                       ; MVN left DBR = $02; restore bank 0 for the globals
 sep #$30
 sec
 xce
 lda #$02
 sta $1122                 ; snd_blk+2 = bank $02 (rest pre-zeroed)
 lda #1
 sta $1124                 ; snd_loaded
:done
 rts

mli_error
 sta mli_errcode           ; visible in a debugger after the QUIT
 jsr $BF00
 dfb $65                   ; QUIT
 da quit_pblock
 bra mli_error             ; QUIT never returns; belt and braces

*----------------------------------------------------------
* ProDOS MLI parameter blocks.
*----------------------------------------------------------
open_pblock  dfb 3
open_path    dw 0             ; pathname pointer (set per call)
open_iobuf   dw $0C00         ; ProDOS I/O buffer (1 KB, page-aligned)
open_ref     dfb 0

read_pblock  dfb 4
read_ref     dfb 0
read_buf     dw $2000         ; load address for the SYS file
read_count   dw $9F00         ; max bytes: $2000..$BEFF, i.e. up to
                              ; the ProDOS global page at $BF00
read_xfer    dw 0             ; bytes actually read

close_pblock dfb 1
close_ref    dfb 0

quit_pblock  dfb 4
             dfb 0            ; quit type
             dw 0             ; reserved
             dfb 0            ; reserved
             dw 0             ; reserved

mli_errcode  dfb 0

*----------------------------------------------------------
* Pathnames (ProDOS 8 format: length byte, then chars).
* Relative to the boot volume, which ProDOS sets as the
* prefix before running the first .SYSTEM file.
*----------------------------------------------------------
title_path    str 'TITLE'
game_path     str 'GAME'
test_path     str 'TEST'
snd_path      str 'SOUNDS'

* The bootstrap copies exactly one page. Fail the build if
* the launcher ever grows past $10FF.
 err *-1/$1100
