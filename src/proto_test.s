*----------------------------------------------------------
* proto_test.s - network-free validation of src/proto.s (spec N2).
*
* Poked into MAME and run from $2000 (like nettest.s) but touches
* NO network: it only builds frames with the proto.s encoder and
* runs the stream parser over bytes poked into $5000. The host
* compares the built frames against server/fixtures/*.bin and the
* parsed fields against the manifest.
*
* Encoder output (built frames), lengths at $4080+i:
*   $4000 hello_human  $4020 welcome  $4040 ping  $4060 pong
* Parser (stream at $5000, fed in two chunks to test partial staging):
*   $4090  first proto_rx_next after 20 bytes: 0 = correctly waited
*   $4091  number of complete frames parsed
*   $40A0  per frame i: type, seq_lo, seq_hi, len_lo, len_hi (5 bytes)
*   $4100  $A5 done marker (written last)
*----------------------------------------------------------
            org   $2000
            mx    %11

DSTP = $F0                    ; direct-page copy pointers (test-local)
SFP  = $F2
STREAM  = $5000               ; host pokes the fixture stream here
STREAM2 = $5014               ; STREAM + 20 (second chunk)

start       sei
            sec
            xce
            cld
            ldx   #$FF
            txs
            lda   #0
            pha
            plb

* ---------------- ENCODER: build the four fixtures ----------------

* hello_human: C_HELLO seq=1; rules=1, build=$00010203, cap=$0003,
* kind=0(human), name "cshepherd".
            lda   #1
            sta   proto_seq+0
            stz   proto_seq+1
            lda   #$01
            jsr   proto_begin
            lda   #1                       ; u16 rules_version
            ldx   #0
            jsr   proto_u16
            lda   #$03                       ; u32 client_build $00010203
            sta   proto_val32+0
            lda   #$02
            sta   proto_val32+1
            lda   #$01
            sta   proto_val32+2
            lda   #$00
            sta   proto_val32+3
            jsr   proto_u32
            lda   #$05                       ; u16 capability $0005 (ENHANCED|RECONNECT)
            ldx   #$00
            jsr   proto_u16
            lda   #0                          ; u8 client_kind human
            jsr   proto_emit
            lda   #<name_csh
            sta   PRP
            lda   #>name_csh
            sta   PRP+1
            lda   #9
            jsr   proto_name
            jsr   proto_finish
            lda   #<$4000
            sta   DSTP
            lda   #>$4000
            sta   DSTP+1
            jsr   save_tx
            lda   proto_total+0
            sta   $4080+0

* welcome: S_WELCOME seq=1; rules=1, session=$DEADBEEF, flags=$0001,
* name "CombatChess".
            lda   #1
            sta   proto_seq+0
            stz   proto_seq+1
            lda   #$02
            jsr   proto_begin
            lda   #1
            ldx   #0
            jsr   proto_u16
            lda   #$EF                        ; u32 session $DEADBEEF
            sta   proto_val32+0
            lda   #$BE
            sta   proto_val32+1
            lda   #$AD
            sta   proto_val32+2
            lda   #$DE
            sta   proto_val32+3
            jsr   proto_u32
            lda   #$01                         ; u16 server_flags $0001
            ldx   #$00
            jsr   proto_u16
            lda   #<name_cc
            sta   PRP
            lda   #>name_cc
            sta   PRP+1
            lda   #11
            jsr   proto_name
            jsr   proto_finish
            lda   #<$4020
            sta   DSTP
            lda   #>$4020
            sta   DSTP+1
            jsr   save_tx
            lda   proto_total+0
            sta   $4080+1

* ping: C_PING seq=$1234; nonce=$11223344.
            lda   #$34
            sta   proto_seq+0
            lda   #$12
            sta   proto_seq+1
            lda   #$20
            jsr   proto_begin
            lda   #$44
            sta   proto_val32+0
            lda   #$33
            sta   proto_val32+1
            lda   #$22
            sta   proto_val32+2
            lda   #$11
            sta   proto_val32+3
            jsr   proto_u32
            jsr   proto_finish
            lda   #<$4040
            sta   DSTP
            lda   #>$4040
            sta   DSTP+1
            jsr   save_tx
            lda   proto_total+0
            sta   $4080+2

* pong: S_PONG seq=$1234; nonce=$11223344.
            lda   #$34
            sta   proto_seq+0
            lda   #$12
            sta   proto_seq+1
            lda   #$21
            jsr   proto_begin
            lda   #$44
            sta   proto_val32+0
            lda   #$33
            sta   proto_val32+1
            lda   #$22
            sta   proto_val32+2
            lda   #$11
            sta   proto_val32+3
            jsr   proto_u32
            jsr   proto_finish
            lda   #<$4060
            sta   DSTP
            lda   #>$4060
            sta   DSTP+1
            jsr   save_tx
            lda   proto_total+0
            sta   $4080+3

* ---------------- PARSER: feed the stream in two chunks ----------------
            jsr   proto_rx_reset
            lda   #<$5000                    ; chunk 1: first 20 bytes (< one frame)
            sta   PRP
            lda   #>STREAM
            sta   PRP+1
            lda   #20
            sta   proto_cnt+0
            stz   proto_cnt+1
            jsr   proto_rx_add
            jsr   proto_rx_next               ; expect carry clear (incomplete)
            lda   #0
            bcc   :waited
            lda   #$FF
:waited     sta   $4090

            lda   #<STREAM2                ; chunk 2: the remaining 59 bytes
            sta   PRP
            lda   #>STREAM2
            sta   PRP+1
            lda   #59
            sta   proto_cnt+0
            stz   proto_cnt+1
            jsr   proto_rx_add

            ldx   #0
:ploop      jsr   proto_rx_next
            bcc   :pdone
            jsr   store_frame
            inx
            cpx   #8
            bne   :ploop
:pdone      stx   $4091

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

* store_frame: write parsed fields for frame X to $40A0 + X*5.
store_frame
            txa
            sta   temp
            asl
            asl
            clc
            adc   temp                       ; X*5
            clc
            adc   #<$40A0
            sta   SFP
            lda   #>$40A0
            adc   #0
            sta   SFP+1
            ldy   #0
            lda   proto_msg_type
            sta   (SFP),y
            iny
            lda   proto_msg_seq+0
            sta   (SFP),y
            iny
            lda   proto_msg_seq+1
            sta   (SFP),y
            iny
            lda   proto_msg_len+0
            sta   (SFP),y
            iny
            lda   proto_msg_len+1
            sta   (SFP),y
            rts

st_cnt       dfb   0
temp         dfb   0
name_csh     asc   'cshepherd'
name_cc      asc   'CombatChess'

            put   proto
