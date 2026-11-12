# Makefile for MIDI keyboard display (midi.prg)
WINE        = /usr/bin/wine
C64LIST     = $(WINE) ~/bin/C64List4.06/c64List.exe     # 4.06+ needed for {scatter}
# VICE 3.10 built with --enable-midi (the x64sc on PATH has no MIDI)
LAUNCH_VICE = ~/Documents/c64/vice-3.10/src/x64sc
MIDI_TYPE   = 2        # 0 Sequential, 1 Passport, 2 Datel, 3 Namesoft
TARGET      = midi

# Second SID for 6 voices: $D420, $D500 or $DF00 (what midi.prg looks for).
# Empty = mono:  make vice SID2_ADDR=
# Note: your VICE saves settings on exit, so this also ends up in ~/.config/vice/vicerc.
SID2_ADDR   = 0xd420
SID2_FLAGS  = $(if $(strip $(SID2_ADDR)),-sidextra 1 -sid2address $(strip $(SID2_ADDR)),-sidextra 0)

all: $(TARGET).prg $(TARGET)-vice-labels check

# C64List silently mis-assembles out-of-range branches; this catches them.
check: $(TARGET).bas
	python3 check-branches.py $(TARGET).bas $(C64LIST)

# one C64List run produces the program, symbol table and listing
$(TARGET).prg $(TARGET).sym $(TARGET).lst &: $(TARGET).bas
	$(C64LIST) $(TARGET).bas -prg -sym -lst -ovr -origs

# C64List "name = $addr" -> VICE "al $addr .name"
# Only 4-digit values are kept, so constants like BLACK = $00 don't
# clutter the monitor's disassembly.
$(TARGET)-vice-labels: $(TARGET).sym
	echo "cl" > $@
	awk '{ sub(/\r$$/, "") } $$2 == "=" && length($$3) == 5 { print "al " $$3 " ." $$1 }' $< >> $@

monitor-commands: $(TARGET)-vice-labels
	echo 'll "$(TARGET)-vice-labels"' > $@

vice: $(TARGET).prg monitor-commands
	$(LAUNCH_VICE) -midi -miditype $(MIDI_TYPE) $(SID2_FLAGS) \
	    -moncommands monitor-commands -autostart $(TARGET).prg

# Record a demo video (song, keyboards, monitor, instruments) -> midi-demo-*.mp4
#   make demo            or   make demo SONG=jesu-joy-6voice.mid
SONG = two-chips-in-c.mid
demo: $(TARGET).prg monitor-commands
	VICE_CMD="$(LAUNCH_VICE) -midi -miditype $(MIDI_TYPE) $(SID2_FLAGS)" ./demo.sh $(SONG)

# Connect a virtual keyboard to VICE (run while both are open):
#   vmpk -> Edit/MIDI Connections -> output "VICE:MIDI in/out"
# or from a shell:  aconnect "MIDI Out" VICE   (VMPK's ALSA client name)
# Note: plain "x64sc" on PATH is VICE 3.8 without MIDI -- use "make vice".

clean:
	rm -f $(TARGET).prg $(TARGET).sym $(TARGET).lst \
	      $(TARGET)-vice-labels monitor-commands

.PHONY: all vice clean check demo
