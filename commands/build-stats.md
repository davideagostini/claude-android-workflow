---
description: Show how long the plugin's build checks take in this project
---

# Build check timing

Show how long the Stop hook's build checks take in this project. Answer in the user's
language.

Run both, from the project folder (a worktree works too: the log is shared by every
worktree of the project):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/build-stats.sh" . --all
bash "${CLAUDE_PLUGIN_ROOT}/hooks/build-stats.sh" .
```

Show the two lines as they are: every branch, then the current one. Add nothing else,
except when there are no build checks: then say that the Stop hook has not compiled
anything in this project yet, and that it logs from plugin 0.4.0 on.

Don't read the log file yourself and don't compute numbers: the script does it.
