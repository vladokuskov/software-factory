---
name: review
description: Run one adversarial review cycle on a pull request - correctness, quality and intent reviewers in parallel on different models, plus a cloud multi-agent pass, triaged and recorded in the cycle log. Use after opening a PR and again after each round of fixes.
---

# /factory:review

Run a review cycle on the PR in `$ARGUMENTS` (a PR number, or the current
branch's PR).

## 1. Gather the context the reviewers need

```bash
PR=<n>
gh pr view $PR --json number,title,body,headRefName,baseRefName,files,additions,deletions
gh pr diff $PR
TASK=$(factory current get)
factory task show ${TASK}
factory cycle count --task ${TASK}
```

Also read the epic's plan in `docs/plans/` for the locked decisions. A reviewer
without the spec reviews the diff against itself, which misses the expensive
half.

If the round count is already at or above `escalation.maxReviewCycles`, say so
before reviewing. This round should probably be an escalation instead.

## 2. Run the reviewers in parallel

Launch all three as subagents **in one message**, so they run concurrently and
cannot anchor on each other:

- **`review-adversarial`** (opus) — correctness and security. Every finding
  needs a concrete failure scenario.
- **`review-quality`** (sonnet) — reuse, simplification, efficiency.
- **`review-intent`** (fable) — the diff against the original task and plan.

Give each: the PR number, the diff, the task with its acceptance criteria, and
the locked decisions. They do not share your context.

In parallel, run the first-party cloud review:

```bash
claude ultrareview $PR --timeout 20
```

That one is a multi-agent pass on Anthropic's infrastructure and finds a
different distribution of things than local reviewers do. Fold its findings in
with the rest.

## 3. Triage

Merge the findings, dropping duplicates. Where two reviewers disagree, say so
explicitly rather than silently picking one: a disagreement is usually a spec
ambiguity, which is worth more to the retro than either verdict.

- **critical** — wrong behaviour, data loss, security. Must be fixed.
- **important** — will bite under realistic conditions. Fix, or argue down in a
  PR comment with reasoning.
- **minor** — worth doing, does not block. Defer only into a task you file.

Discard findings with no concrete failure scenario behind them. Unfounded
findings cost a round and teach the factory nothing.

## 4. Record the round

One entry per reviewer. This is not bookkeeping; it is the dataset the weekly
retro reads, and without it the cycle budget is unenforceable.

```bash
factory cycle append --task ${TASK} --pr $PR \
  --reviewer review-adversarial --model opus \
  --findings '{"critical":0,"important":2,"minor":3}' \
  --outcome changes_requested --tokens <n>
```

`--outcome` is `approved` or `changes_requested`. Repeat for each reviewer,
including `ultrareview`.

## 5. Report

- counts by severity, per reviewer
- the critical and important findings, each with its failure scenario
- what you plan to fix versus argue down
- the new round count, and whether it is over budget

If this was round three or later, do not start a fourth. Escalate:

```bash
factory escalate --to lead --task ${TASK} --reason 'over cycle budget' \
  --detail '<what the reviewers keep finding>'
```

## Optional: a non-Anthropic opinion

If the project has another agent CLI configured (`opencode` is installed on this
machine), running one reviewer on a different vendor's model catches a
genuinely different slice of problems. Worth it on high-risk changes; not worth
the tokens on routine ones.
