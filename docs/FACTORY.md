# The factory SOP

This is the document every agent in the factory works from. It is deliberately
prescriptive: the point of a factory is not that each run is brilliant, it is
that the process catches errors early and keeps catching them as the codebase
and the instructions drift.

The premise, borrowed from the practitioners this design came from: you stop
designing lines of code and start designing the system that reliably produces
good-enough code and repairs itself. Errors are assumed, not avoided. What
matters is how early they are caught and how fast the loop that catches them
improves.

## The loop

```
  you ──────────────► /factory:epic      epic + acceptance criteria + parallelization plan   (opus 1M, max effort, interactive)
                            │
                            ▼
  lead ─────────────► /factory:run       claim a wave, spawn workers, hold the shared locks  (opus 1M, max effort)
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
  worker ───────────► /factory:task      worktree → implement → gates → PR                   (opus, per task)
                            │
                            ▼
  reviewers ────────► /factory:review    adversarial ‖ quality ‖ intent ‖ ultrareview
                            │              ≤ 2 cycles, then escalate
                            ▼
  lead ─────────────► /factory:signoff   final read of the diff and the feedback loop
                            │
                            ▼
  you ──────────────► merge
```

Two agents run on their own, outside this loop:

- `/factory:scan`, daily, reads failed CI runs and error sources and files tasks.
- `/factory:retro`, weekly, reads the cycle log and proposes changes to *this
  process*, not to the product.

## Roles

| role | model | why |
|---|---|---|
| epic lead | opus 1M, max effort | Planning, decomposition and judgement calls. This is the role that argues with you about the goal, and the one whose output every downstream cost is set by, so it gets the largest context and the most thinking. Sees the whole epic; writes no product code. |
| worker | opus | One task, one worktree, one PR. Strong local reasoning is exactly what this needs. |
| adversarial reviewer | opus | Hunts for the failure case. Rewarded for finding, not for approving. |
| quality reviewer | sonnet | Reuse, simplification, efficiency. Cheap and good at this. |
| intent reviewer | fable | Checks the diff against the original plan, not against itself. |
| observability scanner | sonnet | High volume, low judgement. |
| retro analyst | fable | Pattern-finding across many runs. |

Override any of these per project in `.factory/config.json`, both the model and
the thinking depth:

```json
{
  "models": { "lead": "opus[1m]", "worker": "opus", "reviewQuality": "sonnet" },
  "effort":  { "lead": "max",     "worker": "high", "reviewQuality": "medium" }
}
```

Model strings are Claude Code aliases (`opus`, `sonnet`, `haiku`, `fable`), a
full id (`claude-opus-5`), or an alias with a context suffix (`opus[1m]`).
Effort is `low` through `max`. The lead runs at `max` on the 1M window because
planning is where the leverage is: a vague epic costs you every task in it,
while a worker's mistakes are caught by the gates and the review cycle.

## Acceptance criteria

A task without acceptance criteria is rejected at creation. This is the single
highest-leverage rule in the whole system, because the most common failure is
not wrong code, it is work that technically finished and was still not what was
wanted.

Criteria must be checkable without reading the diff. "Handles errors properly"
is not a criterion. "Returns `no matches` and exit code 0 when nothing matches"
is.

When writing them, put these three questions to the model about the task before
accepting its first answer:

- what am I not considering here?
- what is unclear about this?
- what is a better way to do this?

Ask for the negative cases and the alternatives explicitly. A model left to its
own devices will extrapolate from your framing and agree with you, which is the
opposite of useful at spec time.

## Locked decisions

The parallelization plan carries a **Locked decisions** section. Those are
settled. No agent relitigates them.

The exception, and it is a real one: an agent that uncovers *new evidence* that
a locked decision is wrong must say so, state the evidence, and escalate. It
must not quietly work around the decision, and it must not re-argue it from the
same information that was available when it was made.

## Write back to the task

Everything an agent learns that changes the shape of the work goes back into the
task: new evidence, decisions taken, things that turned out to be false, the
reason an approach was abandoned. The test is simple: **the task on its own
should be enough for a different agent, or a person, to pick the work up cold.**

A long-running session is a smell. It usually means the task was not broken down
finely enough, and it always means context that only exists in one agent's head.

## The escalation ladder

Escalation is not failure. It is the mechanism. Use it early.

    factory escalate --to lead|human --task <id> --reason '<short>' --detail '<what you tried>'

**A worker escalates to the lead when:**

| trigger | default |
|---|---|
| review cycles on its PR exceed the limit | `escalation.maxReviewCycles` (2) |
| the same gate fails repeatedly | `escalation.maxGateRetries` (3) |
| it needs to write outside its declared file scope | always |
| it believes a locked decision is wrong, with new evidence | always |
| its context passes the handoff threshold and it is not close to done | `escalation.handoffAtTokens` (500k) |

**The lead escalates to the human when:**

- two workers escalate on the same epic
- one task exceeds the cycle limit across two different reviewers
- the parallelization plan needs restructuring mid-wave
- anything touches a `sensitivePaths` entry

Sensitive paths are denied outright by the `guard-scope` hook. Auth, payments,
migrations, secrets, CI configuration: these are human decisions. An agent that
wants one changed asks for it.

**Calibration.** In a healthy factory the lead re-steers a worker roughly every
other epic, and roughly one epic in three reaches the human. Much less than that
and the ladder is not being used. Much more and the specs are too loose.

## Negative loops

An agent that is going round in circles will not notice on its own. The lead
watches for it:

- **More than two review cycles on one task**: do not send the same worker back
  a third time. Start a fresh worker on the task with the review findings as
  input. A fresh context beats a worn one.
- **Near the context handoff threshold**: ask the worker whether it is close to
  closing out. If it is, let it finish. If it is not, have it write a handoff
  into the task and launch a replacement.
- **Retiring a lead**: the outgoing lead writes a short handoff but stays
  running, so the incoming lead can ask it clarifying questions. Do not shut it
  down until the new lead says it has what it needs.

Every replacement goes through one command, so handoffs are shaped the same way
and land in the cycle log:

    factory handoff --task <id> --file <note> --reason '<why this agent is being replaced>'

The note says what was tried, what was learned, what was ruled out and why, and
what the next step is. The test is the same as for the task itself: the next
agent should be able to continue from the handoff and the task alone. A rising
handoff count in the weekly summary is a task-sizing signal, not a worker
problem.

## Review policy

Every PR gets, in parallel:

1. **adversarial** (opus) — correctness and security. Its job is to find the
   failure case, and it is instructed to give a concrete input-to-wrong-output
   scenario for every finding. A review that approves without having tried to
   break the change has not been done.
2. **quality** (sonnet) — reuse, simplification, efficiency. Is there already a
   function for this? Is this the simplest thing that works?
3. **intent** (fable) — the diff against the *original task and plan*. This is
   the pass that catches the thing local reasoning cannot see: a change that is
   locally correct and globally wrong, or a chance to build an abstraction that
   makes the rest of the epic easy. It is the deliberate answer to the known
   weakness that agents reason well locally and miss the shape of the system.
4. **`claude ultrareview`** — a cloud-hosted multi-agent review, first-party, no
   setup. Run it on the PR and fold its findings in with the rest.

Findings are triaged **critical / important / minor**. Critical and important
must be resolved or explicitly argued down in a PR comment. Minor may be
deferred into a follow-up task, which must actually be filed.

**The cycle budget is 2.** Averaging 1 to 1.5 rounds is healthy. Consistently
needing 3 is not a worker problem, it is a signal that the instructions, the
documentation or the codebase need work. That is what the weekly retro is for.

## The cycle log

`.factory/cycles/<task>.jsonl` records every review round, gate-retry limit,
escalation and completion. It exists so the retro has data instead of anecdote.
Without it the "more than two cycles means fix the process" rule is unenforceable
and the weekly agent has nothing to read.

**A round is one review cycle, not one reviewer.** Three reviewers run in
parallel and all belong to the same round. `factory cycle append` reuses the
current round until a reviewer reports in it twice, and `/factory:review` passes
`--round` explicitly. Counting per reviewer instead trips the two-round
escalation budget on the very first pass, which is exactly what happened on the
first real run of this factory.

    factory cycle count --task <id>     rounds so far
    factory cycle log --task <id>       the raw record
    factory cycle summary --since <ts>  everything, aggregated

## Where worktrees live, and why it matters

Worktrees go **inside the repository**, under `.claude/worktrees/`, which is
where `EnterWorktree` puts them. That is not cosmetic.

npm puts every ancestor directory's `node_modules/.bin` on PATH, so a worktree
inside the repo can run `npm test` using the dependencies already installed at
the repo root. A worktree created outside it (`git worktree add ../foo`) cannot:
the first gate fails with `vitest: command not found`, and the worker either
wastes a full `npm install` or, worse, concludes the project is broken.

The same holds for any toolchain that resolves upwards: `node_modules`, a Python
virtualenv at the root, a vendored toolchain. If you must place a worktree
elsewhere, install dependencies there first and say so in the task.

## Avoiding merge conflicts

The most-reported failure mode of parallel agents is worktrees branched from a
stale base producing conflicts that then get "fixed" into bugs. Three defences:

1. **Waves.** Tasks run in parallel only within a wave. A wave starts when the
   previous one is fully merged, so every worktree branches from a base that
   already contains the previous wave.
2. **Disjoint file scope.** Two tasks in the same wave never declare overlapping
   scope. The `guard-scope` hook enforces it at write time.
3. **Shared resources are serialised by the lead.** A file that several tasks
   must touch (a registry, a barrel export, a schema) is listed under **Shared
   resources** in the plan. Workers do not edit those opportunistically; the
   lead hands out access one at a time, or does the edit itself after the wave.

## Known limitations

Read these before trusting the factory unattended.

- **Agent teams are experimental.** `/resume` and `/rewind` do not restore
  in-process teammates; after a resume the lead may try to message agents that
  no longer exist, and you have to tell it to respawn. Teammates cannot spawn
  teammates. Task status lags: teammates sometimes fail to mark a task complete,
  which blocks its dependents.
- **Agent teams need an interactive session.** Under `claude -p`, Claude does not
  spawn teammates at all: a named subagent runs as an ordinary subagent even with
  agent teams enabled. So `/factory:run` from a script gives you parallel
  subagents, which still gets you waves, worktrees, scopes and parallel PRs, but
  not the shared task list, teammate-to-teammate messaging, or the `TeammateIdle`
  guardrail. For the full team you have to run `/factory:run` in a terminal.
- **`TeammateIdle` blocking is unresolved.** The agent-teams documentation says
  exit code 2 keeps a teammate working; the hooks reference lists the event as
  informational only. `hooks/teammate-idle.sh` emits both a `systemMessage` and
  exit 2 so that whichever is true, the feedback lands. **Still unconfirmed
  against a live team**, because of the point above. Verify it the first time you
  run `/factory:run` interactively, and record the answer here.
- **`claude ultrareview` is a hosted service and can be switched off.** It
  currently returns `Ultrareview is currently unavailable` on this account. The
  review skill treats that as "note it and carry on with the three local
  reviewers", and explicitly forbids writing a cycle-log entry for a review that
  did not run.
- **GitHub claiming is eventually consistent, not atomic.** See
  `docs/TRACKER-ADAPTERS.md`. Every claimant converges on the same winner, but a
  loser can briefly believe it holds the task. With `beads` or the `file`
  tracker the claim is genuinely atomic.
- **Cost.** A team of workers plus four reviewers per PR is a lot of tokens.
  `escalation.maxParallel` defaults to 3 for a reason. Headless runs take
  `--max-budget-usd`. If you are burning quota faster than you are shipping,
  the answer is usually smaller tasks and fewer reviewers, not a bigger team.
- **This is not free.** Practitioners running this shape of workflow report
  spending on the order of 30% of their time maintaining the harness itself.
  Budget for that, and treat `/factory:retro` as the thing that keeps the cost
  honest rather than an optional extra.
