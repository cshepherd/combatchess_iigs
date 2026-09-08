*----------------------------------------------------------
* TITLE - Combat Chess title screen (scaffold build).
*
* SYS file loaded at $2000 by CC.SYSTEM. Runs the one-time
* toolbox start-up, shows a placeholder title, and chains to
* GAME through the launcher jump table on any key.
*
* Later this part also owns the options screen (spec
* section 29); chosen options go in page $11 (shared.s) so
* GAME can read them after chaining.
*----------------------------------------------------------

  ORG $2000
  MX %11

  put shared

  lda tb_inited
  bne :ready
  jsr toolbox_init
  inc tb_inited
:ready
  clc
  xce
  rep $30
  MX %00
  jsr shr_init

  lda #15                   ; white on black
  ldx #0
  jsr set_colors
  lda #s_title
  sta str_ptr
  ldx #118
  ldy #70
  jsr draw_cstr

  lda #14                   ; light grey
  ldx #0
  jsr set_colors
  lda #s_subtitle
  sta str_ptr
  ldx #40
  ldy #100
  jsr draw_cstr

  lda #9                    ; yellow
  ldx #0
  jsr set_colors
  lda #s_pressany
  sta str_ptr
  ldx #124
  ldy #150
  jsr draw_cstr

  jsr wait_key
  and #$00DF                ; fold to upper case
  cmp #'T'
  beq :run_tests

  sec
  xce
  MX %11
  jmp LAUNCH_GAME

* T runs the rules self-tests (src/test.s). Development
* hook; it can go once the rules are complete.
:run_tests
  MX %00
  sec
  xce
  MX %11
  jmp LAUNCH_TEST

s_title    asc 'COMBAT CHESS'
           dfb 0
s_subtitle asc 'APPLE IIGS PORT  -  SCAFFOLD BUILD'
           dfb 0
s_pressany asc 'PRESS ANY KEY  (T: RULES SELF-TESTS)'
           dfb 0

  put common
