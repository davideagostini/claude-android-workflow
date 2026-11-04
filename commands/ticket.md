---
description: Work a task from plan to pull request (Jira key, GitHub issue or free text)
argument-hint: ABC-123 | #45 | free text
---

# Work a ticket

Work on **$ARGUMENTS**, from the plan to the pull request, in an Android project set up
with `/android-workflow:setup`. The user-facing version of this flow is the plugin's
README.

The user approves twice: the plan (step 2) and the commit (step 9). Between the two,
do not stop to ask unless a step cannot be done.

## Project data

Read `.claude/android-workflow.json` first. Its keys are described in the table of
`/android-workflow:setup` (step 2); this command uses `compileTask`, `testTasks`,
`checkTasks`, `runTarget` and `jira`. An old file with `testTask` (a single string) still
works: use it as a one-item `testTasks`, and suggest re-running setup.

In a worktree the file is usually not there (it is local, not tracked): read it from the
main checkout, `$(git rev-parse --git-common-dir)/../.claude/android-workflow.json`.
Missing in both → stop and suggest `/android-workflow:setup`.

Check the plugin's git hooks: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/install-git-hooks.sh" .
--check`. `outdated` → say so and offer to update them (the same command without
`--check`), and update only on a yes. `missing` → suggest `/android-workflow:setup`, and
go on. `blocked` → go on: the project manages its own hooks. `jira` absent → the project has
no Jira: never ask for a key. The project's CLAUDE.md wins over this command wherever
they disagree (extra checks, naming, architecture rules).

---

### 1. Get the request

`$ARGUMENTS` is one of three things:

| Argument | Source | Jira |
|---|---|---|
| A Jira key or URL (`ABC-1584`, `<baseUrl>/browse/ABC-1584`) | the Jira ticket | yes |
| A GitHub issue (`#123`, `123`, or its URL) | `gh issue view 123` | no, unless the issue body carries a `Jira:` line |
| Free text | the text itself | no |

- No argument → ask what to work on. Don't guess.
- Jira: normalise a URL to its key. If an Atlassian connector is authenticated, read the
  ticket (title, description, acceptance criteria); otherwise ask the user to paste what
  matters. Never invent the ticket's content.
- Free text too thin to plan from → ask, don't fill the gaps yourself.
- A bug: before planning, find where it happens in the code and say whether it can be
  reproduced from what is given (variant, device, steps, expected result). If it can't,
  ask for what is missing.

From here on, **with Jira** means a Jira key is known; **without Jira** means it isn't.

### 2. Write the plan

Draft the plan: goal, files to touch, what is out of scope, how it will be verified
(step 6, plus the device journey if a screen changes). Show it and wait for approval.

### 3. Put the plan on GitHub

Only after approval.

- **Jira key or free text**: `gh issue create` with the plan as body. With Jira, add
  `Jira: [ABC-xxx](<baseUrl>/browse/ABC-xxx)`.
- **Existing GitHub issue**: `gh issue comment NN` with the plan. Don't rewrite the body.

Note the issue number `NN`.

### 4. Set up the branch

- With Jira: `ABC-xxx-issue-NN`.
- Without Jira: `feat/<short-slug>-issue-NN`, or `fix/<short-slug>-issue-NN` for a bug.
  The slug is 2-4 lowercase English words joined by `-`.

Check whether the session runs in a worktree: `git rev-parse --git-dir` differs from
`git rev-parse --git-common-dir`.

- **In a worktree** (session started with `claude -w <name>`): it already sits on a fresh
  branch from `origin/<default>`. Rename it: `git branch -m <branch>`.
- **Not in a worktree**: say that the recommended start is `claude -w <name>`, then,
  only if the working tree is clean, `git fetch origin <default>` and
  `git switch -c <branch> origin/<default>`. Dirty tree → stop and ask.

### 5. Implement

Implement the approved plan and nothing else. If something outside it turns out to be
needed, or the plan is wrong, stop and say so.

The plugin's Stop hook compiles `compileTask` at the end of each turn when sources,
resources or build files changed, and sends the errors back. Fix them; don't work around it.

### 6. Verify

Run `./gradlew <compileTask>`, then every task in `testTasks` and `checkTasks` in one
command (`./gradlew <task> <task> ...`, with `--continue` so that one failure doesn't
hide the others), plus anything the project's CLAUDE.md adds to its definition of done.
Keep the output for the report.

Time both commands yourself (`start=$(date +%s)` before, `$(($(date +%s) - start))`
after) and keep the seconds for the report: "Verify: compile 42 s, tests and checks 95 s".

### 7. Review

Run the `code-review` skill on the diff against `origin/<default>`. Fix the findings that
are real, re-run step 6 if code changed, and list in the report the findings left alone
and why.

### 8. Device check (only if a screen changed)

No `runTarget`, or no UI change → skip and say so.

Several tasks may run at once, and there may be several devices. Each device has its own
lock, shared by every project on this machine:

1. `bash "${CLAUDE_PLUGIN_ROOT}/hooks/device-lock.sh" pick` locks a free, ready device
   and prints its serial: a physical device first, then an emulator. It fails when no
   device is connected or every one is busy, and says who holds each lock.
   - Nothing free → tell the user who holds what and ask. You may suggest starting
     another emulator from `emulator -list-avds`, but start it only on a yes.
   - A lock reported as "maybe abandoned" is not removed on its own: ask the user.
2. Use that serial for every command of the journey: `android run --device=<serial>
   "<runTarget>"`, `android layout --device=<serial>`, `android screen capture
   --device=<serial>`, `android input --device=<serial>`, and `ANDROID_SERIAL=<serial>`
   for `adb`.
3. Start from a known state (`adb shell pm clear` or an explicit logout) and record
   pass/fail per step.
4. Always release the lock at the end, also when the journey fails:
   `bash "${CLAUDE_PLUGIN_ROOT}/hooks/device-lock.sh" release <serial>`.

### 9. Report and ask for the commit

Report: what changed, the output of step 6, the review findings, the journey result and
the device it ran on, the timing below, what was not done.

Timing: the Verify durations from step 6, then the Stop hook's build checks on this
branch, from `bash "${CLAUDE_PLUGIN_ROOT}/hooks/build-stats.sh" . --branch <branch>`.
Quote its line as it is, and add that the check at the end of this reply is not counted
yet: the Stop hook runs after the reply.

Then ask once: **"Commit, push e PR?"** (in the user's language).

On yes:

- Commit subject: `ABC-xxx feat: <summary>` with Jira, `feat: <summary>` without
  (`fix:` for a bug).
- `git push -u origin <branch>`.
- `gh pr create`: body carries `Closes #NN`, the step 6 output and the journey result.
  With Jira, the title starts with the key and the body carries the Jira link.
- Wait for the project's CI on the pull request: `gh pr checks <number> --watch`, at most
  20 minutes. Report the result per check. No checks → say the project has no CI on pull
  requests. A failing check → show it and stop: don't push fixes after the PR without
  asking.

### 10. Stop

Give the PR URL and stop. Merge, the Jira transition and the cleanup are the user's.
Remind them:

- With Jira: merging does **not** move the ticket.
- After the merge, from the main checkout: remove the worktree ("remove" when leaving the
  session, or `git worktree remove .claude/worktrees/<name>`), then delete the branch:
  `git branch -D <branch>` and `git push origin --delete <branch>`. "remove" deletes the
  worktree folder but **not** the branch renamed in step 4 (checked on 2026-11-04).
