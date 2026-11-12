#!/bin/bash
# fix-vice-avi.sh -- repair VICE 3.10 ZMBV/AVI recordings that play without sound.
#
# VICE's AVI writer stores the sound correctly but labels it with the wrong
# sample rate (48000 instead of VICE's actual rate, e.g. 22050) and splits
# stereo samples across packets, so players decode silence or errors.
# This pulls out the raw 16-bit stereo audio, works out the real rate from
# its size and the video's length, and writes a normal MP4 (H.264 + AAC).
#
# usage: fix-vice-avi.sh recording.avi [output.mp4]
set -euo pipefail
in="$1"
out="${2:-${in%.*}-fixed.mp4}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ffmpeg -v quiet -y -i "$in" -map 0:a -c copy -f s16le "$tmp/audio.raw"
bytes=$(stat -c %s "$tmp/audio.raw")
secs=$(ffprobe -v error -select_streams v -show_entries stream=duration -of csv=p=0 "$in")
rate=$(python3 -c "
b, s = $bytes, float('$secs')
est = b / 4 / s                               # 16-bit stereo frames per second
print(min((8000, 11025, 22050, 32000, 44100, 48000), key=lambda r: abs(r - est)))")
echo "audio: $bytes bytes over ${secs}s -> stereo ${rate} Hz"

ffmpeg -v warning -y -i "$in" -f s16le -ar "$rate" -ac 2 -i "$tmp/audio.raw" \
    -map 0:v -map 1:a -c:v libx264 -crf 18 -pix_fmt yuv420p \
    -vf "scale=iw*2:ih*2:flags=neighbor" -c:a aac -b:a 192k -shortest "$out"
echo "wrote $out"
