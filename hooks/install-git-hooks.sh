#!/bin/bash
# Installs the plugin's git hooks (pre-commit, pre-push) in a repository, as copies.
#
#   install-git-hooks.sh <dir>           install or update them
#   install-git-hooks.sh <dir> --check   only report: missing | current <v> | outdated <v> | blocked <why>
#
# The hooks go in the repository's common git dir, so every worktree shares them, and
# they are never committed. They are copies, not links to the plugin: the installed
# plugin lives in a folder named after its version, which changes on every update.
# It never overwrites a hook it did not install, and it steps aside when
# core.hooksPath is set (husky, lefthook...).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-.}"
mode="${2:-install}"

version=$(jq -r '.version // "unknown"' "$here/../.claude-plugin/plugin.json" 2>/dev/null)
if ! common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>&1); then
  # Say what git said: "not a repository" is only one of the reasons it can fail.
  echo "blocked git failed in $dir: $(printf '%s' "$common" | head -1)"
  exit 1
fi
hooks="$common/hooks"
marker='# android-workflow-hook'

if path=$(git -C "$dir" config --get core.hooksPath); then
  echo "blocked core.hooksPath is set ($path): the project manages its hooks with another tool"
  exit 3
fi

state=current
for name in pre-commit pre-push; do
  target="$hooks/$name"
  if [ ! -e "$target" ]; then
    state=missing
  elif ! grep -q "^$marker" "$target"; then
    echo "blocked $name already exists and was not installed by this plugin"
    exit 3
  elif ! grep -q "^$marker $version\$" "$target"; then
    [ "$state" = current ] && state="outdated $(grep "^$marker" "$target" | head -1 | cut -d' ' -f3)"
  fi
done

if [ "$mode" = --check ]; then
  if [ "$state" = current ]; then echo "current $version"; else echo "$state"; fi
  exit 0
fi

mkdir -p "$hooks"
cp "$here/lib.sh" "$hooks/android-workflow-lib.sh"
for name in pre-commit pre-push; do
  sed "s/@VERSION@/$version/" "$here/git/$name" > "$hooks/$name"
  chmod +x "$hooks/$name"
done
echo "installed $version in $hooks"
