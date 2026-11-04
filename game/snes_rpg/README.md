# Slime Cellar

A tiny one-screen RPG for the C64 and the "Attack of the PETSCII Robots" user
port SNES gamepad adapter. Find the key, unlock the door, and take the stairs
down. Slimes, gold, potions and bombs are in the way.

It combines the block-moving idea from `../joystick.asm` with the pad reading
from `../snes_controller/snes_controller_code.asm`.

## Buttons

| Button | What it does |
|---|---|
| D-pad | Walk. You turn to face that way even when something blocks you |
| B (hold) | Run while walking |
| A | Act on the tile you face: hit a slime, unlock a door |
| X | Look at the tile you face |
| Y | Use the selected item: drink a potion (+3 HP) or throw a bomb |
| L / R | Select the potion or the bomb |
| Start | Pause / resume; play again after the game ends |
| Select | Show / hide a readout of the pad's buttons on the bottom row |
| STOP | Quit to BASIC |

These follow the usual SNES RPG habits: A to act, B to run or back off, X/Y for
the extra commands, L/R to flip through choices, Start to pause, Select for
something extra.

## The map

```
@ you        $ gold       k key        D locked door    > stairs
S big slime  s small slime  ! potion   * bomb           # wall
```

- A big slime takes two hits. The first hit turns it into a small slime, and it
  hits back for 2 HP. The second hit kills it, and it leaves a gold coin.
- A bomb destroys the wall or slime you face. The outer wall is too thick.
  Three rooms of gold are sealed in, and there are two bombs...
- You start with 9 HP and one potion. At 0 HP the game is over.

## Assembling

From this folder:

```
wine ~/bin/C64List4.06/c64List.exe snes_rpg.asm -prg -ovr
```

A good build ends with `0 Errors; 0 Warnings`. Add `-sym` for a symbol file
(`snes_rpg.sym`) to use with the VICE monitor.

## Running in VICE

The game uses the same VICE settings as the SNES test program. With the keyboard
(Num Lock on; see `../snes_controller/README.md` for the keypad map):

```
x64sc -addconfig ../snes_controller/snes_joypad_keyboard_keys.cfg -autostart snes_rpg.prg
```

With a USB gamepad:

```
x64sc -userportdevice 18 -controlport3device 1 -extrajoydev1 4 -autostart snes_rpg.prg
```

## How it works

- **Timing:** the main loop runs once per jiffy (1/60 s) by waiting for the
  KERNAL's jiffy clock at `$a2` to change.
- **Pad:** `read_pad` reads 16 bits from the adapter (clock = bit 3, latch =
  bit 5, data = bit 6 of `$dd01`) into `pad1` (B, Y, Select, Start, Up, Down,
  Left, Right) and `pad2` (A, X, L, R), with 1 meaning pressed. `new1`/`new2`
  hold the buttons that were just pressed, so one press does one thing.
- **World:** the screen is the map. Each tile is a screen code (see the `T_`
  equates), so the game checks what's ahead by reading screen memory, and
  changes the world by writing to it. `put_tile` sets each tile's color too.
- **Map data:** 21 rows of 40 characters in `map_data`, written as plain text.
  `#` becomes a solid block, and `@` marks the player's start.
- **Text:** strings are PETSCII (built with `{alpha:alt}`), and `pet2scr`
  converts them to screen codes as they are written to the screen.
