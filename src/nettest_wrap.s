*----------------------------------------------------------
* nettest_wrap.s - exercise net_send / net_recv across the 2KB
* socket-ring wrap (spec N1 hardening).
*
* Poked into a running MAME and run from $2000 like nettest.s.
* Connects to the echo server, then:
*   1. sends 1500 bytes (pattern byte i = i & $FF), receives
*      them back, verifying each -- this advances TX_WR/RX_RD
*      to 1500, short of the 2048 ring top;
*   2. sends 1000 bytes (pattern byte i = (i+1) & $FF), which
*      straddles the ring wrap (1500..2047 then 0..451), and
*      receives them back, verifying each.
* A correct wrap split leaves both mismatch counts zero.
*
* Result block:
*   $0300  slot                    ($FF none)
*   $0301  dhcp result             ($00 lease)
*   $0302  socket status at connect
*   $0303  connect result
*   $0310  block1 bytes received (16-bit)
*   $0312  block1 mismatches (capped 255)
*   $0313  block2 bytes received (16-bit)
*   $0315  block2 mismatches (capped 255)
*   $0304  $A5 done marker (written last)
*----------------------------------------------------------
            org   $2000
            mx    %11

BLK1        = 1500
BLK2        = 1000

start       sei
            sec
            xce
            cld
            ldx   #$FF
            txs
            lda   #$00
            pha
            plb

            ldx   #$1F                   ; poison the result block
            lda   #$EE
:poison     sta   $0300,x
            dex
            bpl   :poison

            jsr   net_init
            bcc   :found
            lda   #$FF
            sta   $0300
            jmp   :done
:found      sta   $0300

            jsr   net_config_static
            jsr   net_configure
            lda   #$00
            bcc   :leased
            lda   #$FF
:leased     sta   $0301

            ldx   #3                       ; connect to the gateway host
:setdst     lda   net_gw,x
            sta   net_dest_ip,x
            dex
            bpl   :setdst
            jsr   net_connect
            lda   #$00
            bcc   :cok
            lda   #$FF
:cok        sta   $0303

            stz   $0327
:estwait    jsr   net_poll
            cmp   #W5_SOCK_ESTAB
            beq   :estab
            cmp   #W5_SOCK_CLOSED
            beq   :estab
            inc   $0327
            beq   :estab
            jsr   net_delay
            bra   :estwait
:estab      jsr   net_poll
            sta   $0302
            cmp   #W5_SOCK_ESTAB
            beq   :go
            jmp   :done
:go

* --- block 1: pattern i&$FF, length BLK1 ---
            lda   #$00                     ; xor mask 0 -> byte = index & $FF
            sta   patmask
            lda   #<BLK1
            sta   blklen+0
            lda   #>BLK1
            sta   blklen+1
            jsr   fill_src                 ; net_srcbuf[i] = (i & $FF) ^ patmask
            jsr   send_block               ; net_send net_srcbuf, BLK1
            jsr   recv_verify              ; receive BLK1 bytes, verify vs pattern
            lda   rcvd+0                    ; -> $0310/$0311 count, $0312 mism
            sta   $0310
            lda   rcvd+1
            sta   $0311
            lda   mism
            sta   $0312

* --- block 2: pattern (i+1)&$FF, length BLK2 -- straddles the wrap ---
            lda   #$01                     ; xor mask so the pattern differs...
            sta   patmask                  ;   actually use +1 offset via patadd
            lda   #<BLK2
            sta   blklen+0
            lda   #>BLK2
            sta   blklen+1
            jsr   fill_src2                 ; net_srcbuf[i] = (i+1) & $FF
            jsr   send_block
            jsr   recv_verify2
            lda   rcvd+0
            sta   $0313
            lda   rcvd+1
            sta   $0314
            lda   mism
            sta   $0315

            jsr   net_close

:done       lda   #$A5
            sta   $0304
:spin       bra   :spin

*----------------------------------------------------------
* fill_src: net_srcbuf[i] = i & $FF, for i in 0..blklen-1.
* fill_src2: net_srcbuf[i] = (i+1) & $FF.
*----------------------------------------------------------
fill_src
            lda   #<net_srcbuf
            sta   NPTR
            lda   #>net_srcbuf
            sta   NPTR+1
            lda   blklen+0
            sta   fcnt+0
            lda   blklen+1
            sta   fcnt+1
            lda   #0
            sta   fidx
:fl         lda   fidx
            sta   (NPTR)
            inc   fidx
            inc   NPTR
            bne   :fn
            inc   NPTR+1
:fn         lda   fcnt+0
            bne   :fd
            dec   fcnt+1
:fd         dec   fcnt+0
            lda   fcnt+0
            ora   fcnt+1
            bne   :fl
            rts

fill_src2
            lda   #<net_srcbuf
            sta   NPTR
            lda   #>net_srcbuf
            sta   NPTR+1
            lda   blklen+0
            sta   fcnt+0
            lda   blklen+1
            sta   fcnt+1
            lda   #1
            sta   fidx
:fl         lda   fidx
            sta   (NPTR)
            inc   fidx
            inc   NPTR
            bne   :fn
            inc   NPTR+1
:fn         lda   fcnt+0
            bne   :fd
            dec   fcnt+1
:fd         dec   fcnt+0
            lda   fcnt+0
            ora   fcnt+1
            bne   :fl
            rts

*----------------------------------------------------------
* send_block: net_send net_srcbuf, blklen (<= 2048).
*----------------------------------------------------------
send_block
            lda   #<net_srcbuf
            sta   NPTR
            lda   #>net_srcbuf
            sta   NPTR+1
            lda   blklen+0
            sta   net_len+0
            lda   blklen+1
            sta   net_len+1
            jsr   net_send
            rts

*----------------------------------------------------------
* recv_verify / recv_verify2: receive blklen bytes into
* net_dstbuf (bounded idle polling), then compare against the
* block's pattern. rcvd = bytes received (16-bit); mism = count
* of mismatches (capped 255). recv_verify expects i&$FF,
* recv_verify2 expects (i+1)&$FF.
*----------------------------------------------------------
recv_verify
            jsr   recv_block
            lda   #0
            sta   patadd
            jmp   verify
recv_verify2
            jsr   recv_block
            lda   #1
            sta   patadd
            jmp   verify

* recv_block: accumulate blklen bytes from net_recv into
* net_dstbuf. rcvd = total received (may stop short on timeout).
recv_block
            stz   rcvd+0
            stz   rcvd+1
            stz   rpoll
            lda   #<net_dstbuf
            sta   rdst+0
            lda   #>net_dstbuf
            sta   rdst+1
:rl         lda   rdst+0                  ; NRXP -> next free dst slot
            sta   NRXP
            lda   rdst+1
            sta   NRXP+1
            lda   #$00                     ; read up to 256 bytes per call
            sta   net_len+0
            lda   #$01
            sta   net_len+1
            jsr   net_recv
            lda   net_rcvd+0
            ora   net_rcvd+1
            beq   :idle
            stz   rpoll
            clc                            ; rdst += net_rcvd
            lda   rdst+0
            adc   net_rcvd+0
            sta   rdst+0
            lda   rdst+1
            adc   net_rcvd+1
            sta   rdst+1
            clc                            ; rcvd += net_rcvd
            lda   rcvd+0
            adc   net_rcvd+0
            sta   rcvd+0
            lda   rcvd+1
            adc   net_rcvd+1
            sta   rcvd+1
            lda   rcvd+1                   ; done when rcvd >= blklen
            cmp   blklen+1
            bcc   :rl
            bne   :rdone
            lda   rcvd+0
            cmp   blklen+0
            bcc   :rl
:rdone      rts
:idle       inc   rpoll
            beq   :rdone                  ; 256 idle polls -> give up
            jsr   net_delay
            bra   :rl

* verify: compare net_dstbuf[i] against (i + patadd) & $FF for
* i in 0..rcvd-1; mism = mismatch count (capped 255).
verify
            lda   #<net_dstbuf
            sta   NPTR
            lda   #>net_dstbuf
            sta   NPTR+1
            lda   rcvd+0
            sta   fcnt+0
            lda   rcvd+1
            sta   fcnt+1
            stz   mism
            lda   patadd
            sta   fidx
            lda   fcnt+0                   ; nothing received -> no compares
            ora   fcnt+1
            beq   :vdone
:vl         lda   (NPTR)
            cmp   fidx
            beq   :vok
            lda   mism                     ; count mismatch (cap 255)
            cmp   #$FF
            beq   :vok
            inc   mism
:vok        inc   fidx
            inc   NPTR
            bne   :vn
            inc   NPTR+1
:vn         lda   fcnt+0
            bne   :vd
            dec   fcnt+1
:vd         dec   fcnt+0
            lda   fcnt+0
            ora   fcnt+1
            bne   :vl
:vdone      rts

*----------------------------------------------------------
* Harness state + buffers.
*----------------------------------------------------------
patmask      dfb   0
patadd       dfb   0
patmask2     dfb   0
blklen       dfb   0,0
fcnt         dfb   0,0
fidx         dfb   0
rcvd         dfb   0,0
mism         dfb   0
rpoll        dfb   0
rdst         dfb   0,0

net_srcbuf   ds    2048
net_dstbuf   ds    2048

            put   net
            put   netdhcp
