#!/bin/zsh
# Copyright 2026 The Hum Authors
# SPDX-License-Identifier: Apache-2.0
#
# Turns a raw iPhone simulator recording (1206 x 2622) into an App Store app preview:
# 886 x 1920, 30 fps H.264 with a silent stereo AAC track. Usage: convert.sh <raw.mov> <out.mp4> [hold-seconds]
HOLD=${3:-0}
ffmpeg -v error -y -i "$1" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -filter_complex "[0:v]fps=30,scale=886:-2,crop=886:1920,tpad=stop_mode=clone:stop_duration=$HOLD,format=yuv420p[v]" \
  -map "[v]" -map 1:a -c:v libx264 -profile:v high -level 4.0 -b:v 8M -maxrate 10M -bufsize 16M \
  -c:a aac -b:a 256k -ar 44100 -shortest -movflags +faststart "$2"
ffprobe -v error -show_entries format=duration -show_entries stream=codec_name,width,height,avg_frame_rate,channels,sample_rate -of compact "$2"
