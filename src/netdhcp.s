*----------------------------------------------------------
* netdhcp.s - DHCP client for net_configure (spec N1).
*
* Ported from ../hdtelnet/dhcp.s: acquire an IP lease over
* the W5100 by the standard DISCOVER -> OFFER -> REQUEST ->
* ACK exchange, socket 0 in UDP mode broadcasting to
* 255.255.255.255:67. Fills net.s's net_ip / net_gw / net_mask
* (and net_server / net_dns) from the lease so net_connect can
* run; net.s's register primitives and scratch words do the
* chip I/O.
*
* Put into a part AFTER net.s (it references net_setaddr,
* net_setdata, net_getdata, net_setmr and the net_* data). No
* ProDOS or ROM dependency: net_delay replaces the monitor's
* WAIT, and a fixed MAC / transaction id serve the isolated
* single-client vmnet the harness uses (randomise later by
* seeding net_xid / net_mac+5 from get_tick).
*
* Runs in emulation or native mode, 8-bit A/X/Y, DBR $00.
*----------------------------------------------------------

DHCP_RETRIES = 6                   ; DISCOVER and REQUEST attempts
DHCP_POLLS   = $30                 ; RX poll iterations before a retry

* W5100 UDP receive header: srcIP(4) srcPort(2) len(2) precede the
* datagram in the socket buffer. BOOTP fixed area is 236 bytes.
DHCP_RXHDR   = 8
DHCP_BOOTP   = 236

*----------------------------------------------------------
* net_configure: obtain a DHCP lease. Carry clear on success
* (net_ip/net_gw/net_mask/net_server populated); carry set only
* if no OFFER ever arrived. An ACK timeout still returns success
* on the offered address (as hdtelnet does). Clobbers A/X/Y and
* the net scratch words. Call after net_init and net_config_static.
*----------------------------------------------------------
net_configure
            jsr   net_udp_open        ; S0 UDP, dest = broadcast:67

            ldx   #DHCP_RETRIES
:dloop      phx
            jsr   net_dhcp_discover
            jsr   net_dhcp_getoffer    ; carry clear = OFFER captured
            bcc   :offered
            plx
            dex
            bne   :dloop
            sec                         ; never heard an OFFER
            rts

:offered    plx
            jsr   net_dhcp_parseoffer   ; -> net_ip / net_server / net_mask / net_gw

            ldx   #DHCP_RETRIES
:aloop      phx
            jsr   net_dhcp_request
            jsr   net_dhcp_getack       ; carry clear = ACK captured
            bcc   :acked
            plx
            dex
            bne   :aloop
            bra   :leased               ; no ACK: take the offered address anyway

:acked      plx
            jsr   net_dhcp_verifyack    ; (carry ignored; we keep the offer either way)

:leased     jsr   net_reset             ; clean chip reset before TCP use
            clc
            rts

*----------------------------------------------------------
* net_reset: software-reset the chip and return it to indirect
* + auto-increment mode. Mirrors hdtelnet's post-DHCP wizinit.
* Clobbers A. X/Y preserved.
*----------------------------------------------------------
net_reset
            lda   #$80                  ; reset (self-clears)
            jsr   net_setmr
            lda   #W5_MODE_IND
            jsr   net_setmr
            rts

*----------------------------------------------------------
* net_udp_open: write the config block, size the buffers, open
* socket 0 as UDP with source port 68, and point its dest at the
* broadcast MAC / 255.255.255.255 : 67. Clobbers A/X.
*----------------------------------------------------------
net_udp_open
            lda   #W5_MODE_IND
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
            jsr   net_setdata
            lda   #W5_MEM_2K_EACH
            jsr   net_setdata

            lda   #>W5_S0_PORT         ; $0404: source port 68 (DHCP client)
            ldx   #<W5_S0_PORT
            jsr   net_setaddr
            lda   #0
            jsr   net_setdata
            lda   #68
            jsr   net_setdata

            lda   #>W5_S0_MR           ; $0400: socket 0 mode = UDP
            ldx   #<W5_S0_MR
            jsr   net_setaddr
            lda   #$02
            jsr   net_setdata

            lda   #>W5_S0_CR           ; $0401: OPEN
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            lda   #W5_CMD_OPEN
            jsr   net_setdata

            lda   #>W5_S0_DHAR         ; $0406: dest MAC = broadcast
            ldx   #<W5_S0_DHAR
            jsr   net_setaddr
            ldx   #6
:bmac       lda   #$FF
            jsr   net_setdata
            dex
            bne   :bmac
            lda   #$FF                  ; $040C: dest IP 255.255.255.255
            jsr   net_setdata
            jsr   net_setdata
            jsr   net_setdata
            jsr   net_setdata
            lda   #0                    ; $0410: dest port 67 (DHCP server)
            jsr   net_setdata
            lda   #67
            jsr   net_setdata
            rts

*----------------------------------------------------------
* net_dhcp_discover: push the DHCPDISCOVER datagram into the TX
* ring and SEND_MAC it. Clobbers A/X and the net scratch words.
*----------------------------------------------------------
net_dhcp_discover
            lda   #<net_disc
            sta   NPTR
            lda   #>net_disc
            sta   NPTR+1
            lda   #<net_disc_len
            sta   net_len+0
            lda   #>net_disc_len
            sta   net_len+1
            jsr   net_udp_send
            rts

*----------------------------------------------------------
* net_dhcp_request: fill the REQUEST datagram's server/requested
* IP from the offer, push it, and SEND_MAC it. Clobbers A/X and
* the net scratch words.
*----------------------------------------------------------
net_dhcp_request
            ldx   #3
:cp         lda   net_server,x
            sta   net_req_srvid,x       ; option 54 (server id)
            sta   net_req_siaddr,x      ; BOOTP siaddr
            lda   net_ip,x
            sta   net_req_reqip,x       ; option 50 (requested ip)
            dex
            bpl   :cp

            lda   #<net_req
            sta   NPTR
            lda   #>net_req
            sta   NPTR+1
            lda   #<net_req_len
            sta   net_len+0
            lda   #>net_req_len
            sta   net_len+1
            jsr   net_udp_send
            rts

*----------------------------------------------------------
* net_udp_send: NPTR = datagram pointer (direct page), net_len =
* 16-bit length. Streams the datagram into socket 0's TX ring
* (translated to $4000, masked $07FF), advances TX_WR by the
* length, and issues SEND_MAC ($21). The 16-bit length and DP
* pointer handle the >256-byte DHCP datagrams. Clobbers A/X/Y,
* NPTR, and net scratch.
*----------------------------------------------------------
net_udp_send
            lda   #>W5_S0_TXWR         ; read TX write pointer
            ldx   #<W5_S0_TXWR
            jsr   net_setaddr
            jsr   net_getdata
            sta   ntx_wr+1
            sta   ntx_ptr+1
            jsr   net_getdata
            sta   ntx_wr+0
            sta   ntx_ptr+0

            lda   ntx_wr+1            ; translate high byte into the $4000 ring
            and   #W5_RING_MASK_HI
            clc
            adc   #W5_TX_BASE_HI
            sta   ntx_wr+1

            lda   ntx_wr+1           ; point the register address at the ring
            ldx   ntx_wr+0
            jsr   net_setaddr
:wr         lda   (NPTR)             ; one datagram byte -> ring (auto-inc)
            jsr   net_setdata
            inc   NPTR               ; next source byte (16-bit)
            bne   :sp
            inc   NPTR+1
:sp         inc   ntx_ptr+0          ; advance the raw TX pointer (16-bit)
            bne   :tp
            inc   ntx_ptr+1
:tp         lda   net_len+0          ; net_len -= 1 (16-bit)
            bne   :lo
            dec   net_len+1
:lo         dec   net_len+0
            lda   net_len+0          ; loop until net_len == 0
            ora   net_len+1
            bne   :wr

            lda   #>W5_S0_TXWR       ; write TX_WR back (raw, untranslated)
            ldx   #<W5_S0_TXWR
            jsr   net_setaddr
            lda   ntx_ptr+1
            jsr   net_setdata
            lda   ntx_ptr+0
            jsr   net_setdata

            lda   #>W5_S0_CR         ; SEND_MAC (dest MAC is set manually)
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            lda   #$21
            jsr   net_setdata
:wt         lda   #>W5_S0_CR
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            jsr   net_getdata
            bne   :wt
            rts

*----------------------------------------------------------
* net_dhcp_getoffer / net_dhcp_getack: poll socket 0's RX for a
* datagram, up to DHCP_POLLS times with net_delay between tries.
* On a packet, copy it into net_rxbuf, advance RX_RD, RECV, and
* return carry clear; on timeout, carry set. Clobbers A/X/Y and
* net scratch. (Both paths share net_udp_recv.)
*----------------------------------------------------------
net_dhcp_getoffer
net_dhcp_getack
            jsr   net_udp_recv
            rts

net_udp_recv
            ldx   #DHCP_POLLS
:poll       phx
            lda   #>W5_S0_RXRSR       ; $0426: received size
            ldx   #<W5_S0_RXRSR
            jsr   net_setaddr
            jsr   net_getdata
            sta   nrx_rcvd+1
            jsr   net_getdata
            sta   nrx_rcvd+0
            ora   nrx_rcvd+1
            bne   :got
            jsr   net_delay
            plx
            dex
            bne   :poll
            sec                         ; timed out
            rts

:got        plx
            lda   #>W5_S0_RXRD         ; $0428: RX read pointer
            ldx   #<W5_S0_RXRD
            jsr   net_setaddr
            jsr   net_getdata
            sta   nrx_rd+1
            sta   nrx_rd_orig+1
            jsr   net_getdata
            sta   nrx_rd+0
            sta   nrx_rd_orig+0

            lda   nrx_rd+1            ; translate into the $6000 RX ring
            and   #W5_RING_MASK_HI
            clc
            adc   #W5_RX_BASE_HI
            sta   nrx_rd+1

* Clamp the copy to net_rxbuf's 400 bytes so an oversized packet
* cannot run past the buffer (DHCP datagrams are ~342). The raw
* RX_RD still advances by the true received size below.
            lda   nrx_rcvd+1
            bne   :big               ; >= 256 bytes received
            bra   :setcnt
:big        cmp   #>400
            bcc   :setcnt            ; 256..399: fine
            bne   :clamp             ; >= 512: clamp
            lda   nrx_rcvd+0         ; high == 1: clamp if low > (400 & $FF)
            cmp   #<400
            bcc   :setcnt
:clamp      lda   #<400
            sta   ncopy+0
            lda   #>400
            sta   ncopy+1
            bra   :cpinit
:setcnt     lda   nrx_rcvd+0
            sta   ncopy+0
            lda   nrx_rcvd+1
            sta   ncopy+1

:cpinit     lda   #<net_rxbuf        ; NRXP -> destination buffer
            sta   NRXP
            lda   #>net_rxbuf
            sta   NRXP+1
            lda   nrx_rd+1           ; register address -> RX ring
            ldx   nrx_rd+0
            jsr   net_setaddr
:rd         jsr   net_getdata        ; one ring byte -> buffer (auto-inc)
            sta   (NRXP)
            inc   NRXP
            bne   :dp
            inc   NRXP+1
:dp         lda   ncopy+0            ; ncopy -= 1 (16-bit)
            bne   :cl
            dec   ncopy+1
:cl         dec   ncopy+0
            lda   ncopy+0
            ora   ncopy+1
            bne   :rd

            lda   nrx_rd_orig+0      ; advance raw RX_RD past the datagram
            clc
            adc   nrx_rcvd+0
            sta   nrx_rd_orig+0
            lda   nrx_rd_orig+1
            adc   nrx_rcvd+1
            sta   nrx_rd_orig+1
            lda   #>W5_S0_RXRD
            ldx   #<W5_S0_RXRD
            jsr   net_setaddr
            lda   nrx_rd_orig+1
            jsr   net_setdata
            lda   nrx_rd_orig+0
            jsr   net_setdata

            lda   #>W5_S0_CR         ; RECV: buffer consumed
            ldx   #<W5_S0_CR
            jsr   net_setaddr
            lda   #W5_CMD_RECV
            jsr   net_setdata
            clc
            rts

*----------------------------------------------------------
* net_dhcp_parseoffer: read the captured OFFER in net_rxbuf.
* Verify the magic cookie, take yiaddr as our IP and siaddr as
* the server, then walk the options for subnet mask (1), router
* (3), DNS (6) and server id (54, overriding siaddr). Clobbers
* A/X/Y. Carry set if the cookie is wrong.
*----------------------------------------------------------
net_dhcp_parseoffer
            lda   net_rxcookie+0
            cmp   #$63
            bne   :bad
            lda   net_rxcookie+1
            cmp   #$82
            bne   :bad
            lda   net_rxcookie+2
            cmp   #$53
            bne   :bad
            lda   net_rxcookie+3
            cmp   #$63
            beq   :ok                    ; cookie good -> parse; else fail nearby
:bad        sec
            rts

:ok         ldx   #3                    ; yiaddr -> net_ip, siaddr -> net_server
:ips        lda   net_rxdata+16,x
            sta   net_ip,x
            lda   net_rxdata+20,x
            sta   net_server,x
            dex
            bpl   :ips

            ldx   #0
:opt        lda   net_rxopts,x
            cmp   #$FF                  ; end of options
            beq   :done
            cmp   #$01                  ; subnet mask
            beq   :mask
            cmp   #$03                  ; router
            beq   :router
            cmp   #$06                  ; DNS
            beq   :dns
            cmp   #$36                  ; server identifier (54)
            beq   :srvid
            bra   :skip                 ; any other option: skip by length

:skip       inx                         ; X -> length byte
            lda   net_rxopts,x
            sta   net_tmp
            txa
            clc
            adc   net_tmp
            tax
            inx
            bra   :opt

:mask       inx
            inx                          ; skip type+len
            ldy   #0
:m0         lda   net_rxopts,x
            sta   net_mask,y
            inx
            iny
            cpy   #4
            bne   :m0
            bra   :opt

:router     inx
            inx
            ldy   #0
:r0         lda   net_rxopts,x
            sta   net_gw,y
            inx
            iny
            cpy   #4
            bne   :r0
            bra   :opt

:dns        inx
            inx
            ldy   #0
:d0         lda   net_rxopts,x
            sta   net_dns,y
            inx
            iny
            cpy   #4
            bne   :d0
            bra   :opt

:srvid      inx
            inx
            ldy   #0
:s0         lda   net_rxopts,x
            sta   net_server,y
            inx
            iny
            cpy   #4
            bne   :s0
            bra   :opt

:done       clc
            rts

*----------------------------------------------------------
* net_dhcp_verifyack: confirm the ACK in net_rxbuf carries a
* valid magic cookie. Carry clear if good. Clobbers A.
*----------------------------------------------------------
net_dhcp_verifyack
            lda   net_rxcookie+0
            cmp   #$63
            bne   :bad
            lda   net_rxcookie+1
            cmp   #$82
            bne   :bad
            lda   net_rxcookie+2
            cmp   #$53
            bne   :bad
            lda   net_rxcookie+3
            cmp   #$63
            bne   :bad
            clc
            rts
:bad        sec
            rts

*----------------------------------------------------------
* net_delay: a short busy wait between RX polls (~tens of ms),
* replacing the monitor WAIT hdtelnet used. Clobbers A/X/Y.
*----------------------------------------------------------
net_delay
            ldy   #$40
:d1         ldx   #$FF
:d0         dex
            bne   :d0
            dey
            bne   :d1
            rts

*----------------------------------------------------------
* DHCP datagram templates. chaddr / client-id carry NET_MAC*;
* the transaction id is fixed (see the header note).
*----------------------------------------------------------
NET_XID0 = $C0
NET_XID1 = $C0
NET_XID2 = $13
NET_XID3 = $84

net_disc     = *
            dfb   $01,$01,$06,$00        ; OP HTYPE HLEN HOPS
            dfb   NET_XID0,NET_XID1,NET_XID2,NET_XID3   ; XID
            dfb   $00,$00                ; SECS
            dfb   $00,$00                ; FLAGS
            dfb   0,0,0,0                ; ciaddr
            dfb   0,0,0,0                ; yiaddr
            dfb   0,0,0,0                ; siaddr
            dfb   0,0,0,0                ; giaddr
            dfb   NET_MAC0,NET_MAC1,NET_MAC2,NET_MAC3,NET_MAC4,NET_MAC5
            ds    10                     ; chaddr padding
            ds    64                     ; sname
            ds    128                    ; bootfile
            dfb   $63,$82,$53,$63        ; magic cookie
            dfb   53,1,1                 ; message type = DHCPDISCOVER
            dfb   61,7,1                 ; client id: 01 + MAC
            dfb   NET_MAC0,NET_MAC1,NET_MAC2,NET_MAC3,NET_MAC4,NET_MAC5
            dfb   12,4                   ; hostname
            asc   'iigs'
            dfb   55,6                   ; parameter request list
            dfb   1,3,6,15,58,59         ; mask, router, dns, domain, T1, T2
            dfb   255                    ; end
net_disc_end = *
net_disc_len = net_disc_end - net_disc

net_req      = *
            dfb   $01,$01,$06,$00        ; OP HTYPE HLEN HOPS
            dfb   NET_XID0,NET_XID1,NET_XID2,NET_XID3   ; XID (same as DISCOVER)
            dfb   $00,$00                ; SECS
            dfb   $00,$00                ; FLAGS
            dfb   0,0,0,0                ; ciaddr
            dfb   0,0,0,0                ; yiaddr
net_req_siaddr dfb 0,0,0,0              ; siaddr (filled from the offer)
            dfb   0,0,0,0                ; giaddr
            dfb   NET_MAC0,NET_MAC1,NET_MAC2,NET_MAC3,NET_MAC4,NET_MAC5
            ds    10                     ; chaddr padding
            ds    64                     ; sname
            ds    128                    ; bootfile
            dfb   $63,$82,$53,$63        ; magic cookie
            dfb   53,1,3                 ; message type = DHCPREQUEST
            dfb   50,4                   ; requested IP
net_req_reqip dfb 0,0,0,0
            dfb   54,4                   ; server identifier
net_req_srvid dfb 0,0,0,0
            dfb   255                    ; end
net_req_end  = *
net_req_len  = net_req_end - net_req

*----------------------------------------------------------
* DHCP state. net_rxbuf holds one received datagram; the offset
* aliases name the BOOTP fields and options within it.
*----------------------------------------------------------
net_server   dfb   0,0,0,0            ; DHCP server address
net_dns      dfb   0,0,0,0            ; offered DNS server
net_len      dfb   0,0                ; datagram length (16-bit, net_udp_send)
ncopy        dfb   0,0                ; RX copy counter (16-bit, net_udp_recv)
net_tmp2     dfb   0

net_rxbuf    ds    400
net_rxdata   = net_rxbuf + DHCP_RXHDR
net_rxcookie = net_rxdata + DHCP_BOOTP
net_rxopts   = net_rxcookie + 4
