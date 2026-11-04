#!/bin/bash
# One lock per device (by serial), shared by every project and worktree on this machine,
# so parallel tasks never drive the same emulator or phone at the same time.
#
#   device-lock.sh pick              lock a free, ready device and print its serial
#                                    (a physical device first, then an emulator)
#   device-lock.sh acquire <serial>  lock one device
#   device-lock.sh release <serial>  unlock it (only its holder; --force for any)
#   device-lock.sh status            list the locks
#
# Exit codes: 0 done, 1 busy or nothing free, 2 wrong usage.
# A lock older than 30 minutes is reported as maybe abandoned. It is never removed on
# its own: the user decides.
set -u

root="${AW_LOCK_DIR:-$HOME/.android/android-workflow-locks}"
holder="${AW_LOCK_HOLDER:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
adb="${AW_ADB:-adb}"
stale=1800

# describe <lock dir>: who holds it and for how long.
describe() {
  local by since age
  by=$(cat "$1/holder" 2>/dev/null)
  since=$(cat "$1/since" 2>/dev/null || echo 0)
  age=$(($(date +%s) - since))
  printf 'held by %s for %d min' "${by:-?}" $((age / 60))
  [ "$age" -gt "$stale" ] && printf ', maybe abandoned'
  printf '\n'
}

acquire() {
  local lock="$root/$1.lock"
  mkdir -p "$root"
  # mkdir is atomic: of two tasks asking at once, only one creates the folder.
  if mkdir "$lock" 2>/dev/null; then
    echo "$holder" > "$lock/holder"
    date +%s > "$lock/since"
    return 0
  fi
  [ "$(cat "$lock/holder" 2>/dev/null)" = "$holder" ] && return 0
  echo "busy $1: $(describe "$lock")" >&2
  return 1
}

case "${1:-}" in
  acquire)
    [ -n "${2:-}" ] || { echo "usage: $0 acquire <serial>" >&2; exit 2; }
    acquire "$2"
    ;;
  release)
    [ -n "${2:-}" ] || { echo "usage: $0 release <serial> [--force]" >&2; exit 2; }
    lock="$root/$2.lock"
    [ -d "$lock" ] || exit 0
    if [ "$(cat "$lock/holder" 2>/dev/null)" != "$holder" ] && [ "${3:-}" != --force ]; then
      echo "not yours $2: $(describe "$lock")" >&2
      exit 1
    fi
    rm -rf "$lock"
    ;;
  status)
    for lock in "$root"/*.lock; do
      [ -d "$lock" ] || continue
      echo "$(basename "$lock" .lock): $(describe "$lock")"
    done
    ;;
  pick)
    serials=$("$adb" devices 2>/dev/null | awk -F'\t' 'NR > 1 && $2 == "device" { print $1 }')
    if [ -z "$serials" ]; then
      echo "no device connected and ready (adb devices)" >&2
      exit 1
    fi
    # Physical devices first: their serials don't start with "emulator-".
    for serial in $(printf '%s\n' "$serials" | grep -v '^emulator-') \
      $(printf '%s\n' "$serials" | grep '^emulator-'); do
      if acquire "$serial" 2>/dev/null; then
        echo "$serial"
        exit 0
      fi
    done
    echo "every device is busy:" >&2
    for serial in $serials; do
      echo "  $serial: $(describe "$root/$serial.lock")" >&2
    done
    exit 1
    ;;
  *)
    echo "usage: $0 pick | acquire <serial> | release <serial> [--force] | status" >&2
    exit 2
    ;;
esac
