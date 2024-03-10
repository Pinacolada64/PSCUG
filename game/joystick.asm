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

strout	= $ab1e
chrout	= $ffd2
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

; display instructions:
	lda #<instructions	;  low byte of instructions string
	ldy #>instructions	; high byte of instructions string
	jsr strout

read_joy2:
; we read port 2 since port 1 is scanned using the cia chip and (unless
; interrupts are disabled) will scan the keyboard too, which interferes
; with scanning port 1.
; code from: https://codebase64.org/doku.php?id=base:joystick_input_handling
	lda $dc00
; get direction bits,
; start counting how many frames the joystick has been held
	lsr
	ror joy2_up
	lsr
	ror joy2_down
	lsr
	ror joy2_left
	lsr
	ror joy2_right
	lsr
	ror joy2_fire
check_up:
	bit joy2_up
	bmi check_down		; if not moved up at all
	bvc check_down	; or already up during last joystick read
	jsr go_up
check_down:
	bit joy2_down
	bmi check_left
	bvc check_left
	jsr go_down
check_left:
	bit joy2_left
	bmi check_right
	bvc check_right
	jsr go_left
check_right:
	bit joy2_right
	bmi check_fire
	bvc check_fire
	jsr go_right
check_fire:
	bit joy2_fire
	bmi read_stop
	bvc no_move
	jsr go_fire

read_stop:
	jsr check_stop_key
	bne read_joy2

basic:
	rts

go_up:
	lda player_y
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
; update player y coordinate
	dec player_y
	jsr sub_plot_player
	jmp no_move

go_down:
	lda player_y
	cmp #24
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
; update player y coordinate
	inc player_y
	jsr sub_plot_player
	jmp no_move

go_left:
	; Check for left boundary
	lda player_x
;	cmp #0
	beq no_move
	dec player_x
	jsr sub_plot_player
	sec
	lda PLAYER_SCREEN_RAM_LOC
	sbc #1
	sta PLAYER_SCREEN_RAM_LOC
	lda PLAYER_SCREEN_RAM_LOC+1
	sbc #$00
	sta PLAYER_SCREEN_RAM_LOC+1
	jsr sub_plot_player
	jmp no_move

go_right:
	; Check for right boundary
	lda player_x
	cmp #39
	beq no_move
	inc player_x
	jsr sub_plot_player
	clc
	lda PLAYER_SCREEN_RAM_LOC
	adc #1
	sta PLAYER_SCREEN_RAM_LOC
	lda PLAYER_SCREEN_RAM_LOC+1
	adc #$00
	sta PLAYER_SCREEN_RAM_LOC+1
	jsr sub_plot_player
	jmp no_move

go_fire:
	rts

no_move:
; can't move due to obstacle, or moving will take player out of screen boundaries
	jmp read_joy2

sub_x_y_to_screen_ram:
; convert player_x and player_y coordinates to a screen memory location
; https://www.lemon64.com/forum/viewtopic.php?t=62350&start=15

; enter with:	player_x = x coordinate
;		player_y = y coordinate
; returns:	(PLAYER_SCREEN_RAM_LOC): player location in screen RAM

; first, copy current screen ram location to temp storage:
	lda PLAYER_SCREEN_RAM_LOC	; lo byte
	sta temp
	lda PLAYER_SCREEN_RAM_LOC+1	; hi byte
	sta temp+1
; next, get the y offset (rows) to act as counter:
	ldy player_y
; is adding row needed?
	beq add_cols
add_rows:
; clear carry before addition
	clc
; add to lsb
	lda temp
	adc row_offsets_lo,y
	sta temp
; add to msb
	lda temp+1
;	adc #00
	adc row_offsets_hi,y
	sta temp+1
;next_row:
;	dey
;	bne add_rows
add_cols:
; is adding column needed?
	lda player_x
	beq transfer
; add to lsb
	clc
	lda temp
	adc player_x
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
	lda debug
	beq sub_plot_player1
	lda '{home}'
	jsr chrout
	lda PLAYER_SCREEN_RAM_LOC+1
	ldx PLAYER_SCREEN_RAM_LOC
	jsr $bdcd
sub_plot_player1:
; .y=0: no index needed
	ldy #$00
	lda (PLAYER_SCREEN_RAM_LOC),y
; invert bit 7 to reverse char
	eor #%10000000
	sta (PLAYER_SCREEN_RAM_LOC),y
	rts

temp:
	word $ffff

joy2_up:
	byte $00
joy2_down:
	byte $00
joy2_left:
	byte $00
joy2_right:
	byte $00
joy2_fire:
	byte $00

; player coordinates:
; it may be overkill to keep track of this, but maybe it's better to have it
; now and not need it, than not have it and need to add it later
player_x:
	byte $ff
player_y:
	byte $ff

row_offsets_lo:
	; rows 0-12
	byte <0,<40,<80,<120,<160,<200,<240,<280,<320,<360,<400,<440,<480
	; rows 13-25
	byte <520,<560,<600,<640,<680,<720,<760,<800,<840,<880,<920,<960,<1000
row_offsets_hi:
	; rows 0-12
	byte >0,>40,>80,>120,>160,>200,>240,>280,>320,>360,>400,>440,>480
	; rows 13-25
	byte >520,>560,>600,>640,>680,>720,>760,>800,>840,>880,>920,>960,>1000

joy2_state:
; save joystick state
	byte $ff

instructions:
	;      ----+----+----+----+----+----+----+----+
	ascii "move square with joystick in port 2."
	byte $0d
	ascii "stop key exits to basic."
	byte $0d,$00

debug:
	byte $00

movement_deltas:
; these are values to add to the player's position
; arranged in up, down, left, right order:
; (might be used later)
	byte -40,40,-1,1
