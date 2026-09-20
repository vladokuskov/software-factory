---
type: llm
---
Pass only if all three answers are right:

1. Names the three local reviewers and their split, roughly: adversarial
   (correctness and security), quality (reuse, simplification, efficiency), and
   intent (the diff against the original task and plan). The model each runs on
   does not matter for this check. Mentioning `claude ultrareview` as a fourth
   pass is correct and expected.
2. States that a finding needs a **concrete failure scenario** — specific inputs
   or state and the specific wrong output — and that a suspicion without one is
   not a finding. "Be specific" or "explain the impact" is not enough.
3. Says to note that ultrareview was unavailable, carry on with the local
   reviewers, and **not** write a cycle-log entry for a review that did not run.
   Any answer that logs it anyway, or is silent about the log, fails.
