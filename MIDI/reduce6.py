"""Reduce a multi-part MIDI file to at most 6 simultaneous notes for midi.prg.

usage: reduce6.py <in.mid> <out.mid> <spec> [title]
spec: comma-separated "channel:priority:program" (channel 1-16 as in the
file, priority 0 = most important, program = GM program to send).
Channels not listed (drums, doubled parts) are dropped.
A note that would make 7 bumps the lowest-priority sounding note (cut short,
or dropped if it started at the same tick) or is itself dropped if it is the
lowest.  The same pitch on two channels uses two voices.
"""
import sys
sys.path.insert(0, '.')
from midiscan import parse

PRIORITY = {}; PROGRAMS = {}
for item in sys.argv[3].split(','):
    ch, pr, pg = (int(x) for x in item.split(':'))
    PRIORITY[ch - 1] = pr; PROGRAMS[ch - 1] = pg
TITLE = (sys.argv[4] if len(sys.argv) > 4 else 'arranged for midi.prg').encode('latin1')[:120]
MAXV = 6

fmt, div, tracks = parse(sys.argv[1])
ev = []          # (tick, order, kind, data)  order: 0 meta/prog, 1 note-off, 2 note-on
for tr in tracks:
    for t, k, a, b in tr:
        if k == 'meta' and a == 0x51:
            ev.append((t, 0, 'tempo', b))
        elif k == 'ch' and a & 0xf0 in (0x80, 0x90) and (a & 15) in PRIORITY:
            on = a & 0xf0 == 0x90 and b[1] > 0
            ev.append((t, 2 if on else 1, 'on' if on else 'off', (a & 15, b[0], b[1])))
ev.sort(key=lambda e: (e[0], e[1]))

# Drums (channel 10) are one-shot in the player: a hit holds a voice for about
# 150 ms whatever the file's note length, so budget them that way.
DRUM_CH = 9
if DRUM_CH in PRIORITY:
    us = next((int.from_bytes(d, 'big') for t, o, k, d in ev if k == 'tempo'), 500000)
    hit = max(1, round(0.150 / (us / 1e6 / div)))
    fixed = []
    for t, order, kind, d in ev:
        if kind in ('on', 'off') and d[0] == DRUM_CH:
            if kind == 'on':
                fixed.append((t, order, kind, d)); fixed.append((t + hit, 1, 'off', (d[0], d[1], 0)))
            continue                          # file's own drum note-offs dropped
        fixed.append((t, order, kind, d))
    ev = sorted(fixed, key=lambda e: (e[0], e[1]))

out = []          # (tick, order, bytes)
for c, p in PROGRAMS.items():
    out.append((0, 0, bytes([0xc0 | c, p])))
sounding = {}     # (channel, pitch) -> (start tick, index of its note-on in out)
kept = {}; dropped = {}; bumped = 0
for t, order, kind, d in ev:
    if kind == 'tempo':
        out.append((t, 0, b'\xff\x51\x03' + d)); continue
    c, n, v = d
    if kind == 'off':
        if (c, n) in sounding:
            del sounding[(c, n)]; out.append((t, 1, bytes([0x80 | c, n, 0])))
        continue
    if (c, n) in sounding:                         # repeated note on the same channel
        out.append((t, 1, bytes([0x80 | c, n, 0]))); del sounding[(c, n)]
    if len(sounding) >= MAXV:
        worst = max(sounding, key=lambda cn: PRIORITY[cn[0]])
        if PRIORITY[worst[0]] <= PRIORITY[c]:
            dropped[c] = dropped.get(c, 0) + 1; continue
        wstart, widx = sounding.pop(worst)
        if wstart == t:                            # started this same tick: drop it
            out[widx] = None
            kept[worst[0]] -= 1; dropped[worst[0]] = dropped.get(worst[0], 0) + 1
        else:                                      # cut it short
            out.append((t, 1, bytes([0x80 | worst[0], worst[1], 0]))); bumped += 1
    sounding[(c, n)] = (t, len(out)); kept[c] = kept.get(c, 0) + 1
    out.append((t, 2, bytes([0x90 | c, n, v])))
out = [e for e in out if e is not None]
out.sort(key=lambda e: e[0])      # stable: keeps the simulation's order within a tick

# verify
held = set(); peak = 0
for t, o, m in out:
    if m[0] & 0xf0 == 0x90: held.add((m[0] & 15, m[1])); peak = max(peak, len(held))
    elif m[0] & 0xf0 == 0x80: held.discard((m[0] & 15, m[1]))
for c in sorted(PRIORITY, key=PRIORITY.get):
    k, d = kept.get(c, 0), dropped.get(c, 0)
    print(f'  ch{c+1:2} priority {PRIORITY[c]} program {PROGRAMS[c]:3}: kept {k:4}  dropped {d:4}  ({k/max(1,k+d):.0%})')
print(f'  notes cut short to make room: {bumped}; max simultaneous: {peak}')
assert peak <= MAXV

def vlq(x):
    b = [x & 0x7f]; x >>= 7
    while x: b.insert(0, (x & 0x7f) | 0x80); x >>= 7
    return bytes(b)
data = vlq(0) + b'\xff\x03' + bytes([len(TITLE)]) + TITLE
last = 0
for t, o, m in out:
    data += vlq(t - last) + m; last = t
data += vlq(0) + b'\xff\x2f\x00'
open(sys.argv[2], 'wb').write(b'MThd' + (6).to_bytes(4, 'big') + (0).to_bytes(2, 'big') + (1).to_bytes(2, 'big')
                              + div.to_bytes(2, 'big') + b'MTrk' + len(data).to_bytes(4, 'big') + data)
