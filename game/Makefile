# Makefile for 'joystick.prg'
WINE = /usr/bin/wine
C1541 = c1541
C64LIST = $(WINE) ~/bin/c64list4_04.exe
CONVERT_LABELS = python3 ./c64list-to-vice-labels.py joystick.sym joystick-vice-labels

LAUNCH_X64SC = x64sc

joystick.prg: joystick.asm
	$(C64LIST) joystick.asm -prg

joystick.sym: joystick.asm
	$(C64LIST) joystick.asm -sym

joystick-vice-labels: joystick.sym
	$(CONVERT_LABELS) joystick.sym joystick-vice-labels

all: joystick.prg joystick-vice-labels

clean:
	rm -f joystick.prg joystick.sym joystick-vice-labels

test:
	# The "test" target just creates a few files for "make clean" to clean up
	touch joystick.prg joystick.sym joystick-vice-labels

monitor-commands:
	echo "ll \"vice-joystick-labels\"" > monitor-commands

vice: joystick.prg monitor-commands joystick-vice-labels
	# launch vice 3.7.1
	# enable vice's remote monitor?
	# killall vice
	$(LAUNCH_X64SC) \
	# fixes Kernal ROMs not being found in /usr/share/vice or something:
	-kernal ~/.local/share/vice/kernal-901246-01.bin \
	-basic /home/ryan/.local/share/vice/basic-901226-01.bin \
	-chargen /home/ryan/.local/share/vice/chargen-901225-01.bin \
	# enable IEC device 8, select device #8 as filesystem driver
	-iecdevice8 -device8 1 -fs8 "joystick.prg" \
	# joystick port 2 enabled, keyset/numeric keypad input,
	# load "joystick-vice-labels" for monitor debugging
	-moncommands "monitor-commands"
