*----------------------------------------------------------
* netloop.s - GAME-side network glue (spec N4), included by GAME.
*
* Turns the debug board into a network client: connect + matchmake,
* then a per-frame poll that applies the server's authoritative
* snapshots to the engine (netstate_apply) and marks the screen dirty,
* and action senders that transmit C_MOVE / C_FIRE / C_END_TURN instead
* of applying locally. All routines run in the engine's 8-bit native
* convention (MX %11, DBR $00); dbg.s / game.s call them through the
* same sep #$30 wrappers used for the engine.
*
* Sits on net.s + netdhcp.s + proto.s + netgame.s + netplay.s.
*----------------------------------------------------------

* net_game_start: DHCP, connect to the server, HELLO/WELCOME, request a
* bot match, and apply the MATCH_START snapshot into the engine. Sets
* cfg_board from the match so dbg_init picks the right palette. Returns
* carry clear on success (a match is live), carry set on any failure.
* Clobbers A/X/Y and the net scratch.
            mx    %11

net_game_start
            stz   nl_over
            stz   nl_action+0
            stz   nl_action+1
            jsr   net_init
            bcc   :ok0
            rts                            ; carry set: no card
:ok0        jsr   net_config_static
            jsr   net_configure             ; DHCP
            bcc   :ok1
            rts
:ok1        inc   net_src_port+1             ; bump the TCP source port each game so a
            bne   :sp                        ; sequential game / reconnect does not clash
            inc   net_src_port+0             ; with a prior 4-tuple still in TIME_WAIT
:sp         ldx   #3                         ; dest = gateway host : default port
:ds         lda   net_gw,x
            sta   net_dest_ip,x
            dex
            bpl   :ds
            jsr   net_connect
            bcc   :ok2
            rts
:ok2        stz   nl_to+0                     ; wait for SOCK_ESTABLISHED
            stz   nl_to+1
:ew         jsr   net_poll
            cmp   #W5_SOCK_ESTAB
            beq   :estab
            cmp   #W5_SOCK_CLOSED
            beq   :failest
            inc   nl_to+0
            bne   :ew2
            inc   nl_to+1
:ew2        lda   nl_to+1
            cmp   #$04
            bcs   :failest
            jsr   net_delay
            bra   :ew
:failest    sec
            rts
:estab
* --- send HELLO ---
            lda   #1
            sta   ng_seq+0
            stz   ng_seq+1
            stz   ng_build+0
            stz   ng_build+1
            stz   ng_build+2
            stz   ng_build+3
            lda   #$01
            sta   ng_cap+0
            stz   ng_cap+1
            lda   #<nl_name
            sta   NDP
            lda   #>nl_name
            sta   NDP+1
            lda   #NET_CLIENT_HUMAN
            ldx   #4
            jsr   net_build_hello
            jsr   net_frame_send
            jsr   proto_rx_reset
* --- handshake loop until MATCH_START ---
            stz   nl_to+0
            stz   nl_to+1
:hloop      jsr   net_pump
            bcc   :hidle
            lda   proto_msg_type
            cmp   #NET_S_WELCOME
            beq   :welcome
            cmp   #NET_S_MATCH_START
            beq   :matched
            bra   :hloop
:welcome    lda   #2
            sta   ng_seq+0
            stz   ng_seq+1
            lda   #NET_QUEUE_BOT
            jsr   net_build_queue
            jsr   net_frame_send
            bra   :hloop
:hidle      inc   nl_to+0
            bne   :h2
            inc   nl_to+1
:h2         lda   nl_to+1
            cmp   #$08
            bcs   :failest
            jsr   net_delay
            bra   :hloop
:matched    lda   proto_payload+0            ; match_id -> ng_match_id
            sta   ng_match_id+0
            lda   proto_payload+1
            sta   ng_match_id+1
            lda   proto_payload+2
            sta   ng_match_id+2
            lda   proto_payload+3
            sta   ng_match_id+3
            lda   proto_payload+4            ; assigned side
            sta   nl_my_side
            lda   proto_payload+5            ; board number -> cfg_board
            sta   cfg_board
* decode + apply the embedded snapshot (skip the 37-byte prefix)
            clc
            lda   #<proto_payload
            adc   #37
            sta   NSP
            lda   #>proto_payload
            adc   #0
            sta   NSP+1
            jsr   netstate_decode
            jsr   netstate_apply
            clc
            rts

* net_poll_step: pump one server frame if available and apply it; sets
* nl_dirty nonzero when the board changed. Non-blocking (returns quickly
* when nothing is waiting). Call once per game-loop frame. Clobbers A/X/Y.
net_poll_step
            stz   nl_dirty
            jsr   net_pump
            bcc   :none
            lda   proto_msg_type
            cmp   #NET_S_ACTION_RESULT
            beq   :result
            cmp   #NET_S_STATE
            beq   :state
            cmp   #NET_S_GAME_OVER
            beq   :over
            rts
:state                                       ; payload IS the snapshot
            lda   #<proto_payload
            sta   NSP
            lda   #>proto_payload
            sta   NSP+1
            bra   :apply
:result                                      ; skip header + event list
            lda   proto_payload+8            ; event count
            sta   nl_ecount
            lda   #9                          ; past 8-byte header + count byte
            sta   nl_off
            ldx   nl_ecount
            beq   :evdone
:evskip     ldy   nl_off
            iny
            lda   proto_payload,y             ; nargs
            clc
            adc   nl_off
            clc
            adc   #2
            sta   nl_off
            dex
            bne   :evskip
:evdone     clc
            lda   #<proto_payload
            adc   nl_off
            sta   NSP
            lda   #>proto_payload
            adc   #0
            sta   NSP+1
:apply      jsr   netstate_decode
            jsr   netstate_apply
            lda   #1
            sta   nl_dirty
            rts
:over       lda   #1
            sta   nl_over
            rts
:none       rts

* net_send_move: A = unit id, X = dest x, Y = dest y. Sends C_MOVE with
* the next action id. Clobbers A/X/Y.
net_send_move
            pha
            phx
            phy
            jsr   nl_next_action
            pla                              ; y (pushed last... restore order)
            tay
            pla
            tax
            pla
            jsr   net_build_move
            jsr   net_frame_send
            rts

* net_send_fire: A = attacker id, X = target id. Sends C_FIRE.
net_send_fire
            pha
            phx
            jsr   nl_next_action
            plx
            pla
            jsr   net_build_fire
            jsr   net_frame_send
            rts

* net_send_end: sends C_END_TURN.
net_send_end
            jsr   nl_next_action
            jsr   net_build_end
            jsr   net_frame_send
            rts

* nl_next_action: bump ng_seq and copy nl_action -> ng_action_id, then
* increment nl_action. Clobbers A.
nl_next_action
            inc   ng_seq+0
            bne   :s2
            inc   ng_seq+1
:s2         lda   nl_action+0
            sta   ng_action_id+0
            lda   nl_action+1
            sta   ng_action_id+1
            inc   nl_action+0
            bne   :done
            inc   nl_action+1
:done       rts

* net_frame_send: transmit the frame proto.s just built (proto_tx/total).
net_frame_send
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

* net_pump: get one complete frame (carry set, in proto_msg_*/payload) or
* carry clear if none available yet. Reads a chunk from the socket.
net_pump
            jsr   proto_rx_next
            bcs   :got
            lda   #<nl_rxbuf
            sta   NRXP
            lda   #>nl_rxbuf
            sta   NRXP+1
            lda   #60
            sta   net_len+0
            stz   net_len+1
            jsr   net_recv
            lda   net_rcvd+0
            ora   net_rcvd+1
            beq   :none
            lda   #<nl_rxbuf
            sta   PRP
            lda   #>nl_rxbuf
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

nl_name      asc   'iigs'
nl_my_side   dfb   0
nl_over      dfb   0
nl_dirty     dfb   0
nl_action    dfb   0,0
nl_to        dfb   0,0
nl_ecount    dfb   0
nl_off       dfb   0
nl_rxbuf     =     $0E80              ; recv chunk in free bank-0 RAM ($0E80-$0EFF)
