# android-workflow

[![tests](https://github.com/davideagostini/claude-android-workflow/actions/workflows/test.yml/badge.svg)](https://github.com/davideagostini/claude-android-workflow/actions/workflows/test.yml)

A Claude Code plugin for Android projects. It gives every project the same way of working:

- **one copy of the repository per task** (`claude -w <name>`), so several tasks can run
  side by side without stepping on each other;
- **`/android-workflow:ticket`**: from plan to pull request, with only two approvals
  (the plan and the commit);
- **an automatic build check** when Claude has touched sources, resources or build files;
- **a guard** that blocks commits and pushes on the default branch, in Claude's commands
  and in git itself;
- **one lock per device**, so parallel tasks never drive the same emulator or phone.

Setup commits no files to your project: your team only sees what any task produces,
issues, branches and pull requests.

---

## 1. Install (once per machine)

Requirements: Claude Code, `git`, `jq` (`brew install jq`; recent macOS ships it in
`/usr/bin/jq`), and `gh` for issues and pull requests.

```bash
claude plugin marketplace add davideagostini/claude-android-workflow
claude plugin install android-workflow@davideagostini
claude plugin list          # android-workflow@davideagostini, ✔ enabled
```

Inside a session, `/plugin marketplace add davideagostini/claude-android-workflow` and
`/plugin install android-workflow@davideagostini` do the same.

The plugin is active **in every project**, but in a project that is not set up (step 2)
the hooks do nothing except the default-branch guard.

## 2. Set up a project (once per project)

1. Open a terminal in the project folder, on an up-to-date default branch.
2. `claude`
3. Type `/android-workflow:setup`.
4. Claude shows what it wants to do and waits for your yes:
   - the **project data** in `.claude/android-workflow.json`: what to compile, which tests
     and checks to run, which app to launch on the device, the Jira project if any;
   - the **`.worktreeinclude`** file: the git-ignored files the build needs (for example
     `local.properties`), copied into every new worktree;
   - the lines in **`.git/info/exclude`**, so these files never end up in a commit.
     `.git/info/exclude` works like `.gitignore`, but stays on your machine;
   - `origin/HEAD`, if it is missing, so the guard knows the default branch;
   - the **git hooks** `pre-commit` and `pre-push` (see below), unless the project already
     manages its hooks;
   - a check of the default branch's **protection on GitHub**: that is the real barrier,
     the hooks only catch mistakes on your machine.
5. At the end it compiles once to check that the data is right.

None of this goes into the repository. If the project already has hooks or a `/ticket`
command shared with the team, `setup` leaves them alone and tells you.

Example `.claude/android-workflow.json`:

```json
{
  "compileTask": ":app:compileBlueDebugKotlin",
  "testTasks": [":app:testBlueDebugUnitTest", ":feature:home:testDebugUnitTest"],
  "checkTasks": ["ktlintCheck"],
  "runTarget": "app@blueDebug",
  "jira": { "projectKey": "ABC", "baseUrl": "https://example.atlassian.net" }
}
```

Every key is described in the table in step 2 of `commands/setup.md`.

## 3. Work on a ticket

1. In the project folder:
   ```bash
   claude -w short-name
   ```
   This creates `.claude/worktrees/short-name/`: a copy of the repository on a new branch,
   taken from the up-to-date default branch, with the files from `.worktreeinclude`.
   Claude works only there. Your usual checkout is not touched.
2. In the session, one of these:
   ```
   /android-workflow:ticket ABC-123
   /android-workflow:ticket #45
   /android-workflow:ticket search should also show rooms
   ```
3. Claude proposes a plan. **You read it and approve it** (or correct it).
4. From here it goes on alone: GitHub issue, branch, code, build and tests, code review,
   a check on the device if a screen changes.
5. It reports and asks **"Commit, push and PR?"**. You answer yes.
6. You review the PR and **merge it yourself**.
7. If there is a Jira ticket, you move it: merging does not close it.
8. Close the session and choose "remove": the worktree folder is deleted. The branch is
   not, because `/ticket` renamed it: delete it yourself, local and remote
   (`git branch -D <branch>`, `git push origin --delete <branch>`), or ask Claude to.

Names used:

| | With Jira | Without Jira |
|---|---|---|
| Branch | `ABC-123-issue-NN` | `feat/search-rooms-issue-NN` (`fix/...` for a bug) |
| Commit | `ABC-123 feat: ...` | `feat: ...` |
| PR | title with the key, Jira link, `Closes #NN` | `Closes #NN` |

### Reporting a bug

Same flow. Write (in the ticket, the issue or after the command): app variant, device and
Android version, steps one per line, what you expected, what happens, logs or screenshots
if you have them. If something is missing, Claude asks before the plan.

### Several tasks at once

One terminal per task, each with its own `claude -w`. You approve the plans one after the
other, then the sessions run in parallel.

- **Devices**: each emulator or phone has its own lock. A task takes a free device (a
  physical one first) and the report says which; when every device is busy, Claude asks.
- **Work on different parts of the app**: two tasks on the same files conflict at the
  second merge.
- **Memory**: every worktree runs its own Gradle build. With three at once the machine
  can slow down.

---

## What happens on its own

| When | What |
|---|---|
| You create a worktree with `claude -w` | The files in `.worktreeinclude` are copied |
| Claude finishes a reply and has touched `.kt`, `.java`, `.xml` or build files (`.kts`, `.gradle`, `.toml`, `gradle.properties`) | It compiles `compileTask`. If there are errors, Claude must fix them before stopping. If it can't, on the second attempt with no new edits it is allowed to stop (no endless loop). Code that already compiled is not compiled again. |
| Claude tries `git commit` or `git push` on the default branch, or `--no-verify` | Blocked. The default branch is `origin/HEAD`; if missing, `defaultBranch` in the project data; if that is missing too, both `main` and `master`. It applies to the repository the command acts on (`git -C <dir>`, `cd <dir> && ...`), not only to the session's folder. |
| Anyone commits on the default branch, or pushes to it (git hooks, if installed) | Blocked by git, whoever runs the command: Claude, a `!` command, you. `--no-verify` skips it on purpose. |
| A build check runs | One line in `.git/android-workflow-builds.log` of the worktree (date, task, seconds, result). `/ticket` reports how many ran, the median and the longest. |
| A PR is opened by `/ticket` | It waits for the project's CI (`gh pr checks`, up to 20 minutes) and reports each check. |

The Claude Code guard reads the command text, it doesn't parse the shell: it covers the
common cases and is not a security boundary. The git hooks block at the git level. The
real barrier is the branch protection on GitHub.

The git hooks are **copies** in the repository's common git dir (shared by every
worktree, never committed), with the plugin version inside. After a plugin update,
`/android-workflow:ticket` notices an outdated copy and offers to update it.

## Manage

| What | How |
|---|---|
| Turn it off in one project | `claude plugin disable android-workflow@davideagostini --scope local` (in the project folder) |
| Turn it off everywhere | `claude plugin disable android-workflow@davideagostini` |
| See what it contains | `claude plugin details android-workflow` |
| Update it | `claude plugin update android-workflow@davideagostini` |
| Remove it | `claude plugin uninstall android-workflow@davideagostini` |

## Known issues

- **Worktree "locked" after a session closed badly**: `git worktree remove` says
  `cannot remove a locked working tree`. If the session is no longer open:
  `git worktree unlock .claude/worktrees/<name>`, then `remove` again.
- **Permissions already granted** (`.claude/settings.local.json`) are not copied into the
  worktree, but Claude Code reads them from the main checkout.
- **`/ticket` without the prefix** runs the project's own command, if there is one. The
  plugin's command is always `/android-workflow:ticket`.

## Develop the plugin

Run the plugin from your clone instead of the installed copy:

```bash
claude plugin disable android-workflow@davideagostini   # otherwise every hook runs twice
claude --plugin-dir ./claude-android-workflow
```

After every change:

1. `bash tests/run.sh`: tests the hooks, the git hooks and their installer, and the device
   lock on throwaway repositories, no Android needed. It must end with `failed: 0`. The
   CI runs it on Linux and macOS, plus `shellcheck`.
2. The evals check how `/android-workflow:ticket` behaves (it stops at the plan, never
   commits or pushes before your yes, asks for no Jira key without Jira, suggests setup
   without project data). They use the model and count against your usage:
   ```bash
   claude plugin eval . --scaffold --allow-tools Bash --ablation none --runs 1
   ```
3. On a real Android project, ideally multi-module with product flavors: `setup`, then a
   `ticket` up to the pull request.

## Layout

```
.claude-plugin/plugin.json        name and version
.claude-plugin/marketplace.json   this repository as a one-plugin marketplace
commands/ticket.md                /android-workflow:ticket
commands/setup.md                 /android-workflow:setup
hooks/hooks.json                  wires the two hooks
hooks/verify-build.sh             build check at the end of a reply (Stop)
hooks/guard-default-branch.sh     blocks commit/push on the default branch (PreToolUse)
hooks/lib.sh                      shared by the hooks (also copied next to the git hooks)
hooks/git/pre-commit, pre-push    git hooks, installed as copies by setup
hooks/install-git-hooks.sh        installs, updates or checks the git hooks
hooks/device-lock.sh              one lock per device: pick, acquire, release, status
tests/run.sh                      tests of all the scripts
evals/                            evals of /android-workflow:ticket
.github/workflows/test.yml        CI: tests on Linux and macOS, shellcheck
```

## License

MIT, see `LICENSE`.
