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

check_stop_key	= $ffe1	; .z=1 if stop hit

; https://codebase64.org/doku.php?id=base:joystick_input_handling
; windowing:
; https://codebase64.org/doku.php?id=base:draw_ram_to_screen_or_color_memory
; ($fb) holds where in screen RAM the player is
PLAYER_SCREEN_RAM_LOC      = $fb

; joystick directional bits:
; movement has happened when bit is 0, not 1
JOYSTICK_UP     = %11110
JOYSTICK_DOWN   = %11101
JOYSTICK_LEFT   = %11011
JOYSTICK_RIGHT  = %10111
JOYSTICK_FIRE   = %01111

setup:
; set up screen RAM pointer
	lda #>$0400
	sta PLAYER_SCREEN_RAM_LOC+1
	lda #<$0400
	sta PLAYER_SCREEN_RAM_LOC

; put player in center of screen & make visible
	ldy #20 ; 40 / 2
	stx player_x
	ldx #12 ; 24 / 2
	sty player_y
	jsr sub_x_y_to_screen_ram
;	jsr sub_plot_player

read_joy2:
; we read port 2 since port 1 is scanned using the cia chip and (unless
; interrupts are disabled) will scan the keyboard too, which interferes
; with scanning port 1.
	lda $dc00
	sta joy2_state
;	lda JOYSTICK_UP	; if you want to test code
	lsr
	beq go_up
	lsr
	beq go_down
	lsr
	beq go_left
	lsr
	beq go_right

read_stop:
	jsr check_stop_key
	bne read_joy2

basic:
	rts

go_up:
	lda player_x
; TODO: check for non-walkable chars (>128)
;	cmp #0
	beq no_move
	jsr sub_plot_player
; adjust screen memory location
	sec
	; subtract lo byte
	lda PLAYER_SCREEN_RAM_LOC
	sbc #<40
	sta PLAYER_SCREEN_RAM_LOC
	; subtract hi byte
	lda PLAYER_SCREEN_RAM_LOC+1
	sbc #>40
	sta PLAYER_SCREEN_RAM_LOC+1
; update player x coordinate
	dec player_x
	jsr sub_plot_player
	jmp no_move

go_down:
	lda player_x
	cmp #25
	beq no_move
	jsr sub_plot_player
	; add lo byte
	clc
	lda PLAYER_SCREEN_RAM_LOC
	adc #<40
	sta PLAYER_SCREEN_RAM_LOC
	; add hi byte
	lda PLAYER_SCREEN_RAM_LOC+1
	adc #>40
	sta PLAYER_SCREEN_RAM_LOC+1
; update player x coordinate
	inc player_x
	jsr sub_plot_player
	jmp no_move

go_left:
	; Check for left boundary
	lda player_y
;	cmp #0
	beq no_move
	jsr sub_plot_player
	dec player_x
	jsr sub_plot_player
	jmp no_move

go_right:
	; Check for right boundary
	lda player_y
	cmp #39
	beq no_move
	jsr sub_plot_player
	inc player_y
	jsr sub_plot_player
	jmp no_move

no_move:
; can't move due to obstacle, or moving will take player out of screen boundaries
	jmp read_joy2

sub_x_y_to_screen_ram:
; convert player_x and player_y coordinates to a screen memory location

; enter with:	player_x = x coordinate
;		player_y = y coordinate
; returns:	(PLAYER_SCREEN_RAM_LOC): player location in screen RAM

; first, copy current screen ram location to temp:
	lda PLAYER_SCREEN_RAM_LOC	; lo byte
	sta temp
	lda PLAYER_SCREEN_RAM_LOC+1	; hi byte
	sta temp+1
; next, add the x offset (rows):
	ldx player_x
	beq add_cols
add_rows:
; clear carry before addition
	clc
; add to lsb
	lda temp
	adc #40
	sta temp
; add to msb
	lda temp+1
	adc #00
	sta temp+1
next_row:
	dex
	bne add_rows
add_cols:
	lda player_y
	beq transfer
	clc
; add to lsb
	lda temp
	adc #player_y
	sta temp
; add to msb
	lda temp+1
	adc #$00
	sta temp+1
transfer:
	lda temp
	sta PLAYER_SCREEN_RAM_LOC
	lda temp+1
	sta PLAYER_SCREEN_RAM_LOC+1

; falls through:

sub_plot_player:
	lda PLAYER_SCREEN_RAM_LOC+1
	ldx PLAYER_SCREEN_RAM_LOC
	jsr $bdcd
; .y=0: no index needed
	ldy #$00
	lda (PLAYER_SCREEN_RAM_LOC),y
; invert bit 7 to reverse char
	eor %10000000
	sta (PLAYER_SCREEN_RAM_LOC),y
	rts

temp:
	word $ffff

; player coordinates:
; it may be overkill to keep track of this, but maybe it's better to have it
; now and not need it, than not have it and need to add it later
player_x:
	byte $ff
player_y:
	byte $ff

joy2_state:
; save joystick state
	byte $ff

movement_deltas:
; these are values to add to the player's position
; arranged in up, down, left, right order:
; (might be used later)
	byte -40,40,-1,1
