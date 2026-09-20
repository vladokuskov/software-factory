---
name: status
description: Show what the factory currently has in flight - ready work, claimed tasks, open PRs, review rounds, and anything that has blown its cycle budget or is waiting on a human.
---

# /factory:status

A read-only picture of the factory. Run it before dispatching anything.

```bash
factory doctor
echo '--- ready ---';    factory task ready
echo '--- all tasks ---'; factory task list
echo '--- cycles ---';   factory cycle summary
```

If the tracker is `github`, also:

```bash
gh pr list --json number,title,headRefName,isDraft,reviewDecision,statusCheckRollup \
  --jq '.[] | "#\(.number) \(.title)  [\(.headRefName)]  \(.reviewDecision // "no review")"'
```

And, if other sessions may be running leads:

Use `ListAgents` to see what else is live on this machine.

## Report

Lead with what needs a decision, not with a list of everything.

1. **Waiting on you.** Escalations to human, PRs signed off and ready to merge,
   anything blocked on a sensitive path.
2. **Over budget.** Tasks in `cycle summary --> overCycleLimit`, and tasks that
   hit `gateRetryLimits`. For each, say how many rounds and what the reviewers
   kept finding. These are process problems, not worker problems; name them as
   such.
3. **In flight.** Claimed tasks, who holds them, how long, and their PR state.
4. **Ready.** What could be started now, and whether the wave it belongs to is
   unblocked.
5. **Stale claims.** A task claimed with no PR and no cycle activity for a long
   time usually means a worker died. Say so and suggest
   `factory task release <id>`.

Keep it short. If nothing needs a decision, say that in one line.
