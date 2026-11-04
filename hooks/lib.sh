#!/bin/bash
# Shared by the hooks: source it, don't run it.

# aw_config <dir>: prints the path of the project data file for the repository that
# holds <dir>. It looks in that checkout first, then in the main checkout: a worktree
# does not get untracked files, and the data file is local. Returns 1 if there is none.
aw_config() {
  local root main
  root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  if [ -f "$root/.claude/android-workflow.json" ]; then
    echo "$root/.claude/android-workflow.json"
    return 0
  fi
  main=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  main=$(dirname "$main")
  if [ -f "$main/.claude/android-workflow.json" ]; then
    echo "$main/.claude/android-workflow.json"
    return 0
  fi
  return 1
}
