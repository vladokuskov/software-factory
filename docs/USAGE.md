# Using it

A walkthrough in the order you actually do things. `docs/FACTORY.md` is the
process the agents follow; this is the part you drive.

## One-time, per repository

Open Claude Code in the repo and run:

```
/factory:init
```

It detects your gates and tracker, installs the guardrail hooks into
`.claude/settings.json` without clobbering anything already there, and appends
the factory rules to `CLAUDE.md`. Then check two fields in
`.factory/config.json` by hand, because everything downstream trusts them:

- **`gates`** — run `factory gate` on a clean checkout. If it fails there, the
  gate commands are wrong, and every worker is about to believe them.
- **`sensitivePaths`** — anything listed here is denied to agents outright and
  needs you. Auth, payments, migrations, secrets, CI config are the defaults.
  Being generous here is cheap.

`factory doctor` should be green before you run anything else.

## The two ways to use it

### One task at a time

This is the cheaper mode and the one to start with. No agent team, no lead.

```
/factory:status          what is ready, what is in flight, what needs you
/factory:task 42         take task 42 to a reviewed PR
```

`/factory:task` claims the task, enters its own worktree, implements, keeps the
gates green, opens the PR, then runs a review cycle with three reviewers on
three different models. It hands back when the PR is ready. You merge.

About $4 per task with the full review cycle.

### A whole epic

```
/factory:epic  Add search, tagging and deletion to the CLI
```

Interactive, on Fable. It interrogates the goal before accepting it, writes
tasks with acceptance criteria that are checkable without reading the diff,
groups them into waves with disjoint file scopes, and records the locked
decisions and the shared resources. **This step decides every downstream cost**,
so stay in it and argue with it.

Then:

```
/factory:run 1           dispatch wave 1 of epic 1
```

The lead claims the wave, spawns one worker per task in its own worktree, holds
the shared resources, watches for workers going in circles, and escalates to you.
About $6 per task.

Run this **in a terminal, not headless**. Under `claude -p` agent teams do not
form, so you get parallel subagents without the shared task list, teammate
messaging or the idle guardrail.

## The loop you are in

You are not reviewing code line by line. You are reviewing the feedback loop.

```
/factory:signoff 15      the lead's final pass: verifies every criterion, reads
                         the whole review history, reports deviations
```

Then read the deviations section and merge. The round count is the number to
watch: 1 to 1.5 is healthy, 3 or more means the spec, the docs or the codebase
is wrong, not the worker.

```
factory cycle summary | jq '.overCycleLimit, .escalations, .handoffs'
```

## When something needs you

Agents escalate rather than improvise. You will see:

- **`escalated to human`** in a report, for a sensitive path, a plan that needs
  restructuring, or two workers stuck on the same epic.
- **A task over the cycle budget.** Do not push the worker harder; ask what the
  reviewers kept finding and fix that.
- **A denied write.** Either the scope was specced too narrowly, which is yours
  to widen in the task, or the file belongs to someone else, which is correct.

## The unattended half

Off by default. Turn it on per project:

```bash
factory schedule add .          register this repo
factory schedule install        daily scan 08:47, weekly retro Mondays 09:13
factory schedule status         what is installed and what ran
factory schedule uninstall      stop everything
```

Try each one by hand first:

```bash
factory schedule run scan       reads CI failures and error sources, files tasks
factory schedule run retro      reads the cycle log, proposes process changes
```

The scan files a task only for a real, deduplicated error class, and is
deliberately reluctant. The retro opens a branch on **this** repository with at
most three changes and a write-up; it never merges. Both are capped by
`budget.scanUsd` and `budget.retroUsd`.

## Several epics at once

Each lead is its own terminal session. They find each other with `/list-agents`
and coordinate over messages. Before taking a shared resource, tell the lead to
announce it:

```
Tell the other lead I'm taking src/registry.ts for the next 20 minutes
```

## Switching tracker

`.factory/config.json:tracker` is one of `github`, `file`, `beads` or `jira`.
Nothing else changes: no agent prompt or skill mentions a tracker by name. See
`docs/TRACKER-ADAPTERS.md` for what each one guarantees about claiming, which is
the thing that matters when several workers run at once.

## When it goes wrong

| symptom | cause |
|---|---|
| Hook errors in a worktree | `factory link` was not run inside it |
| Every write denied, wrong task named | stale binding: `factory current clear` |
| `factory gate` fails on a clean checkout | the gate commands in config are wrong |
| A worker says a task is contested | someone else holds the claim; `factory task show <id>` says who |
| Reviews keep finding the same thing | that is the retro's job; run it |

`factory doctor` first, always. It reports the tracker, the hook link, the state
directory, the gates and what the tree is bound to.
