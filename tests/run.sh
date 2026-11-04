#!/bin/bash
# Tests for the plugin's scripts, without Android: the two Claude Code hooks, the git
# hooks and their installer, the device lock. Throwaway repositories in a temp folder,
# fake hook input (JSON), a fake ./gradlew, a fake adb. Usage: bash tests/run.sh
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
check "commit --no-verify on feature" 2 "$(guard "$tmp/onfeature" "git $C --no-verify -m x")"
check "push --no-verify on feature" 2 "$(guard "$tmp/onfeature" "git $P --no-verify origin feature")"
check "commit -an on feature" 2 "$(guard "$tmp/onfeature" "git $C -an -m x")"
check "commit -am on feature" 0 "$(guard "$tmp/onfeature" "git $C -am x")"
check "commit --amend on feature" 0 "$(guard "$tmp/onfeature" "git $C --amend -m x")"

# --- guard: the repository the command acts on ------------------------------------
check "-C repo-on-main from feature" 2 "$(guard "$tmp/onfeature" "git -C $tmp/onmain $C -m x")"
check "-C repo-on-feature from main" 0 "$(guard "$tmp/onmain" "git -C $tmp/onfeature $C -m x")"
check "-C relative path" 0 "$(guard "$tmp/onmain" "git -C ../onfeature $C -m x")"
check "cd repo-on-feature && from main" 0 "$(guard "$tmp/onmain" "cd $tmp/onfeature && git $C -m x")"
check "cd repo-on-main; from feature" 2 "$(guard "$tmp/onfeature" "cd $tmp/onmain; git $C -m x")"
check "cd relative && from main" 0 "$(guard "$tmp/onmain" "cd ../onfeature && git $C -m x")"
check "cd not a repo, falls back to cwd" 2 "$(guard "$tmp/onmain" "cd $tmp && git $C -m x")"
check "cd quoted path" 0 "$(guard "$tmp/onmain" "cd '$tmp/onfeature' && git $C -m x")"
check "cd ~/path (tilde) from main" 0 "$(HOME="$tmp" guard "$tmp/onmain" "cd ~/onfeature && git $C -m x")"
check "-C ~/repo-on-main from feature" 2 "$(HOME="$tmp" guard "$tmp/onfeature" "git -C ~/onmain $C -m x")"

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
buildlog="$(g -C "$p" rev-parse --path-format=absolute --git-common-dir)/android-workflow-builds.log"
check "build log: one line per build" 8 "$(wc -l < "$buildlog" | tr -d ' ')"
check "build log: branch, task and result" "feature :app:compileDebugKotlin ok" "$(tail -1 "$buildlog" | cut -f2,3,5 | tr '\t' ' ')"
check "build log: seconds are a number" yes "$(tail -1 "$buildlog" | cut -f4 | grep -Eq '^[0-9]+$' && echo yes)"

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
check "worktree logs into the project's common log, with its branch" wt "$(tail -1 "$buildlog" | cut -f2)"
rm -rf "$tmp/wt" && g -C "$p" worktree prune
check "log survives the worktree's removal" wt "$(tail -1 "$buildlog" | cut -f2)"

# --- build stats --------------------------------------------------------------------
stats() { bash "$hooks/build-stats.sh" "$@" 2>&1; }
sp="$tmp/stats"
repo "$sp" feature
check "stats: no log" "branch feature: no build checks" "$(stats "$sp")"
slog="$(g -C "$sp" rev-parse --path-format=absolute --git-common-dir)/android-workflow-builds.log"
printf 'd\tfeature\t:t\t%s\t%s\n' 10 ok 30 fail 20 ok > "$slog"
printf 'd\tother\t:t\t%s\t%s\n' 100 ok 1 ok >> "$slog"
check "stats: current branch, odd count" "branch feature: 3 build checks, 1 failed, median 20 s, longest 30 s" "$(stats "$sp")"
check "stats: --branch, even count" "branch other: 2 build checks, 0 failed, median 50.5 s, longest 100 s" "$(stats "$sp" --branch other)"
check "stats: --all" "all branches: 5 build checks, 1 failed, median 20 s, longest 100 s" "$(stats "$sp" --all)"
check "stats: unknown branch" "branch nope: no build checks" "$(stats "$sp" --branch nope)"
check "stats: sorts numbers, not text" "branch big: 2 build checks, 0 failed, median 54.5 s, longest 100 s" "$(printf 'd\tbig\t:t\t9\tok\nd\tbig\t:t\t100\tok\n' >> "$slog"; stats "$sp" --branch big)"

# --- git hooks and their installer -------------------------------------------------
install() { bash "$hooks/install-git-hooks.sh" "$@" 2>&1; }
version=$(jq -r .version "$hooks/../.claude-plugin/plugin.json")
h="$tmp/hk"
repo "$h" master
g init -q --bare "$tmp/hk-remote.git"
g -C "$h" remote set-url origin "$tmp/hk-remote.git"

mkdir -p "$tmp/not-a-repo"
check "installer: not a repo, git's reason shown" yes "$(install "$tmp/not-a-repo" --check | grep -q '^blocked git failed in .*not a git repository' && echo yes)"
check "installer --check: missing" missing "$(install "$h" --check)"
install "$h" >/dev/null
check "installer --check: current" "current $version" "$(install "$h" --check)"
g -C "$h" commit -q --allow-empty -m x 2>/dev/null
check "pre-commit: master blocked" 1 $?
g -C "$h" commit -q --allow-empty --no-verify -m x
check "pre-commit: --no-verify on purpose" 0 $?
g -C "$h" switch -q -c feature
g -C "$h" commit -q --allow-empty -m x
check "pre-commit: feature allowed" 0 $?
g -C "$h" push -q origin feature 2>/dev/null
check "pre-push: feature allowed" 0 $?
g -C "$h" push -q origin feature:master 2>/dev/null
check "pre-push: feature:master blocked" 1 $?
g -C "$h" push -q origin feature:refs/heads/main 2>/dev/null
check "pre-push: to main blocked" 1 $?
g -C "$h" push -q origin feature:release 2>/dev/null
check "pre-push: feature:release allowed" 0 $?

# origin/HEAD decides, and a worktree shares the hooks.
g -C "$h" update-ref refs/remotes/origin/develop HEAD
g -C "$h" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
g -C "$h" worktree add -q -b develop "$tmp/hk-wt"
g -C "$tmp/hk-wt" commit -q --allow-empty -m x 2>/dev/null
check "pre-commit in a worktree: develop (origin/HEAD) blocked" 1 $?
g -C "$h" switch -q master
g -C "$h" commit -q --allow-empty -m x
check "pre-commit: master allowed once origin/HEAD is develop" 0 $?

# Outdated copy, foreign hook, core.hooksPath.
hookdir="$(g -C "$h" rev-parse --path-format=absolute --git-common-dir)/hooks"
sed -i.bak "s/^# android-workflow-hook .*/# android-workflow-hook 0.0.1/" "$hookdir/pre-push" && rm "$hookdir/pre-push.bak"
check "installer --check: outdated" "outdated 0.0.1" "$(install "$h" --check)"
install "$h" >/dev/null
check "installer: update" "current $version" "$(install "$h" --check)"

f="$tmp/foreign"
repo "$f" feature
printf '#!/bin/sh\necho mine\n' > "$f/.git/hooks/pre-commit"
install "$f" >/dev/null
check "installer: foreign hook, exit 3" 3 $?
check "  ...foreign hook untouched" "echo mine" "$(tail -1 "$f/.git/hooks/pre-commit")"
check "  ...no pre-push written" no "$([ -e "$f/.git/hooks/pre-push" ] && echo yes || echo no)"

hp="$tmp/hookspath"
repo "$hp" feature
g -C "$hp" config core.hooksPath .husky
install "$hp" >/dev/null
check "installer: core.hooksPath set, exit 3" 3 $?
check "  ...nothing written" no "$([ -e "$hp/.git/hooks/pre-commit" ] && echo yes || echo no)"

# --- device lock --------------------------------------------------------------------
lock() { AW_LOCK_DIR="$tmp/locks" AW_ADB="$tmp/fake-adb" AW_LOCK_HOLDER="$1" bash "$hooks/device-lock.sh" "${@:2}" 2>/dev/null; }
cat > "$tmp/fake-adb" <<'EOF'
#!/bin/bash
printf 'List of devices attached\n'
cat "$(dirname "$0")/devices" 2>/dev/null
EOF
chmod +x "$tmp/fake-adb"

lock h1 acquire emulator-5554
check "lock: acquire" 0 $?
lock h2 acquire emulator-5554
check "lock: same device, other task busy" 1 $?
lock h1 acquire emulator-5554
check "lock: same task again" 0 $?
lock h2 acquire emulator-5556
check "lock: other device free" 0 $?
lock h2 release emulator-5554
check "lock: release by another task refused" 1 $?
lock h1 release emulator-5554
check "lock: release by holder" 0 $?
lock h2 acquire emulator-5554
check "lock: free again after release" 0 $?
echo 0 > "$tmp/locks/emulator-5556.lock/since"
check "lock: old lock reported" yes "$(lock h3 status | grep -q 'emulator-5556: .*maybe abandoned' && echo yes)"
check "lock: old lock not removed" yes "$([ -d "$tmp/locks/emulator-5556.lock" ] && echo yes)"
lock h3 release emulator-5556 --force
check "lock: --force release" 0 $?
lock h2 release emulator-5554

printf 'emulator-5554\tdevice\n37221FDJH00ABJ\tdevice\nemulator-5556\toffline\n' > "$tmp/devices"
check "pick: physical device first" 37221FDJH00ABJ "$(lock p1 pick)"
check "pick: then a free emulator" emulator-5554 "$(lock p2 pick)"
lock p3 pick >/dev/null
check "pick: all busy (offline ignored)" 1 $?
lock p1 release 37221FDJH00ABJ
check "pick: freed device picked again" 37221FDJH00ABJ "$(lock p3 pick)"
: > "$tmp/devices"
lock p4 pick >/dev/null
check "pick: no device connected" 1 $?

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
