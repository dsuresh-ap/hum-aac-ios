#!/bin/zsh
# Copyright 2026 The Hum Authors
# SPDX-License-Identifier: Apache-2.0
#
# Turns a raw screen recording into an App Store app preview: 30 fps H.264 (11 Mbps, High 4.0) with a
# silent stereo AAC track, 15 to 30 seconds long.
#
# Usage: make-preview.sh <raw.mov> <out.mp4> <WxH> <fill|fit|window> [start-seconds] [hold-seconds] [length-seconds]
#   fill    covers WxH and crops the edges (a screen that already has the right shape: iPhone, iPad)
#   fit     fits inside WxH on Hum's background color (a screen of another shape: iPhone Duo)
#   window  a Mac window on Hum's light teal, like the Mac screenshots
#   start   seconds to skip at the beginning; hold: seconds to keep the last frame at the end;
#   length  seconds of the recording to keep after start (all of it if left out)
set -e
IN=$1; OUT=$2; W=${3%x*}; H=${3#*x}; MODE=$4; START=${5:-0}; HOLD=${6:-0}; LENGTH=${7:+-t $7}
case $MODE in
  fill)   VIDEO="[0:v]fps=30,scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1" ;;
  fit)    VIDEO="[0:v]fps=30,scale=$W:$H:force_original_aspect_ratio=decrease,pad=$W:$H:(ow-iw)/2:(oh-ih)/2:color=0xE9EDF0,setsar=1" ;;
  # The window's rounded corners (radius 12) become see-through, so no desktop shows around them.
  window) R=12; IN_CORNER="lte(pow(max(max($R-X\,X-(W-1-$R))\,0)\,2)+pow(max(max($R-Y\,Y-(H-1-$R))\,0)\,2)\,$((R * R)))"
          VIDEO="color=c=0xD6E6E6:s=${W}x${H}:r=30[bg];[0:v]fps=30,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*$IN_CORNER',scale=-2:$((H * 92 / 100))[win];[bg][win]overlay=(W-w)/2:(H-h)/2:shortest=1,setsar=1" ;;
  *) echo "mode must be fill, fit or window" >&2; exit 1 ;;
esac
ffmpeg -v error -y -ss "$START" ${=LENGTH} -i "$IN" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -filter_complex "$VIDEO,tpad=stop_mode=clone:stop_duration=$HOLD,format=yuv420p[v]" \
  -map "[v]" -map 1:a -c:v libx264 -profile:v high -level 4.0 -b:v 11M -maxrate 12M -bufsize 22M \
  -c:a aac -b:a 256k -ar 44100 -shortest -movflags +faststart "$OUT"
ffprobe -v error -show_entries format=duration -show_entries stream=codec_name,width,height,avg_frame_rate,channels \
  -of compact "$OUT"
