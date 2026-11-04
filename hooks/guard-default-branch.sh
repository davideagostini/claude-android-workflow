#!/bin/bash
# PreToolUse (Bash): blocks `git commit` and `git push` on the default branch,
# and pushes that target it. Exit 2 = blocked, stderr is the reason Claude sees.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

# Only git commit / git push (also `git -C <dir>` / `git -c k=v`, also after && ; or "(").
# It reads the text, it doesn't parse the shell: it covers the common cases, it is
# not a security boundary (quoted paths with spaces, aliases, `cd` in the middle of a
# command slip through).
git_re='(^|[;&|([:space:]])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+'
printf '%s' "$cmd" | grep -Eq "${git_re}(commit|push)([[:space:]]|$)" || exit 0

# resolve <path> <base>: <path> as an absolute path (~ and relative paths handled).
resolve() {
  local p="$1"
  p="${p#[\"\']}"; p="${p%[\"\']}"
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    /*) ;;
    *) p="$2/$p" ;;
  esac
  printf '%s' "$p"
}

# The repository the command acts on: `cd <dir>` at the start of the command, then
# `git -C <dir>`, else the session's cwd. A path that is not a repository is ignored.
dir="${cwd:-${CLAUDE_PROJECT_DIR:-.}}"
path_re='([^[:space:];&|]+)'
cd_re="^[[:space:]]*cd[[:space:]]+${path_re}[[:space:]]*(&&|;)"
gitc_re="git[[:space:]]+-C[[:space:]]+${path_re}"
if [[ "$cmd" =~ $cd_re ]]; then
  cand=$(resolve "${BASH_REMATCH[1]}" "$dir")
  git -C "$cand" rev-parse --git-dir >/dev/null 2>&1 && dir="$cand"
fi
if [[ "$cmd" =~ $gitc_re ]]; then
  cand=$(resolve "${BASH_REMATCH[1]}" "$dir")
  git -C "$cand" rev-parse --git-dir >/dev/null 2>&1 && dir="$cand"
fi

# The default branch: origin/HEAD, else "defaultBranch" in the project data, else
# both main and master are protected. No network calls here.
protected=$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
protected="${protected#origin/}"
if [ -z "$protected" ] && config=$(aw_config "$dir"); then
  protected=$(jq -r '.defaultBranch // empty' "$config" 2>/dev/null)
fi
protected="${protected:-main master}"

current=$(git -C "$dir" branch --show-current 2>/dev/null)

for branch in $protected; do
  if [ "$current" = "$branch" ]; then
    echo "Blocked: you are on '$branch', the default branch. Create a branch first (only if the user asked for one)." >&2
    exit 2
  fi
  if printf '%s' "$cmd" | grep -Eq "${git_re}push([[:space:]][^;&|]*)?[[:space:]:+](refs/heads/)?${branch}([[:space:];&|)]|$)"; then
    echo "Blocked: this push targets '$branch', the default branch." >&2
    exit 2
  fi
done

exit 0
