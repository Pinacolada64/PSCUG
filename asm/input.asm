{asm}
filename_length = $fb
orig $0801
        word line_link
        word 0010  ; line number
        byte $9e    ; sys token
        ascii "2070"
        byte $00
line_link:
        word $0000

	; instr - enhanced string input routine
	; commodore world issue 21, pg. 36
	; last updated: 12/8/2025

; zero-page locations:

chrout   = $ffd2	; kernal character output
getin    = $ffe4	; kernal character input
plot     = $fff0	; kernal cursor position

; variables
datco:    byte 1	; input text color (white)
cpos:     byte 0	; initial cursor position in string input area
lcol:     byte 0	; left
lftlim:   byte 0	; furthest left cursor can move in input area
strrow:   byte 0	; input display row
strcol:   byte 0	; leftmost column of input area (0-80)
strwin:   byte 0	; # viewable chars in input area
rvsflg:   byte 0	; flag for cursor blink
mode:     byte 0	; $00: c64 mode, $80: c128 mode

inbuf	= $cfeb		; buffer for string

; zero-page pointer for string address
strptr   = $0e


setup:   lda #20
         sta strrow

         lda #11
         sta strcol

         lda #17
         sta strwin

         lda #16
         sta strlen

         lda #0
         sta lftlim

         ldx #<inbuf
         ldy #>inbuf
         stx strptr
         sty strptr+1

         lda #0
         sta inbuf

         lda #$00	;use #$80 for c128 mode
         sta mode

;instr main loop

instr:   lda lftlim
         sta cpos
         lda #0
         sta lcol
getstr:  jsr drwstr
         jsr rvson
gets10:  ldx $fe
gekey:   jsr getin
         bne gk1
         ldy #10
         jsr delyms
         dex
         bne gekey
         lda rvsflg
         beq getstr
         jsr rvsoff
         jmp gets10
gk1:     pha
         jsr rvsoff
         pla
         ldx #5
gk2:     cmp edkeys,x
         beq exkey
         dex
         bpl gk2

; addition 12/8/2025:
; ignore control chars:
	cmp #' '	; $87b
	bcc getstr
; allow alphanumeric chars:
	cmp #'Z'+1	; 'Z'
	bcs getstr	; $881

; put character at cursor

putchr:
	ldy cpos
	cpy strlen
	bcs getstr
	pha
	lda (strptr),y
	bne pc1
	iny
	sta (strptr),y
	dey
pc1:
	pla
	sta (strptr),y
	jsr movrt
	jmp getstr

; execute special key routines

exkey:
	txa
	asl
	tax
	lda ekaddr,x
	sta jmpkey+1
	lda ekaddr+1,x
	sta jmpkey+2
jmpkey:
	jsr jmpkey
	jmp getstr

edkeys:
	byte 13,20,148,29,157,34
ekaddr:
	word return,delete,insert
	word cright,cleft,ekrts

; carriage return - finish up
return:
	pla ; af: pull return address,
	pla ; "specialkey" dispatch
	jsr drwstr

	lda #$0d
	jsr $ffd2
	lda #<inbuf
	ldy #>inbuf
	jsr $ab1e

	rts

;handle cursor right

cright:
	ldy cpos
	lda (strptr),y
	beq ekrts

movrt:
	iny
	sty cpos
	tya
	sec
	sbc lcol
	cmp strwin
	bcc ekrts
	inc lcol
ekrts:
	rts

;handle delete key

delete:
	ldy cpos
	cpy lftlim
	bne delchr
	lda (strptr),y
	beq ekrts
	iny

delchr:
	lda (strptr),y
	dey
	sta (strptr),y
	tax
	beq cleft
	iny
	iny
	bne delchr

;handle cursor left

cleft:
	ldy cpos
	cpy lftlim
	bne cl1
	lda lcol
	bne declco
	rts

cl1:
	dey
	sty cpos
	cpy lcol
	bcs cl2
declco:
	dec lcol
cl2:
	rts

;handle insert key

insert:   ldy #0
i1:       lda (strptr),y
         beq i2
         iny
         bne i1
i2:      cpy strlen
         bcs insrts

i3:      lda (strptr),y
         iny
         sta (strptr),y
         dey
         dey
         cpy #$ff
         beq i4
         cpy cpos
         bcs i3
i4:      iny
         lda #$20
         sta (strptr),y
insrts:  rts

;display string in input area

drwstr:  ldx strrow
         ldy strcol
drwsxy:  clc
         jsr plot
         lda datco
         jsr chrout
         jsr quomod
         ldx #0
         ldy lcol
dr1:     lda (strptr),y
         beq dr2
         iny
         byte $2c
dr2:     lda #32
         jsr chrout
         inx
         cpx strwin
         bcc dr1

;set/clear quote mode

clrquo:  lda #0
         byte $2c
quomod:  lda #1
         bit mode
         bmi q1
         sta $d4
         rts
q1:      sta $f4
         rts

;set/clear reverse on/off for cursor
;blink

rvson:   sec
         byte $24
rvsoff:  clc
         php
         lda cpos
         sec
         sbc lcol
         clc
         adc strcol
         tay
         ldx strrow
         clc
         jsr plot
         lda datco
         jsr chrout
         plp
         bcc r1
         lda #18
         jsr chrout
         byte $2c
r1:      lda #0
         sta rvsflg
         jsr quomod
         ldy cpos
         lda (strptr),y
         bne r2
         lda #32
r2:      jsr chrout
         jsr clrquo
         lda #146
         jmp chrout

;delay used for cursor blink

delyms:  pha
         lda #$7f
         sta $dd0d
         lda #$08
         sta $dd0e
         sta $dd0f
         lda #$ff
         sta $dd04
         lda #$04
         sta $dd05
de1:     lda #$11
         sta $dd0e
de2:     lda $dd05
         bne de2
         dey
         bne de2
         pla
         rts

; current string length while in routine
strlen:  byte 0
{endasm}
