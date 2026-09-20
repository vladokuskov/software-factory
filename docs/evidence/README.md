# Evidence

Raw artifacts from the verification runs recorded in `../VERIFICATION.md`, kept
here because the repository they came from is disposable and the claims in that
document should not depend on it.

- `2.jsonl`, `3.jsonl`, `4.jsonl` — the cycle logs for the three tasks taken end
  to end. Every review round, with reviewer, model, findings by severity and
  outcome, plus the one escalation. This is the dataset `/factory:retro` read.
- `issues.txt`, `pulls.txt` — the tasks and pull requests those runs produced.

The proving ground itself was a throwaway TypeScript CLI generated for the
purpose. It had no value beyond giving the factory something real to run
against, which is why it is not preserved.
