#!/bin/bash
# Tests for the two hooks, without Android: throwaway repositories in a temp folder,
# fake hook input (JSON), a fake ./gradlew. It never runs a real commit or push
# through the hooks. Usage: bash tests/run.sh
set -u

hooks="$(cd "$(dirname "$0")/../hooks" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

g() { git -c user.name=test -c user.email=test@example.invalid "$@"; }

# repo <path> <branch>: a repository with one commit on <branch> and an origin
# remote without origin/HEAD.
repo() {
  mkdir -p "$1"
  g -C "$1" init -q -b "$2"
  g -C "$1" commit -q --allow-empty -m init
  g -C "$1" remote add origin "$tmp/none.git"
}

# hook <script> <cwd> <command> [stop_hook_active]: runs a hook with fake input,
# prints its exit code.
hook() {
  jq -n --arg c "$3" --arg d "$2" --argjson s "${4:-false}" \
    '{tool_input: {command: $c}, cwd: $d, stop_hook_active: $s}' \
    | bash "$hooks/$1" >/dev/null 2>&1
  echo $?
}

# check <name> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1 (expected $2, got $3)"
  fi
}

guard() { hook guard-default-branch.sh "$@"; }
C=commit
P=push

# --- guard: default branch without origin/HEAD -----------------------------------
repo "$tmp/onmaster" master
repo "$tmp/onmain" main
repo "$tmp/onfeature" feature
repo "$tmp/ondevelop" develop

check "commit on master, no origin/HEAD" 2 "$(guard "$tmp/onmaster" "git $C -m x")"
check "commit on main, no origin/HEAD" 2 "$(guard "$tmp/onmain" "git $C -m x")"
check "commit on feature" 0 "$(guard "$tmp/onfeature" "git $C -m x")"
check "commit on develop, not default" 0 "$(guard "$tmp/ondevelop" "git $C -m x")"

# origin/HEAD set: only that branch is protected.
g -C "$tmp/ondevelop" update-ref refs/remotes/origin/develop HEAD
g -C "$tmp/ondevelop" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
check "commit on develop, origin/HEAD=develop" 2 "$(guard "$tmp/ondevelop" "git $C -m x")"
g -C "$tmp/ondevelop" switch -q -c master
check "commit on master, origin/HEAD=develop" 0 "$(guard "$tmp/ondevelop" "git $C -m x")"
g -C "$tmp/ondevelop" switch -q develop

# defaultBranch in the project data, used only when origin/HEAD is missing.
repo "$tmp/trunk" trunk
mkdir -p "$tmp/trunk/.claude"
echo '{"defaultBranch": "trunk"}' > "$tmp/trunk/.claude/android-workflow.json"
check "commit on trunk, defaultBranch=trunk" 2 "$(guard "$tmp/trunk" "git $C -m x")"
g -C "$tmp/trunk" switch -q -c master
check "commit on master, defaultBranch=trunk" 0 "$(guard "$tmp/trunk" "git $C -m x")"

# --- guard: pushes that target the default branch ---------------------------------
check "push origin main" 2 "$(guard "$tmp/onfeature" "git $P origin main")"
check "push origin master" 2 "$(guard "$tmp/onfeature" "git $P origin master")"
check "push HEAD:main" 2 "$(guard "$tmp/onfeature" "git $P origin HEAD:main")"
check "push +main" 2 "$(guard "$tmp/onfeature" "git $P origin +main")"
check "push feature:master" 2 "$(guard "$tmp/onfeature" "git $P -f origin feature:master")"
check "push refs/heads/main" 2 "$(guard "$tmp/onfeature" "git $P origin feature:refs/heads/main")"
check "push feature" 0 "$(guard "$tmp/onfeature" "git $P -u origin feature")"
check "push main-fix" 0 "$(guard "$tmp/onfeature" "git $P origin main-fix")"
check "not git" 0 "$(guard "$tmp/onmain" "echo 'git $C' > notes.txt")"
check "git status on main" 0 "$(guard "$tmp/onmain" "git status")"

# --- guard: the repository the command acts on ------------------------------------
check "-C repo-on-main from feature" 2 "$(guard "$tmp/onfeature" "git -C $tmp/onmain $C -m x")"
check "-C repo-on-feature from main" 0 "$(guard "$tmp/onmain" "git -C $tmp/onfeature $C -m x")"
check "-C relative path" 0 "$(guard "$tmp/onmain" "git -C ../onfeature $C -m x")"
check "cd repo-on-feature && from main" 0 "$(guard "$tmp/onmain" "cd $tmp/onfeature && git $C -m x")"
check "cd repo-on-main; from feature" 2 "$(guard "$tmp/onfeature" "cd $tmp/onmain; git $C -m x")"
check "cd relative && from main" 0 "$(guard "$tmp/onmain" "cd ../onfeature && git $C -m x")"
check "cd not a repo, falls back to cwd" 2 "$(guard "$tmp/onmain" "cd $tmp && git $C -m x")"
check "cd quoted path" 0 "$(guard "$tmp/onmain" "cd '$tmp/onfeature' && git $C -m x")"

# --- verify-build: when Gradle runs, the loop guard ----------------------------------
stop() { hook verify-build.sh "$1" "" "${2:-false}"; }
p="$tmp/android"
repo "$p" feature
cat > "$p/gradlew" <<'EOF'
#!/bin/bash
# Fake Gradle: fails when a watched file contains BROKEN, counts its runs.
echo run >> "$(dirname "$0")/.gradle-runs"
if grep -rqs BROKEN --include='*.kt' --include='*.xml' --include='*.toml' "$(dirname "$0")/src"; then
  echo "e: src/A.kt:1:1 Unresolved reference 'BROKEN'."
  exit 1
fi
exit 0
EOF
chmod +x "$p/gradlew"
printf '.gradle-runs\n' > "$p/.gitignore"
mkdir -p "$p/src"
runs() { if [ -f "$p/.gradle-runs" ]; then wc -l < "$p/.gradle-runs" | tr -d " "; else echo 0; fi; }

check "no project data: no Gradle" 0 "$(stop "$p")"
check "  ...runs" "" "$(cat "$p/.gradle-runs" 2>/dev/null | head -1)"

mkdir -p "$p/.claude"
echo '{"compileTask": ":app:compileDebugKotlin"}' > "$p/.claude/android-workflow.json"
check "no changes: exit 0" 0 "$(stop "$p")"
check "  ...no Gradle" "" "$(cat "$p/.gradle-runs" 2>/dev/null | head -1)"

echo "# notes" > "$p/src/README.md"
check "only a .md changed: exit 0" 0 "$(stop "$p")"
check "  ...no Gradle" "" "$(cat "$p/.gradle-runs" 2>/dev/null | head -1)"

for ext in kt java xml toml gradle; do
  rm -f "$p/.gradle-runs" "$(g -C "$p" rev-parse --git-dir)/android-workflow-verify-build"
  echo "ok $ext" > "$p/src/f.$ext"
  check "new .$ext: compiles" 0 "$(stop "$p")"
  check "  ...Gradle ran" 1 "$(runs)"
  rm "$p/src/f.$ext"
done

rm -f "$p/.gradle-runs"
echo "BROKEN" > "$p/src/A.kt"
check "broken .kt: exit 2" 2 "$(stop "$p")"
check "same failure, stop_hook_active: lets Claude stop" 0 "$(stop "$p" true)"
echo "BROKEN again" > "$p/src/A.kt"
check "new edit, still broken: exit 2" 2 "$(stop "$p" true)"
echo "fixed" > "$p/src/A.kt"
check "fixed: exit 0" 0 "$(stop "$p" true)"
check "  ...Gradle ran 3 times" 3 "$(runs)"
check "same changes as last success: no Gradle" 0 "$(stop "$p")"
check "  ...still 3" 3 "$(runs)"

echo '{"compileTask": ":app:compileDebugKotlin", "verifyBuildHook": false}' > "$p/.claude/android-workflow.json"
echo "BROKEN" > "$p/src/A.kt"
check "verifyBuildHook false: exit 0" 0 "$(stop "$p")"

# Project data only in the main checkout, hook run in a worktree.
echo '{"compileTask": ":app:compileDebugKotlin"}' > "$p/.claude/android-workflow.json"
printf '/.claude/\n' >> "$p/.gitignore"
g -C "$p" add .gitignore gradlew src
g -C "$p" commit -q -m base
g -C "$p" worktree add -q -b wt "$tmp/wt"
echo "BROKEN" > "$tmp/wt/src/B.kt"
check "worktree reads project data from main checkout" 2 "$(stop "$tmp/wt")"

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
