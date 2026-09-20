# software-factory

A Claude Code plugin that runs a repository as an agentic software factory:
epics planned on Fable, a team of Opus workers in isolated git worktrees,
adversarial multi-model review, a concrete escalation ladder, and two agents that
run unattended to keep the thing honest.

The premise is not that each agent run is brilliant. It is that errors are
assumed, caught as early in the lifecycle as possible, and that the loop which
catches them measurably improves week over week.

    you ──► /factory:epic ──► /factory:run ──► workers ──► /factory:review ──► /factory:signoff ──► you merge
                                                  │
                     /factory:scan (daily) ───────┴─────── /factory:retro (weekly)

## What is in the box

| | |
|---|---|
| **`factory`** | One CLI every agent talks to. Tasks, gates, cycle log, scope, escalation. |
| **Tracker adapters** | GitHub Issues, a local JSONL file, beads, or Jira, behind one contract. Switching tracker changes no agent prompt. The first three pass the same 24-check suite live; Jira is written but unverified. |
| **7 agents** | epic lead (fable), worker (opus), three reviewers (opus/sonnet/fable), observability scanner, retro analyst. |
| **9 skills** | `/factory:init` `epic` `run` `task` `review` `signoff` `scan` `retro` `status` |
| **6 hooks** | Acceptance criteria enforced at task creation, file scope enforced at write time, gates run on every edit, teammates pushed back from going idle on unfinished work. |
| **The cycle log** | Every review round, escalation and gate failure, recorded. The dataset the weekly retro reads. |
| **launchd jobs** | Daily observability scan, weekly process retro. Budget-capped, least-privilege. |

## Install

```bash
git clone <this repo> ~/projects/software-factory
claude plugin marketplace add ~/projects/software-factory
claude plugin install factory@software-factory
```

Then, in the repository you want to run as a factory:

```
/factory:init
```

That detects your gates and tracker, installs the guardrail hooks into
`.claude/settings.json` without clobbering what is already there, and writes the
rules into `CLAUDE.md`. Re-runnable.

## Use

```
/factory:epic  Add search, tagging and deletion to the CLI    # plan it (interactive, fable)
/factory:run   <epic-id>                                      # dispatch a wave of workers
/factory:task  <task-id>                                      # or just do one task yourself
/factory:status                                               # what is in flight
```

For the unattended half:

```bash
factory schedule add .          # register this project
factory schedule install        # daily scan + weekly retro
factory schedule run scan       # try it now
```

## The rules it enforces

Four of these are enforced by hooks, not by asking nicely:

1. **No task without acceptance criteria.** Rejected at creation. This is the
   highest-leverage rule in the system: the common failure is not wrong code,
   it is work that finished and was still not what was wanted.
2. **Stay in your declared file scope.** Writes outside it are denied. Sensitive
   paths (auth, payments, migrations, secrets, CI) are denied outright and are a
   human decision.
3. **Gates run on every edit**, so a break surfaces on the turn that caused it.
4. **More than two review cycles means the process is wrong, not the worker.**
   The lead starts a fresh worker rather than sending a worn context back, and
   the round is recorded for the weekly retro.
5. Do not relitigate locked decisions without new evidence. Write findings back
   to the task, so the task alone is enough to hand the work over.

`docs/FACTORY.md` is the full SOP, and it is what the agents actually read.

## Read this before running it unattended

- **Agent teams are experimental.** `/resume` does not restore in-process
  teammates, teammates cannot spawn teammates, and task status lags.
- **Whether `TeammateIdle` can block is unresolved** in the documentation. The
  hook emits both a message and exit 2 so either way the feedback lands, but it
  is not yet confirmed against a live team.
- **GitHub claiming is eventually consistent**, not atomic. `file` and `beads`
  are atomic. See `docs/TRACKER-ADAPTERS.md`.
- **This costs real tokens.** Parallelism defaults to 3. Unattended runs are
  budget-capped. If you are burning quota faster than you are shipping, the fix
  is smaller tasks and fewer reviewers, not a bigger team.
- **Budget for maintenance.** People running this shape of workflow report
  spending on the order of 30% of their time on the harness itself. The weekly
  retro is what keeps that number honest rather than an optional extra.

## Development

```bash
tests/conformance.sh        # file adapter, hermetic
tests/hooks.sh              # hook behaviour, hermetic

# plus a live tracker
FACTORY_CONFORMANCE_REPO=~/projects/factory-scratch tests/conformance.sh
FACTORY_CONFORMANCE_REPO=<beads repo> FACTORY_TRACKER=beads tests/conformance.sh
```

`~/projects/factory-scratch` is the proving ground: a small TypeScript CLI with
real lint, typecheck, test and build gates.
