*----------------------------------------------------------
* nettest.s - standalone W5100 driver bring-up (spec N1).
*
* Not part of the game build. Assembled on its own and poked
* into a running MAME (apple2gs, Uthernet II in slot 1) through
* the claudebridge Lua harness, then run from $2000. It drives
* the real src/net.s + src/netdhcp.s routines against the
* emulated chip and leaves a result block the harness reads:
*
*   $0300  slot from net_init, or $FF if no card found
*   $0301  net_configure result: $00 lease/proceed, $FF no OFFER
*   $0302  socket 0 status after net_connect (net_poll)
*   $0303  net_connect result: $00 reached SOCK_INIT, else $FF
*   $0304  $A5 done marker (written last)
*   $0310  net_ip (4)      leased address
*   $0314  net_gw (4)      gateway (router option)
*   $0318  net_mask (4)    subnet mask
*   $031C  net_server (4)  DHCP server
*
* Runs in emulation mode, 8-bit -- no toolbox, no ProDOS calls,
* interrupts masked, spins at the end so the harness can sample
* the result block before the machine is reset. Needs vmnet up
* for DHCP to return a real lease.
*----------------------------------------------------------
            org   $2000
            mx    %11

start       sei                         ; no interrupts during the probe
            sec
            xce                         ; force emulation mode, 8-bit
            cld
            ldx   #$FF                   ; a fresh stack, wherever we were yanked from
            txs
            lda   #$00                   ; DBR = 0 so absolute stores hit bank 0
            pha
            plb

            ldx   #$2F                   ; poison the whole $0300..$032F block
            lda   #$EE
:poison     sta   $0300,x
            dex
            bpl   :poison

            jsr   net_init
            bcc   :found
            lda   #$FF                   ; no card
            sta   $0300
            jmp   :done                  ; (far: past the DHCP + echo stages)
:found      sta   $0300                  ; A = slot

            jsr   net_config_static       ; fills the MAC

            jsr   net_configure           ; DHCP: DISCOVER/OFFER/REQUEST/ACK
            lda   #$00
            bcc   :leased
            lda   #$FF                    ; never heard an OFFER
:leased     sta   $0301

            ldx   #3                       ; echo the lease into the result block
:copy       lda   net_ip,x
            sta   $0310,x
            lda   net_gw,x
            sta   $0314,x
            lda   net_mask,x
            sta   $0318,x
            lda   net_server,x
            sta   $031C,x
            dex
            bpl   :copy

* --- echo round-trip: connect to the gateway host : net_dest_port ---
* The echo server runs on the host, reachable at the DHCP gateway
* (192.168.2.1) on the isolated vmnet; net_dest_port defaults to 1984.
            ldx   #3
:setdst     lda   net_gw,x
            sta   net_dest_ip,x
            dex
            bpl   :setdst

            jsr   net_connect
            lda   #$00
            bcc   :cok
            lda   #$FF                    ; never reached SOCK_INIT
:cok        sta   $0303

            stz   $0327                   ; connect poll counter
:estwait    jsr   net_poll
            cmp   #W5_SOCK_ESTAB
            beq   :estab
            cmp   #W5_SOCK_CLOSED         ; connect failed / refused
            beq   :estab
            inc   $0327
            beq   :estab                  ; timed out
            jsr   net_delay
            bra   :estwait
:estab      jsr   net_poll
            sta   $0302                   ; final socket status

            cmp   #W5_SOCK_ESTAB          ; only send if we actually connected
            bne   :done

            lda   #$C0                     ; send four bytes
            jsr   net_send_byte
            lda   #$C1
            jsr   net_send_byte
            lda   #$C2
            jsr   net_send_byte
            lda   #$C3
            jsr   net_send_byte

            stz   $0326                   ; bytes received so far
            stz   $0325                   ; receive poll counter
:rxloop     jsr   net_recv_byte
            bcs   :rxgot
            inc   $0325
            beq   :rxdone                 ; 256 idle polls -> stop
            jsr   net_delay
            bra   :rxloop
:rxgot      ldx   $0326
            sta   $0320,x                 ; store the echoed byte
            inx
            stx   $0326
            stz   $0325                   ; reset the idle timeout
            cpx   #4
            bne   :rxloop
:rxdone     lda   $0326
            sta   $0324                   ; count of bytes echoed back
            jsr   net_close

:done       lda   #$A5
            sta   $0304                  ; done marker, written last
:spin       bra   :spin

            put   net
            put   netdhcp
