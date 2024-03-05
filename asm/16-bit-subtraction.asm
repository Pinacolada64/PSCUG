; test subtracing and outputting 16-bit numbers
; with verification that math is correct

; 2049
orig $0801

; basic sys line
; 2049-2050 line link:
	word end_of_line
; 2051-2052 line number:
	word 10
;  2053     'sys' token:
	byte $9e
; 2054-2057 address:
	ascii "2061"
end_of_line:
; 2058      zero byte
	byte $00
; 2059-2060 end of program:
	word $0000

out_string	= $ab1e ; enter: >.a, <.y: print string
out_16_bit_num	= $bdcd ; enter: >.a, <.x: output number
chrout		= $ffd2	; enter: .a: char to output
check_stop_key	= $ffe1	; enter: n/a. exit: .z=1 if stop hit

; print "1024":
	lda #>$0400
	ldx #<$0400
	jsr out_16_bit_num ; 256*4=1024
	lda #$0d
	jsr chrout

; 1000 - 100:
	lda starting_value+1
	ldx starting_value
	jsr out_16_bit_num
	lda #'-'
	jsr chrout
	lda subtract_value+1
	ldx subtract_value
	jsr out_16_bit_num
	lda #'='
	jsr chrout
; blank out answer in ram for illustrative purposes:
	lda #$00
	sta answer+1
	sta answer
; works up until this point:
subtract_lo_byte:
; always set carry before subtraction
	sec
	lda starting_value
	sbc subtract_value
	sta answer
subtract_hi_byte:
	lda starting_value+1
	sbc subtract_value+1
	sta answer+1
show_answer:
	lda answer+1
	ldx answer
	jsr out_16_bit_num
	lda #' '
	jsr chrout
compare_computed_to_answer:
	lda computed_answer
	cmp answer
	bne wrong
	lda computed_answer+1
	cmp answer+1
	bne wrong

right:
	lda #<right_answer
	ldy #>right_answer
	jsr out_string
	jmp done
wrong:
	lda #<wrong_answer
	ldy #>wrong_answer
	jsr out_string

done:
	rts

; starting value:
starting_value:
	word 1000
subtract_value:
	word 100
answer:
	word $ffff  ; modified above
computed_answer:
; TODO: calculate this via the assembler
; ['word starting_value-subtract_value' does not work)]
	word 900

wrong_answer:
	ascii "wrong!"
	byte $00
right_answer:
	ascii "correct!"
	byte $00
