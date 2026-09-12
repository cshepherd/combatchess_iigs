*----------------------------------------------------------
* netgame_test.s - network-free validation of src/netgame.s (N4).
*
* Poked into MAME and run from $2000 (no network). Builds the client
* action frames with netgame's encoders and decodes the board-1
* S_STATE fixture through proto.s + netstate_parse. The host compares
* the built frames to server/fixtures/{queue_bot,move,fire}.bin and
* the decoded snapshot to state_board1.bin.
*
* Output:
*   $4000 queue_bot frame   $4020 move frame   $4040 fire frame
*   $4080 lengths (queue, move, fire)
* Parser (state_board1 fixture frame poked at $5000):
*   $4090 ns_ucount   $4091 ns_active   $4092 ns_serial(4)
*   $4096 terrain checksum (u16)
*   $40A0 per unit i: id, x, y, hp (4 bytes each)
*   $4100 $A5 done
*----------------------------------------------------------
            org   $2000
            mx    %11

DSTP = $F0
STATEF = $5000                ; host pokes state_board1.bin here

start       sei
            sec
            xce
            cld
            ldx   #$FF
            txs
            lda   #0
            pha
            plb

* ------- build queue_bot (seq=3, mode=QUEUE_BOT) -------
            lda   #3
            sta   ng_seq+0
            stz   ng_seq+1
            lda   #NET_QUEUE_BOT
            jsr   net_build_queue
            lda   #<$4000
            sta   DSTP
            lda   #>$4000
            sta   DSTP+1
            jsr   save_tx
            lda   proto_total+0
            sta   $4080+0

* ------- build move (seq=7, match=$01020304, action=$0009, u5 x9 y3) -------
            lda   #7
            sta   ng_seq+0
            stz   ng_seq+1
            lda   #$04                    ; match_id LE = 04 03 02 01
            sta   ng_match_id+0
            lda   #$03
            sta   ng_match_id+1
            lda   #$02
            sta   ng_match_id+2
            lda   #$01
            sta   ng_match_id+3
            lda   #$09                    ; action_id = $0009
            sta   ng_action_id+0
            stz   ng_action_id+1
            lda   #5
            ldx   #9
            ldy   #3
            jsr   net_build_move
            lda   #<$4020
            sta   DSTP
            lda   #>$4020
            sta   DSTP+1
            jsr   save_tx
            lda   proto_total+0
            sta   $4080+1

* ------- build fire (seq=8, action=$000A, att=5 tgt=12) -------
            lda   #8
            sta   ng_seq+0
            stz   ng_seq+1
            lda   #$0A
            sta   ng_action_id+0
            stz   ng_action_id+1
            lda   #5
            ldx   #12
            jsr   net_build_fire
            lda   #<$4040
            sta   DSTP
            lda   #>$4040
            sta   DSTP+1
            jsr   save_tx
            lda   proto_total+0
            sta   $4080+2

* ------- parse the state_board1 fixture frame at $5000 -------
            jsr   proto_rx_reset
            lda   #<STATEF                ; feed the whole 421-byte frame
            sta   PRP
            lda   #>STATEF
            sta   PRP+1
            lda   #<421
            sta   proto_cnt+0
            lda   #>421
            sta   proto_cnt+1
            jsr   proto_rx_add
            jsr   proto_rx_next            ; -> proto_payload = S_STATE payload
            jsr   netstate_parse

            lda   ns_ucount
            sta   $4090
            lda   ns_active
            sta   $4091
            ldx   #0
:sc         lda   ns_serial,x
            sta   $4092,x
            inx
            cpx   #4
            bne   :sc

* terrain checksum (u16 sum of 220 bytes)
            stz   $4096
            stz   $4097
            ldy   #0
:tk         clc
            lda   $4096
            adc   ns_terrain,y
            sta   $4096
            lda   $4097
            adc   #0
            sta   $4097
            iny
            cpy   #220
            bne   :tk

* per-unit id,x,y,hp -> $40A0 + i*4
            lda   #0
            sta   uidx
:uloop      lda   uidx
            cmp   ns_ucount
            bcs   :udone
            jsr   net_unit_ptr             ; NDP -> unit record
            lda   uidx                      ; dst = $40A0 + i*4
            asl
            asl
            clc
            adc   #<$40A0
            sta   DSTP
            lda   #>$40A0
            adc   #0
            sta   DSTP+1
            ldy   #0
            lda   (NDP),y                   ; +0 id
            sta   (DSTP),y
            ldy   #3
            lda   (NDP),y                   ; +3 x
            ldy   #1
            sta   (DSTP),y
            ldy   #4
            lda   (NDP),y                   ; +4 y
            ldy   #2
            sta   (DSTP),y
            ldy   #5
            lda   (NDP),y                   ; +5 hp
            ldy   #3
            sta   (DSTP),y
            inc   uidx
            bra   :uloop
:udone
            lda   #$A5
            sta   $4100
:spin       bra   :spin

* save_tx: copy proto_total bytes from proto_tx to (DSTP).
save_tx
            lda   proto_total+0
            sta   st_cnt
            ldy   #0
:l          lda   proto_tx,y
            sta   (DSTP),y
            iny
            cpy   st_cnt
            bne   :l
            rts

st_cnt       dfb   0
uidx         dfb   0

            put   proto
            put   netgame
