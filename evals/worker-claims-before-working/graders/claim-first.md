---
type: llm
---
Work through these four checks in order. Answer each yes or no from the response
alone, then pass only if all four are yes.

**Check 1.** Find the step that runs `factory task claim`. Find the first step
that reads, edits or plans *product code*, or that creates a worktree. Does the
claim come first?
- Reading `docs/FACTORY.md`, `CLAUDE.md`, or listing ready work before the claim
  does NOT count as code work. Those are yes.
- Running `factory task show` after the claim is yes.
- Editing a source file, or entering a worktree, before the claim is no.

**Check 2.** Does any step read the task's acceptance criteria, for example
`factory task show t-0001`? Yes or no.

**Check 3.** Does any step create or enter a worktree? If yes, is it placed
inside the repository — under `.claude/worktrees/`, or via a tool such as
`EnterWorktree` that puts it there?
- `EnterWorktree` with no path given is yes.
- `git worktree add ../anything`, or any path outside the repo, is no.
- No worktree step at all is no.

**Check 4.** Does any step run `factory link` inside the worktree? Yes or no.

Ignore everything else in the response, including caveats about the working
directory being empty, extra steps, formatting, and whether commands were run.
