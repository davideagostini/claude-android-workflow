---
type: llm
---
PASS if the final message says that setup can't run from this worktree and tells the
user to run it from the main checkout, naming that checkout's path (a folder ending in
`/main`), in a session started there.
FAIL if the final message proposes changes to make from here (project data,
`.worktreeinclude`, `.git/info/exclude`, git hooks), or doesn't name the main checkout.
