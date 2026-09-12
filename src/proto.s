*----------------------------------------------------------
* proto.s - Combat Chess network protocol framing (spec N2).
*
* The wire format is defined authoritatively in server/protocol.py;
* this is the 65816 half. It sits above net.s (send/receive bytes)
* and below the game: a frame ENCODER that builds a header+payload
* in proto_tx, and a stream PARSER (spec 34) that reassembles
* frames from arbitrarily-chunked RX bytes in proto_rx.
*
* No game logic here (N2). Runs native or emulation, 8-bit A/X/Y,
* DBR $00. All protocol integers are little-endian.
*
* Frame header (8 bytes): 'C' 'C' version type len(u16) seq(u16).
*----------------------------------------------------------

            mx    %11

PROTO_MAGIC0  = $43           ; 'C'
PROTO_MAGIC1  = $43           ; 'C'
PROTO_VERSION = 1
PROTO_HDR     = 8
PROTO_MAXPAY  = 1024

* Direct-page write/read pointers (alias shared.s rptr/rptr2; live
* only inside one proto routine).
PWP  = $E4                    ; encoder write pointer
PRP  = $E6                    ; parser scratch pointer

*----------------------------------------------------------
* ENCODER. proto_begin starts a frame; proto_emit/u16/u32/bytes/
* name append payload; proto_finish patches the length and returns
* the total frame size. The frame lives in proto_tx, ready for
* net_send(proto_tx, total).
*----------------------------------------------------------

* proto_begin: A = message type, proto_seq (2 bytes) = sequence.
* Lays down the header with a zero length placeholder and points
* PWP at the first payload byte. Clobbers A/Y.
proto_begin
            sta   proto_type
            ldy   #0
            lda   #PROTO_MAGIC0
            sta   proto_tx+0
            lda   #PROTO_MAGIC1
            sta   proto_tx+1
            lda   #PROTO_VERSION
            sta   proto_tx+2
            lda   proto_type
            sta   proto_tx+3
            lda   #0                    ; length placeholder (patched by finish)
            sta   proto_tx+4
            sta   proto_tx+5
            lda   proto_seq+0
            sta   proto_tx+6
            lda   proto_seq+1
            sta   proto_tx+7
            lda   #<proto_tx             ; PWP -> first payload byte (proto_tx+8)
            clc
            adc   #PROTO_HDR
            sta   PWP
            lda   #>proto_tx
            adc   #0
            sta   PWP+1
            rts

* proto_emit: append A to the payload. Clobbers nothing but PWP.
proto_emit
            sta   (PWP)
            inc   PWP
            bne   :done
            inc   PWP+1
:done       rts

* proto_u16: append A (low) then X (high), little-endian.
proto_u16
            jsr   proto_emit
            txa
            jsr   proto_emit
            rts

* proto_u32: append the 4 bytes at proto_val32, little-endian.
proto_u32
            ldx   #0
:l          lda   proto_val32,x
            jsr   proto_emit
            inx
            cpx   #4
            bne   :l
            rts

* proto_bytes: append Y bytes from the pointer in PRP.
proto_bytes
            cpy   #0
            beq   :done
            phy
            ldy   #0
:l          lda   (PRP),y
            jsr   proto_emit
            iny
            cpy   proto_cnt
            bne   :l
            ply
:done       rts

* proto_name: append a length-prefixed name -- A = length, PRP =
* pointer to the ASCII bytes. Emits the count then the bytes.
proto_name
            sta   proto_cnt
            jsr   proto_emit             ; length byte
            ldy   proto_cnt
            jsr   proto_bytes
            rts

* proto_finish: patch the header length = (PWP - payload start) and
* return the total frame length in proto_total (2 bytes) with the
* low byte also in A. Clobbers A.
proto_finish
            sec                          ; payload len = PWP - proto_tx - PROTO_HDR
            lda   PWP
            sbc   #<proto_tx
            sta   proto_len+0
            lda   PWP+1
            sbc   #>proto_tx
            sta   proto_len+1
            sec
            lda   proto_len+0
            sbc   #PROTO_HDR
            sta   proto_len+0
            sta   proto_tx+4
            lda   proto_len+1
            sbc   #0
            sta   proto_len+1
            sta   proto_tx+5
            clc                          ; total = header + payload len
            lda   proto_len+0
            adc   #PROTO_HDR
            sta   proto_total+0
            lda   proto_len+1
            adc   #0
            sta   proto_total+1
            lda   proto_total+0
            rts

*----------------------------------------------------------
* PARSER (spec 34). Bytes arrive in arbitrary chunks; stage them in
* proto_rx and pull out whole frames one at a time.
*----------------------------------------------------------

* proto_rx_reset: empty the staging buffer.
proto_rx_reset
            stz   proto_rx_len+0
            stz   proto_rx_len+1
            rts

* proto_rx_add: append proto_cnt (2 bytes) bytes from PRP into the
* staging buffer. The caller uses this with net_recv output. Assumes
* the staging buffer (proto_rx, PROTO_RXCAP) does not overflow -- the
* parser drains whole frames between adds. Clobbers A/X/Y.
proto_rx_add
            lda   proto_cnt+0            ; nothing to add?
            ora   proto_cnt+1
            beq   :done
* dest = proto_rx + proto_rx_len
            clc
            lda   #<proto_rx
            adc   proto_rx_len+0
            sta   PWP
            lda   #>proto_rx
            adc   proto_rx_len+1
            sta   PWP+1
:l          lda   (PRP)                  ; copy one source byte
            sta   (PWP)
            inc   PRP                     ; advance source (16-bit)
            bne   :ps
            inc   PRP+1
:ps         inc   PWP                     ; advance dest (16-bit)
            bne   :nx
            inc   PWP+1
:nx         inc   proto_rx_len+0         ; rx_len += 1
            bne   :dc
            inc   proto_rx_len+1
:dc         lda   proto_cnt+0            ; cnt -= 1 (16-bit)
            bne   :lo
            dec   proto_cnt+1
:lo         dec   proto_cnt+0
            lda   proto_cnt+0
            ora   proto_cnt+1
            bne   :l
:done       rts

* proto_rx_next: if a complete frame is staged, extract it -- fills
* proto_msg_type / proto_msg_seq / proto_msg_len (2) and copies the
* payload to proto_payload -- removes it from staging, and returns
* carry set. If no full frame yet, carry clear. Carry set with
* proto_msg_type = 0 and proto_err nonzero on a protocol error (bad
* magic or oversize length); the caller should disconnect.
* Clobbers A/X/Y and the proto scratch words.
proto_rx_next
            stz   proto_err
* need at least a header
            lda   proto_rx_len+1
            bne   :haveh                 ; len >= 256 -> surely >= 8
            lda   proto_rx_len+0
            cmp   #PROTO_HDR
            bcs   :haveh
            clc                          ; fewer than 8 bytes: wait
            rts
:haveh      lda   proto_rx+0             ; verify magic 'C' 'C'
            cmp   #PROTO_MAGIC0
            beq   :m0
            jmp   :bad
:m0         lda   proto_rx+1
            cmp   #PROTO_MAGIC1
            beq   :m1
            jmp   :bad
:m1         lda   proto_rx+4             ; payload length (u16 LE)
            sta   proto_msg_len+0
            lda   proto_rx+5
            sta   proto_msg_len+1
* length > 1024 ?  (hi > 4, or hi==4 and lo>0)
            lda   proto_msg_len+1
            cmp   #>PROTO_MAXPAY
            bcc   :lenok
            beq   :lenhi4
            jmp   :bad
:lenhi4     lda   proto_msg_len+0
            beq   :lenok
            jmp   :bad
:lenok
* is the whole frame present?  need = 8 + len
            clc
            lda   proto_msg_len+0
            adc   #PROTO_HDR
            sta   proto_need+0
            lda   proto_msg_len+1
            adc   #0
            sta   proto_need+1
* if rx_len < need -> wait
            lda   proto_rx_len+1
            cmp   proto_need+1
            bcc   :wait
            bne   :full
            lda   proto_rx_len+0
            cmp   proto_need+0
            bcs   :full
:wait       clc
            rts
:full
            lda   proto_rx+3             ; message type + seq
            sta   proto_msg_type
            lda   proto_rx+6
            sta   proto_msg_seq+0
            lda   proto_rx+7
            sta   proto_msg_seq+1
* copy payload (proto_msg_len bytes from proto_rx+8) into proto_payload
            lda   #<proto_rx             ; PRP -> proto_rx + 8
            clc
            adc   #PROTO_HDR
            sta   PRP
            lda   #>proto_rx
            adc   #0
            sta   PRP+1
            lda   #<proto_payload
            sta   PWP
            lda   #>proto_payload
            sta   PWP+1
            lda   proto_msg_len+0
            sta   proto_cnt+0
            lda   proto_msg_len+1
            sta   proto_cnt+1
            ora   proto_cnt+0
            beq   :copied
:cp         lda   (PRP)
            sta   (PWP)
            inc   PRP
            bne   :p1
            inc   PRP+1
:p1         inc   PWP
            bne   :p2
            inc   PWP+1
:p2         lda   proto_cnt+0
            bne   :p3
            dec   proto_cnt+1
:p3         dec   proto_cnt+0
            lda   proto_cnt+0
            ora   proto_cnt+1
            bne   :cp
:copied
* remove the frame: shift the remaining staged bytes down by `need`
            jsr   proto_rx_consume
            sec                          ; frame ready
            rts
:bad        lda   #1
            sta   proto_err
            stz   proto_msg_type
            jsr   proto_rx_reset          ; drop the poisoned stream
            sec
            rts

* proto_rx_consume: drop the first proto_need bytes from the staging
* buffer, shifting the rest to the front and reducing proto_rx_len.
* Clobbers A/X/Y and pointers.
proto_rx_consume
            sec                          ; remain = rx_len - need
            lda   proto_rx_len+0
            sbc   proto_need+0
            sta   proto_rx_len+0
            lda   proto_rx_len+1
            sbc   proto_need+1
            sta   proto_rx_len+1
            lda   proto_rx_len+0          ; nothing left?
            ora   proto_rx_len+1
            beq   :done
* src = proto_rx + need ; dst = proto_rx ; count = rx_len
            clc
            lda   #<proto_rx
            adc   proto_need+0
            sta   PRP
            lda   #>proto_rx
            adc   proto_need+1
            sta   PRP+1
            lda   #<proto_rx
            sta   PWP
            lda   #>proto_rx
            sta   PWP+1
            lda   proto_rx_len+0
            sta   proto_cnt+0
            lda   proto_rx_len+1
            sta   proto_cnt+1
:l          lda   (PRP)
            sta   (PWP)
            inc   PRP
            bne   :s1
            inc   PRP+1
:s1         inc   PWP
            bne   :s2
            inc   PWP+1
:s2         lda   proto_cnt+0
            bne   :s3
            dec   proto_cnt+1
:s3         dec   proto_cnt+0
            lda   proto_cnt+0
            ora   proto_cnt+1
            bne   :l
:done       rts

*----------------------------------------------------------
* State + buffers (bank $00, part-local).
*----------------------------------------------------------
PROTO_RXCAP  = 2048           ; staging capacity (>= one max frame + slack)

proto_type   dfb   0
proto_seq    dfb   0,0                ; sequence for the frame being built
proto_len    dfb   0,0                ; payload length (encoder)
proto_total  dfb   0,0                ; total frame length (encoder result)
proto_cnt    dfb   0,0                ; byte-count scratch (16-bit)
proto_val32  dfb   0,0,0,0            ; u32 argument for proto_u32

proto_msg_type dfb 0                  ; parsed frame: type
proto_msg_seq  dfb 0,0                ;   sequence
proto_msg_len  dfb 0,0                ;   payload length
proto_need     dfb 0,0                ;   full frame size (hdr+len)
proto_err      dfb 0                  ; nonzero after a protocol error

proto_rx_len dfb   0,0                ; bytes currently staged
* The big buffers live in free bank-0 RAM OUTSIDE the part so GAME (which
* also carries the whole engine) fits its $2000-$BEFF window: $0C00-$0FFF
* is the launcher's ProDOS I/O buffer, free once GAME runs, and $1214-$1BFF
* is the gap between the heartbeat record and the sound direct page. They
* are bank 0, so the direct-page pointers still reach them.
proto_rx     =     $0C00              ; RX staging (640 bytes, $0C00-$0E7F)
proto_payload =    $1214              ; last parsed payload (768, $1214-$1513)
proto_tx     ds    PROTO_HDR+256      ; TX build buffer (we only send small frames)
