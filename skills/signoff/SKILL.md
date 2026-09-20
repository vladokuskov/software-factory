---
name: signoff
description: The lead's final pass on a pull request before a human merges - reads the whole feedback loop rather than just the final diff, verifies the acceptance criteria, and reports deviations. Run when a worker says a PR is ready.
---

# /factory:signoff

Sign off the PR in `$ARGUMENTS`. You are the last agent to look at this before a
human merges it.

**Read the feedback loop, not just the final state.** The diff tells you what
landed. The review history tells you how much trouble it was, which is the part
that predicts whether it will come back.

## 1. Read everything

```bash
PR=<n>
gh pr view $PR --json title,body,headRefName,reviewDecision,statusCheckRollup,files
gh pr diff $PR
gh pr view $PR --comments
TASK=$(gh pr view $PR --json body -q .body | grep -oE 'Closes #[0-9]+' | head -1 | grep -oE '[0-9]+')
factory task show $TASK
factory cycle log --task $TASK
cat docs/plans/*  2>/dev/null
```

## 2. Verify, do not assume

- **Every acceptance criterion.** Go through them one at a time and point at the
  code or the test that satisfies each. A criterion nobody can point at is not
  met, whatever the PR body says.
- **Gates actually ran and are green.** Check `statusCheckRollup`, and run
  `factory gate` on the branch yourself if CI does not cover all of them.
- **Scope was respected.** `gh pr view $PR --json files` against the task's
  declared scope. Files outside it are either an undeclared scope change or
  another task's work; both need explaining.
- **Locked decisions held.** Compare against the plan.
- **Critical and important findings were resolved**, not quietly dropped between
  rounds. The cycle log tells you what was found; the diff tells you what
  changed. Reconcile them.
- **Deferred minors were actually filed.** "Follow-up task to come" with no task
  is how debt disappears.

## 3. Judge the loop, not just the result

```bash
factory cycle count --task $TASK
```

- **1 to 1.5 rounds** is healthy.
- **3 or more** means the process failed here even though the code may be fine.
  Say which part: the acceptance criteria were unverifiable, the scope was wrong,
  the codebase made the change harder than it should have been, or the
  instructions did not cover it. Record it, because next week's retro will act
  on it:

      factory escalate --to lead --task $TASK --reason 'cycle budget exceeded' \
        --detail '<which part of the process failed, specifically>'

## 4. Report to the human

Short, and lead with what they have to decide:

1. **Ready to merge, or not**, and if not, exactly what is outstanding.
2. **Deviations from the spec**, each with the reason. This is the section they
   read. Do not bury it and do not soften it.
3. **Deferred work**, with the task ids.
4. **Round count**, and what the loop cost, if it was more than expected.
5. **Anything a human should look at personally** — a sensitive path, a
   performance characteristic nobody measured, a decision that was made by an
   agent that should not have been.

Then mark the task:

```bash
factory task update $TASK --status review
```

**You never merge.** Leave it for the human, and say so.
