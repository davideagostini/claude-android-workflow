---
description: Set up this Android project for the android-workflow plugin (worktrees, build hook, /ticket)
---

# Set up the project

Prepare the current Android project for the plugin. **Show every change first and write
only after the user confirms.** Answer in the user's language.

The setup is **local by default**: nothing is committed, teammates see no change. The
files the plugin needs are hidden from git through `.git/info/exclude`, which is never
pushed and is shared by every worktree of the repository.

## 1. Check the project

- It is a git repository with `./gradlew` at the root. Otherwise stop.
- Read what already exists: `.claude/android-workflow.json`, `.worktreeinclude`,
  `.gitignore`, `.git/info/exclude`, `.claude/settings.json`, `.claude/commands/`,
  `.claude/hooks/`, CLAUDE.md. Report what you found.
- **Overlaps**: a project hook that compiles on Stop, a default-branch guard, or a
  project `/ticket` command duplicate what the plugin does. Plugin hooks run **in
  addition to** project hooks, so two build hooks would compile twice.
  - Committed (shared with the team): leave them. Set `"verifyBuildHook": false` in the
    project data so the plugin's build hook steps aside. A second default-branch guard is
    harmless (both block the same thing). The project's `/ticket` keeps its bare name;
    the plugin's is `/android-workflow:ticket`.
  - Local only (not committed): propose removing them, and remove only on a yes.

## 2. Project data → `.claude/android-workflow.json`

This table is the reference for the file's keys: `/android-workflow:ticket`, the hooks
and the README point here. Propose values, read from the build files, and let the user
correct them:

| Key | How to find it |
|---|---|
| `compileTask` | `:app:compile<Variant>Kotlin` for the reference variant. With product flavors, ask which flavor is the reference (the project's CLAUDE.md may say). |
| `testTasks` | A list: one unit test task per module that has `src/test`, for the reference variant. The name depends on the module: `:app:test<Variant>UnitTest` for a module with flavors, `:feature:x:testDebugUnitTest` for a library without flavors. Check each one with `./gradlew <task> --dry-run`. |
| `checkTasks` | Optional list, run by `/android-workflow:ticket` at Verify (never by the Stop hook). Look in the build files for ktlint (`ktlintCheck`), detekt (`detekt`), spotless (`spotlessCheck`) and propose the tasks found. Android lint (`:app:lint<Variant>`) only if the user wants it: say that it is slow. |
| `runTarget` | `app@<variant>` for `android run`; omit if there is no app module |
| `defaultBranch` | Only if `origin/HEAD` is missing and the user doesn't want to set it (step 4). Omit otherwise. |
| `jira` | `{ "projectKey": "...", "baseUrl": "https://....atlassian.net" }` — only if the project uses Jira. Look for keys in recent commit subjects and branch names, then ask. |
| `verifyBuildHook` | `false` only if the project already has its own committed build hook (step 1); omit otherwise |

Verify `compileTask` exists: `./gradlew <compileTask> --dry-run`.

An existing file with `testTask` (a single string, the old format): propose replacing it
with `testTasks`.

## 3. Files a worktree needs → `.worktreeinclude`

A worktree holds only tracked files. List the ignored files that the build needs:

```bash
git status --ignored --porcelain | grep '^!!' \
  | grep -v -E '/build/|\.gradle/|\.idea/|\.kotlin/|\.DS_Store|/\.cxx/'
```

Typical: `local.properties`, `keystore.properties`, `google-services.json`, local AARs,
assets kept out of git. Propose a `.worktreeinclude` (gitignore syntax). The project data
file does not need to be in it: the plugin reads it from the main checkout. Never read
the content of secret files
(properties, keystores, `.env`): their names are enough.

## 4. Default branch and hiding from git

The default-branch guard reads `origin/HEAD`. Check it:
`git symbolic-ref refs/remotes/origin/HEAD`. If it is missing, the guard protects both
`main` and `master`, which is wrong for a project whose default is, say, `develop`.
Propose `git remote set-head origin --auto`: it asks the remote once (network) and
changes only the local git config. If the user says no, set `defaultBranch` in the
project data.



Append to `.git/info/exclude` (create it if missing), only the lines not already ignored:

```
/.claude/worktrees/
/.worktreeinclude
/.claude/android-workflow.json
```

If the project already tracks `.worktreeinclude` or ignores `.claude/worktrees/` in
`.gitignore`, leave those as they are and skip the matching lines.

`.worktreeinclude` is read from the main checkout's working tree, so it works even when
it is untracked: the copy is local and nothing is committed.

## 5. CLAUDE.md

If the project has a CLAUDE.md, propose one line in its workflow section (or at the end):

> Work on a task: `claude -w <name>`, then `/android-workflow:ticket`. Project data for the
> plugin: `.claude/android-workflow.json`.

CLAUDE.md is usually tracked: say so, and add the line only if the user agrees.

## 6. Check

- `git check-ignore -v .claude/worktrees/x .claude/android-workflow.json` → both ignored.
- `git symbolic-ref refs/remotes/origin/HEAD`, or `defaultBranch` → the default branch is known.
- `./gradlew <compileTask>` → report the result.
- Tell the user how to start: `claude -w <name>`, then `/android-workflow:ticket ...`.

## 7. Report

What was written, what was left alone and why, what is committed (normally nothing).
