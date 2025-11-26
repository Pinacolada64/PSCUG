' better mouse driver with button status
'10 rem f$="0:m1351.64.bas":open1,8,15,"s"+f$:close1:savef$,8
20 if z=0 then z=1: load"mouse.pointer",8,1
'30 if z=1 then z=2: load"m1351.64.bin",8,1
40 input"mouse port (1/2)";p$: p=val(p$)-1
50 if p<0 or p>1 then 40
60 v=13*4096:pokev+21,1:pokev+39,1:    rem sprite#1 on, color
70 pokev+0,100:pokev+1,100:pokev+16,0: rem sprite position
80 poke2040,56:                        rem sprite data @$e00
90 sys{sym:code}+p*3:print"{clr}":     rem install mouse driver
100 print"{home}lmb:    {left:4}"peek({sym:buttonl}),"rmb:    {left:4}"peek({sym:buttonr})
110 print"spr.x:    {left:4}"peek({sym:sprite_x}+1)*256+peek({sym:sprite_x}),"spr.y:    {left:4}"peek({sym:sprite_y})
120 print"char.x:    {left:4}"peek({sym:char_x}),"char.y:    {left:4}"peek({sym:char_y})
130 goto 100

{asm}
;	1351 proportional mouse driver for the c64
;
;	commodore business machines, inc.   27oct86
;		by hedley davis and fred bowen

iirq    = $0314
vic     = $d000
sid     = $d400
cia     = $dc00
cia_ddr = $dc02
potx    = sid+$19
poty    = sid+$1a

xpos    = vic+$00    ;x position (lsb)
ypos    = vic+$01    ;y position
xposmsb = vic+$10    ;x position (msb)
code:
	jmp install_1  ;install mouse in port 1
	jmp install_2  ;install mouse in port 2
	jmp remove     ;remove mouse wedge


install_1:
	ldx #0         ; port 1 mouse
	byte $2c

install_2:
	ldx #2         ; port 2 mouse

	lda iirq+1     ; install irq wedge
	cmp #>mirq_1
	beq exit       ; ...branch if already installed!
	php
	sei

	lda iirq       ; save current irq indirect for our exit
	sta iirq2
	lda iirq+1
	sta iirq2+1

	lda port,x     ; point irq indirect to mouse driver
	sta iirq
	lda port+1,x
	sta iirq+1
	plp
exit:
	rts

remove:
	lda iirq+1     ; remove irq wedge
	cmp #>mirq_1
	bne exit2      ; ...branch if already removed!
	php
	sei
	lda iirq2      ;restore saved indirect
	sta iirq
	lda iirq2+1
	sta iirq+1
	plp
exit2:
	rts

mirq_2:
	lda #$80     ; port2 mouse scan
	byte $2c

mirq_1:
	lda #$40     ; port1 mouse scan

	jsr setpot   ; configure cia per .a
move_x:
	lda potx     ; get delta values for x
	ldy opotx
	jsr movchk
	sty opotx

	clc          ; modify low order x position
	adc xpos
	sta xpos
	; Stash LSB in sprite_x *AFTER* VIC-II update
	sta sprite_x

	txa
	adc #$00
	and #%00000001
	eor xposmsb
	sta xposmsb
	; Stash MSB in sprite_x+1
	sta sprite_x+1

no_update_x:

	lda poty     ; get delta value for y
	ldy opoty

move_y:
	jsr movchk
	sty opoty

	sec          ; modify y position (decrease y for increase in pot)
	eor #$ff
	adc ypos

	; *** UPDATE SPRITE Y-POSITION (CRITICAL STEP) ***
	sta ypos     ; Update VIC-II Y register
	sta sprite_y ; Update shadow Y register

; --------------------------------------- NEW CODE BLOCK STARTS HERE
;
; 1. READ BUTTONS (placed here as it is independent of movement)
; ---------------------------------------
	lda #$9f
	sta $dc00    ; Configure CIA to read joystick/mouse buttons
	lda $dc00
	tay
	and #$01
	sta buttonr  ; Right mouse button: 1 if not pressed, 0 if pressed
	tya
	and #$10     ; 16 if not pressed, 0 if pressed
	sta buttonl  ; Left mouse button

;
; 2. CONVERT SPRITE X (PIXEL) TO CHAR X (COLUMN 0-39)
; ----------------------------------------------------
	lda sprite_x      ; Low Byte of X-coordinate
	sta COORD_L
	lda sprite_x+1    ; High Byte (MSB)
	sta COORD_H
	jsr divide_by_8
	lda coord_l       ; A now holds the X value / 8 (approx 0-39)

; Subtract the X-offset (#3) to normalize pixel 24 to character column 0
	sec             ; Set Carry for subtraction
	sbc #3          ; A = (A / 8) - 3

	; Clamp the resulting character column to 0-39
	cmp #40         ; Compare with 40 (one past the right)
	bpl do_clamp_x
	cmp #$00        ; Compare with 0 (check for underflow)
	bmi do_clamp_x

	sta char_x      ; The character X-coordinate is valid (0-39).
	jmp skip_clamp_x

do_clamp_x:
	lda #39         ; Clamp to the last column
	sta char_x

skip_clamp_x:

;
; 3. CONVERT SPRITE Y (PIXEL) TO CHAR Y (ROW 0-24)
; -------------------------------------------------
    lda #$00
    sta coord_h
    lda sprite_y    ; Load the current, updated sprite Y position
    sta coord_l
    jsr divide_by_8 ; Result in coord_l (approx 0-31)
    lda coord_l

; Subtract the Y-offset (#6) to normalize pixel 50 to character row 0
	sec             ; Set Carry for subtraction
	sbc #6          ; A = (A / 8) - 6

	; Clamp the resulting character row to 0-24
	cmp #25         ; Compare with 25 (one row past the bottom)
	bpl do_clamp_y
	cmp #$00        ; Compare with 0 (check for underflow)
	bmi do_clamp_y

	sta char_y      ; The character Y-coordinate is valid (0-24).
	jmp skip_clamp_y

do_clamp_y:
	lda #24         ; Clamp to the last row
	sta char_y

skip_clamp_y:
; --------------------------------------- NEW CODE BLOCK ENDS HERE

	ldx ciasave  ; restore keyboard
	sta cia

exit4:
	jmp (iirq2)  ; continue w/ irq operation

movchk:
	sty oldvalue
	sta newvalue
	ldx #0

	sec
	sbc oldvalue
	and #%01111111
	cmp #%01000000
	bcs movchk2
	lsr
	beq exit3
	ldy newvalue
	rts

movchk2:
	ora #%11000000
	cmp #$ff
	beq exit3
	sec
	ror
	ldx #$ff
	ldy newvalue
	rts

exit3:
	lda #0
	rts


; setpot (CIA port configuration and delay routine)
setpot:
	ldx cia
	stx ciasave

	sta cia

	ldx #4
	ldy #$c7
wait:
	dey
	bne wait
	dex
	bne wait
	rts

; ------------------------------------- DIVIDE_BY_8 ROUTINE -------------------------------------
; Routine: DIVIDE_BY_8
; Divides the 16-bit value in COORD_L/COORD_H by 8.
; The result remains in COORD_L/COORD_H.

DIVIDE_BY_8:
	; *** Shift #1 (Divide by 2) ***
	lsr coord_h
	ror coord_l

	; *** Shift #2 (Divide by 4) ***
	lsr coord_h
	ror coord_l

	; *** Shift #3 (Divide by 8) ***
	lsr coord_h
	ror coord_l

	rts
	; ------------------------------------------------------------------------------------------------

; ------------------------------------- DATA VARIABLES -------------------------------------
iirq2:
    word $ffff
opotx:
    byte $ff
opoty:
    byte $ff
newvalue:
    byte $ff
oldvalue:
    byte $ff
ciasave:
    byte $ff

port:
    word mirq_1
    word mirq_2

; mouse buttons:
buttonl:
    byte $00
buttonr:
    byte $00

; copies of VIC-II sprite X/Y registers:
sprite_x:
    word $0000
sprite_y:
    byte $00

; which character the mouse pointer is on
char_x:
    byte $00
char_y:
    byte $00

; used by divide_by_8 routine:
coord_l:
    byte $00
coord_h:
    byte $00
{endasm}
