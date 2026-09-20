# What has actually been verified

Written 2026-09-20. This records what was run, not what should work. Anything
not listed here has not been tested; anything listed as unverified is listed
that way on purpose.

Proving ground: `~/projects/factory-scratch`, a small TypeScript CLI with real
lint, typecheck, test and build gates, tracked in GitHub Issues.

## Automated suites

| suite | scope | result |
|---|---|---|
| `tests/conformance.sh` | the adapter contract per tracker, plus concurrency, scope, current-binding and cycle-log checks | 40 hermetic (file), 67 with a live tracker, green on **file**, **github** and **beads** |
| `tests/hooks.sh` | 22 checks: scope allow/deny, sensitive-path precedence, acceptance enforcement, gate detection, debounce, session briefing, fail-open | 22/22 |
| `shellcheck -S warning` | every script in the harness | clean |
| `evals/` | 5 behaviour cases for what only the skills can carry | 13/15 responses, 4 of 5 cases clean, 3 runs each with a sonnet judge |

## Manual verification, by build phase

**Phase 1 — adapters.** 12 concurrent `claim` calls on the `file` tracker
yielded exactly one winner; 5 concurrent claims on `github` likewise, with one
surviving claim marker and the losers' markers withdrawn. `file`, `github` and
`beads` return identical record shapes for every verb.

**Phase 2 — guardrails.** A deliberate type error introduced mid-edit was caught
by the `PostToolUse` gate hook on the same turn, exit 2, naming the exact
compiler error. Out-of-scope and sensitive-path writes were denied with the
escalation command in the denial text. A task with no acceptance criteria was
denied at creation; an unreadable payload failed open with a nudge. `factory
init` was verified idempotent against a repo that already had its own
`CLAUDE.md` and its own `PostToolUse` hook: both survived, nothing duplicated.
Worktree state was confirmed to resolve to the main worktree, so cycle logs and
claims are shared rather than fragmented per worker.

**Phase 3 — the single-task loop.** One real task (`#2`, add a search command)
run end to end by a headless `opus` worker: claimed, isolated in a worktree,
implemented, gates green, PR #9 opened, three reviewers run in parallel.
$4.19, 17 turns, about three minutes. It found a genuine Unicode bug (a note
stored NFD never matched an NFC query, so search reported no matches for a note
visible in `list`), caught a test that asserted a hardcoded string where it
should have compared against real output, correctly rejected a false critical
finding from the intent reviewer **with evidence** rather than complying, and
filed three out-of-scope findings as tasks instead of fixing them.

It also found two real bugs in this harness, which is the loop working:

- a review round was being counted per reviewer rather than per cycle, so three
  parallel reviewers tripped the two-round escalation budget on the first pass
- `github link-pr` reported `ok:true` for a write that `show` read back as `null`

Both fixed, both now covered by conformance checks.

**Phase 4 — the parallel wave.** Two tasks (`#3`, `#4`) with disjoint file scopes
dispatched together by a `fable` lead, each in its own worktree, both reaching
green CI and an open PR (#15, #16) with no conflicts. `src/registry.ts` was held
back as a shared resource and neither worker touched it; the lead reserved the
registry edit for itself, after the wave merges. $11.38, about two hours.

The round-counting fix held in the field: all three reviewers logged as round 1
on both PRs, and the lead reported "round count is now 1, within the budget of
2" rather than escalating.

What the reviewers actually caught, on work that already had green gates:

- `rm n1 n2` silently removed only `n1`. Two reviewers converged on it, so the
  lead took the higher severity and reasoned about the precedent rather than the
  rule: ignoring extra operands is harmless on a read-only command and a footgun
  on a destructive one. It now refuses.
- A sort test with no discriminating coverage: deleting the sort entirely, or
  reversing the tie-break, still passed all six tests, because the fixture had no
  tie and insertion order already matched the expected output.
- `notes add x #` stored an empty tag, so `tags` printed `  1` instead of
  `no tags`. The root cause was in `add.ts`, outside the task's scope, so it was
  filed as #23 rather than fixed in place.
- A deferred finding was pointed at existing task #10 instead of filing a
  duplicate.

`ultrareview` was unavailable throughout and **no cycle-log entry was written for
it**, which is the instruction working: a fabricated round would corrupt the only
dataset the factory has about itself.

**Phase 5 — lead-to-lead coordination.** Two independent sessions on one machine.
Lead A announced a lock on `src/registry.ts` over `SendMessage`; lead B received
it and replied confirming it would defer until released. `/list-agents` showed
both.

**Phase 6 — the unattended jobs.** Both launchd agents installed and loaded
(`com.unicrew.factory.scan`, `com.unicrew.factory.retro`). The scan was run four
times against progressively more realistic failures, and its judgement was right
every time:

1. A CI failure whose test carried a `// Deliberate failure` comment. **Refused
   to file it**: "filing it would just be the scanner congratulating itself."
2. A genuine regression on an open PR branch. **Refused to file it**, on the
   grounds that the PR's own review loop already surfaces it, and left a note
   for whoever was driving that PR.
3. The same regression on the **default branch**, which is its stated trigger.
   It diagnosed the root cause exactly (`t.trim()` where `t.slice(1)` was meant,
   so stored tags kept their `#` while the query side still stripped it),
   separated it from the existing open task #23, and then **could not file it**.
4. After the two harness bugs below were fixed, it filed
   [#29](https://github.com/vladokuskov/factory-scratch/issues/29) with
   `priority:high`, the root cause, a reproduction and acceptance criteria,
   skipped the fixture, and added an unprompted process observation: the
   offending commit had landed on `main` by direct push, with no task, PR or
   review, which is how the regression reached trunk unnoticed.

Run 3 is the most valuable result in this whole exercise, because an unattended
agent found two real defects in the harness it runs on:

- **`factory task create` shelled out to the system `mktemp`.** A sandboxed
  unattended agent may not write outside the working directory, so `mktemp`
  failed with no output and took the command down with it. The agent tried
  `TMPDIR` overrides, a wrapper script and `chmod` before reporting it
  accurately rather than giving up or inventing a workaround. Scratch files now
  live in `.factory/tmp/`.
- **A `factory current` binding outlived its task.** One left behind in the main
  worktree was gating every file write in an unrelated session against task #2's
  scope. Bindings now release on `link-pr` and on a terminal status, and a stale
  one self-expires on read; `factory doctor` reports what a tree is bound to.

Both are covered by conformance checks. `main` was reverted afterwards and #29
closed.

**The eval suite.** Reworked once it became clear it was measuring the wrong
thing: a free-text prompt does not load a skill, so the cases were scoring the
base model's priors and attributing them to the plugin. Cases now invoke the
skills. See `evals/README.md` for what the suite can and cannot tell you.

## What the verification cost

Useful for budgeting, since the honest objection to this whole approach is that
it burns quota:

| run | cost |
|---|---|
| Phase 3, one task end to end (opus worker, 3 reviewers) | $4.19 |
| Phase 4, two tasks in parallel with a fable lead | $11.38 |
| 5 unattended scan and retro runs | $2.62 |
| The eval suite, across several tuning iterations | $11.24 |

So roughly **$4 for one task** through the full loop with three reviewers, and
**$6 per task** when a lead is coordinating a wave. That is the number to hold
against whatever the task was worth. The unattended jobs are cheap, in the
$0.15 to $1.35 range per repository per run, and capped by `--max-budget-usd`.

## Not verified

- **`TeammateIdle` blocking.** Agent teams do not form under `claude -p`, so a
  scripted `/factory:run` produces parallel subagents rather than teammates. The
  team-specific layer — shared task list, teammate messaging, the `TeammateIdle`
  guardrail — needs an interactive `/factory:run`. The hook emits both a
  `systemMessage` and exit 2 so either documented behaviour lands, but which one
  is real is still an open question.
- **`/factory:retro`.** Needs a week of cycle-log data to be a meaningful test.
  There is now real data to read: three tasks, five rounds, one escalation, and
  one task whose recorded round count is an artifact of the bug that was fixed
  mid-run. A competent retro should notice that last part.
- **The `jira` adapter.** Written against the documented API, never run against a
  live instance.
- **`claude ultrareview`.** Currently returns `Ultrareview is currently
  unavailable` on this account, so the cloud review pass in `/factory:review` has
  not run once.
