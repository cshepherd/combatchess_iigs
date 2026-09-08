*----------------------------------------------------------
* board.s - Board geometry, cells and terrain (spec sections
* 3, 18-21, 23 and 31).
*
* PUT into any part that carries the rules engine, after
* shared.s and tables.s. Same convention: native mode, 8-bit
* A/X/Y, DBR $00, D $0000.
*
* A cell is one byte: its terrain type. Everything a type
* does lives in the terrain_* tables, so a board is 220 type
* bytes and destruction is a type change (spec 31): TREE ->
* CLEAR, BRIDGE -> WATER, GREY -> WHITE. Terrain hit points
* belong to the unit standing on a cell (spec 23), not to
* the cell, so cells carry no HP.
*----------------------------------------------------------

BOARD_W     = 20
BOARD_H     = 11
BOARD_CELLS = 220          ; BOARD_W * BOARD_H, row-major, y*20+x

* Directions (spec 3.2), clockwise from north. Even values
* are orthogonal and odd are diagonal, so a direction's
* orientation is (dir AND 1) = ORIENT_ORTH or ORIENT_DIAG.
DIR_N    = 0
DIR_NE   = 1
DIR_E    = 2
DIR_SE   = 3
DIR_S    = 4
DIR_SW   = 5
DIR_W    = 6
DIR_NW   = 7
NUM_DIRS = 8

* Unit steps per direction; $FF is -1 and wraps correctly
* in 8-bit arithmetic (a step off the top or left edge lands
* on $FF, which cell_in_bounds rejects).
dir_dx dfb 0,1,1,1,0,$FF,$FF,$FF
dir_dy dfb $FF,$FF,0,1,1,1,0,$FF

*----------------------------------------------------------
* Terrain types. Natural boards 1-5 and 10 use the first
* five; abstract boards 6-9 use the rest.
*----------------------------------------------------------
TERR_CLEAR    = 0   ; open ground
TERR_TREE     = 1   ; forest: passable at a cost, blocks fire, burns to CLEAR
TERR_WATER    = 2   ; impassable, fire crosses it
TERR_BRIDGE   = 3   ; passable crossing, destroyed to WATER
TERR_MOUNTAIN = 4   ; blocks everything, permanent
TERR_WHITE    = 5   ; abstract open cell (board 6 free blocks, board 9 white)
TERR_YELLOW   = 6   ; abstract open cell, boards 7-8 centre (differs only in look)
TERR_GREY     = 7   ; board 9 grey: sealed until destroyed, then WHITE
TERR_PURPLE   = 8   ; fire crosses, no movement (board 9 purple, board 6 centre)
TERR_BLACK    = 9   ; abstract blocker, permanent
NUM_TERRAIN   = 10

* Terrain flags. TF_FIRE and TF_MOVE sit in bits 7 and 6 so
* "bit terrain_flags,x" answers with N and V in one go:
* bpl = fire blocked, bvc = movement blocked.
TF_FIRE     = $80   ; shots pass through the cell
TF_MOVE     = $40   ; units may enter and pass through
TF_DESTRUCT = $01   ; destroy_cell turns it into terrain_after
TF_SLOW     = $02   ; movement penalties apply (spec 9.4, 19.1)

* Spec 18 lists "can move into" and "blocks movement through"
* separately, but no terrain in the manual tells them apart,
* so one TF_MOVE bit serves both until the Atari executable
* shows otherwise (spec 34).
*
* UNVERIFIED (spec 34, board 9): whether GREY blocks fire
* before it is destroyed, and what destroys it, since no
* unit can stand on it. Sealed to both here.
terrain_flags
 dfb TF_FIRE+TF_MOVE                 ; CLEAR
 dfb TF_MOVE+TF_DESTRUCT+TF_SLOW     ; TREE
 dfb TF_FIRE                         ; WATER
 dfb TF_FIRE+TF_MOVE+TF_DESTRUCT     ; BRIDGE
 dfb 0                               ; MOUNTAIN
 dfb TF_FIRE+TF_MOVE                 ; WHITE
 dfb TF_FIRE+TF_MOVE                 ; YELLOW
 dfb TF_DESTRUCT                     ; GREY
 dfb TF_FIRE                         ; PURPLE
 dfb 0                               ; BLACK

* What a destroyed cell becomes. Indestructible types map to
* themselves so the table is safe to read for any type.
terrain_after
 dfb TERR_CLEAR,TERR_CLEAR,TERR_WATER,TERR_WATER,TERR_MOUNTAIN
 dfb TERR_WHITE,TERR_YELLOW,TERR_WHITE,TERR_PURPLE,TERR_BLACK

* Movement penalties by terrain type (spec 9.4, 19.1). The
* manual says trees cost extra fuel and reduce the move
* allowance but gives no numbers.
* UNVERIFIED: every entry is 0 until measured on the Atari
* executable (spec 34). Movement code must read these, not
* assume them.
terrain_move_penalty dfb 0,0,0,0,0,0,0,0,0,0   ; squares off the allowance
terrain_fuel_penalty dfb 0,0,0,0,0,0,0,0,0,0   ; extra fuel per square entered

*----------------------------------------------------------
* cell_in_bounds - Is (X, Y) on the board?
* In:  X = x, Y = y
* Out: carry set = on the board. Preserves A, X, Y.
*----------------------------------------------------------
cell_in_bounds
 MX %11
 cpx #BOARD_W
 bcs :out
 cpy #BOARD_H
 bcs :out
 sec
 rts
:out
 clc
 rts

*----------------------------------------------------------
* cell_index - Board array index of (X, Y).
* In:  X = x, Y = y (must be on the board)
* Out: A = y*20 + x. Preserves X, Y. Clobbers rt0.
*----------------------------------------------------------
cell_index
 MX %11
 tya
 asl
 asl                       ; y*4
 sta rt0
 asl
 asl                       ; y*16
 clc
 adc rt0                   ; y*20
 sta rt0
 txa
 clc
 adc rt0
 rts

*----------------------------------------------------------
* get_cell - Terrain type at (X, Y).
* In:  X = x, Y = y (on the board)
* Out: A = TERR_*. Preserves X, Y. Clobbers rt0.
*----------------------------------------------------------
get_cell
 MX %11
 jsr cell_index
 phx
 tax
 lda board,x
 plx
 rts

*----------------------------------------------------------
* set_cell - Put terrain type A at (X, Y).
* In:  X = x, Y = y (on the board), A = TERR_*
* Out: A = the type. Preserves X, Y. Clobbers rt0, rt1.
*----------------------------------------------------------
set_cell
 MX %11
 sta rt1
 jsr cell_index
 phx
 tax
 lda rt1
 sta board,x
 plx
 rts

*----------------------------------------------------------
* cell_flags - Flags for a terrain type.
* In:  A = TERR_*
* Out: A = TF_* bits. Preserves X, Y.
*----------------------------------------------------------
cell_flags
 MX %11
 phx
 tax
 lda terrain_flags,x
 plx
 rts

*----------------------------------------------------------
* cell_step - Move (X, Y) one square in a direction.
* In:  X = x, Y = y, A = DIR_*
* Out: X, Y = the new square; carry set = it is on the
*      board. Clobbers A, rt1.
*----------------------------------------------------------
cell_step
 MX %11
 stx rt1                   ; x
 tax                       ; direction
 lda rt1
 clc
 adc dir_dx,x
 sta rt1
 tya
 clc
 adc dir_dy,x
 tay
 ldx rt1
 jmp cell_in_bounds

*----------------------------------------------------------
* destroy_cell - Destroy the terrain at (X, Y) if it can be.
* In:  X = x, Y = y (on the board)
* Out: carry set = destroyed, A = the new type
*      carry clear = indestructible, A = the type unchanged
* Preserves X, Y. Clobbers rt0, rt1, rt2.
* Only the type change; the caller raises the event.
*----------------------------------------------------------
destroy_cell
 MX %11
 jsr get_cell
 sta rt2
 jsr cell_flags
 and #TF_DESTRUCT
 beq :keep
 phx
 ldx rt2
 lda terrain_after,x
 plx
 jsr set_cell
 sec
 rts
:keep
 lda rt2
 clc
 rts

*----------------------------------------------------------
* board_fill - Set every cell to terrain type A.
* Clobbers X.
*----------------------------------------------------------
board_fill
 MX %11
 ldx #0
:loop
 sta board,x
 inx
 cpx #BOARD_CELLS
 bne :loop
 rts

*----------------------------------------------------------
* board_load - Copy a 220-byte board definition into board.
* In: rptr -> source (bank $00), row-major like board.
* Clobbers A, Y.
*----------------------------------------------------------
board_load
 MX %11
 ldy #0
:loop
 lda (rptr),y
 sta board,y
 iny
 cpy #BOARD_CELLS
 bne :loop
 rts

* The live board. Part of the game state (spec 30); a save
* game stores these 220 bytes as they are.
board ds BOARD_CELLS
