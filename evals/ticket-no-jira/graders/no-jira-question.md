---
type: llm
---

PASS if no message from the assistant asks the user for a Jira key, a Jira ticket or a
Jira project, and nothing suggests that a Jira key is needed.
FAIL if any assistant message asks for a Jira key or ticket, or says one is missing.
