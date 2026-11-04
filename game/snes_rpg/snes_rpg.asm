        ; slime cellar - a tiny rpg for the
        ; "petscii robots" user port snes adapter
        ; ryan sherwood 11/4/2026
        ; c64list 4.06 format, see README.md

        ; find the key, unlock the door and reach the stairs.
        ;
        ;   d-pad   walk (turns you to face that way)
        ;   b       hold while walking to run
        ;   a       act on the tile you face: fight, unlock
        ;   x       look at the tile you face
        ;   y       use the selected item (potion or bomb)
        ;   l / r   select the previous / next item
        ;   start   pause; restart after the game ends
        ;   select  show / hide the pad readout
        ;   stop    quit to basic

        orig $0801
{alpha:alt}
basic:
         word basic_end ; line link
         word 10        ; line 10
         byte $9e       ; sys
         ascii "2061"
         byte $00       ; end of line
basic_end:
         word $00       ; no more lines

; ---------------------------------------------------------------
; equates

chrout     = $ffd2 ; kernal: print .a
kernal_stop = $ffe1 ; kernal: .z=1 if stop is pressed
jiffy      = $a2   ; low byte of the 60 hz jiffy clock

cia2_pb    = $dd01 ; user port: clock (bit 3), latch (bit 5), data (bit 6)
cia2_ddrb  = $dd03

screen     = $0400
colors     = $d800

str_ptr    = $22   ; 2 bytes: basic scratch, free while we run
scr_ptr    = $fb   ; 2 bytes: screen ram address
col_ptr    = $fd   ; 2 bytes: color ram address

; pad1 bits (first 8 bits from the pad), 1 = pressed
PAD_B      = $01
PAD_Y      = $02
PAD_SELECT = $04
PAD_START  = $08
PAD_UP     = $10
PAD_DOWN   = $20
PAD_LEFT   = $40
PAD_RIGHT  = $80
PAD_DIRS   = $f0
; pad2 bits (next 4 bits)
PAD_A      = $01
PAD_X      = $02
PAD_L      = $04
PAD_R      = $08

; tiles, as screen codes (lowercase character set)
T_PLAYER   = $00 ; @
T_KEY      = $0b ; k
T_SLIME2   = $13 ; s  small slime: one more hit
T_FLOOR    = $20 ; space
T_POTION   = $21 ; !
T_WALLCHR  = $23 ; # in the map data...
T_GOLD     = $24 ; $
T_BOMB     = $2a ; *
T_STAIRS   = $3e ; >
T_DOOR     = $44 ; D
T_SLIME    = $53 ; S  big slime
T_WALL     = $a0 ; ...drawn as a solid block

NUM_TILES  = 11

; screen rows
ROW_STATUS = 0
ROW_MAP    = 1  ; map is rows 1-21
MAP_ROWS   = 21
ROW_HELP   = 22
ROW_MSG    = 23
ROW_PAD    = 24

; status line columns (see status_text)
COL_HP     = 3
COL_GOLD   = 10
COL_KEYS   = 18
COL_POTION = 20 ; "Potions 0": columns 20-28
COL_POTNUM = 28
COL_BOMB   = 30 ; "Bombs 0": columns 30-36
COL_BOMBNUM = 36

; game states
ST_PLAY    = 0
ST_PAUSED  = 1
ST_OVER    = 2

MAX_HP     = 9

; ---------------------------------------------------------------
; start-up

game_start:
         lda cia2_ddrb  ; save what we change, for quit
         sta save_ddrb
         lda $d020
         sta save_border
         lda $d021
         sta save_bg
         lda $0286
         sta save_cursor

         lda #$28       ; clock and latch are outputs
         sta cia2_ddrb
         lda #0
         sta $d020      ; black border and background
         sta $d021
         lda #14        ; lowercase character set
         jsr chrout
         lda #8         ; and lock it (no shift+c=)
         jsr chrout

new_game:
         jsr init_game

; ---------------------------------------------------------------
; main loop: once per jiffy (1/60 s)

main_loop:
         lda jiffy
wait_jiffy:
         cmp jiffy
         beq wait_jiffy

         jsr kernal_stop
         bne ml_run
         jmp quit
ml_run:
         jsr read_pad
         jsr update_pad_row

         ; start: pause / resume / restart
         lda new1
         and #PAD_START
         beq ml_select
         lda state
         cmp #ST_PLAY
         beq ml_pause
         cmp #ST_PAUSED
         beq ml_resume
         jmp new_game   ; game over: play again
ml_pause:
         lda #ST_PAUSED
         sta state
         lda #<msg_paused
         ldy #>msg_paused
         jsr show_msg
         jmp main_loop
ml_resume:
         lda #ST_PLAY
         sta state
         lda #<msg_empty
         ldy #>msg_empty
         jsr show_msg
         jmp main_loop

         ; select: pad readout on/off (works while paused too)
ml_select:
         lda new1
         and #PAD_SELECT
         beq ml_playing
         lda pad_row_on
         eor #1
         sta pad_row_on
         jsr draw_pad_row

ml_playing:
         lda state
         cmp #ST_PLAY
         beq ml_move
         jmp main_loop
ml_move:
         jsr handle_move
         lda state
         cmp #ST_PLAY
         beq ml_a
         jmp main_loop  ; walked onto the stairs

ml_a:
         lda new2
         and #PAD_A
         beq ml_x
         jsr act
         jmp main_loop
ml_x:
         lda new2
         and #PAD_X
         beq ml_y
         jsr look_ahead
         jmp main_loop
ml_y:
         lda new1
         and #PAD_Y
         beq ml_lr
         jsr use_item
         jmp main_loop
ml_lr:
         lda new2
         and #PAD_L+PAD_R ; only 2 items, so both just swap
         beq ml_done
         lda selected
         eor #1
         sta selected
         jsr draw_status
ml_done:
         jmp main_loop

quit:
         lda save_ddrb
         sta cia2_ddrb
         lda save_border
         sta $d020
         lda save_bg
         sta $d021
         lda save_cursor
         sta $0286
         lda #9         ; allow shift+c= again
         jsr chrout
         lda #147       ; clear screen
         jsr chrout
         rts

; ---------------------------------------------------------------
; new game: reset stats, draw everything

init_game:
         lda #MAX_HP
         sta hp
         lda #0
         sta gold
         sta keys
         sta bombs
         sta selected
         sta pad_row_on
         sta new1
         sta new2
         lda #1
         sta potions
         lda #ST_PLAY
         sta state
         lda #1         ; facing down
         sta facing
         lda #$ff       ; ignore buttons already held
         sta pad1
         sta pad2

         lda #147       ; clear screen
         jsr chrout
         jsr load_map
         jsr draw_status

         lda #12        ; gray
         sta text_color
         lda #<help_text
         sta str_ptr
         lda #>help_text
         sta str_ptr+1
         ldy #ROW_HELP
         jsr write_row

         jsr draw_pad_row

         lda #<msg_welcome
         ldy #>msg_welcome
         jmp show_msg

; copy map_data to screen rows 1-21, with colors.
; the @ in the map is where the player starts.
load_map:
         lda #<map_data
         sta str_ptr
         lda #>map_data
         sta str_ptr+1
         lda #ROW_MAP
         sta map_row
lm_row:
         ldx #0
         ldy map_row
         jsr set_ptr
         ldy #0
lm_col:
         lda (str_ptr),y
         jsr pet2scr
         cmp #T_WALLCHR
         bne lm_notwall
         lda #T_WALL
lm_notwall:
         cmp #T_PLAYER
         bne lm_put
         sty px
         ldx map_row
         stx py
lm_put:
         jsr put_tile
         iny
         cpy #40
         bne lm_col

         clc            ; next row of map data
         lda str_ptr
         adc #40
         sta str_ptr
         bcc lm_next
         inc str_ptr+1
lm_next:
         inc map_row
         lda map_row
         cmp #ROW_MAP+MAP_ROWS
         bne lm_row
         rts

; ---------------------------------------------------------------
; snes pad

; read 16 bits from the pad into pad1/pad2 (1 = pressed),
; and set new1/new2 to the buttons pressed since last time
read_pad:
         lda pad1
         sta prev1
         lda pad2
         sta prev2

         lda #$28       ; latch and clock high
         sta cia2_pb
         lda #$08       ; latch low: pad holds its buttons
         sta cia2_pb

         ldx #8         ; b y select start up down left right
rp_lo:
         jsr read_bit
         ror pad1
         dex
         bne rp_lo
         ldx #8         ; a x l r, then 4 unused bits
rp_hi:
         jsr read_bit
         ror pad2
         dex
         bne rp_hi
         lda pad2
         and #$0f       ; drop the unused bits
         sta pad2

         lda prev1      ; new = now and not before
         eor #$ff
         and pad1
         sta new1
         lda prev2
         eor #$ff
         and pad2
         sta new2
         rts

; .c = 1 if the current bit is pressed (data line low),
; then pulse the clock for the next bit
read_bit:
         lda cia2_pb
         eor #$40
         and #$40
         cmp #$40       ; .c = 1 if pressed
         lda #$00       ; clock low (lda/sta keep .c)
         sta cia2_pb
         lda #$08       ; clock high
         sta cia2_pb
         rts

; pad readout on row 24 (select toggles it):
; each button's label shows reversed while it is held
draw_pad_row:
         lda #11        ; dark gray
         sta text_color
         lda pad_row_on
         bne dpr_on
         lda #<pad_off_text
         sta str_ptr
         lda #>pad_off_text
         sta str_ptr+1
         ldy #ROW_PAD
         jmp write_row
dpr_on:
         lda #15        ; light gray
         sta text_color
         lda #<pad_on_text
         sta str_ptr
         lda #>pad_on_text
         sta str_ptr+1
         ldy #ROW_PAD
         jsr write_row
         ; falls through to fill in the labels

update_pad_row:
         lda pad_row_on
         beq upr_done
         lda pad1
         sta upr_lo
         lda pad2
         sta upr_hi
         ldx #11        ; b is the last label (cell 11)
upr_cell:
         lsr upr_hi     ; next bit into .c
         ror upr_lo
         lda #0
         ror            ; $80 if pressed
         sta upr_rev
         txa
         asl            ; 2 columns per label
         tay
         lda pad_labels,y
         jsr pet2scr
         ora upr_rev
         sta screen+960,y ; row 24
         iny
         lda pad_labels,y
         jsr pet2scr
         ora upr_rev
         sta screen+960,y ; row 24
         dex
         bpl upr_cell
upr_done:
         rts

; ---------------------------------------------------------------
; walking

; d-pad: move once when pressed; keep moving while held,
; faster with b held
handle_move:
         lda pad1
         and #PAD_DIRS
         bne hm_held
         rts
hm_held:
         ldx #0         ; 0 up 1 down 2 left 3 right
         and #PAD_UP
         bne hm_dir
         inx
         lda pad1
         and #PAD_DOWN
         bne hm_dir
         inx
         lda pad1
         and #PAD_LEFT
         bne hm_dir
         inx
hm_dir:
         lda new1
         and #PAD_DIRS
         beq hm_repeat
         lda #16        ; first repeat after 16 jiffies
         sta repeat_timer
         jmp try_move
hm_repeat:
         dec repeat_timer
         bne hm_wait
         lda #8         ; walk: 8 jiffies per step
         sta repeat_timer
         lda pad1
         and #PAD_B
         beq hm_go
         lda #4         ; run: 4
         sta repeat_timer
hm_go:
         jmp try_move
hm_wait:
         rts

; .x = direction. turn that way, then step if the tile allows
try_move:
         stx facing
         jsr tile_ahead
         cmp #T_FLOOR
         bne tm_gold
         jmp step_player
tm_gold:
         cmp #T_GOLD
         bne tm_key
         jsr add_gold
         lda #<msg_gold
         ldy #>msg_gold
         jsr show_msg
         jmp step_player
tm_key:
         cmp #T_KEY
         bne tm_potion
         inc keys
         lda #<msg_key
         ldy #>msg_key
         jsr show_msg
         jmp step_player
tm_potion:
         cmp #T_POTION
         bne tm_bomb
         inc potions
         lda #<msg_potion
         ldy #>msg_potion
         jsr show_msg
         jmp step_player
tm_bomb:
         cmp #T_BOMB
         bne tm_stairs
         inc bombs
         lda #<msg_bomb
         ldy #>msg_bomb
         jsr show_msg
         jmp step_player
tm_stairs:
         cmp #T_STAIRS
         bne tm_blocked
         jsr step_player
         lda #ST_OVER
         sta state
         lda #<msg_win
         ldy #>msg_win
         jmp show_msg
tm_blocked:
         jmp look_ahead       ; wall, door or slime: say what it is

; move the player from px,py to tx,ty
step_player:
         ldx px
         ldy py
         jsr set_ptr
         ldy #0
         lda #T_FLOOR
         jsr put_tile
         lda tx
         sta px
         lda ty
         sta py
         ldx px
         ldy py
         jsr set_ptr
         ldy #0
         lda #T_PLAYER
         jsr put_tile
         jmp draw_status

; ---------------------------------------------------------------
; buttons

; a: act on the tile ahead
act:
         jsr tile_ahead
         cmp #T_SLIME
         bne act_slime2
         ldy #0
         lda #T_SLIME2  ; big slime shrinks...
         jsr put_tile
         lda #<msg_hit
         ldy #>msg_hit
         jsr show_msg
         lda #2         ; ...and hits back for 2
         jmp hurt_player
act_slime2:
         cmp #T_SLIME2
         bne act_door
         ldy #0
         lda #T_FLOOR
         jsr put_tile
         jsr add_gold
         lda #<msg_slain
         ldy #>msg_slain
         jsr show_msg
         jmp draw_status
act_door:
         cmp #T_DOOR
         bne act_nothing
         lda keys
         bne act_unlock
         lda #<msg_locked
         ldy #>msg_locked
         jmp show_msg
act_unlock:
         dec keys
         ldy #0
         lda #T_FLOOR
         jsr put_tile
         lda #<msg_unlock
         ldy #>msg_unlock
         jsr show_msg
         jmp draw_status
act_nothing:
         lda #<msg_no_act
         ldy #>msg_no_act
         jmp show_msg

; x: describe the tile ahead
look_ahead:
         jsr tile_ahead
         jsr tile_index
         lda look_lo,x
         ldy look_hi,x
         jmp show_msg

; y: use the selected item
use_item:
         lda selected
         bne use_bomb
         lda potions
         bne use_potion
         lda #<msg_no_potion
         ldy #>msg_no_potion
         jmp show_msg
use_potion:
         lda hp
         cmp #MAX_HP
         bne drink
         lda #<msg_hp_full
         ldy #>msg_hp_full
         jmp show_msg
drink:
         dec potions
         clc
         adc #3
         cmp #MAX_HP+1
         bcc drink_ok
         lda #MAX_HP
drink_ok:
         sta hp
         lda #<msg_drink
         ldy #>msg_drink
         jsr show_msg
         jmp draw_status

use_bomb:
         lda bombs
         bne have_bomb
         lda #<msg_no_bomb
         ldy #>msg_no_bomb
         jmp show_msg
have_bomb:
         jsr tile_ahead
         cmp #T_SLIME
         beq blast
         cmp #T_SLIME2
         beq blast
         cmp #T_WALL
         bne no_target
         lda tx         ; outer walls are too thick
         beq too_thick
         cmp #39
         beq too_thick
         lda ty
         cmp #ROW_MAP
         beq too_thick
         cmp #ROW_MAP+MAP_ROWS-1
         beq too_thick
blast:
         dec bombs
         ldy #0
         lda #T_FLOOR
         jsr put_tile
         lda #<msg_boom
         ldy #>msg_boom
         jsr show_msg
         jmp draw_status
too_thick:
         lda #<msg_thick
         ldy #>msg_thick
         jmp show_msg
no_target:
         lda #<msg_no_target
         ldy #>msg_no_target
         jmp show_msg

; ---------------------------------------------------------------
; helpers

; tx,ty = the tile the player faces; .a = what's there,
; scr_ptr/col_ptr point at it
tile_ahead:
         ldx facing
         clc
         lda px
         adc dir_dx,x
         sta tx
         clc
         lda py
         adc dir_dy,x
         sta ty
         ldx tx
         ldy ty
         jsr set_ptr
         ldy #0
         lda (scr_ptr),y
         rts

; .a = tile -> .x = its index in tile_list (unknown: floor)
tile_index:
         ldx #NUM_TILES-1
ti_loop:
         cmp tile_list,x
         beq ti_done
         dex
         bpl ti_loop
         ldx #0
ti_done:
         rts

; .x = column, .y = row -> scr_ptr, col_ptr
set_ptr:
         txa
         clc
         adc row_lo,y
         sta scr_ptr
         sta col_ptr
         lda row_hi,y
         adc #0
         sta scr_ptr+1
         clc
         adc #$d4       ; screen $04xx -> colors $d8xx
         sta col_ptr+1
         rts

; store tile .a at (scr_ptr),y with its color
put_tile:
         sta (scr_ptr),y
         stx put_x
         jsr tile_index
         lda tile_color,x
         sta (col_ptr),y
         ldx put_x
         rts

; lose .a hit points; the game ends at 0
hurt_player:
         sta damage
         sec
         lda hp
         sbc damage
         beq hp_zero
         bcs hp_left
hp_zero:
         lda #0
hp_left:
         sta hp
         jsr draw_status
         lda hp
         bne hp_ok
         lda #ST_OVER
         sta state
         lda #<msg_dead
         ldy #>msg_dead
         jmp show_msg
hp_ok:
         rts

add_gold:
         sei            ; the kernal irq can't run in decimal mode
         sed
         clc
         lda gold
         adc #1
         sta gold
         cld
         cli
         rts

; petscii (.a) -> screen code, for the lowercase set
pet2scr:
         cmp #$40
         bcc p2s_done   ; $20-$3f: same
         cmp #$60
         bcc p2s_40
         cmp #$80
         bcc p2s_20
         cmp #$c0
         bcc p2s_done
         and #$7f       ; $c0-$df -> $40-$5f (capitals)
         rts
p2s_40:
         and #$3f       ; $40-$5f -> $00-$1f (lowercase)
         rts
p2s_20:
         and #$5f       ; $60-$7f -> $40-$5f
p2s_done:
         rts

; message (.a lo, .y hi) on the message row
show_msg:
         sta str_ptr
         sty str_ptr+1
         lda #13        ; light green
         sta text_color
         ldy #ROW_MSG
         ; falls through

; clear row .y, then write the $00-terminated string at
; (str_ptr) into it in text_color
write_row:
         ldx #0
         jsr set_ptr
         ldy #39
wr_clear:
         lda #T_FLOOR
         sta (scr_ptr),y
         lda text_color
         sta (col_ptr),y
         dey
         bpl wr_clear
         ldy #0
wr_char:
         lda (str_ptr),y
         beq wr_done
         jsr pet2scr
         sta (scr_ptr),y
         iny
         cpy #40
         bne wr_char
wr_done:
         rts

; status line: hp, gold, keys and items; the selected
; item is shown reversed
draw_status:
         lda #7         ; yellow
         sta text_color
         lda #<status_text
         sta str_ptr
         lda #>status_text
         sta str_ptr+1
         ldy #ROW_STATUS
         jsr write_row

         lda hp
         ora #$30
         sta screen+COL_HP
         lda gold       ; 2 bcd digits
         lsr
         lsr
         lsr
         lsr
         ora #$30
         sta screen+COL_GOLD
         lda gold
         and #$0f
         ora #$30
         sta screen+COL_GOLD+1
         lda keys
         ora #$30
         sta screen+COL_KEYS
         lda potions
         ora #$30
         sta screen+COL_POTNUM
         lda bombs
         ora #$30
         sta screen+COL_BOMBNUM

         ldx #COL_POTION
         ldy #COL_POTNUM+1
         lda selected
         beq ds_rev
         ldx #COL_BOMB
         ldy #COL_BOMBNUM+1
ds_rev:
         sty ds_end
ds_loop:
         lda screen,x
         ora #$80
         sta screen,x
         inx
         cpx ds_end
         bne ds_loop
         rts

; ---------------------------------------------------------------
; tables

; screen row start addresses
row_lo: ; $0400 + 40 * row
         byte $00,$28,$50,$78,$a0,$c8,$f0,$18,$40,$68,$90,$b8,$e0,$08,$30,$58,$80,$a8,$d0,$f8,$20,$48,$70,$98,$c0
row_hi:
         byte $04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$06,$06,$06,$06,$06,$06,$06,$07,$07,$07,$07,$07

; facing: up, down, left, right
dir_dx:
         byte $00,$00,$ff,$01
dir_dy:
         byte $ff,$01,$00,$00

; tiles, their colors, and what x (look) says about them
tile_list:
         byte T_FLOOR,T_WALL,T_GOLD,T_KEY,T_DOOR,T_POTION
         byte T_BOMB,T_STAIRS,T_SLIME,T_SLIME2,T_PLAYER
tile_color:
         byte 1,12,7,14,8,10
         byte 15,1,5,13,3
look_lo:
         byte <look_floor,<look_wall,<look_gold,<look_key,<look_door,<look_potion
         byte <look_bomb,<look_stairs,<look_slime,<look_slime2,<look_floor
look_hi:
         byte >look_floor,>look_wall,>look_gold,>look_key,>look_door,>look_potion
         byte >look_bomb,>look_stairs,>look_slime,>look_slime2,>look_floor

; pad readout labels, 2 columns per button: cell 0 is r,
; cell 11 is b (the order the bits come in, reversed)
pad_labels:
         ascii "RbLbX A RtLfDnUpStSlY B "

; ---------------------------------------------------------------
; text
;            ----+----+----+----+----+----+----+----+

status_text:
         ascii "HP 9 Gold 00 Keys 0 Potions 0 Bombs 0"
         byte $00
help_text:
         ascii "A:act X:look Y:use L/R:item Start:pause"
         byte $00
pad_off_text:
         ascii "B:run  Select:pad readout  STOP:quit"
         byte $00
pad_on_text:
         ascii "                         Select:hide"
         byte $00

msg_welcome:
         ascii "Find the key and the way down."
         byte $00
msg_empty:
         byte $00
msg_paused:
         ascii "Paused. Press Start."
         byte $00
msg_gold:
         ascii "Gold!"
         byte $00
msg_key:
         ascii "You found a key."
         byte $00
msg_potion:
         ascii "You found a potion."
         byte $00
msg_bomb:
         ascii "You found a bomb."
         byte $00
msg_win:
         ascii "Down the stairs! Start: play again"
         byte $00
msg_dead:
         ascii "You fall... Start: play again"
         byte $00
msg_hit:
         ascii "You hit the slime. It hits back!"
         byte $00
msg_slain:
         ascii "The slime is gone. It left gold!"
         byte $00
msg_locked:
         ascii "Locked. You need a key."
         byte $00
msg_unlock:
         ascii "The key turns. The door opens."
         byte $00
msg_no_act:
         ascii "Nothing to do there."
         byte $00
msg_no_potion:
         ascii "No potions."
         byte $00
msg_hp_full:
         ascii "You feel fine already."
         byte $00
msg_drink:
         ascii "You drink a potion. HP +3"
         byte $00
msg_no_bomb:
         ascii "No bombs."
         byte $00
msg_boom:
         ascii "BOOM!"
         byte $00
msg_thick:
         ascii "This wall is too thick to blast."
         byte $00
msg_no_target:
         ascii "Face a wall or a slime to use a bomb."
         byte $00

look_floor:
         ascii "Nothing there."
         byte $00
look_wall:
         ascii "A stone wall. Maybe a bomb..."
         byte $00
look_gold:
         ascii "A gold coin."
         byte $00
look_key:
         ascii "A key!"
         byte $00
look_door:
         ascii "A locked door. A opens it with a key."
         byte $00
look_potion:
         ascii "A potion. Y drinks it (+3 HP)."
         byte $00
look_bomb:
         ascii "A bomb. Y blasts the wall ahead."
         byte $00
look_stairs:
         ascii "Stairs down. The way out!"
         byte $00
look_slime:
         ascii "A big slime. A attacks it."
         byte $00
look_slime2:
         ascii "A small slime. One more hit!"
         byte $00

; ---------------------------------------------------------------
; map: 21 rows of 40, drawn on screen rows 1-21
;   #  wall      $  gold      k  key       D  locked door
;   S  slime     s  small     !  potion    *  bomb
;   >  stairs    @  player start

map_data:
         ascii "########################################"
         ascii "#        #         #         #         #"
         ascii "#   @    #    $    #    S    #    $    #"
         ascii "#        #         #         #         #"
         ascii "#        ####   ####         #         #"
         ascii "#   !                   $    D    >    #"
         ascii "#        ####   ####         #         #"
         ascii "#        #  $   $  #    S    #   $     #"
         ascii "####  ####         ####  ###############"
         ascii "#                     #                #"
         ascii "#   *   ######  s     #   S       k    #"
         ascii "#       #    #        #                #"
         ascii "#       # $$ #        ######   #########"
         ascii "#       #    #                         #"
         ascii "#       ######     $        S          #"
         ascii "#####  ##################  ##########  #"
         ascii "#   #                   #  #       #   #"
         ascii "# $ #    !       $      #  #  $$$  #   #"
         ascii "# $ #                   #  #       #   #"
         ascii "#   #       *           #  #########   #"
         ascii "########################################"

; ---------------------------------------------------------------
; variables

pad1:
         byte 0
pad2:
         byte 0
prev1:
         byte 0
prev2:
         byte 0
new1:
         byte 0
new2:
         byte 0
state:
         byte 0
hp:
         byte 0
gold:
         byte 0 ; bcd
keys:
         byte 0
potions:
         byte 0
bombs:
         byte 0
selected:
         byte 0 ; 0 potion, 1 bomb
facing:
         byte 0
px:
         byte 0
py:
         byte 0
tx:
         byte 0
ty:
         byte 0
repeat_timer:
         byte 0
map_row:
         byte 0
text_color:
         byte 0
put_x:
         byte 0
pad_row_on:
         byte 0
upr_lo:
         byte 0
upr_hi:
         byte 0
upr_rev:
         byte 0
ds_end:
         byte 0
save_ddrb:
         byte 0
save_border:
         byte 0
save_bg:
         byte 0
save_cursor:
         byte 0
damage:
         byte 0
