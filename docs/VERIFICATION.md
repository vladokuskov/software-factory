# What has actually been verified

Written 2026-09-20. This records what was run, not what should work. Anything
not listed here has not been tested; anything listed as unverified is listed
that way on purpose.

Proving ground: `~/projects/factory-scratch`, a small TypeScript CLI with real
lint, typecheck, test and build gates, tracked in GitHub Issues.

## Automated suites

| suite | scope | result |
|---|---|---|
| `tests/conformance.sh` | 18 contract checks per tracker plus concurrency, scope and cycle-log checks | 36 hermetic (file) + 26 live, green on **file**, **github** and **beads** |
| `tests/hooks.sh` | 22 checks: scope allow/deny, sensitive-path precedence, acceptance enforcement, gate detection, debounce, session briefing, fail-open | 22/22 |
| `shellcheck -S warning` | every script in the harness | clean |
| `evals/` | 5 behaviour cases for what only the prompts can carry | schema validated, one case run end to end |

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
dispatched together, each in its own worktree, both reaching green CI and an open
PR (#15, #16) with no conflicts. `src/registry.ts` was held back as a shared
resource and neither worker touched it. The round-counting fix was confirmed in
the field: all three reviewers for task #3 logged as round 1.

**Phase 5 — lead-to-lead coordination.** Two independent sessions on one machine.
Lead A announced a lock on `src/registry.ts` over `SendMessage`; lead B received
it and replied confirming it would defer until released. `/list-agents` showed
both.

**Phase 6 — the unattended jobs.** Both launchd agents installed and loaded
(`com.unicrew.factory.scan`, `com.unicrew.factory.retro`). The scan was run
against a repository whose CI was deliberately red. On the first pass the
failure carried an explicit "deliberate failure" comment, and **the scanner
refused to file it**, reporting it as a self-labelled fixture rather than a
production issue. The failure was then replaced with a genuine regression and
the scan re-run.

## Not verified

- **`TeammateIdle` blocking.** Agent teams do not form under `claude -p`, so a
  scripted `/factory:run` produces parallel subagents rather than teammates. The
  team-specific layer — shared task list, teammate messaging, the `TeammateIdle`
  guardrail — needs an interactive `/factory:run`. The hook emits both a
  `systemMessage` and exit 2 so either documented behaviour lands, but which one
  is real is still an open question.
- **`/factory:retro`.** Needs a week of cycle-log data to be a meaningful test.
  The data it reads is being produced now.
- **The `jira` adapter.** Written against the documented API, never run against a
  live instance.
- **`claude ultrareview`.** Currently returns `Ultrareview is currently
  unavailable` on this account, so the cloud review pass in `/factory:review` has
  not run once.
