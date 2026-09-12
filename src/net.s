*----------------------------------------------------------
* net.s - Wiznet W5100 (Uthernet II) TCP client for the
* network-play milestone (spec N1). A faithful port of the
* proven driver in ../hdtelnet (hdtelnet.s), adapted to the
* Combat Chess house style:
*
*   - Entered in native mode, 8-bit A/X/Y (MX %11), DBR $00,
*     D $0000, exactly like the rules engine.
*   - No ProDOS, printing or exit dependencies: every routine
*     returns to its caller with a status in carry / A.
*   - Binary-clean: net_send_byte never rewrites CR as CRLF.
*   - Spec API names (net_init / net_connect / net_poll /
*     net_send_byte / net_recv_byte / net_close). DHCP
*     (net_configure) is ported separately; net_config_static
*     fills the same parameter block for bring-up.
*
* The W5100 is driven in Indirect Bus mode with address
* auto-increment (MR=$03): a 16-bit register address is set
* through two I/O bytes, then data streams through a third.
* The Uthernet II decodes those four bytes at slot offset
* +4..+7 ($C0n4-$C0n7, n = slot+8); net_setbase patches the
* low byte of each access instruction for the detected slot.
* MAME's a2uthernet2 mirrors the four registers across the
* whole $C0n0-$C0nF window, so the same addresses work there.
*
* Socket 0 memory (default 2KB per socket, RMSR/TMSR=$55):
* TX buffer at $4000, RX buffer at $6000, each a 2KB ring
* masked by $07FF -- the translation netin/out perform on the
* raw read/write pointers.
*----------------------------------------------------------

* --- W5100 common + socket-0 register addresses (16-bit) ---
W5_MR       = $0000            ; mode register (via the MR I/O byte, not indirect)
W5_GAR      = $0001            ; gateway address (4)
W5_SUBR     = $0005            ; subnet mask (4)
W5_SHAR     = $0009            ; source MAC (6)
W5_SIPR     = $000F            ; source IP (4)
W5_RMSR     = $001A            ; RX memory size per socket
W5_TMSR     = $001B            ; TX memory size per socket
W5_S0_MR    = $0400            ; socket 0 mode
W5_S0_CR    = $0401            ; socket 0 command
W5_S0_SR    = $0403            ; socket 0 status
W5_S0_PORT  = $0404            ; socket 0 source port (2)
W5_S0_DHAR  = $0406            ; socket 0 dest MAC (6)
W5_S0_DIPR  = $040C            ; socket 0 dest IP (4)
W5_S0_DPORT = $0410            ; socket 0 dest port (2)
W5_S0_TXFSR = $0420            ; socket 0 TX free size (2)
W5_S0_TXWR  = $0424            ; socket 0 TX write pointer (2)
W5_S0_RXRSR = $0426            ; socket 0 RX received size (2)
W5_S0_RXRD  = $0428            ; socket 0 RX read pointer (2)

* Socket command values.
W5_CMD_OPEN    = $01
W5_CMD_CONNECT = $04
W5_CMD_DISCON  = $08
W5_CMD_CLOSE   = $10
W5_CMD_SEND    = $20
W5_CMD_RECV    = $40

* Socket status values.
W5_SOCK_CLOSED = $00
W5_SOCK_INIT   = $13
W5_SOCK_ESTAB  = $17

W5_MODE_TCP    = $01           ; S0_MR: TCP
W5_MODE_IND    = $03           ; MR: indirect bus + address auto-increment
W5_MEM_2K_EACH = $55           ; RMSR/TMSR: 2KB to each of the four sockets

* Socket 0 buffer bases and ring mask in W5100 memory.
W5_TX_BASE_HI  = $40           ; $4000
W5_RX_BASE_HI  = $60           ; $6000
W5_RING_MASK_HI = $07           ; 2KB-1 high byte

* Direct-page pointers for the DHCP UDP copy loops (netdhcp.s).
* These alias shared.s rptr/rptr2 ($E4/$E6): only live inside one
* net routine, never held across a call, so they are safe to use
* here and standalone (emulation DP $0000) alike.
NPTR = $E4
NRXP = $E6

* A locally-administered MAC for the emulated/real card. The
* DHCP client identifier must use this same value.
NET_MAC0 = $08
NET_MAC1 = $00
NET_MAC2 = $20
NET_MAC3 = $CC                 ; "CC" = Combat Chess
NET_MAC4 = $CC
NET_MAC5 = $01

*----------------------------------------------------------
* Register-access primitives. net_setbase patches the low
* byte of each $C0nX operand below; until it runs the operands
* read $C000 and do nothing useful.
*----------------------------------------------------------

* net_setaddr: A = address hi, X = address lo -> both bytes.
net_setaddr
np_ah       sta   $C000              ; +1 = base+5 (address hi)
* net_setaddrlo: X = address lo -> low byte only.
net_setaddrlo
np_al       stx   $C000              ; +1 = base+6 (address lo)
            rts

* net_setmr: A -> MR (the direct mode register byte).
net_setmr
np_mr       sta   $C000              ; +1 = base+4 (MR)
            rts

* net_getmr: MR -> A.
net_getmr
np_mrr      lda   $C000              ; +1 = base+4 (MR)
            rts

* net_setdata: A -> data (auto-increments the register address).
net_setdata
np_wd       sta   $C000              ; +1 = base+7 (data)
            rts

* net_getdata: data -> A (auto-increments the register address).
net_getdata
np_rd       lda   $C000              ; +1 = base+7 (data)
            rts

* net_setbase: A = slot (1-7). Patch every access operand's low
* byte to this slot's I/O window (offset +4..+7 within $C0nX).
* Clobbers A. X/Y preserved.
net_setbase
            phx
            asl                       ; slot * 16
            asl
            asl
            asl
            clc
            adc   #$84                ; MR at $C0(slot*16+$84) = base+4
            sta   np_mr+1
            sta   np_mrr+1
            inc                       ; +5 address hi
            sta   np_ah+1
            inc                       ; +6 address lo
            sta   np_al+1
            inc                       ; +7 data
            sta   np_wd+1
            sta   np_rd+1
            plx
            rts

*----------------------------------------------------------
* net_init: detect the Uthernet II, reset it, and leave it in
* indirect+auto-increment mode with net_slot / the access
* operands set. Returns carry clear on success (A = slot),
* carry set if no card was found.
* Clobbers A/X/Y.
*----------------------------------------------------------
net_init
            ldx   #$FF
:next       inx
            lda   net_slots,x
            bmi   :notfound           ; $FF terminator (only 0-7 are valid)
            pha                        ; remember the candidate slot
            jsr   net_probe            ; carry clear if a W5100 answered
            bcc   :found
            pla
            bra   :next
:found      pla
            sta   net_slot
            jsr   net_setbase          ; lock the operands to this slot
            lda   #W5_MODE_IND         ; leave the chip in indirect+AI mode
            jsr   net_setmr
            clc
            lda   net_slot
            rts
:notfound   sec
            rts

* net_probe: A = candidate slot. Point the access operands at it,
* reset (MR=$80, must read back 0), then set indirect mode
* (MR=$03, must read back $03). Carry clear if both held -- a
* real W5100 -- else carry set. Clobbers A. X/Y preserved.
net_probe
            jsr   net_setbase
            lda   #$80                 ; software reset
            jsr   net_setmr
            jsr   net_getmr
            bne   :fail                ; reset must self-clear to 0
            lda   #W5_MODE_IND
            jsr   net_setmr
            jsr   net_getmr
            cmp   #W5_MODE_IND
            bne   :fail                ; a real chip latches the mode
            clc
            rts
:fail       sec
            rts

* Slot probe order (Uthernet II is usually in 1 or 3). $FF ends.
net_slots   dfb   1,7,2,4,3,5,6,0,$FF

*----------------------------------------------------------
* net_config_static: fill the parameter block from the caller's
* net_gw / net_mask / net_ip (already stored) and the fixed MAC.
* Used for bring-up before DHCP is wired in; net_configure will
* fill the same block from a lease. Clobbers A/X.
*----------------------------------------------------------
net_config_static
            lda   #NET_MAC0
            sta   net_mac+0
            lda   #NET_MAC1
            sta   net_mac+1
            lda   #NET_MAC2
            sta   net_mac+2
            lda   #NET_MAC3
            sta   net_mac+3
            lda   #NET_MAC4
            sta   net_mac+4
            lda   #NET_MAC5
            sta   net_mac+5
            rts

*----------------------------------------------------------
* net_connect: open socket 0 as TCP and issue CONNECT to
* net_dest_ip:net_dest_port. Writes the whole parameter block
* (gw/mask/mac/ip), sizes the socket buffers, sets the source
* port, and waits for SOCK_INIT before commanding CONNECT.
* Returns carry clear once CONNECT is issued (poll net_poll for
* SOCK_ESTAB), carry set if the socket never reached SOCK_INIT.
* Clobbers A/X/Y.
*----------------------------------------------------------
net_connect
            lda   #W5_MODE_IND         ; ensure indirect+AI
            jsr   net_setmr

            lda   #>W5_GAR             ; $0001: gw(4)+mask(4)+mac(6)+ip(4)
            ldx   #<W5_GAR
            jsr   net_setaddr
            ldx   #0
:cfg        lda   net_cfg,x
            jsr   net_setdata
            inx
            cpx   #18
            bne   :cfg

            lda   #>W5_RMSR            ; $001A: RX then TX memory size
            ldx   #<W5_RMSR
            jsr   net_setaddr
            lda   #W5_MEM_2K_EACH
            jsr   net_setdata          ; RMSR
            lda   #W5_MEM_2K_EACH
            jsr   net_setdata          ; TMSR (auto-inc)

            lda   #>W5_S0_PORT         ; $0404: socket 0 source port
            ldx   #<W5_S0_PORT
            jsr   net_setaddr
            lda   net_src_port+0
            jsr   net_setdata
            lda   net_src_port+1
            jsr   net_setdata

            lda   #>W5_S0_MR           ; $0400: socket 0 mode = TCP
            ldx   #<W5_S0_MR
            jsr   net_setaddr
            lda   #W5_MODE_TCP
            jsr   net_setdata

            lda   #>W5_S0_CR           ; $0401: OPEN
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            lda   #W5_CMD_OPEN
            jsr   net_setdata

            lda   #>W5_S0_DIPR         ; $040C: dest ip(4) + dest port(2)
            ldx   #<W5_S0_DIPR
            jsr   net_setaddr
            ldx   #0
:dst        lda   net_dest_ip,x
            jsr   net_setdata
            inx
            cpx   #6
            bne   :dst

* Wait for the OPEN to advance the socket to SOCK_INIT, bounded
* by a 16-bit retry counter so a dead card cannot hang the game.
* net_setaddr clobbers X, so the counter lives in memory.
            stz   net_timeout+0
            stz   net_timeout+1
:wait       lda   #>W5_S0_SR
            ldx   #<W5_S0_SR
            jsr   net_setaddr
            jsr   net_getdata
            cmp   #W5_SOCK_INIT
            beq   :inited
            inc   net_timeout+0
            bne   :wait
            inc   net_timeout+1
            bne   :wait
            sec                         ; timed out: never reached SOCK_INIT
            rts

:inited     lda   #>W5_S0_CR           ; $0401: CONNECT
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            lda   #W5_CMD_CONNECT
            jsr   net_setdata
            clc
            rts

*----------------------------------------------------------
* net_poll: read socket 0 status ($0403) into A. Handy values:
* $00 CLOSED, $13 SOCK_INIT, $17 SOCK_ESTAB. Clobbers A. X/Y kept.
*----------------------------------------------------------
net_poll
            lda   #>W5_S0_SR
            phx
            ldx   #<W5_S0_SR
            jsr   net_setaddr
            plx
            jsr   net_getdata
            rts

*----------------------------------------------------------
* net_close: issue DISCON on socket 0 (graceful FIN). Clobbers A.
*----------------------------------------------------------
net_close
            lda   #>W5_S0_CR
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            lda   #W5_CMD_DISCON
            jsr   net_setdata
            rts

*----------------------------------------------------------
* net_send_byte: A = byte to send on socket 0. Reads TX_WR,
* translates it into the 2KB TX ring at $4000, waits for free
* space, writes the byte, advances TX_WR, and commands SEND,
* waiting for the command register to clear. Binary-clean.
* Preserves nothing meaningful; returns with carry clear.
* Clobbers A/X/Y and the net scratch words.
*----------------------------------------------------------
net_send_byte
            sta   net_tmp             ; hold the data byte

            lda   #>W5_S0_TXWR        ; $0424: TX write pointer
            ldx   #<W5_S0_TXWR
            jsr   net_setaddr
            jsr   net_getdata
            sta   ntx_wr+1            ; high byte first (big-endian on the wire)
            sta   ntx_ptr+1
            jsr   net_getdata
            sta   ntx_wr+0
            sta   ntx_ptr+0

            lda   ntx_wr+0            ; translate low = raw low (& $FF)
            sta   ntx_wr+0
            lda   ntx_wr+1           ; high = (raw hi & $07) + $40  -> $4000 ring
            and   #W5_RING_MASK_HI
            clc
            adc   #W5_TX_BASE_HI
            sta   ntx_wr+1

:free       lda   #>W5_S0_TXFSR      ; $0420: wait for any free space
            ldx   #<W5_S0_TXFSR
            jsr   net_setaddr
            jsr   net_getdata
            sta   ntx_free+1
            jsr   net_getdata
            sta   ntx_free+0
            lda   ntx_free+0
            ora   ntx_free+1
            beq   :free

            lda   ntx_wr+1           ; write the byte at the ring address
            ldx   ntx_wr+0
            jsr   net_setaddr
            lda   net_tmp
            jsr   net_setdata

            inc   ntx_ptr+0          ; advance the raw pointer by 1
            bne   :nohi
            inc   ntx_ptr+1
:nohi
            lda   #>W5_S0_TXWR       ; write TX_WR back (raw, untranslated)
            ldx   #<W5_S0_TXWR
            jsr   net_setaddr
            lda   ntx_ptr+1
            jsr   net_setdata
            lda   ntx_ptr+0
            jsr   net_setdata

            lda   #>W5_S0_CR         ; SEND
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            lda   #W5_CMD_SEND
            jsr   net_setdata

:wt         lda   #>W5_S0_CR         ; wait for the command register to clear
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            jsr   net_getdata
            bne   :wt
            clc
            rts

*----------------------------------------------------------
* net_recv_byte: pull one byte from socket 0's RX ring. Returns
* carry set with the byte in A, or carry clear if none is
* available yet. Does NOT distinguish an empty ring from a
* closed socket -- the caller polls net_poll for close. Reads
* RX_RSR, and on a byte reads it at the translated $6000 ring
* address, advances RX_RD, and commands RECV.
* Clobbers A/X/Y and the net scratch words.
*----------------------------------------------------------
net_recv_byte
            lda   #>W5_S0_RXRD       ; $0428: RX read pointer
            ldx   #<W5_S0_RXRD
            jsr   net_setaddr
            jsr   net_getdata
            sta   nrx_rd+1
            sta   nrx_rd_orig+1
            jsr   net_getdata
            sta   nrx_rd+0
            sta   nrx_rd_orig+0

            lda   nrx_rd+1           ; translate into the $6000 RX ring
            and   #W5_RING_MASK_HI
            clc
            adc   #W5_RX_BASE_HI
            sta   nrx_rd+1

            lda   #>W5_S0_RXRSR      ; $0426: received size
            ldx   #<W5_S0_RXRSR
            jsr   net_setaddr
            jsr   net_getdata
            sta   nrx_rcvd+1
            jsr   net_getdata
            sta   nrx_rcvd+0
            ora   nrx_rcvd+1
            bne   :have
            clc                       ; nothing waiting
            rts

:have       lda   nrx_rd+1           ; read the byte at the ring address
            ldx   nrx_rd+0
            jsr   net_setaddr
            jsr   net_getdata
            sta   net_tmp

            inc   nrx_rd_orig+0      ; advance the raw read pointer by 1
            bne   :nohi
            inc   nrx_rd_orig+1
:nohi
            lda   #>W5_S0_RXRD       ; write RX_RD back (raw, untranslated)
            ldx   #<W5_S0_RXRD
            jsr   net_setaddr
            lda   nrx_rd_orig+1
            jsr   net_setdata
            lda   nrx_rd_orig+0
            jsr   net_setdata

            lda   #>W5_S0_CR         ; RECV: we consumed a byte
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            lda   #W5_CMD_RECV
            jsr   net_setdata

            lda   net_tmp
            sec
            rts

*----------------------------------------------------------
* Driver state (bank $00 data, part-local). The parameter block
* is one contiguous 18-byte run so net_connect can stream it.
*----------------------------------------------------------
net_slot     dfb   0                  ; detected slot (1-7)

net_cfg      = *                      ; --- 18-byte W5100 config block ---
net_gw       dfb   0,0,0,0            ; gateway IP
net_mask     dfb   0,0,0,0            ; subnet mask
net_mac      dfb   0,0,0,0,0,0        ; source MAC
net_ip       dfb   0,0,0,0            ; our IP

net_src_port dfb   $19,$66           ; source port (default 6502)
net_dest_ip  dfb   0,0,0,0            ; connect target IP
net_dest_port dfb  $07,$C0           ; connect target port (default 1984)

net_tmp      dfb   0                  ; one-byte scratch across I/O calls
net_timeout  dfb   0,0               ; net_connect SOCK_INIT poll counter
ntx_wr       dfb   0,0                ; translated TX write address
ntx_ptr      dfb   0,0               ; raw TX write pointer
ntx_free     dfb   0,0               ; TX free size
nrx_rd       dfb   0,0               ; translated RX read address
nrx_rd_orig  dfb   0,0               ; raw RX read pointer
nrx_rcvd     dfb   0,0               ; RX received size
