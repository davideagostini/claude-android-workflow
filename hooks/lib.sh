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

# aw_default_branches <dir>: prints the protected branch names for the repository that
# holds <dir>, space separated: origin/HEAD, else "defaultBranch" in the project data,
# else both main and master. No network calls: this runs before every command.
aw_default_branches() {
  local branch config
  branch=$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
  branch="${branch#origin/}"
  if [ -z "$branch" ] && config=$(aw_config "$1"); then
    branch=$(jq -r '.defaultBranch // empty' "$config" 2>/dev/null)
  fi
  echo "${branch:-main master}"
}
