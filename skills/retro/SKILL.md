---
name: retro
description: Weekly process retro - read the factory's own cycle logs, find recurring failure modes in how work is specced and reviewed, and open a PR that changes the process. Improves the factory, never the product.
---

# /factory:retro

Improve **the factory**, not the product. If you end up proposing a product
change, file it as a task and get back to the process.

This exists because of a rule the factory runs on: when tasks consistently take
more than two review cycles, the problem is the instructions, the documentation
or the codebase, not the worker. Your job is to work out which.

## 1. The numbers

```bash
SINCE=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
factory cycle summary --since "$SINCE" | jq .
```

That gives rounds per task, findings by severity, which reviewer found what,
escalations with reasons, gate-retry limits hit, and which tasks blew the budget.

Then read the text behind the worst numbers: `factory cycle log --task <id>`,
the PR discussions, and the tasks themselves. Numbers tell you where to look;
only the text tells you why.

## 2. Look for patterns, not incidents

One task taking four rounds is noise. Four tasks taking three rounds each for
the same reason is a finding. Specifically worth checking:

- **Repeating findings.** The same class of review finding across unrelated
  tasks means a standard exists in a reviewer's head and nowhere a worker reads.
- **Under-specified tasks.** Escalations that amount to "the task did not say".
  Fix the task template or the epic-lead prompt.
- **Over-specified tasks.** Work that came out rigid and fragile because the task
  prescribed the implementation instead of the outcome. Look for review findings
  that amount to "more complicated than it needed to be". Harder to spot, more
  expensive.
- **Scope drawn wrong.** Repeated `scope too narrow` escalations mean the lead is
  drawing boundaries that do not match how the codebase is actually organised.
- **Reviewers not earning their keep.** A reviewer with no critical or important
  findings for weeks is either redundant or broken. Say which. Removing a
  reviewer is a legitimate, and cheap, outcome.
- **Gate gaps.** A bug class that review keeps catching and the gates never do is
  a missing lint rule or a missing test. It should stop costing a review round.

## 3. Change something

Open a branch on the **harness** repository and a PR containing:

1. `docs/retros/<YYYY-MM-DD>.md` — what you saw with the numbers, and what you
   concluded, citing specific tasks and rounds. An unsourced claim is not useful.
2. **The actual edits.** An agent prompt, the task template, the `CLAUDE.md`
   rules, a gate. A retro that only describes a problem changes nothing.
3. For each change: what it should prevent, and what you would expect to see in
   next week's numbers if it worked. That is how the next retro knows whether to
   keep it.

## 4. Restraint

- **Propose, never merge.** Open the PR and stop.
- **At most three changes.** A process that changes in ten places at once cannot
  be evaluated, and you are the one who has to evaluate it next week.
- **If the data does not support a change, propose none.** "Nothing systematic
  this week, here are the numbers" is a good retro. Manufacturing a finding to
  look busy corrodes the only dataset the factory has about itself.
