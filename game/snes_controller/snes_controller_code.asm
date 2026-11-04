        ; read "petscii robots" user port
        ; snes adapter - ryan sherwood 2/8/2024
        ; converted to c64list 4.06 format 11/4/2026

        ; to use in VICE with a USB gamepad attached:
        ; x64sc -userportdevice 18 -controlport3device 1 -extrajoydev1 4

        ; 4 is the first host gamepad. Its D-pad or stick drives the directions,
        ; and its buttons go to A, B, X, Y, the shoulder buttons, Select and Start
        ; in that order. You can remap them under Settings → Input devices → Joystick.

        ; to use in VICE with the keyboard (no gamepad needed):
        ; x64sc -addconfig snes_joypad_keyboard_keys.cfg -autostart snes_controller_code.prg

        ; snes_joypad_keyboard_keys.cfg (in this folder) sets up everything:
        ; the userport adapter, no device in joystick ports 1 and 2 (so they
        ; can't take the keypad keys first), Keyset 1 (Keyset A in the menu)
        ; in the adapter's port, and all 12 SNES buttons on the keypad.
        ; Num Lock must be on:
        ;
        ;    7 Lb   8 Up   9 Rb          + Y
        ;    4 Lf   5 --   6 Rt
        ;    1 Sl   2 Dn   3 St
        ;    0 A           . B      Enter X
        ;
        ; The diagonals are cleared, so 7, 9, 1 and 3 work as buttons.
        ; Settings > Save settings would copy all of this into vicerc.

        orig $0801
{alpha:alt}
basic:
         word next_line ; line ptr
         word $0a       ; line 10
         byte $9e       ; sys
         ascii "2061"   ; 2061
         byte $00       ; end of line
next_line:
         word $00       ; no more lines

chrout = $ffd2   ; kernal: print the character in .a
str_ptr = $fb    ; 2 zero page bytes free for user programs

cia2 = $dd00   ; cia #2 base addr
cia2_data = cia2+1 ; clock & latch
cia2_ddr = cia2+3  ; data direction
                   ; register

cia2_clock_hi = {%:00001000} ; bit 3
cia2_latch_hi = {%:00100000} ; bit 5

snes_begin_msg:
         lda #<begin_msg
         ldy #>begin_msg
         jsr printstring

         lda #<button_msg
         ldy #>button_msg
         jsr printstring

snes_read:
         ; set data direction
         ; on pins 3 and 5 to output
         lda #{%:00101000}
         sta cia2+3
         sta cia2+1
         ; set latch & clock high
         lda #{%:00101000}
         sta cia2+1
         ; set latch low
         lda #{%:00001000}
         sta cia2+1

         ldy #16 ; read 16 data bits
snes_input_loop:
         ; get data from snes pad:
         lda cia2+1
         and #{%:01000000} ; isolate bit 6
         sta buttons-1,y ; y=16..1 -> buttons+15..+0
         ; pulse clock line low...
         lda #{%:00000000}
         sta cia2+1
         ; pulse clock line high...
         lda #{%:00001000}
         sta cia2+1
         dey
         bne snes_input_loop

         ; show the 12 buttons (bits 1-12, at buttons+15..+4);
         ; skip bits 13-16, which aren't buttons
         ldy #16
         ldx #24 ; spacing counter: B is at column 24
snes_show:
         ; show button status line
         lda buttons-1,y
         beq snes_pressed ; data line low = pressed
         lda #$20         ; screen code: space
         bne snes_put     ; (always)
snes_pressed:
         lda #$2a         ; screen code: *
snes_put:
         sta $0400+(40*8),x
         dex
         dex ; display 2 columns earlier
         dey
         cpy #4 ; stop after Rb (bit 12)
         bne snes_show

         jsr $ffe1
         bne snes_read
         rts

printstring:
         ; print the $00-terminated string at .a (lo) / .y (hi)
         ; (BASIC's $ab1e stops at a quote, which cut off begin_msg)
         sta str_ptr
         sty str_ptr+1
         ldy #0
printstring_loop:
         lda (str_ptr),y
         beq printstring_done
         jsr chrout
         iny
         bne printstring_loop ; strings up to 255 bytes
printstring_done:
         rts

begin_msg:
         byte 14,8,147,17,34
         ascii "Attack of the PetSCII "
         ascii "Robots"
         byte 34,$0d
         ascii "User port adapter - "
         ascii "SNES gamepad test"
         byte $0d,$0d
         ascii "STOP exits to BASIC."
         byte $0d,$0d,$0d,$00 ; labels on row 7, just above the readout on row 8
; "Attack of the PetSCII Robots"
; user port adapter - SNES gamepad test
;
; STOP exits to BASIC

button_msg:
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

         ascii "  "
         ascii "RbLbX A "
         ascii "RtLfDnUpStSlY B "
         byte $0d       ; cursor to row 8: the readout, poked in the loop

         ; legend, from row 10 down (lines under 40 chars, so no wrap)
         byte $0d,$0d
         ascii "Up D-pad up       Dn D-pad down"
         byte $0d
         ascii "Lf D-pad left     Rt D-pad right"
         byte $0d
         ascii "A  A button       B  B button"
         byte $0d
         ascii "X  X button       Y  Y button"
         byte $0d
         ascii "Lb Left shoulder  Rb Right shoulder"
         byte $0d
         ascii "Sl Select         St Start"
         byte $0d
         byte $0d
         ascii "* = pressed"
         byte $0d,$00

         ; store 16 bytes of button data
buttons:
         byte 0,0,0,0,0,0,0,0
         byte 0,0,0,0,0,0,0,0
