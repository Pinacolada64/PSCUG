{VersionMin:4.06}

{scatter}
{:Start}
    rem protect data $3000, midi buffer $3600, sprites $3700, charset $3800
    poke55,0:poke56,48:clr
    sys{sym:start}
    end

{asm}
;==============================================================================
; MIDI keyboard display and SID player for the C64
;
; Acknowledgements -- sources this program relies on:
;
; * C64List 4.06 by Jeff Hoag (assembler, BASIC tokenizer and the Users Guide).
;   The pack/scatter loader that C64List inserts into this program at build
;   time (ScatterPackedData.asm, shipped with C64List) is Jeff Hoag's code.
;
; * VICE, the Versatile Commodore Emulator (vice-emu.sourceforge.io), 3.10
;   source code, GPL v2: the MIDI cartridge register layouts and clock
;   dividers (src/c64/cart/c64-midi.c) and the 6850 ACIA register bits
;   (src/midi.c) used in the interface table below.
;
; * Commodore 64 KERNAL ROM (Commodore Business Machines), and the JiffyDOS
;   KERNAL (Creative Micro Designs): keyboard decode tables checked for the
;   CTRL-I/K/L codes, the IRQ exit at $EA81, and the routines called here
;   (GETIN, CHROUT, PLOT, screen clear).
;
; * MOS Technology 6581/8580 SID documentation and the Commodore 64
;   Programmer's Reference Guide: oscillator frequency formula
;   (Fn = f * 2^24 / clock), ADSR rate tables, and the OSC3 register.
;
; * MOS Technology 6850 ACIA data sheet (as implemented by the MIDI
;   cartridges and by VICE): control and status register bits.
;
; * MIDI 1.0 and General MIDI specifications (MIDI Manufacturers Association):
;   running status, Note On velocity 0 as Note Off, program families of 8,
;   and the channel-10 percussion key map.
;
; * Well-known C64 programming techniques from the demo and music scene:
;   the SID "hard restart" against the ADSR delay bug, sprite multiplexing
;   with a raster interrupt, and copying the character ROM to RAM.
;
; * STATION64 manual (sta64.txt, by DJ Indikator): which MIDI interfaces
;   matter on the C64, and the configurable hard-restart idea.
;==============================================================================

;------------------------------------------------------------------------------
; Hardware / KERNAL
;------------------------------------------------------------------------------
VIC_BORDER  = $d020
VIC_BKGND   = $d021
VIC_MEMSET  = $d018
CPU_PORT    = $01
SHIFT_LOCK  = $0291         ; $80 = SHIFT+C= charset toggle disabled
GETIN       = $ffe4
CHROUT      = $ffd2
PLOT        = $fff0
CLRSCR      = $e544
TEXT_COLOR  = $0286

BLACK       = 0
WHITE       = 1
BLUE        = 6
YELLOW      = 7

KEY_CTRL_L  = $0c
KEY_STOP    = $03
KEY_F1      = $85
KEY_CTRL_I  = $09
KEY_CTRL_K  = $0b

; zero page pointers (free for user code; also used by scatter)
SRC         = $fb
DST         = $fd
SCRPTR      = $fb
COLPTR      = $fd

;------------------------------------------------------------------------------
; Custom character set: ROM uppercase/graphics copied to $3800
; Screen $0400 + charset $3800 => $d018 = $1e
;------------------------------------------------------------------------------
CHARSET         = $3800
CHARSET_SHARPS  = $3cd8     ; CHARSET + ($1b+$80)*8: the reversed copies
                            ; (the VIC has no reverse mode; $80-$ff are
                            ;  separate pre-inverted glyphs)
CHARSET_SHAPES  = $3b80     ; CHARSET + $70*8

; screen codes of redefined characters
SH_C        = $1b           ; C#  (replaces [ )
SH_D        = $1c           ; D#  (replaces pound)
SH_F        = $1d           ; F#  (replaces ] )
SH_G        = $1e           ; G#  (replaces up arrow)
SH_A        = $1f           ; A#  (replaces left arrow)
G_SEP       = $70           ; gap between two white keys
G_SEPBOT    = $71           ;   ...bottom row, rounded corners
G_LEDGE     = $72           ; left edge of keyboard
G_LTOP      = $73
G_LBOT      = $74
G_REDGE     = $75           ; right edge of keyboard
G_RTOP      = $76
G_RBOT      = $77
SOLID       = $a0           ; reversed space

;------------------------------------------------------------------------------
; Keyboard layout: 19 white keys (C..G, ~2 2/3 octaves), 2 columns per key,
; 39 columns wide, on screen rows 20-24.
;   col 0 = left edge, odd cols = white keys, even cols = gaps / black keys
;------------------------------------------------------------------------------
KB_WIDTH    = 39
KB_ROWS     = 5
KB_SCREEN   = $0720         ; $0400 + 20*40
KB_COLOR    = $db20         ; $d800 + 20*40
KB_ROW2     = $0748         ; screen row 21: black-key labels
KB_ROW4     = $0798         ; screen row 23: white-key labels
; upper keyboard (CTRL-K): screen rows 8-12, sharing the top area with the
; MIDI monitor
UKB_SCREEN  = $0540         ; $0400 + 8*40
UKB_COLOR   = $d940         ; $d800 + 8*40
UKB_ROW2    = $0568         ; screen row 9: black-key labels
UKB_ROW4    = $05b8         ; screen row 11: white-key labels
; sprite multiplexing: a raster interrupt loads the upper keyboard's sprites
; above it and the lower keyboard's sprites between the two keyboards
VIC_IRQ     = $d019
VIC_IRQEN   = $d01a
SPLIT_UPPER = 30            ; raster line: load upper sprites (keyboard at 114)
SPLIT_LOWER = 160           ; upper sprites end at 156, lower start at 210

; column types
KT_LEFT     = 0
KT_WHITE    = 1
KT_SEP      = 2
KT_BLACK    = 3
KT_RIGHT    = 4
KT_COUNT    = 5

;------------------------------------------------------------------------------
; Sprites: white-key highlight "slivers" (the 3-4 px of a white key that lie
; in the shared gap cells; colour RAM handles the key's own column).
; Each highlight slot k uses sprite k: Y-expanded (21 rows = 42 lines), enough
; for the whole 40-line keyboard, so 8 sprites = 8 highlighted white keys.
; Highlights are coloured by the SID playing the note.
;------------------------------------------------------------------------------
SPR_POS     = $d000         ; x0,y0,x1,y1,...
SPR_XMSB    = $d010
SPR_ENABLE  = $d015
SPR_YEXP    = $d017
SPR_PRIO    = $d01b         ; 0 = in front of text
SPR_MCOL    = $d01c
SPR_XEXP    = $d01d
SPR_COLOR0  = $d027
SPR_PTRS    = $07f8         ; screen $0400 + $3f8

SPR_DATA    = $3700         ; 3 blocks, $3700-$37bf
SP_TOP_CF   = $dc           ; $3700/64: black key on right (C, F)
SP_TOP_EB   = $dd           ; black key on left (E, B, last G)
SP_TOP_DGA  = $de           ; black keys both sides (D, G, A)

SPR_Y       = 210           ; 50 + 20*8: lower keyboard top line
SPR_Y2      = 114           ; 50 + 8*8: upper keyboard top line
SPR_X_ADJ   = 21            ; 24 (sprite x offset) - 3 (left sliver)
NUM_SLOTS   = 8             ; sprite slots per keyboard
TOTAL_SLOTS = 16            ; 8 lower + 8 upper (sprites reused per keyboard)
HILITE      = YELLOW        ; notes on SID 1 (and mono)
HILITE2     = 13            ; light green: notes on SID 2
NO_NOTE     = $ff
NUM_NOTES   = 32            ; keys per keyboard: C .. G
NUM_KEYS    = 64            ; 0-31 lower keyboard, 32-63 upper

;------------------------------------------------------------------------------
; MIDI input: 6850 ACIA cartridges (as emulated by TeensyROM and VICE).
; Register offsets from $de00 and control values match VICE's
; src/c64/cart/c64-midi.c.  Polled, so receive interrupts stay off.
;------------------------------------------------------------------------------
MIDI_IO         = $de00
ACIA_RESET      = $03       ; control: master reset
ACIA_RDRF       = $01       ; status: receive data register full
ACIA_TDRE       = $02       ; status: transmit data register empty
ACIA_CHECK_MASK = $52       ; PE, FE, TDRE: used to detect a real ACIA
ACIA_RIE        = $80       ; control: receive interrupt enable
ACIA_IRQ        = $80       ; status: the ACIA is requesting an interrupt

; Interrupt-driven receive: the ACIA interrupts on every byte and the handler
; stores it in a 256-byte ring buffer that the main loop drains.
; Sequential/Passport/Datel use IRQ, Namesoft uses NMI; both are hooked.
RX_BUF          = $3600     ; 256-byte ring buffer (below the sprites)
TABLES          = $3000     ; data and tables (scatter puts them here)
IRQ_VECTOR      = $0314
NMI_VECTOR      = $0318
CIA1_ICR        = $dc0d     ; reading it acknowledges CIA1 interrupts
KERNAL_IRQ_RTI  = $ea81     ; KERNAL: pull Y, X, A and RTI
NUM_IFACES      = 4
DEFAULT_IFACE   = 2         ; Datel
KB_LOW_NOTE     = 36        ; lower keyboard: C2-G4 (MIDI 36-67)
KB2_LOW_NOTE    = 72        ; upper keyboard: C5-G7 (MIDI 72-103)

; status lines above the keyboard
STATUS_ROW      = 14
IFACE_COL       = 6         ; where the interface name goes
HEX_SCREEN      = $065e     ; $0400 + 15*40 + 6: last MIDI byte

; MIDI monitor window (CTRL-I): title on row 0, log on rows 1-12
MON_TITLE       = $0400     ; row 0
MON_BOTTOM      = $05e0     ; row 12: newest line (upper keyboard hidden)
MON_BOTTOM2     = $04f0     ; row 6: newest line (upper keyboard shown)
MON_ROWS_1_6    = $0428     ; rows 1-6 and 7-12: two 240-byte blocks
MON_ROWS_7_12   = $0518
MON_COLOR_7_12  = $d918
MON_ROWS_COLOR  = $d800
MON_COLOR       = 3         ; cyan
MON_LABEL_COL   = 10        ; "on  ", "cc  " ...
MON_NOTE_COL    = 15        ; "c#4"
MON_VEL_COL     = 20        ; "v100"
MON_CH_COL      = 26        ; "ch16"
MON_WRAP_COL    = 9         ; hex stops before the label; SysEx continues below

;------------------------------------------------------------------------------
; SID piano.  Fn = f * 2^24 / clock.  One octave (MIDI 84-95) is stored per
; clock (PAL 985248 Hz, NTSC 1022727 Hz); lower octaves are made by shifting
; right 7 - (note / 12) times.
;------------------------------------------------------------------------------
SID             = $d400     ; voice v at SID + v*7
SID_VOLUME      = $d418
VIC_CTRL1       = $d011     ; bit 7 = raster line bit 8
VIC_RASTER      = $d012
WAVE_PULSE      = $40
GATE            = $01
; Velocity: the SID has no per-voice volume, so the sustain level is used
; as one.  A note hits full level, drops fast to a sustain level set by
; velocity, then (for fading patches) the program lowers the sustain step by
; step while a slow decay rate smooths the steps into a fade.
; Each instrument ("patch") sets waveform, pulse width, the hit and hold
; envelopes, release, and the fade speed -- see the patch tables.
HIT_JIFFIES     = 2         ; time for the fast drop before going slow
NUM_PATCHES     = 8
INST_SCREEN     = $0662     ; $0400 + 15*40 + 10: instrument name
INST_COLOR      = $da62     ; its colour RAM

; Hard restart (ADSR bug): before a note starts, the voice sits with gate off
; and ADSR $00/$00 for at least one full rate-counter wrap (32768 cycles,
; 33 ms) so the attack begins on time.  Timed in KERNAL jiffies (1/60 s).
JIFFY           = $a2       ; low byte of the KERNAL jiffy clock
HR_JIFFIES      = 3         ; 3 ticks: at least 33.3 ms after the reset

; voice states
VS_BUSY         = 0         ; gate on, sustain stepping down
VS_RELEASING    = 1         ; gate off, release audible; timer -> park
VS_SETTLING     = 2         ; ADSR zeroed, waiting out the counter wrap
VS_READY        = 3         ; settled: a new note can start instantly
VS_RESTART      = 4         ; hard restart in progress, note pending
VS_HIT          = 5         ; gate on, fast drop to the velocity level
VS_DRUM         = 6         ; playing a drum program (channel 10)
DRUM_CH         = 9         ; MIDI channel 10
DRUM_FIRST      = 35        ; GM drum map range handled
DRUM_LAST       = 59
MAX_VOICES      = 6         ; 3 per SID; 3 if there's no second SID
VPTR            = $fd       ; zero-page pointer to the current voice's registers
SND_MAX_NOTE    = 96        ; MIDI 96+ is above the stored octave
TUNING_COL      = 19        ; "sid: pal" on the second status line

    orig $c000

;------------------------------------------------------------------------------
start:
    lda #BLUE
    sta VIC_BORDER
    sta VIC_BKGND
    jsr CLRSCR
    jsr setup_charset
    jsr draw_keyboard
    jsr setup_sprites
    jsr draw_status
    lda #0
    jsr set_all_patches
    jsr sid_init
    jsr install_irq
    lda #DEFAULT_IFACE
    jsr midi_select

main_loop:
    jsr midi_poll
    lda JIFFY               ; once per jiffy: advance the voice timers
    cmp last_jiffy
    beq >@NoTick
    sta last_jiffy
    jsr sound_tick
@NoTick:
    jsr GETIN
    cmp #KEY_CTRL_L
    bne >@NotL
    lda show_labels
    eor #1
    sta show_labels
    jsr draw_labels
    jmp main_loop
@NotL:
    cmp #KEY_F1
    bne >@NotF1
    ldx midi_iface          ; next interface, wrapping around
    inx
    cpx #NUM_IFACES
    bne >@NoWrap
    ldx #0
@NoWrap:
    txa
    jsr midi_select
    jmp main_loop
@NotF1:
    cmp #KEY_CTRL_I
    bne >@NotI
    jsr mon_toggle
    jmp main_loop
@NotI:
    cmp #KEY_CTRL_K
    bne >@NotK
    jsr kb2_toggle
    jmp main_loop
@NotK:
    cmp #$31                ; keys 1-8: instrument for every channel
    bcc >@NotNum
    cmp #$39
    bcs >@NotNum
    sbc #$30-1              ; carry is clear here: A - $31 -> 0..7
    jsr set_all_patches
    jmp main_loop
@NotNum:
    cmp #KEY_STOP
    bne main_loop

    ; RUN/STOP: silence, remove sprites, restore ROM charset, back to BASIC
    jsr remove_irq
    jsr all_notes_off
    jsr sound_all_off
    lda #0
    sta SID_VOLUME
    sta SPR_ENABLE
    ldx sid2_base+1
    beq >@NoSid2
    stx VPTR+1
    ldx sid2_base
    stx VPTR
    ldy #$18
    sta (VPTR),y
@NoSid2:
    lda #$15
    sta VIC_MEMSET
    lda #$00
    sta SHIFT_LOCK
    jmp CLRSCR

;------------------------------------------------------------------------------
; Copy the uppercase/graphics ROM charset to CHARSET, install custom glyphs,
; and switch the VIC to it.
setup_charset:
    sei
    lda CPU_PORT
    pha
    and #$fb                ; bank in character ROM at $d000
    sta CPU_PORT

    lda #$00
    sta SRC
    sta DST
    lda #$d0
    sta SRC+1
    lda #>CHARSET
    sta DST+1
    ldx #8                  ; 8 pages = 2K
    ldy #0
@Loop:
    lda (SRC),y
    sta (DST),y
    iny
    bne <@Loop
    inc SRC+1
    inc DST+1
    dex
    bne <@Loop

    pla
    sta CPU_PORT
    cli

    ldx #39                 ; 5 glyphs * 8 bytes
@Sharps:
    lda sharp_glyphs,x
    eor #$ff                ; store inverted: blue label on black key
    sta CHARSET_SHARPS,x
    dex
    bpl <@Sharps

    ldx #63                 ; 8 glyphs * 8 bytes
@Shapes:
    lda shape_glyphs,x
    sta CHARSET_SHAPES,x
    dex
    bpl <@Shapes

    lda #$1e                ; screen $0400, charset $3800
    sta VIC_MEMSET
    lda #$80                ; lock out SHIFT+C= charset switch
    sta SHIFT_LOCK
    rts

;------------------------------------------------------------------------------
; Draw the keyboard: each cell = row_glyph/row_color[row*KT_COUNT + coltype]
draw_keyboard:
    lda #<KB_SCREEN         ; screen and color RAM share the low byte
    sta SCRPTR
    sta COLPTR
    lda #>KB_SCREEN
    sta SCRPTR+1
    lda #>KB_COLOR
    sta COLPTR+1
    jsr draw_kb_rows
    jmp draw_labels

draw_keyboard2:             ; the upper keyboard
    lda #<UKB_SCREEN
    sta SCRPTR
    sta COLPTR
    lda #>UKB_SCREEN
    sta SCRPTR+1
    lda #>UKB_COLOR
    sta COLPTR+1
    jsr draw_kb_rows
    jmp draw_labels

draw_kb_rows:
    lda #0
    sta rowbase
@Row:
    ldy #KB_WIDTH-1
@Col:
    lda coltype,y
    clc
    adc rowbase
    tax
    lda row_glyph,x
    sta (SCRPTR),y
    lda row_color,x
    sta (COLPTR),y
    dey
    bpl <@Col

    lda SCRPTR              ; next screen row
    clc
    adc #40
    sta SCRPTR
    sta COLPTR
    bcc >@NoCarry
    inc SCRPTR+1
    inc COLPTR+1
@NoCarry:
    lda rowbase
    clc
    adc #KT_COUNT
    sta rowbase
    cmp #KT_COUNT*KB_ROWS
    bne <@Row
    rts

;------------------------------------------------------------------------------
; Write note labels (or blank keys) depending on show_labels.
; Only screen codes change, so highlight colors are preserved.
draw_labels:
    ldx #KB_WIDTH-1
@Loop:
    lda #SOLID
    ldy show_labels
    beq >@Off
    lda labels,x
@Off:
    ldy coltype,x
    cpy #KT_WHITE
    bne >@NotWhite
    sta KB_ROW4,x
    bit kb2_on              ; upper keyboard shown? (bit 7)
    bpl >@NoUp4
    sta UKB_ROW4,x
@NoUp4:
@NotWhite:
    cpy #KT_BLACK
    bne >@Next
    sta KB_ROW2,x
    bit kb2_on
    bpl >@NoUp2
    sta UKB_ROW2,x
@NoUp2:
@Next:
    dex
    bpl <@Loop
    rts

;------------------------------------------------------------------------------
setup_sprites:
    lda #0
    sta SPR_ENABLE
    sta SPR_PRIO            ; all sprites in front of text
    sta SPR_MCOL            ; hi-res
    sta SPR_XEXP
    sta SPR_XMSB
    lda #$ff                ; all sprites Y-expanded
    sta SPR_YEXP
    lda #NO_NOTE
    ldx #TOTAL_SLOTS-1
@Slot:
    sta slot_note,x
    dex
    bpl <@Slot
    lda #0
    sta sh_en
    sta sh_en+1
    rts

;------------------------------------------------------------------------------
; Colour one key's cells.
; Input: A = colour, X = screen column, Y = rows (3 = black key, 6 = white)
; Preserves A, X, Y.
set_key_color:              ; on the keyboard in cur_kb
    pha
    lda cur_kb
    bne >@Upper
    pla
    sta KB_COLOR,x
    sta KB_COLOR+40,x
    cpy #2
    beq >@Done
    sta KB_COLOR+80,x
    sta KB_COLOR+120,x
    sta KB_COLOR+160,x
@Done:
    rts
@Upper:
    pla
    sta UKB_COLOR,x
    sta UKB_COLOR+40,x
    cpy #2
    beq >@Done
    sta UKB_COLOR+80,x
    sta UKB_COLOR+120,x
    sta UKB_COLOR+160,x
@Done:
    rts

;------------------------------------------------------------------------------
; Highlight a key.  Input: A = note, 0..31 (C .. G)
note_on:
    tay
    lda key_ch_lo,y         ; was any channel already holding this key?
    ora key_ch_hi,y
    sta key_was
    ldx snd_chan            ; add this channel to the key's holders
    cpx #8
    bcs >@HiCh
    lda key_ch_lo,y
    ora slot_mask,x
    sta key_ch_lo,y
    jmp >@Added
@HiCh:
    lda key_ch_hi,y
    ora slot_mask-8,x
    sta key_ch_hi,y
@Added:
    lda key_was
    beq >@NotLit
    rts                     ; already lit by another note: nothing to draw
@NotLit:
    ; fall through

; Draw a key's highlight (colour RAM + a sprite slot if one is free).
; Input: Y = key 0..63.  Upper keys are only drawn while that keyboard shows.
key_light:
    sty cur_note
    jsr key_kb              ; cur_kb, Y = key within its keyboard
    bcc >@Shown
    rts
@Shown:
    ldx note_col,y
    stx cur_col
    lda note_shape,y
    bne >@White
    lda hl_color            ; black key: colour RAM only
    ldy #2
    jmp set_key_color
@White:
    sta cur_shape
    lda hl_color
    ldy #5
    jsr set_key_color

    lda cur_kb              ; find a free sprite slot on this keyboard
    asl
    asl
    asl
    clc
    adc #NUM_SLOTS-1
    tax
    ldy #NUM_SLOTS
@Find:
    lda slot_note,x
    cmp #NO_NOTE
    beq >@Got
    dex
    dey
    bne <@Find
    rts                     ; none free: colour-only highlight
@Got:
    stx cur_slot
    lda cur_note
    sta slot_note,x
    lda cur_shape           ; shadow sprite registers; the raster
    sta sh_ptr,x            ; interrupt copies them to the VIC
    lda hl_color
    sta sh_col,x

    lda #0                  ; X position = col*8 + SPR_X_ADJ (9 bits)
    sta xhi
    lda cur_col
    asl
    asl
    asl
    rol xhi
    clc
    adc #SPR_X_ADJ
    bcc >@NoInc
    inc xhi
@NoInc:
    sta sh_x,x

    txa                     ; sprite bit for this slot
    and #7
    tay
    lda slot_mask,y
    sta cur_mask
    ldx cur_kb
    eor #$ff
    and sh_msb,x
    ldy xhi
    beq >@NoMsb
    ora cur_mask
@NoMsb:
    sta sh_msb,x
    lda sh_en,x
    ora cur_mask
    sta sh_en,x
    rts

; Key Y (0..63) -> cur_kb (0 lower, 1 upper) and Y = key within the keyboard.
; Carry set if it is an upper key while the upper keyboard is hidden.
key_kb:
    lda #0
    cpy #NUM_NOTES
    bcc >@Lower
    tya
    and #NUM_NOTES-1
    tay
    lda kb2_on
    bne >@Up
    sec
    rts
@Up:
    lda #1
@Lower:
    sta cur_kb
    clc
    rts

;------------------------------------------------------------------------------
; Remove a key's highlight.  Input: A = note, 0..31
note_off:
    tay
    ldx snd_chan            ; remove this channel from the key's holders
    lda slot_mask-0,x
    cpx #8
    bcc >@LoCh
    lda slot_mask-8,x
    eor #$ff
    and key_ch_hi,y
    sta key_ch_hi,y
    jmp >@Removed
@LoCh:
    eor #$ff
    and key_ch_lo,y
    sta key_ch_lo,y
@Removed:
    lda key_ch_lo,y         ; still held by another channel? stay lit
    ora key_ch_hi,y
    beq >@Unlight
    rts
@Unlight:
key_unlight:                ; Y = key 0..63: remove its highlight
    sty cur_note
    jsr key_kb
    bcc >@Shown
    rts                     ; upper keyboard hidden: nothing drawn
@Shown:
    ldx note_col,y
    lda note_shape,y
    bne >@White
    lda #BLACK
    ldy #2
    jmp set_key_color
@White:
    lda #WHITE
    ldy #5
    jsr set_key_color

    lda cur_kb              ; find its sprite slot on this keyboard
    asl
    asl
    asl
    clc
    adc #NUM_SLOTS-1
    tax
    ldy #NUM_SLOTS
@Find:
    lda slot_note,x
    cmp cur_note
    beq >@Got
    dex
    dey
    bne <@Find
    rts                     ; was a colour-only highlight
@Got:
    lda #NO_NOTE
    sta slot_note,x
    txa
    and #7
    tay
    lda slot_mask,y
    eor #$ff
    ldx cur_kb
    and sh_en,x
    sta sh_en,x
    rts

;------------------------------------------------------------------------------
; Turn off every lit key.
all_notes_off:
    ldx #NUM_KEYS-1
@Loop:
    lda key_ch_lo,x
    ora key_ch_hi,x
    beq >@Next
    lda #0
    sta key_ch_lo,x
    sta key_ch_hi,x
    stx loop_i
    txa
    tay
    jsr key_unlight
    ldx loop_i
@Next:
    dex
    bpl <@Loop
    rts

;==============================================================================
; MIDI input
;==============================================================================

; Select and reset an interface.  Input: A = interface index 0..NUM_IFACES-1
midi_select:
    pha
    jsr all_notes_off       ; the old interface can't send their Note Offs
    jsr sound_all_off
    sei                     ; no MIDI interrupts while switching
    jsr acia_off            ; silence the old interface's interrupts
    pla
    sta midi_iface
    tay
    lda if_ctrl,y
    sta midi_ctrl_off
    lda if_status,y
    sta midi_stat_off
    lda if_rx,y
    sta midi_rx_off

    ldx midi_ctrl_off
    lda #ACIA_RESET
    sta MIDI_IO,x
    lda if_ctrl_val,y       ; clock divider + 8N1, receive IRQ off
    sta MIDI_IO,x

    lda #0
    sta run_status
    sta data_count

    ; Is there really an ACIA here?  With nothing at these addresses the
    ; C64 reads "open bus" junk, which would look like random MIDI bytes.
    ; A real 6850 that hasn't transmitted always shows TDRE=1, FE=0, PE=0.
    sta midi_present
    ldx midi_stat_off
    ldy #0                  ; 256 reads
@Detect:
    lda MIDI_IO,x
    and #ACIA_CHECK_MASK
    cmp #ACIA_TDRE
    bne >@Show              ; not a 6850: leave midi_present = 0
    dey
    bne <@Detect
    inc midi_present
    ldy midi_iface          ; found: turn on receive interrupts
    lda if_ctrl_val,y
    ora #ACIA_RIE
    ldx midi_ctrl_off
    sta MIDI_IO,x
@Show:
    lda #0                  ; empty the ring buffer
    sta rx_head
    sta rx_tail
    cli

    ; show the interface name
    clc
    ldx #STATUS_ROW
    ldy #IFACE_COL
    jsr PLOT
    ldx midi_iface
    lda if_name_hi,x
    tay
    lda if_name_lo,x
    jsr print_str
    lda #$20                ; space
    jsr CHROUT
    lda #<text_found
    ldy #>text_found
    ldx midi_present
    bne >@Found
    lda #<text_missing
    ldy #>text_missing
@Found:
    jmp print_str

;------------------------------------------------------------------------------
; Parse every byte the interrupt handler has buffered.  Called from main_loop.
midi_poll:
    ldy rx_tail
    cpy rx_head
    beq >@Done
    lda RX_BUF,y
    inc rx_tail             ; only the main loop moves the tail
    jsr midi_byte
    jmp midi_poll
@Done:
    rts

;------------------------------------------------------------------------------
; Master-reset the current interface's ACIA (stops its interrupts).
acia_off:
    lda midi_present
    beq >@Done
    ldx midi_ctrl_off
    lda #ACIA_RESET
    sta MIDI_IO,x
    lda #0
    sta midi_present
@Done:
    rts

install_irq:
    sei
    lda IRQ_VECTOR
    sta old_irq
    lda IRQ_VECTOR+1
    sta old_irq+1
    lda NMI_VECTOR
    sta old_nmi
    lda NMI_VECTOR+1
    sta old_nmi+1
    lda #<irq_handler
    sta IRQ_VECTOR
    lda #>irq_handler
    sta IRQ_VECTOR+1
    lda #<nmi_handler
    sta NMI_VECTOR
    lda #>nmi_handler
    sta NMI_VECTOR+1
    lda VIC_CTRL1           ; raster compare line < 256
    and #$7f
    sta VIC_CTRL1
    lda #SPLIT_UPPER
    sta VIC_RASTER
    lda #0
    sta next_split
    lda #$ff
    sta VIC_IRQ             ; clear pending VIC interrupts
    lda #$01
    sta VIC_IRQEN           ; raster interrupt on
    cli
    rts

remove_irq:
    sei
    lda #0
    sta VIC_IRQEN           ; raster interrupt off
    lda #$ff
    sta VIC_IRQ
    jsr acia_off
    lda old_irq
    sta IRQ_VECTOR
    lda old_irq+1
    sta IRQ_VECTOR+1
    lda old_nmi
    sta NMI_VECTOR
    lda old_nmi+1
    sta NMI_VECTOR+1
    cli
    rts

;------------------------------------------------------------------------------
; IRQ (Sequential, Passport, Datel).  The KERNAL has already pushed A, X, Y.
irq_handler:
    lda #0
    sta irq_ours
    lda VIC_IRQ             ; raster interrupt: switch the sprite set
    and #$01
    beq >@NoRaster
    sta VIC_IRQ             ; acknowledge
    sta irq_ours
    jsr raster_split
@NoRaster:
    lda midi_present
    beq >@NoAcia
    ldx midi_stat_off
    lda MIDI_IO,x
    bpl >@NoAcia            ; bit 7 clear: not the ACIA
    jsr midi_rx_service
    lda #1
    sta irq_ours
@NoAcia:
    lda irq_ours
    beq >@Kernal            ; neither: it's the CIA timer
    lda CIA1_ICR            ; did the 1/60 s timer fire too? (acknowledges it)
    and #$01
    bne >@Kernal            ; yes: let the KERNAL do its jiffy work
    jmp KERNAL_IRQ_RTI      ; no: return without running it, so the jiffy
                            ; clock doesn't speed up
@Kernal:
    jmp (old_irq)

; Raster interrupt: at SPLIT_UPPER show the upper keyboard's sprites (or none),
; at SPLIT_LOWER the lower keyboard's.
raster_split:
    lda next_split
    bne >@Lower
    bit kb2_on
    bpl >@NoUpper
    jsr load_set1
    jmp >@Next
@NoUpper:
    lda #0
    sta SPR_ENABLE
@Next:
    lda #SPLIT_LOWER
    sta VIC_RASTER
    lda #1
    sta next_split
    rts
@Lower:
    jsr load_set0
    lda #SPLIT_UPPER
    sta VIC_RASTER
    lda #0
    sta next_split
    rts

load_set0:                  ; lower keyboard sprite set -> VIC
    ldx #7
@Loop:
    txa
    asl
    tay
    lda sh_x+0,x
    sta SPR_POS,y
    lda #SPR_Y
    sta SPR_POS+1,y
    lda sh_ptr+0,x
    sta SPR_PTRS,x
    lda sh_col+0,x
    sta SPR_COLOR0,x
    dex
    bpl <@Loop
    lda sh_msb+0
    sta SPR_XMSB
    lda sh_en+0
    sta SPR_ENABLE
    rts

load_set1:                  ; upper keyboard sprite set -> VIC
    ldx #7
@Loop:
    txa
    asl
    tay
    lda sh_x+8,x
    sta SPR_POS,y
    lda #SPR_Y2
    sta SPR_POS+1,y
    lda sh_ptr+8,x
    sta SPR_PTRS,x
    lda sh_col+8,x
    sta SPR_COLOR0,x
    dex
    bpl <@Loop
    lda sh_msb+1
    sta SPR_XMSB
    lda sh_en+1
    sta SPR_ENABLE
    rts


; NMI (Namesoft).  The KERNAL jumps here without saving any registers.
nmi_handler:
    pha
    txa
    pha
    tya
    pha
    lda midi_present
    beq >@NotUs
    ldx midi_stat_off
    lda MIDI_IO,x
    bpl >@NotUs
    jsr midi_rx_service
    pla
    tay
    pla
    tax
    pla
    rti
@NotUs:                     ; RESTORE key etc.: pass to the KERNAL
    pla
    tay
    pla
    tax
    pla
    jmp (old_nmi)

; Move every waiting byte from the ACIA into the ring buffer.
midi_rx_service:
@Loop:
    ldx midi_stat_off
    lda MIDI_IO,x
    and #ACIA_RDRF
    beq >@Done
    ldx midi_rx_off
    lda MIDI_IO,x           ; reading clears RDRF and the interrupt
    ldy rx_head
    sta RX_BUF,y
    iny
    cpy rx_tail
    beq <@Loop              ; buffer full: drop the byte
    sty rx_head
    jmp <@Loop
@Done:
    rts

;------------------------------------------------------------------------------
; MIDI parser: Note On / Note Off on any channel, with running status.
; Input: A = received byte
midi_byte:
    cmp #$f8                ; real-time (clock, active sensing, ...):
    bcc >@NotRealtime       ;   ignore, and leave running status alone
    rts
@NotRealtime:
    sta midi_data
    jsr show_hex
    jsr mon_log
    lda midi_data
    bpl >@Data

    ; status byte
    cmp #$f0                ; system common / SysEx: cancels running status
    bcc >@Channel
    lda #0
    sta run_status
    rts
@Channel:
    sta run_status
    lda #0
    sta data_count
    rts

@Data:
    lda run_status
    and #$f0
    cmp #$c0                ; Program Change: pick this channel's patch
    bne >@NotProg
    jmp program_change
@NotProg:
    lda run_status
    and #$e0                ; $8n (Note Off) and $9n (Note On) -> $80
    cmp #$80
    beq >@NoteMsg
    rts                     ; data for a message we don't use
@NoteMsg:
    lda data_count
    bne >@Velocity
    lda midi_data           ; 1st data byte: note number
    sta midi_note
    inc data_count
    rts
@Velocity:
    lda #0                  ; 2nd data byte: velocity; with running status
    sta data_count          ; the next data byte starts a new message
    ldx midi_data
    beq >@Off               ; Note On with velocity 0 = Note Off
    ldx run_status
    cpx #$90
    bcc >@Off               ; $8n

    lda midi_data           ; Note On: sound it, then light the key
    sta snd_vel
    lda run_status          ; this channel's instrument
    and #$0f
    tax
    lda chan_patch,x
    sta snd_patch
    stx snd_chan
    lda #0
    sta snd_drum
    cpx #DRUM_CH
    bne >@Melodic
    ldy midi_note           ; channel 10: GM drum note -> kit sound
    cpy #DRUM_FIRST
    bcc >@Out
    cpy #DRUM_LAST+1
    bcs >@Out
    lda drum_map-DRUM_FIRST,y
    beq >@Out               ; not in our kit
    sta snd_drum
    lda midi_note
    jmp sound_on            ; drums don't light keys
@Melodic:
    lda midi_note
    jsr sound_on
    jsr pick_color
    jsr key_index
    bcs >@Out
    jmp note_on
@Off:
    lda run_status
    and #$0f
    sta snd_chan
    cmp #DRUM_CH            ; drums play out; Note Off is ignored
    beq >@Out
    lda midi_note
    jsr sound_off
    jsr key_index
    bcs >@Out
    jmp note_off
@Out:
    rts

; Program Change (data byte in midi_data).  General MIDI groups programs in
; families of 8 (pianos, chromatic percussion, organs, guitars, basses, ...);
; each family maps to the nearest of our patches.
program_change:
    lda midi_data
    lsr
    lsr
    lsr
    tax
    lda gm_family_patch,x
    pha
    lda run_status
    and #$0f
    tax
    pla
    sta chan_patch,x
    jmp show_patch

; Keys 1-8.  Input: A = patch, for all 16 channels
set_all_patches:
    ldx #15
@Loop:
    sta chan_patch,x
    dex
    bpl <@Loop
    ; fall through

; Show patch A's name on the status line.
show_patch:
    asl
    asl
    asl                     ; 8 characters per name
    tax
    ldy #0
@Loop:
    lda patch_names,x
    and #$3f
    sta INST_SCREEN,y
    lda #WHITE
    sta INST_COLOR,y
    inx
    iny
    cpy #8
    bne <@Loop
    rts

; Highlight colour for the note sound_on just placed: voices alternate
; SID 1 / SID 2 (odd voice = SID 2) when there are two SIDs.
pick_color:
    lda #HILITE
    ldx sid2_base+1
    beq >@Store
    lda snd_voice
    lsr
    lda #HILITE
    bcc >@Store
    lda #HILITE2
@Store:
    sta hl_color
    rts

; MIDI note -> key index on the display.
; Output: A = index, carry clear if the key is on the display
key_index:
    lda midi_note
    sec
    sbc #KB_LOW_NOTE
    bcc >@Out
    cmp #NUM_NOTES
    bcc >@Done              ; lower keyboard: keys 0-31, carry clear
    lda midi_note
    sec
    sbc #KB2_LOW_NOTE
    bcc >@Out
    cmp #NUM_NOTES
    bcs >@Out
    ora #NUM_NOTES          ; upper keyboard: keys 32-63 (carry still clear)
@Done:
    rts
@Out:
    sec
    rts

;==============================================================================
; SID piano
;==============================================================================

sid_init:
    lda #0
    ldx #$18
@Clear:
    sta SID,x
    dex
    bpl <@Clear

    jsr detect_sid2         ; sets sid2_base (hi byte 0 = none)
    jsr build_voices
    lda sid2_base+1
    beq >@Mono
    sta VPTR+1              ; clear the second SID too, volume up
    lda sid2_base
    sta VPTR
    lda #0
    ldy #$18
@Clear2:
    sta (VPTR),y
    dey
    bpl <@Clear2
    lda #$0f
    ldy #$18
    sta (VPTR),y
@Mono:

    ldx voice_last
@Voice:
    jsr voice_ptr
    lda #$08                ; pulse width: set per patch at note start
    ldy #3
    sta (VPTR),y
    dex
    bpl <@Voice
    jsr sound_all_off       ; gate off, ADSR 0, settling
    lda #0
    sta next_voice
    lda JIFFY
    sta last_jiffy
    lda #$0f                ; full volume, no filter
    sta SID_VOLUME

    ; pick the frequency table for this machine's clock
    jsr detect_pal
    ldx #11
@Copy:
    lda is_pal
    beq >@Ntsc
    lda pal_lo,x
    sta freq_lo,x
    lda pal_hi,x
    sta freq_hi,x
    jmp >@Next
@Ntsc:
    lda ntsc_lo,x
    sta freq_lo,x
    lda ntsc_hi,x
    sta freq_hi,x
@Next:
    dex
    bpl <@Copy

    clc                     ; show which table is in use
    ldx #STATUS_ROW+1
    ldy #TUNING_COL
    jsr PLOT
    lda #<text_pal
    ldy #>text_pal
    ldx is_pal
    bne >@Show
    lda #<text_ntsc
    ldy #>text_ntsc
@Show:
    jsr print_str
    lda #$20
    jsr CHROUT
    ldx sid2_index          ; " d420" / " d500" / " df00" / " mono"
    lda sid2_name_lo,x
    ldy sid2_name_hi,x
    jmp print_str

;------------------------------------------------------------------------------
; Point VPTR at voice X's registers.  Preserves X and Y.
voice_ptr:
    lda v_base_lo,x
    sta VPTR
    lda v_base_hi,x
    sta VPTR+1
    rts

; Fill the voice table.  With two SIDs the voices alternate between the chips
; (S1, S2, S1, S2, ...) so chords spread across both stereo channels.
build_voices:
    ldx #0                  ; voice index
    ldy #0                  ; voice number on each chip
@Loop:
    lda sid1_voice_lo,y
    sta v_base_lo,x
    lda #>SID
    sta v_base_hi,x
    inx
    lda sid2_base+1
    beq >@Next              ; mono: only SID 1 voices
    lda sid2_base
    clc
    adc sid1_voice_lo,y     ; + 0 / 7 / 14 (no page crossing for $xx00/$xx20)
    sta v_base_lo,x
    lda sid2_base+1
    sta v_base_hi,x
    inx
@Next:
    iny
    cpy #3
    bne <@Loop
    dex
    stx voice_last
    rts

;------------------------------------------------------------------------------
; Look for a second SID at $D420, $D500, $DF00 ($DE00 is the MIDI interface).
; A candidate must
;   1. read OSC3 = $00 steadily while its voice 3 is held by the TEST bit
;      (empty I/O reads changing junk), then
;   2. show a changing OSC3 once voice 3 runs a fast sawtooth, while
;   3. SID 1's own OSC3 stays at $00: a "SID" at $D420 that is really the
;      $D400 chip seen through its address mirror would make SID 1 run too.
detect_sid2:
    lda #0
    sta sid2_base
    sta sid2_base+1
    lda #NUM_SID2_CANDIDATES-1
    sta sid2_index
@Candidate:
    lda #0                  ; SID 1 voice 3: sawtooth held at 0 by the
    sta $d40e               ; TEST bit, so its OSC3 ($d41b) reads $00
    sta $d40f               ; (with no waveform selected the output floats).
    lda #$28                ; Redone for every candidate: probing a mirror
    sta $d412               ; of SID 1 writes SID 1's own voice 3.
    ldx sid2_index
    lda sid2_cand_lo,x
    sta VPTR
    lda sid2_cand_hi,x
    sta VPTR+1

    lda #$ff                ; voice 3 at full speed, held by TEST
    ldy #$0e
    sta (VPTR),y
    iny
    sta (VPTR),y
    lda #$28                ; sawtooth + TEST
    ldy #$12
    sta (VPTR),y
    ldx #8                  ; 1. must read $00 every time
@Held:
    ldy #$1b
    lda (VPTR),y
    bne >@Reject
    jsr probe_delay
    dex
    bne <@Held

    lda #$20                ; sawtooth, TEST off: OSC3 starts climbing
    ldy #$12
    sta (VPTR),y
    lda #0
    sta probe_changes
    ldy #$1b
    lda (VPTR),y
    sta probe_last
    ldx #8
@Running:
    jsr probe_delay
    lda $d41b               ; 3. SID 1 must still be at $00
    bne >@Reject
    ldy #$1b                ; 2. the candidate must be moving
    lda (VPTR),y
    cmp probe_last
    beq >@Same
    sta probe_last
    inc probe_changes
@Same:
    dex
    bne <@Running
    lda probe_changes
    cmp #3
    bcc >@Reject

    lda VPTR                ; found one
    sta sid2_base
    lda VPTR+1
    sta sid2_base+1
    jsr >@Quiet
    jmp >@Done
@Reject:
    jsr >@Quiet
    dec sid2_index
    bmi >@None
    jmp <@Candidate         ; (too far back for a branch)
@None:
    lda #NUM_SID2_CANDIDATES ; index of the " mono" name
    sta sid2_index
@Done:
    lda #0                  ; SID 1 voice 3 back to normal
    sta $d412
    rts
@Quiet:
    lda #0                  ; candidate voice 3 off again
    ldy #$12
    sta (VPTR),y
    ldy #$0e
    sta (VPTR),y
    iny
    sta (VPTR),y
    rts

; About 300 cycles: OSC3's top byte moves about every 256 cycles at full speed
probe_delay:
    ldy #60
@Loop:
    dey
    bne <@Loop
    rts

;------------------------------------------------------------------------------
; PAL has 312 raster lines (last = $137), NTSC 263 or 262 (last = $106/$105).
; Watch the low byte while bit 8 is set and keep the highest value seen.
detect_pal:
@Wait1:
    lda VIC_CTRL1           ; wait for a line below 256...
    bmi <@Wait1
@Wait2:
    lda VIC_CTRL1           ; ...then for line 256
    bpl <@Wait2
    lda #0
    sta max_line
@Track:
    lda VIC_RASTER
    cmp max_line
    bcc >@Lower
    sta max_line
@Lower:
    lda VIC_CTRL1
    bmi <@Track
    ldx #0
    lda max_line
    cmp #$20                ; PAL reaches $37, NTSC only $06
    bcc >@Done
    inx
@Done:
    stx is_pal
    rts

;------------------------------------------------------------------------------
; Start a note.  Input: A = MIDI note
sound_on:
    cmp #SND_MAX_NOTE
    bcc >@InRange
    rts
@InRange:
    sta snd_note

    ; frequency: note = octave*12 + semitone
    ldy #0
@Div:
    cmp #12
    bcc >@DivDone
    sbc #12                 ; carry is set here
    iny
    bne <@Div               ; always (Y >= 1)
@DivDone:
    tax                     ; X = semitone
    lda freq_lo,x
    sta snd_lo
    lda freq_hi,x
    sta snd_hi
    sty snd_tmp             ; shift right 7 - octave times
    lda #7
    sec
    sbc snd_tmp
    tay
    beq >@Shifted
@Shift:
    lsr snd_hi
    ror snd_lo
    dey
    bne <@Shift
@Shifted:

    ; choose a voice: same note on the same channel (restrike) > ready >
    ; settling > releasing > the oldest busy one
    ldx voice_last
@Same:
    lda v_note,x
    cmp snd_note
    bne >@NotSame
    lda v_chan,x
    cmp snd_chan
    beq >@Got
@NotSame:
    dex
    bpl <@Same
    lda #VS_READY
    jsr find_state
    bcc >@Got
    lda #VS_SETTLING
    jsr find_state
    bcc >@Got
    lda #VS_RELEASING
    jsr find_state
    bcc >@Got
    ldx next_voice
@Got:
    lda snd_note
    sta v_note,x
    lda snd_chan
    sta v_chan,x
    lda snd_patch
    sta v_patch,x
    lda snd_drum
    sta v_drum,x
    lda snd_vel             ; sustain level = (velocity + 8) / 8: 1..15
    clc
    adc #8
    lsr
    lsr
    lsr
    cmp #16
    bcc >@LevelOk
    lda #15
@LevelOk:
    sta v_level,x
    lda snd_lo
    sta v_freq_lo,x
    lda snd_hi
    sta v_freq_hi,x
    lda #0
    sta v_relflag,x
    stx snd_voice
    inx                     ; round-robin pointer for stealing
    cpx voice_last
    beq >@NoWrap
    bcc >@NoWrap
    ldx #0
@NoWrap:
    stx next_voice
    ldx snd_voice

    lda v_state,x
    cmp #VS_READY
    bne >@NotReady
    jmp voice_start         ; settled: start right now
@NotReady:
    cmp #VS_SETTLING
    beq >@Wait              ; already resetting: let it finish
    cmp #VS_RESTART
    beq >@Wait              ; restart pending: just swap the note
    jmp voice_hard_restart  ; busy or releasing
@Wait:
    lda #VS_RESTART
    sta v_state,x
    rts

; Find a voice in state A.  Output: X = voice, carry clear if found
find_state:
    ldx voice_last
@Loop:
    cmp v_state,x
    beq >@Found
    dex
    bpl <@Loop
    sec
    rts
@Found:
    clc
    rts

;------------------------------------------------------------------------------
; Release a note.  Input: A = MIDI note
sound_off:
    sta snd_note
    ldx voice_last
@Find:
    lda v_note,x
    cmp snd_note
    bne >@Next
    lda v_chan,x
    cmp snd_chan
    bne >@Next
    lda v_state,x
    cmp #VS_BUSY
    beq >@Sounding
    cmp #VS_HIT
    bne >@NotBusy
@Sounding:
    jmp voice_release
@NotBusy:
    cmp #VS_RESTART         ; released before it even started:
    bne >@Next              ;   release it one tick after it starts
    lda #1
    sta v_relflag,x
    rts
@Next:
    dex
    bpl <@Find
    rts

;------------------------------------------------------------------------------
; Voice actions.  Input: X = voice.  All preserve X.

voice_start:                ; patch, frequency, hit envelope, gate on
    lda v_drum,x
    beq >@Melodic
    jmp drum_start
@Melodic:
    ldy v_patch,x
    lda p_wave,y
    sta v_wave,x
    lda p_pw,y
    sta snd_pw
    lda p_ad_hit,y
    sta snd_ad
    jsr voice_ptr
    lda v_freq_lo,x
    ldy #0
    sta (VPTR),y
    lda v_freq_hi,x
    ldy #1
    sta (VPTR),y
    lda #0
    ldy #2
    sta (VPTR),y
    lda snd_pw
    ldy #3
    sta (VPTR),y
    lda snd_ad
    ldy #5
    sta (VPTR),y
    lda v_wave,x            ; gate on BEFORE writing SR: with the gate off
    ora #GATE               ; the envelope is in release, and a new release
    ldy #4                  ; rate there would trigger the ADSR bug again
    sta (VPTR),y
    jsr write_sr
    lda #HIT_JIFFIES
    sta v_timer,x
    lda #VS_HIT
    sta v_state,x
    rts

write_sr:                   ; SR = sustain level / patch release
    jsr voice_ptr
    ldy v_patch,x
    lda v_level,x
    asl
    asl
    asl
    asl
    ora p_rel,y
    ldy #6
    sta (VPTR),y
    rts

voice_hard_restart:         ; gate off, ADSR 0, start after HR_JIFFIES
    jsr voice_ptr
    lda v_wave,x
    ldy #4
    sta (VPTR),y
    lda #0
    ldy #5
    sta (VPTR),y
    ldy #6
    sta (VPTR),y
    lda #HR_JIFFIES
    sta v_timer,x
    lda #VS_RESTART
    sta v_state,x
    rts

voice_release:              ; gate off: the patch's release plays out
    jsr voice_ptr
    lda v_wave,x
    ldy #4
    sta (VPTR),y
    lda #NO_NOTE
    sta v_note,x
    lda v_drum,x            ; wait out this sound's release before parking
    beq >@Patch
    tay
    lda dk_rel-1,y
    jmp >@Rel
@Patch:
    ldy v_patch,x
    lda p_rel,y
@Rel:
    tay
    lda release_jiffies,y
    sta v_timer,x
    lda #VS_RELEASING
    sta v_state,x
    rts

voice_park:                 ; silent now: zero ADSR so it can settle
    jsr voice_ptr
    lda #0
    ldy #5
    sta (VPTR),y
    ldy #6
    sta (VPTR),y
    lda #HR_JIFFIES
    sta v_timer,x
    lda #VS_SETTLING
    sta v_state,x
    rts

;------------------------------------------------------------------------------
; Called once per jiffy from the main loop.
sound_tick:
    ldx voice_last
@Loop:
    lda v_state,x
    cmp #VS_DRUM
    bne >@NotDrum
    jsr drum_tick
    jmp >@Next
@NotDrum:
    cmp #VS_HIT
    beq >@Sounding
    cmp #VS_BUSY
    bne >@Timed
@Sounding:
    lda v_relflag,x         ; a Note Off arrived during its restart
    beq >@Held
    lda #0
    sta v_relflag,x
    jsr voice_release
    jmp >@Next
@Held:
    dec v_timer,x
    bne >@Next
    ldy v_patch,x
    lda p_step,y
    bne >@Rearm
    lda #$ff                ; no fade: just wait (re-armed every 255 ticks)
@Rearm:
    sta v_timer,x
    lda v_state,x
    cmp #VS_HIT
    bne >@Step
    lda p_ad_hold,y         ; hit done: the patch's hold envelope
    pha                     ; (never a faster decay than the hit: ADSR bug)
    jsr voice_ptr
    pla
    ldy #5
    sta (VPTR),y
    lda #VS_BUSY
    sta v_state,x
    jmp >@Next
@Step:
    lda p_step,y            ; sustained patch: no fade
    beq >@Next
    lda v_level,x           ; fade: lower the sustain level one step
    beq >@Next
    dec v_level,x
    jsr write_sr
    jmp >@Next
@Timed:
    cmp #VS_READY
    beq >@Next
    dec v_timer,x
    bne >@Next
    lda v_state,x           ; timer ran out
    cmp #VS_RELEASING
    bne >@NotRel
    jsr voice_park
    jmp >@Next
@NotRel:
    cmp #VS_SETTLING
    bne >@NotSet
    lda #VS_READY
    sta v_state,x
    jmp >@Next
@NotSet:
    jsr voice_start         ; VS_RESTART: the reset is done, play
@Next:
    dex
    bmi >@Done
    jmp <@Loop              ; (too far back for a branch)
@Done:
    rts

;------------------------------------------------------------------------------
; Drums.  A drum program: first jiffy waveform/pitch (the click), then a
; second waveform whose pitch (hi byte) drops by "sweep" each jiffy; the gate
; goes off after "len" jiffies and the release plays out.  Input: X = voice.
drum_start:
    ldy v_drum,x
    dey                     ; kit index
    lda dk_wave2,y
    sta v_wave,x
    lda dk_f2,y             ; first tick subtracts sweep and lands on f2
    clc
    adc dk_sweep,y
    sta v_freq_hi,x
    lda dk_len,y
    sta v_timer,x
    lda dk_ad,y
    sta snd_ad
    lda dk_f1,y
    sta snd_lo
    lda dk_wave1,y
    sta snd_pw
    lda v_level,x           ; SR = velocity level / drum release
    asl
    asl
    asl
    asl
    ora dk_rel,y
    sta snd_hi
    lda #VS_DRUM
    sta v_state,x
    jsr voice_ptr
    lda #0
    ldy #0
    sta (VPTR),y
    lda snd_lo
    ldy #1
    sta (VPTR),y
    lda #$08                ; pulse width 50% for the pulse drums
    ldy #3
    sta (VPTR),y
    lda snd_ad
    ldy #5
    sta (VPTR),y
    lda snd_pw              ; gate on before SR (ADSR bug)
    ora #GATE
    ldy #4
    sta (VPTR),y
    lda snd_hi
    ldy #6
    sta (VPTR),y
    rts

drum_tick:
    ldy v_drum,x
    dey
    lda v_freq_hi,x         ; pitch drops by sweep, never below 1
    sec
    sbc dk_sweep,y
    bcc >@Floor
    bne >@PitchOk
@Floor:
    lda #1
@PitchOk:
    sta v_freq_hi,x
    jsr voice_ptr
    lda v_freq_hi,x
    ldy #1
    sta (VPTR),y
    lda v_wave,x
    ora #GATE
    ldy #4
    sta (VPTR),y
    dec v_timer,x
    bne >@Done
    jmp voice_release       ; drum over: gate off, release plays out
@Done:
    rts

;------------------------------------------------------------------------------
; Silence everything and start every voice's reset.
sound_all_off:
    ldx voice_last
@Loop:
    lda #NO_NOTE
    sta v_note,x
    lda #0
    sta v_relflag,x
    jsr voice_ptr
    lda v_wave,x
    ldy #4
    sta (VPTR),y
    jsr voice_park
    dex
    bpl <@Loop
    rts

;==============================================================================
; MIDI monitor window (CTRL-I)
;==============================================================================

mon_toggle:
    lda mon_on
    eor #1
    sta mon_on
    bit kb2_on              ; upper keyboard shown: only rows 0-6 are ours
    bmi >@Short
    jsr mon_clear           ; blank rows 0-12
    jmp >@Cleared
@Short:
    jsr mon_clear_short     ; blank rows 0-6
@Cleared:
    lda mon_on
    bne >@Show
    rts
@Show:
    lda #$20                ; empty line buffer
    ldx #39
@Buf:
    sta mon_line,x
    dex
    bpl <@Buf
    lda #0
    sta mon_status
    sta mon_need
    sta mon_got
    sta mon_col
    ldx #39                 ; title
@Title:
    lda mon_title_text,x
    and #$3f                ; PETSCII -> screen code
    sta MON_TITLE,x
    dex
    bpl <@Title
    rts

; Spaces on rows 0-6 (monitor above the upper keyboard).
mon_clear_short:
    ldx #0
@Loop:
    lda #$20
    sta $0400,x
    lda #MON_COLOR
    sta $d800,x
    inx
    bne <@Loop
    ldx #23                 ; $0500-$0517: rest of row 6
@Tail:
    lda #$20
    sta $0500,x
    lda #MON_COLOR
    sta $d900,x
    dex
    bpl <@Tail
    jmp mon_title_color

; Spaces on rows 0-12; title row white, log rows cyan.
mon_clear:
    ldx #0
@Loop:
    lda #$20
    sta $0400,x
    sta $0500,x
    lda #MON_COLOR
    sta $d800,x
    sta $d900,x
    inx
    bne <@Loop
    ldx #7                  ; $0600-$0607: end of row 12
@Tail:
    lda #$20
    sta $0600,x
    lda #MON_COLOR
    sta $da00,x
    dex
    bpl <@Tail
mon_title_color:
    ldx #39
    lda #WHITE
@TitleColor:
    sta $d800,x
    dex
    bpl <@TitleColor
    rts

;------------------------------------------------------------------------------
; CTRL-K: show / hide the upper keyboard (rows 8-12, shared with the monitor).
kb2_toggle:
    bit kb2_on
    bpl >@Show
    jsr kb2_hide
    lda mon_on
    bne >@Grow
    jmp mon_clear
@Grow:                      ; monitor back to rows 0-12: its 6 lines move
    ldx #240                ; down to rows 7-12, rows 1-6 are cleared
@GLoop:
    dex
    lda MON_ROWS_1_6,x
    sta MON_ROWS_7_12,x
    lda #$20
    sta MON_ROWS_1_6,x
    lda #MON_COLOR
    sta MON_COLOR_7_12,x
    txa
    bne <@GLoop
    rts
@Show:
    lda mon_on
    beq >@NoMon
    ldx #240                ; monitor shrinks to rows 0-6: keep its newest
@SLoop:                     ; 6 lines (rows 7-12 move up to rows 1-6)
    dex
    lda MON_ROWS_7_12,x
    sta MON_ROWS_1_6,x
    lda #$20
    sta MON_ROWS_7_12,x
    txa
    bne <@SLoop
    jmp >@Draw
@NoMon:
    jsr mon_clear
@Draw:
    lda #$80
    sta kb2_on
    jsr draw_keyboard2
    lda #HILITE             ; light the upper keys already held
    sta hl_color
    ldx #NUM_KEYS-1
@Loop:
    lda key_ch_lo,x
    ora key_ch_hi,x
    beq >@Next
    stx loop_i
    txa
    tay
    jsr key_light
    ldx loop_i
@Next:
    dex
    cpx #NUM_NOTES
    bcs <@Loop
    rts

; Hide the upper keyboard: free its sprite slots (the caller clears the rows).
kb2_hide:
    lda #0
    sta kb2_on
    sta sh_en+1
    lda #NO_NOTE
    ldx #TOTAL_SLOTS-1
@Loop:
    sta slot_note,x
    dex
    cpx #NUM_SLOTS
    bcs <@Loop
    rts

;------------------------------------------------------------------------------
; Log one MIDI byte (already filtered of real-time bytes).  Input: midi_data
mon_log:
    lda mon_on
    bne >@On
    rts
@On:
    jsr mon_log_body
    ; fall through

; Copy the line buffer to the monitor's bottom row.
mon_show_line:
    ldx #39
    bit kb2_on
    bmi >@Short
@Full:
    lda mon_line,x
    sta MON_BOTTOM,x
    dex
    bpl <@Full
    rts
@Short:
    lda mon_line,x
    sta MON_BOTTOM2,x
    dex
    bpl <@Short
    rts

mon_log_body:
    lda midi_data
    bpl >@Data
    cmp #$f7                ; End of SysEx: finish the SysEx line
    bne >@Status
    lda mon_status
    cmp #$f0
    beq >@Append
    lda midi_data
@Status:
    ; status byte: start a new line
    sta mon_status
    jsr mon_need_for
    lda #0
    sta mon_got
    jsr mon_newline
    lda mon_status
    jsr mon_hex
    jmp mon_label

@Data:
    lda mon_need
    beq >@Append            ; SysEx / unknown length
    lda mon_got
    cmp mon_need
    bne >@Append
    ; message complete and another data byte: running status
    lda #0
    sta mon_got
    jsr mon_newline
    lda #$2d                ; "--" in place of the omitted status byte
    sta mon_line
    sta mon_line+1
    lda #3
    sta mon_col
    jsr mon_label
@Append:
    lda mon_col
    cmp #MON_WRAP_COL
    bcc >@Room
    jsr mon_newline         ; long message: carry on below
    lda #3
    sta mon_col
@Room:
    lda midi_data
    jsr mon_hex
    inc mon_got
    lda mon_status          ; decode Note On / Note Off
    and #$e0
    cmp #$80
    bne >@Done
    lda mon_got
    cmp #1
    bne >@NotFirst
    lda midi_data
    sta mon_note
    rts
@NotFirst:
    cmp #2
    bne >@Done
    jmp mon_note_decode
@Done:
    rts

; Data bytes per message for status A.  0 = until the next status (SysEx)
mon_need_for:
    cmp #$f0
    bcs >@System
    lsr
    lsr
    lsr
    lsr
    tax
    lda mon_need_table-8,x
    sta mon_need
    rts
@System:
    and #$0f
    tax
    lda mon_sys_need,x
    sta mon_need
    rts

; Scroll the log up one line and clear the bottom line.
mon_newline:
    ldx #39
@Loop:
    lda $0450,x
    sta $0428,x
    lda $0478,x
    sta $0450,x
    lda $04a0,x
    sta $0478,x
    lda $04c8,x
    sta $04a0,x
    lda $04f0,x
    sta $04c8,x
    bit kb2_on              ; short monitor: rows 1-6 only
    bmi >@Short
    lda $0518,x
    sta $04f0,x
    lda $0540,x
    sta $0518,x
    lda $0568,x
    sta $0540,x
    lda $0590,x
    sta $0568,x
    lda $05b8,x
    sta $0590,x
    lda $05e0,x
    sta $05b8,x
@Short:
    lda #$20
    sta mon_line,x
    dex
    bmi >@Done
    jmp <@Loop
@Done:
    lda #0
    sta mon_col
    rts

; A as two hex digits at mon_col, then a space.
mon_hex:
    pha
    ldx mon_col
    lsr
    lsr
    lsr
    lsr
    tay
    lda hex_digits,y
    sta mon_line,x
    pla
    and #$0f
    tay
    lda hex_digits,y
    sta mon_line+1,x
    inx
    inx
    inx
    stx mon_col
    rts

; Message type label, and the channel for channel messages.
mon_label:
    lda mon_status
    lsr
    lsr
    lsr
    lsr
    sec
    sbc #8
    asl
    asl                     ; 4 characters per label
    tay
    ldx #0
@Loop:
    lda mon_labels,y
    and #$3f
    sta mon_line+MON_LABEL_COL,x
    iny
    inx
    cpx #4
    bne <@Loop
    lda mon_status
    cmp #$f0
    bcs >@Done
    lda #$03                ; "ch"
    sta mon_line+MON_CH_COL
    lda #$08
    sta mon_line+MON_CH_COL+1
    lda mon_status
    and #$0f
    clc
    adc #1
    ldx #MON_CH_COL+2
    jmp mon_decimal
@Done:
    rts

; Note name + octave and velocity for a complete Note On / Note Off.
mon_note_decode:
    lda mon_status
    cmp #$90
    bcc >@Name
    lda midi_data           ; Note On with velocity 0 is a Note Off
    bne >@Name
    ldx #3
@Off:
    lda mon_off_text,x
    and #$3f
    sta mon_line+MON_LABEL_COL,x
    dex
    bpl <@Off
@Name:
    lda mon_note            ; octave = note / 12 - 1 (middle C 60 = c4)
    ldy #0
@Div:
    cmp #12
    bcc >@DivDone
    sbc #12
    iny
    bne <@Div
@DivDone:
    asl                     ; 2 characters per name
    tax
    lda note_names,x
    and #$3f
    sta mon_line+MON_NOTE_COL
    lda note_names+1,x
    and #$3f
    sta mon_line+MON_NOTE_COL+1
    ldx #2                  ; "c4" or "c#4": octave after the name
    lda mon_line+MON_NOTE_COL+1
    cmp #$20
    bne >@Sharp
    dex
@Sharp:
    dey                     ; octave - 1
    bpl >@Oct
    lda #$2d                ; "-": MIDI notes 0-11 are octave -1
    bne >@PutOct
@Oct:
    tya
    ora #$30
@PutOct:
    sta mon_line+MON_NOTE_COL,x
    lda #$16                ; "v" + velocity
    sta mon_line+MON_VEL_COL
    lda midi_data
    ldx #MON_VEL_COL+1
    ; fall through

; A as decimal (no leading zeros) at mon_line+X.
mon_decimal:
    ldy #0
    sty mon_digits
@Hundreds:
    cmp #100
    bcc >@Tens0
    sbc #100
    iny
    bne <@Hundreds
@Tens0:
    cpy #0
    beq >@NoHundreds
    pha
    tya
    ora #$30
    sta mon_line,x
    inx
    inc mon_digits
    pla
@NoHundreds:
    ldy #0
@Tens:
    cmp #10
    bcc >@Ones
    sbc #10
    iny
    bne <@Tens
@Ones:
    pha
    lda mon_digits          ; print the tens digit if non-zero or if a
    bne >@PutTens           ; hundreds digit came before it
    cpy #0
    beq >@NoTens
@PutTens:
    tya
    ora #$30
    sta mon_line,x
    inx
@NoTens:
    pla
    ora #$30
    sta mon_line,x
    rts

;------------------------------------------------------------------------------
; Show A as two hex digits on the status line (last byte received).
show_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    tax
    lda hex_digits,x
    sta HEX_SCREEN
    pla
    and #$0f
    tax
    lda hex_digits,x
    sta HEX_SCREEN+1
    rts

;------------------------------------------------------------------------------
; Static status text above the keyboard.
draw_status:
    lda #WHITE
    sta TEXT_COLOR
    clc
    ldx #STATUS_ROW
    ldy #0
    jsr PLOT
    lda #<status_text
    ldy #>status_text
    jmp print_str

; Print a zero-terminated PETSCII string at the cursor.  Input: A/Y = lo/hi
print_str:
    sta SRC
    sty SRC+1
    ldy #0
@Loop:
    lda (SRC),y
    beq >@Done
    jsr CHROUT              ; preserves Y
    iny
    bne <@Loop
@Done:
    rts

code_end:                   ; (check-branches.py: code ends here)

    addrcheck $d000         ; code must stay below the I/O area

;------------------------------------------------------------------------------
; Static lookup tables, out of the crowded $C000 block.
;------------------------------------------------------------------------------
    orig TABLES

;------------------------------------------------------------------------------
; Data
;------------------------------------------------------------------------------
show_labels:    byte 1      ; labels on by default; CTRL-L toggles
loop_i:         byte 0
key_ch_lo:      area NUM_KEYS, 0    ; channels 1-8 holding each key (bits)
key_ch_hi:      area NUM_KEYS, 0    ; channels 9-16
key_was:        byte 0

; MIDI state
midi_iface:     byte 0
midi_present:   byte 0      ; 1 = an ACIA answered at this interface's address
midi_ctrl_off:  byte 0
midi_stat_off:  byte 0
midi_rx_off:    byte 0
run_status:     byte 0      ; current channel status byte, 0 = none
data_count:     byte 0      ; data bytes received for the current message
midi_note:      byte 0
midi_data:      byte 0
rx_head:        byte 0      ; written only by the interrupt handler
rx_tail:        byte 0      ; written only by the main loop
old_irq:        word 0
old_nmi:        word 0

; interface table:      Sequential Passport Datel Namesoft
if_ctrl:        byte    $00,       $08,     $04,  $00
if_status:      byte    $02,       $08,     $06,  $02
if_rx:          byte    $03,       $09,     $07,  $03
if_ctrl_val:    byte    $15,       $15,     $16,  $15   ; /16 (/64 Datel), 8N1
if_name_lo:     byte    <name_seq, <name_pass, <name_datel, <name_names
if_name_hi:     byte    >name_seq, >name_pass, >name_datel, >name_names

; names padded to the same length so a shorter one overwrites a longer one
name_seq:       ascii "sequential", 0
name_pass:      ascii "passport  ", 0
name_datel:     ascii "datel     ", 0
name_names:     ascii "namesoft  ", 0

text_found:     ascii "found    ", 0
text_missing:   ascii "not found", 0

status_text:
    ascii "midi: .......... .........", $0d
    ascii "in:   --", $0d
    ascii "f1 interface  1-8 sound  ctrl-k 2nd kb", $0d
    ascii "ctrl-l labels ctrl-i monitor stop exit", 0

; MIDI monitor
mon_on:         byte 0
mon_line:       area 40, $20  ; the newest monitor line, built here
mon_col:        byte 0
mon_status:     byte 0      ; status of the message on the current line
mon_need:       byte 0      ; data bytes per message, 0 = until next status
mon_got:        byte 0      ; data bytes so far
mon_note:       byte 0
mon_digits:     byte 0
mon_need_table: byte 2, 2, 2, 2, 1, 1, 2   ; $8n..$en
mon_sys_need:   byte 0, 1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
mon_labels:     ascii "off on  polycc  progpresbendsys "
mon_off_text:   ascii "off "
mon_title_text: ascii "midi monitor             ctrl-i: close  "
note_names:     ascii "c c#d d#e f f#g g#a a#b "

; SID state
voice_last:     byte 2      ; number of voices - 1 (2 or 5)
v_base_lo:      area MAX_VOICES, 0   ; register base of each voice
v_base_hi:      area MAX_VOICES, 0
sid1_voice_lo:  byte $00, $07, $0e
v_state:        area MAX_VOICES, VS_SETTLING
v_timer:        area MAX_VOICES, 0
v_note:         area MAX_VOICES, NO_NOTE  ; sounding or pending note
v_relflag:      area MAX_VOICES, 0
v_freq_lo:      area MAX_VOICES, 0
v_level:        area MAX_VOICES, 0  ; sustain level 0..15 (velocity, then fading)
v_freq_hi:      area MAX_VOICES, 0
v_patch:        area MAX_VOICES, 0
v_chan:         area MAX_VOICES, 0  ; MIDI channel of the voice's note
v_drum:         area MAX_VOICES, 0  ; 0 = instrument, else drum kit index + 1
v_wave:         area MAX_VOICES, $40  ; waveform bits of the patch now sounding

; second SID
NUM_SID2_CANDIDATES = 3
sid2_cand_lo:   byte $20, $00, $00
sid2_cand_hi:   byte $d4, $d5, $df
sid2_base:      word 0      ; 0 = none (mono)
sid2_index:     byte 0
sid2_name_lo:   byte <name_d420, <name_d500, <name_df00, <name_mono
sid2_name_hi:   byte >name_d420, >name_d500, >name_df00, >name_mono
name_d420:      ascii "d420", 0
name_d500:      ascii "d500", 0
name_df00:      ascii "df00", 0
name_mono:      ascii "mono", 0
probe_last:     byte 0
probe_changes:  byte 0
next_voice:     byte 0
last_jiffy:     byte 0
snd_note:       byte 0
snd_vel:        byte 0
snd_patch:      byte 0
snd_chan:       byte 0
snd_drum:       byte 0
snd_pw:         byte 0
snd_ad:         byte 0
chan_patch:     area 16, 0  ; instrument of each MIDI channel

; Patches.   wave: $10 triangle, $20 sawtooth, $40 pulse.  AD/SR as the SID's
; registers; hold decay must never be faster than the hit decay (ADSR bug).
;               piano harpsi organ guitar bass strings brass flute
p_wave:     byte $40,  $40,   $40,  $20,   $20, $20,    $20,  $10
p_pw:       byte $06,  $02,   $08,  $08,   $08, $08,    $08,  $08   ; pulse width hi
p_ad_hit:   byte $00,  $00,   $00,  $00,   $00, $80,    $50,  $60   ; attack/decay at hit
p_ad_hold:  byte $0a,  $09,   $00,  $09,   $0a, $88,    $58,  $68   ; after HIT_JIFFIES
p_rel:      byte $06,  $03,   $02,  $05,   $04, $09,    $05,  $06   ; release
p_step:     byte 8,    4,     0,    3,     6,   0,      0,    0     ; fade: jiffies/step
patch_names:    ascii "piano   harpsi  organ   guitar  bass    strings brass   flute   "
; GM program / 8 -> patch: piano chrom organ guitar bass strings ensemble brass
;                          reed pipe lead pad fx ethnic percussive sfx
gm_family_patch: byte 0, 1, 2, 3, 4, 5, 5, 6, 6, 7, 6, 5, 5, 3, 1, 0
snd_voice:      byte 0
snd_lo:         byte 0
snd_hi:         byte 0
snd_tmp:        byte 0
max_line:       byte 0
is_pal:         byte 1
freq_lo:        area 12, 0  ; the table in use, copied from PAL or NTSC
freq_hi:        area 12, 0

; octave 6 (MIDI 84-95):  C     C#    D     D#    E     F     F#    G     G#    A     A#    B
pal_lo:         byte    $9c,  $c0,  $23,  $c8,  $b4,  $eb,  $72,  $4c,  $80,  $12,  $08,  $68
pal_hi:         byte    $45,  $49,  $4e,  $52,  $57,  $5c,  $62,  $68,  $6e,  $75,  $7c,  $83
ntsc_lo:        byte    $0f,  $0c,  $46,  $bf,  $7d,  $84,  $d6,  $7a,  $73,  $c8,  $7d,  $97
ntsc_hi:        byte    $43,  $47,  $4b,  $4f,  $54,  $59,  $5e,  $64,  $6a,  $70,  $77,  $7e

text_pal:       ascii "sid: pal ", 0
text_ntsc:      ascii "sid: ntsc", 0

hex_digits:     byte $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$01,$02,$03,$04,$05,$06

rowbase:        byte 0
cur_note:       byte 0
cur_col:        byte 0
cur_shape:      byte 0
cur_slot:       byte 0
xhi:            byte 0
slot_note:      area TOTAL_SLOTS, NO_NOTE  ; slots 0-7 lower, 8-15 upper
sh_x:           area TOTAL_SLOTS, 0 ; shadow sprite registers per keyboard
sh_ptr:         area TOTAL_SLOTS, 0
sh_col:         area TOTAL_SLOTS, 0
sh_msb:         byte 0, 0
sh_en:          byte 0, 0
kb2_on:         byte 0          ; $80 = upper keyboard shown
next_split:     byte 0          ; 0: next raster IRQ is the upper split
irq_ours:       byte 0
cur_kb:         byte 0
cur_mask:       byte 0
hl_color:       byte HILITE     ; colour for the next note_on
slot_mask:      byte $01,$02,$04,$08,$10,$20,$40,$80   ; sprite bit for slot k

;------------------------------------------------------------------------------
; Sprite shapes. scatter packs these and copies them to $3700 at startup.
; px 0-2 = left sliver, px 3-10 = key column (colour RAM), px 11-14 = right
;------------------------------------------------------------------------------
; note (0..31) -> screen column of the key
note_col:
    ;    C  C# D  D# E  F  F# G  G# A  A# B
    byte 1, 2, 3, 4, 5, 7, 8, 9, 10,11,12,13
    byte 15,16,17,18,19,21,22,23,24,25,26,27
    byte 29,30,31,32,33,35,36,37

; note -> top sprite shape (0 = black key)
note_shape:
    byte SP_TOP_CF,0,SP_TOP_DGA,0,SP_TOP_EB,SP_TOP_CF,0,SP_TOP_DGA,0,SP_TOP_DGA,0,SP_TOP_EB
    byte SP_TOP_CF,0,SP_TOP_DGA,0,SP_TOP_EB,SP_TOP_CF,0,SP_TOP_DGA,0,SP_TOP_DGA,0,SP_TOP_EB
    byte SP_TOP_CF,0,SP_TOP_DGA,0,SP_TOP_EB,SP_TOP_CF,0,SP_TOP_EB  ; last G: no G# to its right

; column type for each of the 39 keyboard columns
coltype:
    byte KT_LEFT
    ;     C        C#       D        D#       E        gap     F        F#       G        G#       A        A#       B        gap
    byte KT_WHITE,KT_BLACK,KT_WHITE,KT_BLACK,KT_WHITE,KT_SEP,KT_WHITE,KT_BLACK,KT_WHITE,KT_BLACK,KT_WHITE,KT_BLACK,KT_WHITE,KT_SEP
    byte KT_WHITE,KT_BLACK,KT_WHITE,KT_BLACK,KT_WHITE,KT_SEP,KT_WHITE,KT_BLACK,KT_WHITE,KT_BLACK,KT_WHITE,KT_BLACK,KT_WHITE,KT_SEP
    byte KT_WHITE,KT_BLACK,KT_WHITE,KT_BLACK,KT_WHITE,KT_SEP,KT_WHITE,KT_BLACK,KT_WHITE
    byte KT_RIGHT

; label screen code for each column (reversed, so they show blue on the key)
labels:
    byte 0
    ;     C   C#      D   D#      E   gap F   F#      G   G#      A   A#      B   gap
    byte $83,SH_C+$80,$84,SH_D+$80,$85,0,$86,SH_F+$80,$87,SH_G+$80,$81,SH_A+$80,$82,0
    byte $83,SH_C+$80,$84,SH_D+$80,$85,0,$86,SH_F+$80,$87,SH_G+$80,$81,SH_A+$80,$82,0
    byte $83,SH_C+$80,$84,SH_D+$80,$85,0,$86,SH_F+$80,$87
    byte 0

; per-row glyph and color, indexed by column type
;         LEFT     WHITE  SEP       BLACK     RIGHT
row_glyph:
    byte G_LEDGE, SOLID, G_SEP,    SOLID,    G_REDGE    ; row 0 (screen row 20)
    byte G_LEDGE, SOLID, G_SEP,    SOLID,    G_REDGE    ; row 1 (sharp labels)
    byte G_LEDGE, SOLID, G_SEP,    G_SEP,    G_REDGE    ; row 2
    byte G_LEDGE, SOLID, G_SEP,    G_SEP,    G_REDGE    ; row 3 (note labels)
    byte G_LBOT,  SOLID, G_SEPBOT, G_SEPBOT, G_RBOT     ; row 4
row_color:
    byte WHITE,   WHITE, WHITE,    BLACK,    WHITE
    byte WHITE,   WHITE, WHITE,    BLACK,    WHITE
    byte WHITE,   WHITE, WHITE,    WHITE,    WHITE
    byte WHITE,   WHITE, WHITE,    WHITE,    WHITE
    byte WHITE,   WHITE, WHITE,    WHITE,    WHITE

; Sharp labels: letter in pixel cols 1-3, '#' in cols 5-7, rows 2-6
sharp_glyphs:
    byte $00,$00,$75,$47,$45,$47,$75,$00    ; C#
    byte $00,$00,$65,$57,$55,$57,$65,$00    ; D#
    byte $00,$00,$75,$47,$65,$47,$45,$00    ; F#
    byte $00,$00,$75,$47,$55,$57,$75,$00    ; G#
    byte $00,$00,$25,$57,$75,$57,$55,$00    ; A#

; Solid key shapes (set pixels = white key, clear = blue gap)
shape_glyphs:
    byte $f7,$f7,$f7,$f7,$f7,$f7,$f7,$f7    ; G_SEP     1px gap at col 4
    byte $f7,$f7,$f7,$f7,$f7,$f7,$e3,$c1    ; G_SEPBOT  gap widens: rounded corners
    byte $07,$07,$07,$07,$07,$07,$07,$07    ; G_LEDGE
    byte $01,$03,$07,$07,$07,$07,$07,$07    ; G_LTOP    (unused since the top row went)
    byte $07,$07,$07,$07,$07,$07,$03,$01    ; G_LBOT
    byte $f0,$f0,$f0,$f0,$f0,$f0,$f0,$f0    ; G_REDGE
    byte $c0,$e0,$f0,$f0,$f0,$f0,$f0,$f0    ; G_RTOP    (unused)
    byte $f0,$f0,$f0,$f0,$f0,$f0,$e0,$c0    ; G_RBOT

;------------------------------------------------------------------------------
; Drum kit.  Waveform $10 triangle, $20 saw, $40 pulse, $80 noise; f = pitch
; hi byte (x about 15 Hz); sweep = drop per jiffy; len = jiffies before gate off.
;           kick  snare chh   ohh   crash ride  ltom  mtom  htom
dk_wave1: byte $80, $40,  $80,  $80,  $80,  $80,  $80,  $80,  $80
dk_f1:    byte $20, $10,  $f0,  $f0,  $c0,  $c0,  $30,  $30,  $30
dk_wave2: byte $10, $80,  $80,  $80,  $80,  $80,  $40,  $40,  $40
dk_f2:    byte $0c, $28,  $f0,  $f0,  $c8,  $d0,  $0a,  $0e,  $12
dk_sweep: byte $02, $01,  $00,  $00,  $00,  $00,  $01,  $01,  $01
dk_len:   byte 3,   2,    1,    4,    6,    2,    4,    4,    4
dk_ad:    byte $08, $06,  $02,  $07,  $0a,  $08,  $08,  $08,  $07
dk_rel:   byte $05, $06,  $02,  $06,  $09,  $07,  $06,  $06,  $06
; SID release setting 0-15 -> jiffies until the release has died away
; (6 ms ... 24 s), after which the idle voice may be parked (ADSR zeroed)
release_jiffies: byte 2, 3, 4, 6, 8, 12, 14, 16, 19, 46, 91, 145, 181, 255, 255, 255

; GM drum notes 35-59 -> kit index + 1 (0 = not played)
;   1 kick 2 snare 3 closed hh 4 open hh 5 crash 6 ride 7 low tom 8 mid tom 9 high tom
drum_map:
    byte 1, 1, 3, 2, 2, 2, 7, 3, 7, 3      ; 35-44
    byte 7, 4, 8, 8, 5, 9, 6, 5, 6, 3      ; 45-54
    byte 5, 9, 5, 0, 6                     ; 55-59

    addrcheck RX_BUF        ; data must stay below the MIDI buffer


    orig SPR_DATA

; Y-expanded: each data row covers 2 raster lines; row 0 = keyboard line 0,
; so 20 rows cover the whole 40-line keyboard.
shape_top_cf:          ; $dc: black key on the right (C, F)
    bits ***.....................   ; lines 0-15: black-key zone
    bits ***.....................
    bits ***.....................
    bits ***.....................
    bits ***.....................
    bits ***.....................
    bits ***.....................
    bits ***.....................
    bits ***........****.........   ; lines 16-37: both slivers
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ..*........**...........   ; lines 38-39: rounded bottom corners
    bits ........................   ; (below the keyboard)
    align 64, 0

shape_top_eb:          ; $dd: black key on the left (E, B, last G)
    bits ...........****.........   ; lines 0-15: black-key zone
    bits ...........****.........
    bits ...........****.........
    bits ...........****.........
    bits ...........****.........
    bits ...........****.........
    bits ...........****.........
    bits ...........****.........
    bits ***........****.........   ; lines 16-37: both slivers
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ..*........**...........   ; lines 38-39: rounded bottom corners
    bits ........................   ; (below the keyboard)
    align 64, 0

shape_top_dga:         ; $de: black keys on both sides (D, G, A)
    bits ........................   ; lines 0-15: black-key zone
    bits ........................
    bits ........................
    bits ........................
    bits ........................
    bits ........................
    bits ........................
    bits ........................
    bits ***........****.........   ; lines 16-37: both slivers
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ***........****.........
    bits ..*........**...........   ; lines 38-39: rounded bottom corners
    bits ........................   ; (below the keyboard)
    align 64, 0

    addrcheck CHARSET
{endasm}
