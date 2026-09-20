---
type: llm
---
Pass only if the sequence satisfies all four:

1. **Claims the task first.** `factory task claim t-0001 ...` comes before
   anything else substantive. Reading the task immediately after the claim is
   fine; reading, planning or working before the claim is not.
2. Reads the task and its acceptance criteria (`factory task show t-0001`).
3. Works in an isolated worktree. The response must show the work being isolated
   before implementation. It may name a tool rather than a shell command, since
   entering a worktree is a tool call and not a bash command; what fails is a
   worktree placed **outside** the repository, such as
   `git worktree add ../something`, because the gates cannot resolve the
   project's dependencies from there.
4. Runs `factory link` inside the worktree before doing any work.

`factory scope set` and `factory current set` are expected too but are not
required to pass.

Fail if the claim is not first, if `factory link` is missing, or if the worktree
is placed outside the repository.
