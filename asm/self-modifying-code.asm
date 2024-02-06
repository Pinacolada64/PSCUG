address = $0400		; sample address (start of screen ram)
    lda #$ff		; reset selfmod address to prove this works
    sta selfmod+1
    sta selfmod+2

    lda >address	; get high byte of address...
    sta selfmod+1	; ...store it 1 byte after 'sta' opcode
    lda <address	; get low byte of address...
    sta selfmod+2	; ...store it 2 bytes after 'sta' opcode

    lda #$01		; put something in the selfmod address
selfmod:
    sta $ffff		; $ffff is a temporary placeholder
    rts
