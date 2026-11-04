# PETSCII Robots SNES gamepad test

A C64 test program for the "Attack of the PETSCII Robots" user port SNES
gamepad adapter. It reads the pad and shows a `*` under the label of each
button being held. Press STOP to exit to BASIC.

It runs on real hardware, or in VICE 3.8, which emulates the adapter.

## Files

| File | What it is |
|---|---|
| `snes_controller_code.asm` | Source, in C64List 4.06 format |
| `snes_controller_code.prg` | Assembled program (loads at `$0801`, runs with `RUN`) |
| `snes_joypad_keyboard_keys.cfg` | VICE settings for using the keyboard as the SNES pad |

## Assembling

C64List is a Windows program, so on Linux run it with Wine. From this folder:

```
wine ~/bin/C64List4.06/c64List.exe snes_controller_code.asm -prg -ovr
```

- `-prg` writes `snes_controller_code.prg` next to the source.
- `-ovr` overwrites the old `.prg` without asking.

A good build ends with `0 Errors; 0 Warnings`. Wine may also print a warning
that wine32 is missing; the 64-bit `c64List.exe` runs without it.

The source uses `{alpha:alt}`, so capital letters in the `ascii` strings become
shifted PETSCII and the text shows in mixed case (the program switches the C64
to upper/lowercase mode before printing).

## Running in VICE

Run these from this folder. Otherwise give the full paths to the `.cfg` and
`.prg` files.

### With the keyboard

```
x64sc -addconfig snes_joypad_keyboard_keys.cfg -autostart snes_controller_code.prg
```

`snes_joypad_keyboard_keys.cfg` sets up everything:

- the PETSCII SNES pad on the user port (`UserportDevice=18`)
- a joystick in the adapter's port (`JoyPort3Device=1`), driven by Keyset 1
  (`JoyDevice3=2`, shown as Keyset A in the menus)
- no device in joystick ports 1 and 2, so they can't take the keypad keys first
- all 12 SNES buttons on the keypad

Turn Num Lock on. The keypad layout:

```
 7 Lb   8 Up   9 Rb          + Y
 4 Lf   5 --   6 Rt
 1 Sl   2 Dn   3 St
 0 A           . B      Enter X
```

The config clears Keyset 1's diagonals, so 7, 9, 1 and 3 work as buttons.

### With a USB gamepad

```
x64sc -userportdevice 18 -controlport3device 1 -extrajoydev1 4 -autostart snes_controller_code.prg
```

`4` is the first host gamepad, and VICE only looks for one at startup, so plug
it in first (`ls /dev/input/js*` should list it). Its D-pad or stick drives the
directions, and its buttons go to A, B, X, Y, Lb, Rb, Select and Start in that
order. Remap them under *Settings → Input devices → Joystick*.

### Saving the settings

*Settings → Save settings* copies everything in effect into
`~/.config/vice/vicerc`, including ports 1 and 2 set to no device. After that
they stay that way in every session until you change them back.

## Screen

```
"Attack of the PetSCII Robots"
User port adapter - SNES gamepad test

STOP exits to BASIC.


  RbLbX A RtLfDnUpStSlY B
                             <- * under each held button

Up D-pad up       Dn D-pad down
Lf D-pad left     Rt D-pad right
A  A button       B  B button
X  X button       Y  Y button
Lb Left shoulder  Rb Right shoulder
Sl Select         St Start

* = pressed
```

## How it reads the pad

The adapter uses CIA #2 port B (`$dd01`):

| Bit | Direction | Line |
|---|---|---|
| 3 | output | clock |
| 5 | output | latch |
| 6 | input | data (low = pressed) |

The program pulses latch, then reads 16 bits, pulsing clock after each. The
first 12 bits are B, Y, Select, Start, Up, Down, Left, Right, A, X, Lb and Rb.
The last 4 aren't buttons, so the display skips them.
