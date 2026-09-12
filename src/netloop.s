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
            stz   nl_matched
            stz   nl_lost
            stz   nl_recon_tries
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
            lda   proto_payload+6            ; moves/turn -> opt_moves_per_turn
            sta   opt_moves_per_turn         ; (setup_game is skipped in net mode)
            ldx   #0                          ; reconnect token (16 bytes @ +21)
:tkc        lda   proto_payload+21,x
            sta   ng_token,x
            inx
            cpx   #16
            bne   :tkc
            lda   #1                          ; a match is live: enable reconnect
            sta   nl_matched
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
            jsr   nl_check_link                ; dropped connection? resume via token
            jsr   net_pump
            bcs   :havemsg
            rts
:havemsg    lda   proto_msg_type
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
:evskip     phx                               ; nl_anim_event reuses X (event counter)
            jsr   nl_anim_event               ; capture a move/shot for the display to animate
            plx
            ldy   nl_off
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
:over       lda   proto_payload+1            ; winner side (0xFF = draw)
            cmp   #$FF
            bne   :haswin
            lda   #RESULT_STALEMATE
            bra   :setres
:haswin     clc
            adc   #RESULT_RED_WINS           ; RED_WINS + side
:setres     sta   game_result
            lda   proto_payload+0            ; server reason -> engine reason
            cmp   #1                          ; OVER_SURRENDER
            beq   :rsurr
            cmp   #2                          ; OVER_STALEMATE
            beq   :rstale
            lda   #REASON_CRUISER             ; OVER_CRUISER (0)
            bra   :setreason
:rsurr      lda   #REASON_SURRENDER
            bra   :setreason
:rstale     lda   #REASON_STALEMATE
:setreason  sta   result_reason
            lda   #1
            sta   nl_over
            rts
:none       rts

* nl_check_link: once a match is live, watch socket 0's status each frame; if
* the connection dropped (no longer ESTABLISHED) try to resume it with our
* token. One-shot per drop -- a failed resume sets nl_lost so we stop hammering
* (the game is effectively lost from the client's side). Clobbers A/X/Y.
nl_check_link
            lda   nl_matched
            beq   :done                        ; no match yet
            lda   nl_lost
            bne   :done                        ; already gave up
            lda   nl_over
            bne   :done                        ; game finished normally
            jsr   net_poll                       ; socket 0 status
            cmp   #W5_SOCK_ESTAB
            beq   :ok                            ; still connected
            jsr   net_reconnect
            bcs   :retry                         ; this attempt failed
            stz   nl_recon_tries                 ; resumed -- reset the budget
            rts
:retry      inc   nl_recon_tries                 ; try again next frame, up to a cap
            lda   nl_recon_tries                 ; (~8 x 7.5s fits the 120s grace,
            cmp   #12                             ; and beats a flaky SYN)
            bcc   :done
            lda   #1                             ; out of tries: give up
            sta   nl_lost
            rts
:ok         stz   nl_recon_tries
:done       rts

* net_reconnect: the TCP link dropped mid-match -- reopen it and resume with
* our reconnect token (spec 24.3). Close socket 0, reconnect to the gateway,
* send C_RECONNECT, and on S_RECONNECT_RESULT / RC_OK apply the restored
* snapshot. Carry clear on success, carry set on failure. Clobbers A/X/Y.
net_reconnect
            jsr   net_close                      ; DISCON the dead socket (send FIN)
            ldx   #8
:cw         jsr   net_delay                       ; let the DISCON settle
            dex
            bne   :cw
            lda   #>W5_S0_CR                       ; then a hard CLOSE: net_connect's
            ldx   #<W5_S0_CR                       ; OPEN needs the socket in CLOSED,
            jsr   net_setaddr                      ; but DISCON alone leaves it mid-
            lda   #W5_CMD_CLOSE                     ; teardown (FIN_WAIT/CLOSE_WAIT)
            jsr   net_setdata
            ldx   #4
:cw2        jsr   net_delay
            dex
            bne   :cw2
            inc   net_src_port+1                  ; fresh 4-tuple
            bne   :sp
            inc   net_src_port+0
:sp         ldx   #3                              ; dest = gateway : default port
:ds         lda   net_gw,x
            sta   net_dest_ip,x
            dex
            bpl   :ds
            jsr   net_connect
            bcc   :ewait
            sec
            rts
:ewait      stz   nl_to+0                          ; wait for SOCK_ESTABLISHED
            stz   nl_to+1
:ew         jsr   net_poll
            cmp   #W5_SOCK_ESTAB
            beq   :estab
            cmp   #W5_SOCK_CLOSED
            beq   :fail
            inc   nl_to+0
            bne   :ew2
            inc   nl_to+1
:ew2        lda   nl_to+1                          ; ~7.5s per attempt (net_delay ~29ms
            cmp   #$01                             ; x 256); nl_check_link retries so
            bcs   :fail                            ; a flaky SYN gets several tries
            jsr   net_delay
            bra   :ew
:fail       sec
            rts
:estab      jsr   proto_rx_reset
            jsr   net_build_reconnect
            jsr   net_frame_send
            stz   nl_to+0                          ; wait for S_RECONNECT_RESULT
            stz   nl_to+1
:rl         jsr   net_pump
            bcc   :ridle
            lda   proto_msg_type
            cmp   #NET_S_RECONNECT_RESULT
            beq   :got
            bra   :ridle                           ; other frame: keep the timeout ticking
                                                   ; (never spin free on unexpected data)
:ridle      inc   nl_to+0
            bne   :r2
            inc   nl_to+1
:r2         lda   nl_to+1
            cmp   #$02
            bcs   :fail
            jsr   net_delay
            bra   :rl
:got        lda   proto_payload+0                  ; result code
            cmp   #NET_RC_OK
            bne   :fail
            clc                                     ; payload = code, side, then S_STATE
            lda   #<proto_payload
            adc   #2
            sta   NSP
            lda   #>proto_payload
            adc   #0
            sta   NSP+1
            jsr   netstate_decode
            jsr   netstate_apply
            lda   #1
            sta   nl_dirty
            clc
            rts

* nl_anim_event: proto_payload+nl_off points at one S_ACTION_RESULT event
* [type][nargs][args...]. Set the same mv_* / fr_* records the local
* do_move/do_fire set, so the game loop's anim_check slides a moved unit and
* shot_check flies + explodes a shot -- for the server's actions exactly like
* local play (our own move comes back the same way). Server event numbering
* (state.py): 1 UNIT_MOVED, 2 SHOT_FIRED, 3 SHOT_HIT, 4 SHOT_MISSED; args are
* 1 byte each and start at +2. Runs 8-bit. Clobbers A/X/Y.
nl_anim_event
            ldx   nl_off
            lda   proto_payload,x             ; event type
            cmp   #1                          ; EV_UNIT_MOVED
            beq   :moved
            cmp   #2                          ; EV_SHOT_FIRED
            beq   :fired
            cmp   #3                          ; EV_SHOT_HIT
            beq   :hit
            cmp   #4                          ; EV_SHOT_MISSED
            beq   :missed
            rts                               ; other events carry no animation
:moved                                        ; args: unit, oldx, oldy, newx, newy
            lda   proto_payload+2,x
            sta   mv_last_unit
            lda   proto_payload+3,x
            sta   mv_last_fx
            lda   proto_payload+4,x
            sta   mv_last_fy
            lda   proto_payload+5,x
            sta   mv_last_tx
            lda   proto_payload+6,x
            sta   mv_last_ty
            lda   #1
            sta   mv_moved
            rts
:fired                                        ; args: attacker, target, ax, ay, tx, ty
            lda   proto_payload+2,x           ; attacker id -> class (for the box size)
            tay
            lda   unit_class,y
            sta   fr_shot_class
            lda   proto_payload+4,x
            sta   fr_shot_fx
            lda   proto_payload+5,x
            sta   fr_shot_fy
            lda   proto_payload+6,x
            sta   fr_shot_tx
            lda   proto_payload+7,x
            sta   fr_shot_ty
            stz   fr_shot_hit                 ; a following HIT event upgrades this
            lda   #1
            sta   fr_shot
            rts
:hit        lda   #1
            sta   fr_shot_hit
            rts
:missed     jmp   nl_miss_land                ; where the stray shot comes to rest

* nl_miss_land: fr_shot_land_x/y = the square a missed shot lands on -- one
* square past the target along the line of fire, shifted a tile in y (up, or
* down when up would leave the top of the board), clamped to the board. The
* exact copy of miss_resolve's landing math (fire.s), reusing ms_sgn/ms_clamp,
* since the snapshot carries no scatter square. In: fr_shot_fx/fy/tx/ty.
nl_miss_land
            lda   fr_shot_tx                  ; dx = sgn(tx - fx)
            sec
            sbc   fr_shot_fx
            jsr   ms_sgn
            sta   rt0
            lda   fr_shot_ty                  ; dy = sgn(ty - fy)
            sec
            sbc   fr_shot_fy
            jsr   ms_sgn
            sta   rt1
            lda   fr_shot_fy                  ; y shift from the higher endpoint
            cmp   fr_shot_ty
            bcc   :miny                        ; fy < ty: min is fy (already in A)
            lda   fr_shot_ty
:miny       cmp   #1
            bcs   :up                          ; min >= 1: shift up
            lda   #1                           ; top-row endpoint: shift down
            bra   :yadd
:up         lda   #$FF
:yadd       clc
            adc   rt1
            sta   rt1                          ; dy + y shift
            lda   fr_shot_tx                   ; land_x = clamp(tx + dx)
            clc
            adc   rt0
            ldx   #BOARD_W
            jsr   ms_clamp
            sta   fr_shot_land_x
            lda   fr_shot_ty                   ; land_y = clamp(ty + dy + shift)
            clc
            adc   rt1
            ldx   #BOARD_H
            jsr   ms_clamp
            sta   fr_shot_land_y
            rts

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
nl_matched   dfb   0                  ; a match is live (token stored) -> watch the link
nl_lost      dfb   0                  ; reconnect gave up; stop retrying
nl_recon_tries dfb 0                  ; reconnect attempts since the link dropped
nl_dirty     dfb   0
nl_action    dfb   0,0
nl_to        dfb   0,0
nl_ecount    dfb   0
nl_off       dfb   0
nl_rxbuf     =     $0E80              ; recv chunk in free bank-0 RAM ($0E80-$0EFF)
