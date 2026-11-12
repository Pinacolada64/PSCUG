#!/usr/bin/env python3
"""Catch out-of-range branches that C64List assembles silently.

C64List 4.06 does not report a 6502 branch whose target is more than
-128/+127 bytes away: it quietly emits a garbage offset (usually $FF).
This script assembles a copy of the source WITHOUT {scatter} (so the listing
shows real addresses instead of packed data) and without the remote sprite
block, then checks that every branch in the code lands on an instruction.

usage: check-branches.py <source.bas> <c64list command...>
"""
import os, re, subprocess, sys, tempfile

BRANCHES = {'10', '30', '50', '70', '90', 'b0', 'd0', 'f0'}

def main():
    src, c64list = sys.argv[1], sys.argv[2:]
    text = open(src).read().replace('{scatter}\n', '')
    a = text.index('    orig SPR_DATA')          # drop the remote sprite block
    b = text.index('{endasm}', a)
    text = text[:a] + text[b:]
    # keep the table block right after the code (no backward orig without
    # {scatter}); branch offsets don't depend on where the tables live
    text = '\n'.join(line for line in text.split('\n')
                     if not line.strip().startswith(('orig TABLES', 'addrcheck')))

    with tempfile.TemporaryDirectory(dir='.') as tmp:
        name = os.path.join(tmp, 'check.bas')
        open(name, 'w').write(text)
        subprocess.run(c64list + [name, '-lst', '-sym', '-ovr'],
                       cwd=tmp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        lst = open(os.path.join(tmp, 'check.lst'), errors='replace').read().splitlines()
        sym = {}
        for line in open(os.path.join(tmp, 'check.sym'), errors='replace'):
            parts = line.split()
            if len(parts) == 3 and parts[1] == '=':
                sym[parts[0]] = int(parts[2].lstrip('$'), 16)

    code_end = sym['code_end']           # label at the end of the code
    rows = []
    for line in lst:
        m = re.match(r'\s*([0-9a-f]{4})  ((?:[0-9a-f]{2} ?)+)\s+(.*)', line)
        if m:
            addr = int(m.group(1), 16)
            if 0xc000 <= addr < code_end:
                rows.append((addr, m.group(2).split(), m.group(3).strip()))
    starts = {addr for addr, _, _ in rows}
    bad = []
    count = 0
    for addr, code, text in rows:
        if code[0] in BRANCHES and len(code) == 2:
            count += 1
            offset = (int(code[1], 16) ^ 0x80) - 0x80
            if addr + 2 + offset not in starts:
                bad.append(f'  ${addr:04x}: {text}')
    if count == 0:
        print('check-branches: found no branches at $c000 -- the scratch build did '
              'not assemble as expected (a {directive} in a comment?)')
        sys.exit(1)
    if bad:
        print(f'check-branches: {len(bad)} branch(es) out of range '
              '(use "bmi/bne >@skip" + "jmp <@target"):')
        print('\n'.join(bad))
        sys.exit(1)
    print(f'check-branches: {count} branches OK (code $c000-${code_end:04x})')

if __name__ == '__main__':
    main()
