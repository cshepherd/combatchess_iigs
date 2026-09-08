*----------------------------------------------------------
* events.s - The event queue between the rules engine and
* the display layer (spec section 32).
*
* PUT into any part that carries the rules engine, after
* units.s. Same convention: native mode, 8-bit A/X/Y,
* DBR $00, D $0000.
*
* Rules code never draws or plays sound. Each action queues
* the events describing what happened; the display layer
* pops them in order and animates. An event is a type plus
* five parameter bytes whose meaning depends on the type
* (see the EV_* list). The queue is drained between player
* commands, so a modest fixed size is enough; a push into a
* full queue is dropped and reported by carry clear.
*----------------------------------------------------------
EV_NONE              = 0
EV_UNIT_MOVED        = 1   ; unit, from x, from y, to x, to y
EV_SHOT_FIRED        = 2   ; attacker, target, -, -, -
EV_SHOT_HIT          = 3   ; attacker, target, roll, -, -
EV_SHOT_MISSED       = 4   ; attacker, target, roll, -, -
EV_STRAY_HIT         = 5   ; attacker, victim, x, y, -
EV_UNIT_DAMAGED      = 6   ; unit, damage, hp left, -, -
EV_UNIT_DESTROYED    = 7   ; unit, x, y, -, -
EV_TERRAIN_DAMAGED   = 8   ; x, y, terrain hp left, -, -
EV_TERRAIN_DESTROYED = 9   ; x, y, old type, new type, -
EV_TURN_CHANGED      = 10  ; side now to move, -, -, -, -
EV_GAME_OVER         = 11  ; result, winner, -, -, -

EV_SIZE = 6                ; type + 5 parameters
EV_MAX  = 32               ; records the queue holds

*----------------------------------------------------------
* events_clear - Empty the queue. Clobbers nothing.
*----------------------------------------------------------
events_clear
 MX %11
 stz ev_count
 stz ev_read
 rts

*----------------------------------------------------------
* event_push - Queue the record in ev_type / ev_p0..ev_p4.
* Out: carry set = queued, clear = queue full (dropped).
* Clobbers A, X, Y, rt0.
*----------------------------------------------------------
event_push
 MX %11
 lda ev_count
 cmp #EV_MAX
 bcs :full
 inc ev_count
 jsr ev_offset
 tax
 ldy #0
:copy
 lda ev_rec,y
 sta event_queue,x
 inx
 iny
 cpy #EV_SIZE
 bne :copy
 sec
 rts
:full
 clc
 rts

*----------------------------------------------------------
* event_pop - Take the oldest record into ev_type /
* ev_p0..ev_p4.
* Out: carry set = got one, clear = queue empty (the queue
*      resets to its start when it empties).
* Clobbers A, X, Y, rt0.
*----------------------------------------------------------
event_pop
 MX %11
 lda ev_read
 cmp ev_count
 bcs :empty
 inc ev_read
 jsr ev_offset
 tax
 ldy #0
:copy
 lda event_queue,x
 sta ev_rec,y
 inx
 iny
 cpy #EV_SIZE
 bne :copy
 sec
 rts
:empty
 stz ev_count
 stz ev_read
 clc
 rts

* ev_offset - A = record index -> A = index * EV_SIZE.
ev_offset
 MX %11
 asl
 sta rt0
 asl
 clc
 adc rt0
 rts

ev_rec  ds EV_SIZE         ; the record being pushed or popped
ev_type = ev_rec
ev_p0   = ev_rec+1
ev_p1   = ev_rec+2
ev_p2   = ev_rec+3
ev_p3   = ev_rec+4
ev_p4   = ev_rec+5

ev_count ds 1              ; records written since the last reset
ev_read  ds 1              ; records consumed
event_queue ds EV_MAX*EV_SIZE
