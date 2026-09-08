*----------------------------------------------------------
* GAME - Combat Chess game part (scaffold build).
*
* SYS file loaded at $2000 by CC.SYSTEM after TITLE. This is
* where the rules engine (spec section 32) and the debug
* board (milestone 3) will live. For now it proves the chain
* works: draw a placeholder, wait for a key, return to TITLE.
*----------------------------------------------------------

  ORG $2000
  MX %11

  put shared

  lda tb_inited
  bne :ready
  jsr toolbox_init          ; only if GAME was launched directly
  inc tb_inited
:ready
  clc
  xce
  rep $30
  MX %00
  jsr shr_init

  lda #10                   ; green on black
  ldx #0
  jsr set_colors
  lda #s_heading
  sta str_ptr
  ldx #104
  ldy #70
  jsr draw_cstr

  lda #14
  ldx #0
  jsr set_colors
  lda #s_body
  sta str_ptr
  ldx #46
  ldy #100
  jsr draw_cstr

  lda #9
  ldx #0
  jsr set_colors
  lda #s_return
  sta str_ptr
  ldx #64
  ldy #150
  jsr draw_cstr

  jsr wait_key

  sec
  xce
  MX %11
  jmp LAUNCH_TITLE

s_heading asc 'GAME PART - STUB'
          dfb 0
s_body    asc 'MILESTONE 1 RULES ENGINE GOES HERE'
          dfb 0
s_return  asc 'PRESS ANY KEY TO RETURN TO TITLE'
          dfb 0

* Rules engine (milestone 1). Data tables, the board and the
* RNG first; movement, fire and turn logic will follow as
* further includes.
  put tables
  put board
  put line
  put units
  put rng

  put common
