*----------------------------------------------------------
* nettest_client.s - live IIGS network client slice (spec 46).
*
* Poked into MAME and run from $2000. Drives the whole client stack
* (net.s + proto.s + netgame.s) against the real Python match server
* over vmnet: DHCP, TCP connect, HELLO, WELCOME, request a bot match,
* receive MATCH_START, make one legal move, and receive the
* authoritative S_ACTION_RESULT. Proves the IIGS half of the vertical
* slice end to end.
*
* Result block:
*   $0300 slot   $0301 dhcp(0=ok)   $0302 sock   $0303 connect(0=ok)
*   $0305 progress (1 hello,2 welcome,3 matchstart,4 result)
*   $0310 my_side   $0311 ucount   $0312 u0 id   $0313 u0 x  $0314 u0 y
*   $0320 move result_code   $0321 u0 new x   $0322 u0 new y
*   $0304 $A5 done
*----------------------------------------------------------
            org   $2000
            mx    %11

MS_PREFIX = 37                ; S_MATCH_START fixed header + 16-byte token

start       sei
            sec
            xce
            cld
            ldx   #$FF
            txs
            lda   #0
            pha
            plb

            ldx   #$3F                     ; poison $0300..$033F
            lda   #$EE
:poison     sta   $0300,x
            dex
            bpl   :poison
            stz   nc_prog

            jsr   net_init
            bcc   :haveslot
            lda   #$FF
            sta   $0300
            jmp   :done
:haveslot   sta   $0300

            jsr   net_config_static
            jsr   net_configure             ; DHCP
            lda   #$00
            bcc   :leased
            lda   #$FF
:leased     sta   $0301

            ldx   #3                         ; connect to the gateway host:1984
:dst        lda   net_gw,x
            sta   net_dest_ip,x
            dex
            bpl   :dst
            jsr   net_connect
            lda   #$00
            bcc   :ck
            lda   #$FF
:ck         sta   $0303

            stz   nc_to+0                    ; wait for SOCK_ESTABLISHED
            stz   nc_to+1
:estw       jsr   net_poll
            cmp   #W5_SOCK_ESTAB
            beq   :estab
            cmp   #W5_SOCK_CLOSED
            beq   :estab
            inc   nc_to+0
            bne   :e2
            inc   nc_to+1
:e2         lda   nc_to+1
            cmp   #$04                        ; ~1024 tries -> give up
            bcs   :estab
            jsr   net_delay
            bra   :estw
:estab      jsr   net_poll
            sta   $0302
            cmp   #W5_SOCK_ESTAB
            beq   :go
            jmp   :done
:go
* --- send C_HELLO ---
            lda   #1
            sta   ng_seq+0
            stz   ng_seq+1
            stz   ng_build+0
            stz   ng_build+1
            stz   ng_build+2
            stz   ng_build+3
            lda   #$01                        ; cap = ENHANCED
            sta   ng_cap+0
            stz   ng_cap+1
            lda   #<nc_name
            sta   NDP
            lda   #>nc_name
            sta   NDP+1
            lda   #NET_CLIENT_HUMAN
            ldx   #4                           ; "iigs"
            jsr   net_build_hello
            jsr   nc_send
            lda   #1
            sta   nc_prog
            sta   $0305

* --- event loop ---
            jsr   proto_rx_reset
            stz   nc_loops+0
            stz   nc_loops+1
:loop       jsr   nc_pump                     ; carry set: a frame is in proto_*
            bcc   :idle
            lda   proto_msg_type
            cmp   #NET_S_WELCOME
            bne   :d1
            jmp   :welcome
:d1         cmp   #NET_S_MATCH_START
            bne   :d2
            jmp   :matchstart
:d2         cmp   #NET_S_ACTION_RESULT
            bne   :loop                        ; ignore others (e.g. S_STATE)
            jmp   :result

:idle       inc   nc_loops+0
            bne   :l2
            inc   nc_loops+1
:l2         lda   nc_loops+1
            cmp   #$08                          ; overall timeout
            bcc   :cont
            jmp   :done
:cont       jsr   net_delay
            bra   :loop

* --- S_WELCOME: request a bot match ---
:welcome    lda   #2
            sta   nc_prog
            sta   $0305
            lda   #2
            sta   ng_seq+0
            stz   ng_seq+1
            lda   #NET_QUEUE_BOT
            jsr   net_build_queue
            jsr   nc_send
            jmp   :loop

* --- S_MATCH_START: record + make one legal move ---
:matchstart lda   #3
            sta   nc_prog
            sta   $0305
            lda   proto_payload+4              ; assigned_side
            sta   $0310
            ldx   #0                             ; match_id (u32) -> ng_match_id
:mi         lda   proto_payload,x
            sta   ng_match_id,x
            inx
            cpx   #4
            bne   :mi
* decode the embedded snapshot (skip the 37-byte prefix)
            clc
            lda   #<proto_payload
            adc   #MS_PREFIX
            sta   NSP
            lda   #>proto_payload
            adc   #0
            sta   NSP+1
            jsr   netstate_decode
            lda   ns_ucount
            sta   $0311
* pick unit 0 and move it one step left (x-1, same y)
            lda   #0
            jsr   net_unit_ptr                  ; NDP -> unit 0 record
            ldy   #0
            lda   (NDP),y
            sta   nc_uid
            sta   $0312
            ldy   #3
            lda   (NDP),y
            sta   nc_ux
            sta   $0313
            ldy   #4
            lda   (NDP),y
            sta   nc_uy
            sta   $0314
            lda   #3
            sta   ng_seq+0
            stz   ng_seq+1
            lda   #1                             ; action_id = 1
            sta   ng_action_id+0
            stz   ng_action_id+1
            lda   nc_uid
            ldx   nc_ux
            dex                                  ; dest x = x-1
            ldy   nc_uy                          ; dest y = y
            jsr   net_build_move
            jsr   nc_send
            jmp   :loop

* --- S_ACTION_RESULT: record result code + unit 0 new position ---
:result     lda   #4
            sta   nc_prog
            sta   $0305
            lda   proto_payload+7               ; result_code
            sta   $0320
* find the state blob: skip 8-byte header + event list
            lda   proto_payload+8               ; event count
            sta   nc_ecount
            lda   #8+1                            ; offset past header + count byte
            sta   nc_off
            ldx   nc_ecount
            beq   :evdone
:evskip     ldy   nc_off
            iny                                  ; skip event type
            lda   proto_payload,y                ; nargs
            clc
            adc   nc_off
            clc
            adc   #2                              ; type + nargs bytes consumed
            sta   nc_off
            dex
            bne   :evskip
:evdone
            clc
            lda   #<proto_payload
            adc   nc_off
            sta   NSP
            lda   #>proto_payload
            adc   #0
            sta   NSP+1
            jsr   netstate_decode
            lda   #0                              ; unit 0 new position
            jsr   net_unit_ptr
            ldy   #3
            lda   (NDP),y
            sta   $0321
            ldy   #4
            lda   (NDP),y
            sta   $0322
            jmp   :done

:done       lda   #$A5
            sta   $0304
:spin       bra   :spin

* nc_send: transmit the frame proto.s just built (proto_tx/proto_total).
nc_send
            lda   #<proto_tx
            sta   NPTR
            lda   #>proto_tx
            sta   NPTR+1
            lda   proto_total+0
            sta   net_len+0
            lda   proto_total+1
            sta   net_len+1
            jsr   net_send
            rts

* nc_pump: return one complete frame (carry set, in proto_msg_*/payload),
* or carry clear if none is available yet. Reads a chunk from the socket
* into nc_rxbuf and stages it.
nc_pump
            jsr   proto_rx_next               ; already-staged frame?
            bcs   :got
            lda   #<nc_rxbuf                   ; else read from the socket
            sta   NRXP
            lda   #>nc_rxbuf
            sta   NRXP+1
            lda   #250
            sta   net_len+0
            stz   net_len+1
            jsr   net_recv
            lda   net_rcvd+0
            ora   net_rcvd+1
            beq   :none
            lda   #<nc_rxbuf
            sta   PRP
            lda   #>nc_rxbuf
            sta   PRP+1
            lda   net_rcvd+0
            sta   proto_cnt+0
            lda   net_rcvd+1
            sta   proto_cnt+1
            jsr   proto_rx_add
            jsr   proto_rx_next
            bcs   :got
:none       clc
            rts
:got        sec
            rts

nc_name      asc   'iigs'
nc_prog      dfb   0
nc_to        dfb   0,0
nc_loops     dfb   0,0
nc_uid       dfb   0
nc_ux        dfb   0
nc_uy        dfb   0
nc_ecount    dfb   0
nc_off       dfb   0
nc_rxbuf     ds    512

            put   net
            put   netdhcp
            put   proto
            put   netgame
