---
type: llm
---
Pass only if the listed sequence:

1. Claims the task (`factory task claim 7 ...`) before anything else substantive.
2. Reads the task and its acceptance criteria (`factory task show 7`).
3. Enters an isolated worktree, and runs `factory link` inside it before working.
4. Declares its scope (`factory scope set --task 7 ...`) or states that the
   scope came from the task.

Fail if it starts editing files before claiming, or if it omits `factory link`
after entering a worktree.
