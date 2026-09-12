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
            lda   ns_moves                  ; HUD reads the server's move count
            sta   moves_used
            ldx   #3                        ; side_time RED = ns_red_ms * 3/50 (ms -> ticks)
:crt        lda   ns_red_ms,x
            sta   np_ms,x
            dex
            bpl   :crt
            jsr   np_ms_to_ticks
            ldx   #3
:crs        lda   np_ms,x
            sta   side_time,x
            dex
            bpl   :crs
            ldx   #3                        ; side_time BLACK = ns_black_ms * 3/50
:cbt        lda   ns_black_ms,x
            sta   np_ms,x
            dex
            bpl   :cbt
            jsr   np_ms_to_ticks
            ldx   #3
:cbs        lda   np_ms,x
            sta   side_time+4,x
            dex
            bpl   :cbs
            jsr   get_tick                   ; turn_start_tick = now, so the active
            ldx   #3                        ; side's clock shows the stored ticks
:ctt        lda   now_tick,x                 ; (not floored by a stale elapsed)
            sta   turn_start_tick,x
            dex
            bpl   :ctt
            rts

* np_ms_to_ticks: np_ms (4-byte LE) := np_ms * 3 / 50, the exact ms->tick
* conversion (60 Hz / 1000 = 3/50) that replaces the old >>4 (which ran
* the clocks ~4% fast). Enters 8-bit native, does the 32-bit multiply and
* long division in 16-bit, returns 8-bit. Clobbers A/X, np_tmp, np_rem.
np_ms_to_ticks
            rep   #$30
            mx    %00
            lda   np_ms+0                  ; np_tmp = np_ms  (keep the x1 value)
            sta   np_tmp+0
            lda   np_ms+2
            sta   np_tmp+2
            asl   np_ms+0                  ; np_ms *= 2
            rol   np_ms+2
            clc                             ; np_ms = np_ms*2 + np_ms = *3
            lda   np_ms+0
            adc   np_tmp+0
            sta   np_ms+0
            lda   np_ms+2
            adc   np_tmp+2
            sta   np_ms+2
            stz   np_rem                    ; divide the 32-bit np_ms by 50
            ldx   #32
:dl         asl   np_ms+0                  ; {np_rem:np_ms} <<= 1
            rol   np_ms+2
            rol   np_rem
            lda   np_rem
            cmp   #50
            bcc   :ds
            sbc   #50                       ; carry set by cmp -> subtract
            sta   np_rem
            inc   np_ms+0                   ; quotient bit into the vacated bit 0
:ds         dex
            bne   :dl
            sep   #$30
            mx    %11
            rts

np_i         dfb   0
np_x         dfb   0
np_y         dfb   0
np_t         dfb   0
np_ms        dfb   0,0,0,0
np_tmp       dfb   0,0,0,0
np_rem       dfb   0,0
