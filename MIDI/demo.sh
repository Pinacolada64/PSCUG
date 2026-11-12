#!/bin/bash
# demo.sh -- record a demo video of midi.prg in VICE (run it via "make demo").
#
# Starts VICE like "make vice", plays a MIDI song into it, presses the
# program's keys on a timeline (upper keyboard, MIDI monitor, instruments,
# labels) and records the C64 screen plus VICE's sound to an MP4.
#
#   VICE runs as an X11 client (XWayland) so ffmpeg can capture its window;
#   its sound goes to a private PulseAudio/PipeWire sink that ffmpeg records
#   (looped back to your speakers so you can listen while it records);
#   key presses go into the C64 keyboard buffer through VICE's binary monitor
#   (one persistent connection; the text monitor can't do this in VICE 3.10:
#   it keeps the C64 stopped while connected and jams after a disconnect).
#   +saveres keeps the demo from changing your saved VICE settings, and it
#   logs to a temporary file instead of your usual VICE log.
#
# usage: demo.sh [song.mid] [output.mp4]      (keep the VICE window visible)
set -euo pipefail
cd "$(dirname "$0")"

SONG="${1:-two-chips-in-c.mid}"
OUT="${2:-midi-demo-$(date +%Y%m%d-%H%M%S).mp4}"
VICE_CMD="${VICE_CMD:-$HOME/Documents/c64/vice-3.10/src/x64sc -midi -miditype 2 -sidextra 1 -sid2address 0xd420}"
VICE_CMD="${VICE_CMD/#\~/$HOME}"     # a quoted ~ (from make) isn't expanded
MON_PORT=6599                        # binary monitor for the demo VICE
PORT_NAME="MIDIDEMO"                 # this VICE's ALSA MIDI port name
SINK="vice_demo"

# Timeline: seconds after recording starts, the key (C64 keyboard code), what.
#   0b CTRL-K upper keyboard   09 CTRL-I monitor   0c CTRL-L labels
#   31-38 keys 1-8 instrument
TIMELINE=(
    "6  0b  show the upper keyboard"
    "12 09  open the MIDI monitor (shares the top with the keyboard)"
    "18 36  instrument 6: strings"
    "24 0b  hide the upper keyboard (monitor grows back)"
    "29 31  instrument 1: piano"
    "32 0c  note labels off"
    "35 0c  note labels on"
    "38 0b  upper keyboard back (monitor shrinks)"
    "43 09  close the monitor"
)
SONG_START=2                         # seconds after recording starts

for t in ffmpeg xdotool aplaymidi pactl python3; do
    command -v $t >/dev/null || { echo "demo.sh: needs $t"; exit 1; }
done
[ -f "$SONG" ] || { echo "demo.sh: no song file $SONG"; exit 1; }

# The song's length (from its tempo map) sets the recording length.
SONG_SECS=$(python3 -I midiscan.py "$SONG" | awk '/^ length/ {print int($2 + 1.5)}')
LAST_KEY=$(printf '%s\n' "${TIMELINE[@]}" | awk '{print $1}' | sort -n | tail -1)
# ffmpeg needs ~3 s to start capturing, so the video runs ~3 s behind this
# timeline; the generous tail makes sure the end of the song is recorded.
DURATION=$(( SONG_START + SONG_SECS + 7 ))
(( DURATION < LAST_KEY + 4 )) && DURATION=$(( LAST_KEY + 4 ))
echo "demo: $SONG (${SONG_SECS}s), recording ${DURATION}s -> $OUT"

VPID=""; FPID=""; MOD_SINK=""; MOD_LOOP=""
VLOG=$(mktemp --suffix=.log)
DRIVER=$(mktemp --suffix=.py)
cleanup() {
    [ -n "$FPID" ] && kill "$FPID" 2>/dev/null || true
    [ -n "$VPID" ] && kill "$VPID" 2>/dev/null || true
    [ -n "$MOD_LOOP" ] && pactl unload-module "$MOD_LOOP" 2>/dev/null || true
    [ -n "$MOD_SINK" ] && pactl unload-module "$MOD_SINK" 2>/dev/null || true
    rm -f "$VLOG" "$DRIVER"
}
trap cleanup EXIT

make -s midi.prg monitor-commands

# private sound sink for VICE, looped back to the speakers
MOD_SINK=$(pactl load-module module-null-sink sink_name=$SINK sink_properties=device.description=VICE_demo)
MOD_LOOP=$(pactl load-module module-loopback source=$SINK.monitor latency_msec=40)

PULSE_SINK=$SINK GDK_BACKEND=x11 $VICE_CMD +saveres -logfile "$VLOG" -sounddev pulse \
    -midiname $PORT_NAME -binarymonitor -binarymonitoraddress 127.0.0.1:$MON_PORT \
    -moncommands monitor-commands -autostart midi.prg >/dev/null 2>&1 &
VPID=$!

WIN=""
for i in $(seq 1 80); do
    WIN=$(xdotool search --pid "$VPID" 2>/dev/null | tail -1 || true)
    [ -n "$WIN" ] && break; sleep 0.25
done
[ -n "$WIN" ] || { echo "demo.sh: VICE window not found"; exit 1; }
MIDIPORT=""
for i in $(seq 1 40); do
    MIDIPORT=$(aplaymidi -l | awk -v n="$PORT_NAME" 'NR>1 && $2==n {print $1; exit}')
    [ -n "$MIDIPORT" ] && break; sleep 0.25
done
[ -n "$MIDIPORT" ] || { echo "demo.sh: VICE MIDI port $PORT_NAME not found"; exit 1; }
sleep 8                                  # let autostart load and run the program

# Crop to the C64 screen: rows and columns that are mostly the blue screen
# colour (VICE's menu and status bar are not).
TMPF=$(mktemp --suffix=.png)
ffmpeg -v error -y -f x11grab -draw_mouse 0 -window_id "$WIN" -i "${DISPLAY:-:0}" -frames:v 1 "$TMPF"
CROP=$(python3 -I -c '
import sys
import numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int)
blue = (a[..., 2] > a[..., 0] + 60) & (a[..., 2] > a[..., 1] + 60)
cols = np.where(blue.mean(axis=0) > 0.30)[0]
rows = np.where(blue.mean(axis=1) > 0.10)[0]
x0, x1, y0, y1 = cols[0], cols[-1] + 1, rows[0], rows[-1] + 1
print(f"{(x1 - x0) // 2 * 2}:{(y1 - y0) // 2 * 2}:{x0}:{y0}")' "$TMPF")
rm -f "$TMPF"
echo "demo: capturing window $WIN, crop $CROP"

# Timeline driver: starts the song and presses the keys.
cat > "$DRIVER" <<'PYEOF'
import socket, struct, subprocess, sys, time
port, song_start, midiport, song = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3], sys.argv[4]
events = [line.split(None, 2) for line in sys.stdin if line.strip()]

# Minimal VICE binary-monitor client (protocol API version 2): commands stop
# the C64 briefly, EXIT (0xaa) resumes it; the connection stays open.
mon = socket.create_connection(('127.0.0.1', port), timeout=5)
rid = 0
def recv_exact(n):
    out = b''
    while len(out) < n:
        d = mon.recv(n - len(out))
        if not d:
            raise ConnectionError('VICE binary monitor closed')
        out += d
    return out
def command(ctype, body=b''):
    global rid
    rid += 1
    mon.sendall(struct.pack('<BBIIB', 2, 2, len(body), rid, ctype) + body)
    while True:                          # skip async events until our reply
        _, _, blen, _, err, r = struct.unpack('<BBIBBI', recv_exact(12))
        recv_exact(blen)
        if r == rid:
            if err:
                raise RuntimeError(f'binary monitor error {err:#x}')
            return
def mem_set(addr, data):                 # MEMORY_SET (0x02), main memory
    command(0x02, struct.pack('<BHHBH', 0, addr, addr + len(data) - 1, 0, 0) + bytes(data))
def press(code):                         # one key into the C64 keyboard buffer
    mem_set(0x0277, [code])
    mem_set(0x00c6, [1])
    command(0xaa)                        # EXIT: resume the C64

start = time.time()

def wait(at):
    d = start + at - time.time()
    if d > 0:
        time.sleep(d)

wait(song_start)
player = subprocess.Popen(['aplaymidi', '-p', midiport, song])
for at, key, what in events:
    wait(float(at))
    print(f'  {at}s: {what}', flush=True)
    press(int(key, 16))
player.wait()
mon.close()
PYEOF

ffmpeg -v error -y \
    -f x11grab -draw_mouse 0 -window_id "$WIN" -framerate 50 -i "${DISPLAY:-:0}" \
    -f pulse -i "$SINK.monitor" \
    -t "$DURATION" -vf "crop=$CROP" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k "$OUT" &
FPID=$!

printf '%s\n' "${TIMELINE[@]}" | python3 -I "$DRIVER" "$MON_PORT" "$SONG_START" "$MIDIPORT" "$SONG"
wait "$FPID"; FPID=""
kill "$VPID" 2>/dev/null || true          # +saveres: nothing is saved on exit
wait "$VPID" 2>/dev/null || true; VPID=""
echo "demo: wrote $OUT"
