*----------------------------------------------------------
* netloop_test.s - exercise the GAME network glue (netloop.s) live.
*
* Runs the exact routines GAME uses -- net_game_start, net_send_move,
* net_send_end, net_poll_step -- against the running Python match server,
* checking that the engine's unit arrays track the server's authoritative
* state. No toolbox/render: it validates the loop glue, not the pixels.
*
* Result block:
*   $0300 start(0=ok)  $0301 my_side  $0302/03 unit0 initial x,y
*   $0304 move-poll dirty seen(1)  $0305/06 unit0 x,y after our move
*   $0307 bot-activity applies after END_TURN
*   $030F $A5 done
*----------------------------------------------------------
            org   $2000
            mx    %11
            put   shared

start       sei
            sec
            xce
            cld
            ldx   #$FF
            txs
            lda   #0
            pha
            plb
            ldx   #$0F
            lda   #$EE
:pz         sta   $0300,x
            dex
            bpl   :pz

            jsr   net_game_start            ; connect + match + apply snapshot
            lda   #0
            bcc   :ok
            lda   #$FF
:ok         sta   $0300
            lda   nl_my_side
            sta   $0301
* unit 0 initial position from the engine (net_game_start applied it)
            lda   unit_x+0
            sta   $0302
            lda   unit_y+0
            sta   $0303

* send C_MOVE unit0 -> (x-1, y); poll until the server's snapshot applies
            lda   unit_x+0
            dec
            tax                              ; dest x
            ldy   unit_y+0                    ; dest y
            lda   #0                          ; unit id 0
            jsr   net_send_move
            ldx   #40
:mp         phx
            jsr   net_poll_step
            lda   nl_dirty
            beq   :mpn
            lda   #1
            sta   $0304                       ; a snapshot applied
            plx
            bra   :moved
:mpn        jsr   net_delay
            plx
            dex
            bne   :mp
:moved      lda   unit_x+0
            sta   $0305
            lda   unit_y+0
            sta   $0306

* end our turn; poll and count how many bot-driven snapshots arrive
            jsr   net_send_end
            stz   $0307
            ldx   #60
:bp         phx
            jsr   net_poll_step
            lda   nl_dirty
            beq   :bpn
            inc   $0307
:bpn        jsr   net_delay
            plx
            dex
            bne   :bp

            lda   #$A5
            sta   $030F
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
            put   netloop
            put   common
