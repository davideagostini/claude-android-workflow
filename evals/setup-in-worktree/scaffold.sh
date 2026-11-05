#!/bin/bash
# The session's folder is a worktree; the main checkout is main/ inside it (hidden from
# the worktree through info/exclude), as if the session had started with claude -w.
set -eu
g() { git -c user.name=eval -c user.email=eval@example.invalid "$@"; }
here=$(pwd)
mkdir main
(cd main && bash "$(dirname "$0")/../_fixture/android-project.sh" no-config)
g -C main worktree add -q -b feature/sign-out .wt
shopt -s dotglob
mv main/.wt/* "$here/"
rmdir main/.wt
g -C "$here" worktree repair >/dev/null
printf '/main/\n' >> main/.git/info/exclude
