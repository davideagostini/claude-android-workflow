#!/bin/bash
# How long the Stop hook's build checks take in a project.
#
#   build-stats.sh [<dir>]                     the current branch
#   build-stats.sh [<dir>] --branch <branch>   one branch
#   build-stats.sh [<dir>] --all               every branch of the project
#
# It reads android-workflow-builds.log in the project's common git dir, written by
# verify-build.sh: one line per build, tab separated: date, branch, task, seconds, result.
set -u

dir=.
if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
  dir="$1"
  shift
fi
scope=branch
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
case "${1:-}" in
  --all) scope=all ;;
  --branch)
    [ -n "${2:-}" ] || { echo "usage: $0 [<dir>] [--branch <branch> | --all]" >&2; exit 2; }
    branch="$2"
    ;;
  "") ;;
  *) echo "usage: $0 [<dir>] [--branch <branch> | --all]" >&2; exit 2 ;;
esac

common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
  echo "not a git repository: $dir" >&2
  exit 1
}
log="$common/android-workflow-builds.log"

if [ "$scope" = all ]; then
  label="all branches"
  lines=$(cat "$log" 2>/dev/null)
else
  label="branch ${branch:-detached}"
  lines=$(awk -F'\t' -v b="${branch:-detached}" '$2 == b' "$log" 2>/dev/null)
fi

if [ -z "$lines" ]; then
  echo "$label: no build checks"
  exit 0
fi

# LC_ALL=C: a decimal point, whatever the system language (it would print 50,5 in Italian).
printf '%s\n' "$lines" | LC_ALL=C awk -F'\t' -v label="$label" '
  { secs[NR] = $4; if ($5 != "ok") failed++ }
  END {
    n = NR
    # Sort the durations (insertion sort: logs are small).
    for (i = 2; i <= n; i++) { v = secs[i]; j = i - 1
      while (j > 0 && secs[j] + 0 > v + 0) { secs[j + 1] = secs[j]; j-- }
      secs[j + 1] = v }
    median = (n % 2) ? secs[(n + 1) / 2] : (secs[n / 2] + secs[n / 2 + 1]) / 2
    printf "%s: %d build checks, %d failed, median %g s, longest %d s\n", label, n, failed, median, secs[n]
  }'
