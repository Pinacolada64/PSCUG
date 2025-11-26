' better mouse driver with button status
'10 rem f$="0:m1351.64.bas":open1,8,15,"s"+f$:close1:savef$,8
20 if z=0 then z=1: load"mouse.pointer",8,1
'30 if z=1 then z=2: load"m1351.64.bin",8,1
40 input"mouse port (1/2)";p$:p=val(p$)-1
50 if p<0 or p>1 then 40
60 v=13*4096:pokev+21,1:pokev+39,1:rem sprite#1 on, color
70 pokev+0,8*1+24:pokev+1,8*2+50:pokev+16,0:rem sprite x/y position on char boundary within visible area, y msb
80 poke2040,56:rem sprite data @$e00
90 sys{sym:code}+p*3:print"{clr}":rem install mouse driver
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

	clc
adc xpos         ; A = raw new low byte for X
sta xpos         ; store raw (we'll quantize it below)

; Quantize X to 8-pixel grid (clear low 3 bits)
lda xpos
and #%11111000
sta xpos         ; xpos now quantized
sta sprite_x     ; write quantized LSB to sprite shadow (and later to VIC)

; restore X/MSB handling as original code intended (X kept from movchk)
txa
adc #$00
and #%00000001
eor xposmsb
sta xposmsb
sta sprite_x+1

; Clamp combined 9-bit X to max visible (0..319). For 8-px steps max = 312.
; If xposmsb shows high bit set, combined >= 256; then low must be <= 63.
lda xposmsb
and #$01
beq no_x_highbit ; no high bit => combined < 256 => within 0..255 -> OK
lda xpos
cmp #64          ; if low >= 64 then combined >= 320 -> clamp
bcc no_x_highbit
lda #56          ; 256 + 56 = 312 (largest 8-px step <= 319)
sta xpos
sta sprite_x
no_x_highbit:

	lda poty     ; get delta value for y
	ldy opoty

move_y:
lda poty
ldy opoty
jsr movchk
sty opoty
sta dpy ; save delta (movchk returns the computed delta in A)

; Quantize Y to 8-pixel grid (clear low 3 bits)
lda ypos ; ypos = ypos - delta
and #%11111000
sec
sbc dpy
sta ypos	; now quantized
sta sprite_y
no_y_clamp:
;
; 1. READ BUTTONS (placed here as it is independent of movement)
; ---------------------------------------
	lda #$9f
	sta $dc00    ; Configure CIA to read joystick/mouse buttons
	lda $dc00
	tay
	and #$01
	sta buttonr  ; Right mouse button
	tya
	and #$10     ; 16 if not pressed, 0 if pressed
	sta buttonl  ; Left mouse button

;
; 2. CONVERT SPRITE X (PIXEL) TO CHAR X (COLUMN 0-39)
; ----------------------------------------------------
; --- CHAR X (column 0..39) ---
	lda sprite_x
	sta coord_l
	lda sprite_x+1
	sta coord_h
	jsr divide_by_8 ; coord_l := pixel_x / 8
	lda coord_l
	sec
	sbc #3 ; A := (coord_l) - 3
; subtract X offset
	bcc set_char_x_zero
; borrow => result < 0 -> clamp to 0
	cmp #40
	bcs set_char_x_39 ; A >= 40 -> clamp to 39
	sta char_x
	jmp done_char_x

set_char_x_zero:
	lda #0
	sta char_x
	jmp done_char_x

set_char_x_39:
	lda #39
	sta char_x

done_char_x:

;
; 3. CONVERT SPRITE Y (PIXEL) TO CHAR Y (ROW 0-24)
; -------------------------------------------------
; --- CHAR Y (row 0..24) ---
	lda #$00
	sta coord_h
	lda sprite_y
	sta coord_l
	jsr divide_by_8 ; coord_l := pixel_y / 8
	lda coord_l
	sec
	sbc #6 ; A := (coord_l) - 6
; subtract Y offset
	bcc set_char_y_zero ; borrow => result < 0 -> clamp to 0
	cmp #25
	bcs set_char_y_24 ; A >= 25 -> clamp to 24
	sta char_y
	jmp done_char_y

set_char_y_zero:
	lda #0
	sta char_y
	jmp done_char_y

set_char_y_24:
	lda #24
	sta char_y

done_char_y:
; --------------------------------------- NEW CODE BLOCK ENDS HERE

	ldx ciasave  ; restore keyboard
	sta cia

exit4:
	jmp (iirq2)  ; continue w/ irq operation

; ... (movchk, setpot, DIVIDE_BY_8 routines, and data variables follow) ...
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
; ... (unchanged) ...
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
dpy:
; delta position y
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

coord_l:
	byte $00
coord_h:
	byte $00
{endasm}
