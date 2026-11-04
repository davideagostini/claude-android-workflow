#!/bin/bash
# Stop hook: compiles the project's reference variant when sources or build files changed.
#
# - Project without .claude/android-workflow.json, without compileTask, or with
#   "verifyBuildHook": false: does nothing.
# - No changed source or build file (see `watched` below): exits at once, no Gradle.
# - Same changes as the last successful compile: skipped.
# - Compile fails: exit 2, the errors go back to Claude, which keeps working.
# - Fails again with no new edits since the last failure: lets Claude stop,
#   so a failure it cannot fix never loops.
#
# The state lives in the worktree's own git dir: every worktree has its own. The build
# log (android-workflow-builds.log) lives in the common git dir: one per project, shared
# by every worktree, so it survives "remove". hooks/build-stats.sh reads it.

set -u
. "$(dirname "$0")/lib.sh"

input=$(cat)
# The session's cwd, not CLAUDE_PROJECT_DIR: after a mid-session switch into a
# worktree the latter may still name the main checkout.
dir=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
cd "${dir:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

config=$(aw_config .) || exit 0
# "verifyBuildHook": false → the project already has its own build hook.
[ "$(jq -r '.verifyBuildHook' "$config" 2>/dev/null)" = "false" ] && exit 0
task=$(jq -r '.compileTask // empty' "$config" 2>/dev/null)
[ -n "$task" ] || exit 0
[ -x ./gradlew ] || exit 0

# Files that can break the compile: sources, resources and manifests, build scripts.
watched=('*.kt' '*.kts' '*.java' '*.xml' '*.gradle' '*.toml' 'gradle.properties' '*/gradle.properties')
changes=$(
  {
    git diff HEAD -- "${watched[@]}"
    git ls-files --others --exclude-standard -z -- "${watched[@]}" | xargs -0 cat 2>/dev/null
  }
)
[ -z "$changes" ] && exit 0

fingerprint=$(printf '%s' "$changes" | shasum | cut -d' ' -f1)
state="$(git rev-parse --git-dir)/android-workflow-verify-build"
last=$(cat "$state" 2>/dev/null)

[ "$last" = "ok:$fingerprint" ] && exit 0
if [ "$last" = "fail:$fingerprint" ] && printf '%s' "$input" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then
  exit 0
fi

start=$(date +%s)
log=$(./gradlew "$task" --console=plain -q 2>&1)
result=$?
# One line per build: date, branch, task, seconds, result.
branch=$(git branch --show-current)
printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${branch:-detached}" "$task" \
  "$(($(date +%s) - start))" "$([ $result -eq 0 ] && echo ok || echo fail)" \
  >> "$(git rev-parse --path-format=absolute --git-common-dir)/android-workflow-builds.log"
if [ $result -eq 0 ]; then
  echo "ok:$fingerprint" > "$state"
  exit 0
fi

echo "fail:$fingerprint" > "$state"
{
  echo "Build check failed ($task). Fix these errors, or tell the user why you can't:"
  # Kotlin: "e: ...", Java: "...: error: ...", AAPT/manifest: "ERROR: ..." / "AAPT: error:".
  errors=$(printf '%s\n' "$log" | grep -E '^e: |error:|^ERROR' | head -30)
  if [ -n "$errors" ]; then
    printf '%s\n' "$errors"
  else
    printf '%s\n' "$log" | tail -30
  fi
} >&2
exit 2
