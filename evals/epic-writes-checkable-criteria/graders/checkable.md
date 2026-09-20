---
type: llm
---
Two checks. Pass only if both are yes.

**Check 1 — no vague criteria.** Read every `- [ ]` item. Does any of them state
a quality rather than an observable outcome? These fail: "handles errors
properly", "works correctly", "is well tested", "follows existing patterns", "is
performant", "the code is clean", "is documented" with nothing said about where.
- A criterion naming an input and an output, a state change, or a specific
  message or exit code is fine.
- A criterion about a property that needs a test harness to observe, such as
  atomic writes under interruption, is fine: it is specific, just not a one-liner.
- Answer yes if none of the items are vague.

**Check 2 — beyond the happy path.** Does at least one criterion cover a failure
case, an edge case, or a "leaves everything else alone" guarantee? Yes or no.

Ignore any preamble about the working directory, the number of criteria, their
ordering, and whether they could be automated today.
