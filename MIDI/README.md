# MIDI keyboard display and SID player (C64)

`midi.prg` shows two on-screen keyboards that light up from MIDI input and
plays the notes on one or two SID chips (3 or 6 voices), with instruments,
velocity, drums on channel 10 and a MIDI monitor.

## Building and running

| Command | What it does |
|---|---|
| `make` | Builds `midi.prg` with C64List 4.06, makes VICE labels, and runs `check-branches.py` |
| `make vice` | Runs it in VICE 3.10 with a MIDI cartridge and a second SID at `$D420` (`make vice SID2_ADDR=` for mono) |

Keys: **F1** MIDI interface, **1–8** instrument, **CTRL-K** upper keyboard,
**CTRL-I** MIDI monitor, **CTRL-L** note labels, **RUN/STOP** exit.

## Files

| File | Purpose |
|---|---|
| `midi.bas` | Program source (C64List format: BASIC stub + assembly) |
| `check-branches.py` | Fails the build on out-of-range 6502 branches, which C64List assembles silently |
| `midiscan.py` | Prints a MIDI file's tracks, channels, programs, note ranges and polyphony |
| `reduce6.py` | Reduces a multi-part MIDI file to 6 simultaneous notes for the player |
| `fix-vice-avi.sh` | Repairs the sound in VICE 3.10 ZMBV/AVI recordings |
| `*.mid` | Test songs (below) |
| `midi.prg` | Prebuilt program, for running without C64List: `LOAD"MIDI",8` then `RUN` |

## Songs

**`two-chips-in-c.mid`** — original six-voice test piece written for this
project.

**`jesu-joy.mid`** — *Jesu, Joy of Man's Desiring* by Johann Sebastian Bach
(cantata BWV 147, 1723; public domain). Short arrangement written for this
project from memory.

**`jesu-joy-6voice.mid`** — *Jesu, Joy of Man's Desiring* by J. S. Bach
(BWV 147, public domain), reduced to 6 voices from the MIDI file
`Jesu-Joy-Of-Man-Desiring-1.mid` downloaded from BitMidi:
<https://bitmidi.com/jesu-joy-of-man-desiring-1-mid>.
BitMidi does not credit an arranger or sequencer for that file and states no
licence for it.

```
python3 reduce6.py Jesu-Joy-Of-Man-Desiring-1.mid jesu-joy-6voice.mid \
    "4:0:73,2:1:68,3:2:48,5:3:19,1:4:48" \
    "Jesu, Joy of Man's Desiring (Bach) - 6 voices for midi.prg"
```

**`penny-lane-6voice.mid`** (not included in this repository) — *Penny Lane*
by John Lennon and Paul McCartney (The Beatles, 1967). The song is under
copyright, so the reduction is not distributed here; recreate it for personal
use with the command below. Reduced to 6 voices plus drums from the MIDI file
`14_Magical_Mystery_Tour__Penny_Lane.mid` (download source not recorded; its
sequencer is not credited in the file).

```
python3 reduce6.py 14_Magical_Mystery_Tour__Penny_Lane.mid penny-lane-6voice.mid \
    "1:0:16,9:1:56,7:2:33,10:3:0,4:4:73,5:5:61,2:6:52,3:7:52,6:8:1" \
    "Penny Lane - 6 voices + drums for midi.prg"
```

The `reduce6.py` spec is a list of `channel:priority:program`: channels not
listed (doubled parts) are dropped, priority 0 is kept first when more than
6 notes would sound, and the program picks the player's instrument
(General MIDI program number; families of 8 map to the 8 SID patches).

## Acknowledgements

The sources the program relies on (C64List, VICE, the KERNAL, SID and ACIA
documentation, the MIDI specifications and C64 programming techniques) are
credited in the comment block at the top of the assembly in `midi.bas`.
