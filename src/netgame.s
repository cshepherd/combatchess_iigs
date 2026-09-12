*----------------------------------------------------------
* netgame.s - IIGS network client glue (spec N4).
*
* Sits above proto.s (framing) and net.s (bytes): builds the
* client action frames the game sends and decodes the S_STATE
* snapshot the server broadcasts into a flat, indexable form the
* renderer/HUD can read. No W5100 access here; no game logic --
* it only marshals bytes and mirrors the authoritative state.
*
* The wire format is server/protocol.py; the encoders here are
* checked byte-exact against server/fixtures/*.bin (netgame_test).
* Runs native or emulation, 8-bit A/X/Y, DBR $00.
*----------------------------------------------------------

* Message type IDs (protocol.py section 9).
NET_C_HELLO       = $01
NET_S_WELCOME     = $02
NET_C_QUEUE_JOIN  = $03
NET_S_MATCH_START = $10
NET_C_MOVE        = $11
NET_C_FIRE        = $12
NET_C_END_TURN    = $13
NET_C_SURRENDER   = $14
NET_S_ACTION_RESULT = $15
NET_S_STATE       = $16
NET_S_GAME_OVER   = $17
NET_C_PING        = $20
NET_S_PONG        = $21

* Matchmaking modes + client kinds (protocol.py).
NET_QUEUE_QUICK = 0
NET_QUEUE_HUMAN = 1
NET_QUEUE_BOT   = 2
NET_CLIENT_HUMAN = 0
NET_CLIENT_BOT   = 1

* Direct-page source/dest pointers for the snapshot decode (alias
* shared.s rt4-rt7; live only inside one netgame routine).
NSP = $E8
NDP = $EA

*----------------------------------------------------------
* Client frame builders. Each lays a complete frame in proto_tx
* (via proto.s) and returns the total length in proto_total /
* A (proto_finish); the caller then net_sends proto_tx. Frame
* seq comes from ng_seq, action_id from ng_action_id, and the
* match id from ng_match_id (all set by the game).
*----------------------------------------------------------

* Load ng_seq into proto_seq (proto_begin reads proto_seq).
_ng_seq
            lda   ng_seq+0
            sta   proto_seq+0
            lda   ng_seq+1
            sta   proto_seq+1
            rts

* Emit ng_match_id (u32) then ng_action_id (u16) -- the common
* head of every client action message.
_ng_action_head
            ldx   #0
:cp         lda   ng_match_id,x
            sta   proto_val32,x
            inx
            cpx   #4
            bne   :cp
            jsr   proto_u32
            lda   ng_action_id+0
            ldx   ng_action_id+1
            jsr   proto_u16
            rts

* net_build_hello: rules=1, build=ng_build(u32), cap=ng_cap(u16),
* kind=A, name at (NDP) length X. Builds C_HELLO.
net_build_hello
            sta   ng_tmp                 ; client_kind
            stx   ng_tmp2                ; name length
            jsr   _ng_seq
            lda   #NET_C_HELLO
            jsr   proto_begin
            lda   #1                      ; u16 rules_version
            ldx   #0
            jsr   proto_u16
            ldx   #0                       ; u32 client_build
:cb         lda   ng_build,x
            sta   proto_val32,x
            inx
            cpx   #4
            bne   :cb
            jsr   proto_u32
            lda   ng_cap+0                 ; u16 capability_bits
            ldx   ng_cap+1
            jsr   proto_u16
            lda   ng_tmp                   ; u8 client_kind
            jsr   proto_emit
            lda   NDP                      ; name -> PRP for proto_name
            sta   PRP
            lda   NDP+1
            sta   PRP+1
            lda   ng_tmp2
            jsr   proto_name
            jsr   proto_finish
            rts

* net_build_queue: A = mode. Builds C_QUEUE_JOIN.
net_build_queue
            sta   ng_tmp
            jsr   _ng_seq
            lda   #NET_C_QUEUE_JOIN
            jsr   proto_begin
            lda   ng_tmp
            jsr   proto_emit
            jsr   proto_finish
            rts

* net_build_move: A = unit id, X = dest x, Y = dest y. C_MOVE.
net_build_move
            sta   ng_tmp
            stx   ng_tmp2
            sty   ng_tmp3
            jsr   _ng_seq
            lda   #NET_C_MOVE
            jsr   proto_begin
            jsr   _ng_action_head
            lda   ng_tmp
            jsr   proto_emit
            lda   ng_tmp2
            jsr   proto_emit
            lda   ng_tmp3
            jsr   proto_emit
            jsr   proto_finish
            rts

* net_build_fire: A = attacker id, X = target id. C_FIRE.
net_build_fire
            sta   ng_tmp
            stx   ng_tmp2
            jsr   _ng_seq
            lda   #NET_C_FIRE
            jsr   proto_begin
            jsr   _ng_action_head
            lda   ng_tmp
            jsr   proto_emit
            lda   ng_tmp2
            jsr   proto_emit
            jsr   proto_finish
            rts

* net_build_end: C_END_TURN (match_id + action_id only).
net_build_end
            jsr   _ng_seq
            lda   #NET_C_END_TURN
            jsr   proto_begin
            jsr   _ng_action_head
            jsr   proto_finish
            rts

* net_build_surrender: C_SURRENDER (match_id + action_id only).
net_build_surrender
            jsr   _ng_seq
            lda   #NET_C_SURRENDER
            jsr   proto_begin
            jsr   _ng_action_head
            jsr   proto_finish
            rts

*----------------------------------------------------------
* netstate_parse: decode an S_STATE payload sitting in proto_payload
* (as left by proto_rx_next) into the flat ns_* fields. The unit
* block (<= 22 units x 11 bytes = 242) and the 220-byte terrain each
* fit in a page, so 8-bit index copies suffice per block. Clobbers
* A/X/Y and the netgame scratch.
*
* Snapshot layout (spec 20): active,phase,moves,inactive (4) |
* red_ms,black_ms (u32 x2) | ucount (1) | units[ucount*11] |
* terrain[220] | serial (u32).
*----------------------------------------------------------
netstate_parse
            lda   #<proto_payload
            sta   NSP
            lda   #>proto_payload
            sta   NSP+1
* netstate_decode: as netstate_parse, but the caller has already pointed
* NSP at the start of the S_STATE bytes. Used for the snapshot embedded
* in S_MATCH_START (after its 37-byte prefix) and S_ACTION_RESULT (after
* its header + event list).
netstate_decode
            ldy   #0                       ; 4 header bytes
            lda   (NSP),y
            sta   ns_active
            iny
            lda   (NSP),y
            sta   ns_phase
            iny
            lda   (NSP),y
            sta   ns_moves
            iny
            lda   (NSP),y
            sta   ns_inactive
            ldy   #4                        ; red_ms (u32)
            ldx   #0
:rm         lda   (NSP),y
            sta   ns_red_ms,x
            iny
            inx
            cpx   #4
            bne   :rm
            ldx   #0                        ; black_ms (u32), y=8..11
:bm         lda   (NSP),y
            sta   ns_black_ms,x
            iny
            inx
            cpx   #4
            bne   :bm
            lda   (NSP),y                   ; ucount at offset 12
            sta   ns_ucount

* advance NSP past the 13-byte header
            clc
            lda   NSP
            adc   #13
            sta   NSP
            lda   NSP+1
            adc   #0
            sta   NSP+1

* unit bytes = ucount * 11  (<= 242, fits a byte)
            lda   ns_ucount
            asl                            ; *2
            asl                            ; *4
            asl                            ; *8
            sta   ng_tmp                    ; ucount*8
            lda   ns_ucount
            asl                            ; *2
            clc
            adc   ng_tmp                    ; *10
            clc
            adc   ns_ucount                 ; *11
            sta   ns_ubytes
            beq   :noutx                    ; zero units (shouldn't happen)
            ldy   #0
:ucp        lda   (NSP),y
            sta   ns_units,y
            iny
            cpy   ns_ubytes
            bne   :ucp
:noutx
* advance NSP past the unit block
            clc
            lda   NSP
            adc   ns_ubytes
            sta   NSP
            lda   NSP+1
            adc   #0
            sta   NSP+1

* copy 220 terrain bytes
            ldy   #0
:tcp        lda   (NSP),y
            sta   ns_terrain,y
            iny
            cpy   #220
            bne   :tcp
* advance NSP past terrain
            clc
            lda   NSP
            adc   #220
            sta   NSP
            lda   NSP+1
            adc   #0
            sta   NSP+1

* serial (u32)
            ldy   #0
:sc         lda   (NSP),y
            sta   ns_serial,y
            iny
            cpy   #4
            bne   :sc
            rts

*----------------------------------------------------------
* Accessors into the decoded unit block (11 bytes/unit):
*   +0 id +1 cls +2 side +3 x +4 y +5 hp +6/7 fuel +8 ammo
*   +9 terr_hp +10 flags
* net_unit_ptr: A = unit index -> NDP points at that record.
* Clobbers A/X.
*----------------------------------------------------------
net_unit_ptr
            sta   ng_tmp                    ; index
            asl                            ; *2
            asl                            ; *4
            asl                            ; *8
            sta   ng_tmp2                    ; idx*8
            lda   ng_tmp
            asl                            ; *2
            clc
            adc   ng_tmp2                    ; *10
            clc
            adc   ng_tmp                     ; *11
            clc
            adc   #<ns_units
            sta   NDP
            lda   #>ns_units
            adc   #0
            sta   NDP+1
            rts

*----------------------------------------------------------
* State (bank $00, part-local).
*----------------------------------------------------------
NS_MAX_UNITS = 22

ng_seq       dfb   0,0                ; frame sequence for the next build
ng_match_id  dfb   0,0,0,0            ; current match id (u32 LE)
ng_action_id dfb   0,0                ; client action sequence (u16)
ng_build     dfb   0,0,0,0            ; client_build for HELLO (u32)
ng_cap       dfb   0,0                ; capability_bits for HELLO (u16)
ng_tmp       dfb   0
ng_tmp2      dfb   0
ng_tmp3      dfb   0

* Decoded S_STATE snapshot.
ns_active    dfb   0
ns_phase     dfb   0
ns_moves     dfb   0
ns_inactive  dfb   0
ns_red_ms    dfb   0,0,0,0
ns_black_ms  dfb   0,0,0,0
ns_ucount    dfb   0
ns_ubytes    dfb   0
ns_serial    dfb   0,0,0,0
ns_units     ds    NS_MAX_UNITS*11
ns_terrain   ds    220
