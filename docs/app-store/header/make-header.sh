#!/bin/zsh
# Copyright 2026 The Hum Authors
# SPDX-License-Identifier: Apache-2.0
#
# Draws the three header and search results assets next to this script, as PNGs with no alpha
# channel (App Store Connect refuses images with transparency). Needs ffmpeg.
set -e
cd ${0:a:h}
for asset in universal:universal-5244x2950 header:header-3840x1646 search:search-results-3840x2560; do
  swift make-header.swift ${asset%%:*} raw.png
  ffmpeg -v error -y -i raw.png -pix_fmt rgb24 ${asset##*:}.png
  rm raw.png
  echo "${asset##*:}.png"
done
