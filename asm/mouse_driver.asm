; kaleidoscope_mouse_driver.asm
; 2025-04-28 -- pinacolada and brobryce

firq	= $0314
vic	= $d000
sid	= $d400
potx	= sid + $19
poty	= sid + $1a

xpos	= vic + $00	; low-order x position
ypos	= vic + $01	; y position
xpos_msb= vic + $10	; bit 0 is high-order x position

firq2:	word $ffff	; current irq vector?
opotx:	byte $ff
opoty:	byte $ff
newvalue: byte $ff
oldvalue: byte $ff

install:
	lda firq + 1
	cmp #>mouse_irq
	beq installed
	php
	sei
	lda firq
	sta firq2
	lda firq  + 1
	sta firq2 + 1
	lda #<mouse_irq
	sta firq  + 1
	plp
installed:
	rts
	
mouse_irq:
	cld		; just in case...
	lda potx	; get delta values for x
	ldy opotx
	jsr movchk
	sty opotx
	
	clc
	adc xpos
	sta xpos
	txa
	adc #$00
	and #{%:00000001}
	eor xposmsb
	sta xposmsb
	
	lda poty	; get delta value for y
	ldy opoty
	jsr movchk
	sty opoty
	
			; modify y position (decrease y for increase in pot)
	eor #$ff
	adc ypos
	sta ypos
	
	jmp (firq2)	; continue with irq operation
	
movchk:
	; entry:	.y	= old value of pot register
	;		.a	= current value of pot register
	; exit:		.y	= value to use for old value
	; 		.x, .a	= delta value for position

	sty oldvalue	; save old and new values
	sta newvalue
	ldx #0
	sec		; a <= a/2
	sbc oldvalue
	and #(%:01111111}
	cmp #{%:01000000}
	bcs label_50
	lsr a		; < a/2
	beq label_80	; if <> 0
	ldy newvalue	; y <= newvalue
	rts

label_50:
	ora #{%:11000000}	; else or in high order bits
	cmp #$ff		; if <> -1
	beq label_80
	sec
	ror a
	ldx #$ff	; x <= -1
	ldy newvalue	; y <= newvalue
	rts
	
label_80:
	lda #0		; a <= 0
	rts		; return with y = old value
		