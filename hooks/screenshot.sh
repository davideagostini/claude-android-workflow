#!/bin/bash
# A screenshot of one device that is really a PNG.
#
#   screenshot.sh <serial> <file.png>
#
# It tries `android screen capture` first. On an emulator with two displays that command
# says "Screenshot written" but the file holds the "Multiple displays" warning, not a PNG.
# Then it falls back to `adb exec-out screencap` on the first display listed by
# SurfaceFlinger. Exit codes: 0 PNG written, 1 no PNG, 2 wrong usage.
set -u

serial="${1:-}"
out="${2:-}"
if [ -z "$serial" ] || [ -z "$out" ]; then
  echo "usage: $0 <serial> <file.png>" >&2
  exit 2
fi
android="${AW_ANDROID:-android}"
adb="${AW_ADB:-adb}"

# The 8-byte PNG signature.
is_png() {
  [ -s "$1" ] && [ "$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ]
}

"$android" screen capture --device="$serial" --output="$out" >/dev/null 2>&1
if is_png "$out"; then
  echo "$out"
  exit 0
fi

display=$("$adb" -s "$serial" shell dumpsys SurfaceFlinger --display-id 2>/dev/null \
  | awk '/^Display [0-9]+/ { print $2; exit }')
if [ -n "$display" ]; then
  "$adb" -s "$serial" exec-out screencap -p -d "$display" > "$out" 2>/dev/null
else
  "$adb" -s "$serial" exec-out screencap -p > "$out" 2>/dev/null
fi
if is_png "$out"; then
  echo "$out (adb screencap, display ${display:-default})"
  exit 0
fi

rm -f "$out"
echo "screenshot failed on $serial: neither android screen capture nor adb screencap wrote a PNG" >&2
exit 1
