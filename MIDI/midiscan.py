"""Minimal Standard MIDI File reader: parses bytes only, executes nothing."""
import sys

def read_vlq(d, i):
    v = 0
    while True:
        b = d[i]; i += 1
        v = (v << 7) | (b & 0x7f)
        if not b & 0x80:
            return v, i

def parse(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'MThd', 'not a MIDI file'
    hlen = int.from_bytes(d[4:8], 'big')
    fmt, ntrk, div = (int.from_bytes(d[8+k:10+k], 'big') for k in (0, 2, 4))
    i = 8 + hlen
    tracks = []
    for _ in range(ntrk):
        assert d[i:i+4] == b'MTrk'
        ln = int.from_bytes(d[i+4:i+8], 'big'); j = i + 8; end = j + ln
        t = 0; rs = 0; ev = []
        while j < end:
            dt, j = read_vlq(d, j); t += dt
            b = d[j]
            if b == 0xff:
                typ = d[j+1]; ml, k = read_vlq(d, j+2)
                ev.append((t, 'meta', typ, d[k:k+ml])); j = k + ml
            elif b in (0xf0, 0xf7):
                ml, k = read_vlq(d, j+1); ev.append((t, 'sysex', b, d[k:k+ml])); j = k + ml
            else:
                if b & 0x80: rs = b; j += 1
                n = 1 if (rs & 0xf0) in (0xc0, 0xd0) else 2
                ev.append((t, 'ch', rs, tuple(d[j:j+n]))); j += n
        tracks.append(ev); i = end
    return fmt, div, tracks

if __name__ == '__main__':
    fmt, div, tracks = parse(sys.argv[1])
    print(f'format {fmt}, {len(tracks)} tracks, {div} ticks/quarter')
    tempos = []; progs = {}; notes = {}; allev = []
    for ti, tr in enumerate(tracks):
        names = [m[3].decode('latin1') for m in tr if m[1] == 'meta' and m[2] in (3, 4)]
        chs = sorted({m[2] & 15 for m in tr if m[1] == 'ch'})
        non = sum(1 for m in tr if m[1] == 'ch' and m[2] & 0xf0 == 0x90 and m[3][1] > 0)
        print(f' track {ti}: names={names} channels={[c+1 for c in chs]} note-ons={non}')
        for t, kind, a, b in tr:
            if kind == 'meta' and a == 0x51: tempos.append((t, int.from_bytes(b, 'big')))
            if kind == 'meta' and a == 0x58: print(f'   time signature at {t}: {b[0]}/{2**b[1]}')
            if kind == 'ch':
                c = a & 15; s = a & 0xf0
                if s == 0xc0: progs.setdefault(c, []).append((t, b[0]))
                if s in (0x80, 0x90): allev.append((t, 1 if (s == 0x90 and b[1] > 0) else 0, c, b[0], b[1]))
    print(' tempos (tick, bpm):', [(t, round(60e6/u, 1)) for t, u in tempos[:6]], '...' if len(tempos) > 6 else '')
    print(' programs:', {c+1: p for c, p in progs.items()})
    allev.sort(key=lambda e: (e[0], e[1]))
    held = {}; peak = 0; per = {}
    for t, on, c, n, v in allev:
        if on:
            held[(c, n)] = t; peak = max(peak, len(held))
            p = per.setdefault(c, [999, 0, 0, 0, 0]); p[0] = min(p[0], n); p[1] = max(p[1], n); p[2] += 1
            p[3] = min(p[3] or 127, v) if p[3] else v; p[4] = max(p[4], v)
        else:
            held.pop((c, n), None)
    for c, (lo, hi, cnt, vlo, vhi) in sorted(per.items()):
        print(f' ch{c+1:2}: {cnt:4} notes, range {lo}-{hi}, velocity {vlo}-{vhi}')
    print(' max simultaneous notes:', peak)
    last = max(e[0] for e in allev)
    # duration using the tempo map
    tempos = sorted(tempos) or [(0, 500000)]
    secs = 0; tp = 0; us = 500000
    for t, u in tempos + [(last, None)]:
        secs += (min(t, last) - tp) * us / div / 1e6; tp = min(t, last)
        if u: us = u
    print(f' length {secs:.1f} s')
