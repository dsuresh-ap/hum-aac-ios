#!/bin/zsh
# Copyright 2026 The Hum Authors
# SPDX-License-Identifier: Apache-2.0
#
# Makes the Mac App Store screenshots (2880 x 1800). Run it from Terminal, which needs
# Screen Recording permission (System Settings > Privacy & Security). Each shot opens a
# separate test copy of Hum with an in-memory demo board, so your own boards aren't touched.
#
# Usage: docs/app-store/mac-screenshots.sh /path/to/Debug/Hum.app
set -e
APP=${1:?Pass the path to a Debug build of Hum.app (Product > Show Build Folder in Xcode)}
OUT=${0:a:h}/screenshots/mac
mkdir -p $OUT

shot() {
  local name=$1; shift
  open -n "$APP" --args -uiTesting "$@"
  sleep 6
  local pid=$(pgrep -nf "$APP/Contents/MacOS/Hum")
  local win=$(swift -e "
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
print(list.first { (\$0[kCGWindowOwnerPID as String] as? Int32) == $pid && (\$0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowNumber as String] ?? 0)")
  screencapture -x -o -l$win $OUT/raw.png
  kill $pid
  # Shrink the window only if it doesn't fit inside 2880 x 1800, then fill the rest with Hum's light teal.
  local w=$(sips -g pixelWidth $OUT/raw.png | awk '/pixelWidth/{print $2}')
  local h=$(sips -g pixelHeight $OUT/raw.png | awk '/pixelHeight/{print $2}')
  if (( w > 2760 || h > 1700 )); then sips --resampleHeightWidthMax 1700 $OUT/raw.png --out $OUT/raw.png >/dev/null; fi
  if (( $(sips -g pixelWidth $OUT/raw.png | awk '/pixelWidth/{print $2}') > 2760 )); then sips --resampleWidth 2760 $OUT/raw.png --out $OUT/raw.png >/dev/null; fi
  sips --padToHeightWidth 1800 2880 --padColor D6E6E6 $OUT/raw.png --out $OUT/$name.png >/dev/null 2>&1
  rm $OUT/raw.png
  echo "$OUT/$name.png"
}

shot 1-child-board -skipFirstRun -demoFolder -demoHistory
shot 2-grown-up-editor -skipFirstRun -demoFolder -startInParent
shot 3-dark-mode -skipFirstRun -demoFolder -demoHistory -darkMode
shot 4-welcome
