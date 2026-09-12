*----------------------------------------------------------
* netplay_test.s - verify netstate_apply populates the engine (N4).
*
* Network-free: decodes the board-1 S_STATE fixture (poked at $5000) and
* applies it to the engine's board / occupant / unit_* arrays, which the
* host then reads back and compares to the snapshot. Proves the renderer
* would see the server's authoritative state.
*
* Result: $0300 = $A5 done. The host reads board[], unit_x/y/hp[] and
* occupant[] at their engine addresses (from the listing) and checks them.
*----------------------------------------------------------
            org   $2000
            mx    %11
            put   shared

STATEF = $7000                ; host pokes state_board1.bin here

start       sei
            sec
            xce
            cld
            ldx   #$FF
            txs
            lda   #0
            pha
            plb
            stz   $0300

            jsr   proto_rx_reset
            lda   #<STATEF
            sta   PRP
            lda   #>STATEF
            sta   PRP+1
            lda   #<421
            sta   proto_cnt+0
            lda   #>421
            sta   proto_cnt+1
            jsr   proto_rx_add
            jsr   proto_rx_next               ; -> proto_payload = S_STATE payload
            jsr   netstate_parse              ; -> ns_*
            jsr   netstate_apply              ; -> board / occupant / unit_*

            lda   #$A5
            sta   $0300
:spin       bra   :spin

            put   tables
            put   board
            put   line
            put   units
            put   events
            put   move
            put   rng
            put   fire
            put   turn
            put   aiplayer
            put   net
            put   netdhcp
            put   proto
            put   netgame
            put   netplay
            put   common
