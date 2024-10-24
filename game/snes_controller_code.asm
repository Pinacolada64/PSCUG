               ; read "petscii robots" user port
               ; snes adapter - ryan sherwood 2/8/2024

                        *= $0801

basic
         .word next.line ; line ptr
         .word $0a       ; line 10
         .byte $9e       ; sys
         .text "2061"    ; 2061
         .byte $00       ; end of line
next.line
         .word $00       ; no more lines

printstring = $ab1e

cia2 = $dd00   ; cia #2 base addr
cia2.data = cia2+1 ; clock & latch
cia2.ddr = cia2+3  ; data direction
                   ; register

cia2.clock.hi = %00001000 ; bit 3
cia2.latch.hi = %00100000 ; bit 5

snes.begin.msg
         lda #<begin.msg
         ldy #>begin.msg
         jsr printstring

         lda #<button.msg
         ldy #>button.msg
         jsr printstring

snes.read
         ; set data direction
         ; on pins 3 and 5 to output
         lda #%00101000
         sta cia2+3
         sta cia2+1
         ; set latch & clock high
         lda #%00101000
         sta cia2+1
         ; set latch low
         lda #%00001000
         sta cia2+1

         ldy #16 ; read 16 data bits
snes.input.loop
         ; get data from snes pad:
         lda cia2+1
         and #%01000000 ; isolate bit 6
         sta buttons,y
         ; pulse clock line low...
         lda #%00000000
         sta cia2+1
         ; pulse clock line high...
         lda #%00001000
         sta cia2+1
         dey
         bne snes.input.loop

         ldy #16
         ldx #32 ; spacing counter
snes.show
         ; show button status line
         lda buttons,y
         sta $0400+(40*8),x
         dex
         dex ; display 2 columns earlier
         dey
         bne snes.show

         jsr $ffe1
         bne snes.read
         rts

begin.msg
         .byte 14,8,147,17,34
         .text "Attack of the PetSCII "
         .text "Robots"
         .byte 34,$0d
         .text "User port adapter - "
         .text "SNES gamepad test"
         .byte $0d,$0d
         .text "STOP exits to BASIC."
         .byte $0d,$0d,$00
; "Attack of the PetSCII Robots"
; user port adapter - SNES gamepad test
;
; STOP exits to BASIC

button.msg
; SNES controller button abbreviations:

; Rb = Right shoulder button
; Lb = Left shoulder button
; X  = X button
; A  = A button
; Rt = D-pad right
; Lf = D-pad left
; Dn = D-pad down
; Up = D-pad up
; St = Start button
; Sl = Select button
; Y  = Y button
; B  = B button

         .text "  "
         .text "- - - - RbLbX A "
         .text "RtLfDnUpStSlY B "
         .byte $0d,$00

         ; store 16 bytes of button data
buttons
         .byte 0,0,0,0,0,0,0,0
         .byte 0,0,0,0,0,0,0,0
