*----------------------------------------------------------
* netplay.s - apply a decoded network snapshot to the engine (N4).
*
* netstate_parse/decode (netgame.s) leaves the authoritative state in
* the flat ns_* fields; netstate_apply mirrors it into the engine's
* board / occupant / unit_* arrays so the existing renderer (art.s) and
* HUD draw the server's truth without any other change. The engine slot
* index is the server unit id (both assign 0..N in the same order), so a
* unit keeps its identity across the wire.
*
* Included by GAME (needs board.s / units.s). Runs 8-bit A/X/Y, DBR $00.
*----------------------------------------------------------

* netstate_apply: copy ns_terrain -> board, rebuild the occupant map, and
* fill the unit arrays from ns_units (slot = id). Dead units keep their
* slot data but are not placed on the board. Clobbers A/X/Y and np scratch.
            mx    %11

netstate_apply
            ldy   #0                       ; terrain: ns_terrain -> board (220)
:tc         lda   ns_terrain,y
            sta   board,y
            iny
            cpy   #220
            bne   :tc

            ldx   #0                         ; clear the occupant map
:oc         stz   occupant,x
            inx
            cpx   #220
            bne   :oc

            ldx   #MAX_UNITS-1               ; mark every slot dead first
:df         stz   unit_flags,x
            dex
            bpl   :df

            stz   np_i
:ul         lda   np_i
            cmp   ns_ucount
            bcc   :cont
            jmp   :udone
:cont       jsr   net_unit_ptr               ; NDP -> this unit's 11-byte record
            ldy   #0
            lda   (NDP),y                     ; +0 id -> engine slot
            tax
            ldy   #1
            lda   (NDP),y
            sta   unit_class,x
            ldy   #2
            lda   (NDP),y
            sta   unit_side,x
            ldy   #3
            lda   (NDP),y
            sta   unit_x,x
            sta   np_x
            ldy   #4
            lda   (NDP),y
            sta   unit_y,x
            sta   np_y
            ldy   #5
            lda   (NDP),y
            sta   unit_hp,x
            ldy   #6                          ; fuel u16 -> 1-byte engine fuel (<=240)
            lda   (NDP),y
            sta   unit_fuel,x
            ldy   #8
            lda   (NDP),y
            sta   unit_ammo,x
            ldy   #9
            lda   (NDP),y
            sta   unit_terr_hp,x
            ldy   #10
            lda   (NDP),y
            sta   unit_flags,x
            and   #$80                        ; alive? then place on the board
            beq   :nextu
            lda   np_y                         ; cell = y*20 + x
            asl
            asl                                ; y*4
            sta   np_t
            lda   np_y
            asl
            asl
            asl
            asl                                ; y*16
            clc
            adc   np_t                          ; y*20
            clc
            adc   np_x                          ; + x  (<=219, fits a byte)
            tay
            txa                                 ; slot id
            clc
            adc   #1                            ; occupant stores id+1
            sta   occupant,y
:nextu      inc   np_i
            jmp   :ul
:udone
* mirror the server's turn + clocks into the engine so the HUD and turn
* logic read the server's truth (the server owns time, spec 22)
            lda   ns_active
            sta   active_side
            ldx   #3                        ; side_time RED = ns_red_ms >> 4 (ms -> ticks)
:crt        lda   ns_red_ms,x
            sta   side_time,x
            dex
            bpl   :crt
            ldx   #4
:crs        lsr   side_time+3
            ror   side_time+2
            ror   side_time+1
            ror   side_time+0
            dex
            bne   :crs
            ldx   #3                        ; side_time BLACK = ns_black_ms >> 4
:cbt        lda   ns_black_ms,x
            sta   side_time+4,x
            dex
            bpl   :cbt
            ldx   #4
:cbs        lsr   side_time+7
            ror   side_time+6
            ror   side_time+5
            ror   side_time+4
            dex
            bne   :cbs
            jsr   get_tick                   ; turn_start_tick = now, so the active
            ldx   #3                        ; side's clock shows the stored ticks
:ctt        lda   now_tick,x                 ; (not floored by a stale elapsed)
            sta   turn_start_tick,x
            dex
            bpl   :ctt
            rts

np_i         dfb   0
np_x         dfb   0
np_y         dfb   0
np_t         dfb   0
