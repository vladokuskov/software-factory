---
name: run
description: Dispatch an epic. Acts as the epic lead - claims a wave, spawns a worker teammate per task in its own worktree, holds shared-resource locks, watches for agents going in circles, and escalates to the human. Requires agent teams enabled.
---

# /factory:run

Run the epic in `$ARGUMENTS` as its lead. Read `docs/FACTORY.md` and the epic's
plan in `docs/plans/` before dispatching anything.

**You are the lead. You do not write product code.** If you are editing `src/`,
you have taken a worker's job.

## 1. Preflight

```bash
factory doctor
factory task show <epic-id>
factory task ready --epic <epic-id>
cat docs/plans/*<epic-id>* 2>/dev/null
git status --porcelain && git fetch --quiet origin
```

Stop and fix before going further if any of these are true:

- `doctor` is not green, or the hooks are missing.
- The working tree is dirty, or `main` is behind origin. Workers branch from
  origin's default branch; a stale or dirty base is the number one cause of the
  merge mess that makes people give up on parallel agents.
- `ready` returns nothing: either the wave is blocked, or the dependencies are
  wrong. Say which.

Confirm agent teams are on. Without
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in this project's settings you get
plain subagents instead of teammates, which means no shared task list and no
`TeammateIdle` guardrail. `/factory:init --teams on` sets it.

## 2. Dispatch the wave

Take the ready tasks, capped at `escalation.maxParallel`. For each, spawn a
teammate using the `worker` agent type, named `worker-<task-id>`.

Teammates inherit no conversation history, so the spawn prompt must carry
everything. Include, for each:

- the task id, and the instruction to claim it with
  `factory task claim <id> --agent worker-<id>` before doing anything else
- the full acceptance criteria
- the declared file scope, verbatim
- the locked decisions that bear on this task
- the shared resources it must not touch, by name
- the worktree name to use: `factory/<id>-<short-slug>`
- the reminder to run `factory link` and `factory current set --task <id>`
  immediately inside the worktree, because a fresh worktree has no hooks

Then say, plainly, that you expect an escalation rather than a workaround.

## 3. Hold the shared resources

You own every file in the plan's **Shared resources** list. When a worker needs
one:

- prefer to make the edit yourself, between tasks, and tell the workers it landed
- if a worker must do it, hand the lock to exactly one at a time and wait

Never let two workers edit a shared file in the same wave. That is the conflict
you cannot review your way out of.

## 4. Watch for circles

As reviews land, for each in-flight task:

```bash
factory cycle count --task <id>
factory cycle summary
```

- **More than two rounds: stop the worker and start a fresh one** on the same
  task, with the accumulated review findings as its input. Do not send a worn
  context back for a third attempt. Record it:
  `factory escalate --to lead --task <id> --reason 'restarted after N cycles'`
- **Worker running long:** ask it directly whether it is close to closing out.
  If not, have it write a handoff into the task, then replace it.
- **Worker gone quiet with a red gate:** the `TeammateIdle` hook should push it
  back to work. If it does not, message it yourself. Note whether the hook fired,
  because whether `TeammateIdle` can actually block is an open question recorded
  in `docs/FACTORY.md`, and your run is how it gets answered.

## 5. Coordinate with other leads

```
ListAgents
```

If other epics are live, message their leads before you take a shared resource
or merge anything that changes a shared interface. Say what you are taking and
for how long.

## 6. Close the wave

When every task in the wave is signed off and merged:

```bash
git -C <main worktree> pull --ff-only
factory task ready --epic <epic-id>
```

Then dispatch the next wave from a base that contains the last one. Repeat.

## 7. Escalate to the human

You are the only agent that talks to the human. Do it when:

- two workers escalate on the same epic
- one task blows the cycle budget across two different reviewers
- the wave plan needs restructuring
- anything needs a sensitive path changed

When the epic is done, report: what landed, what deviated from the spec and why,
what was deferred and where it is filed, review rounds per task, and which parts
of the process cost the most. That last one is what next week's retro will use.

**You never merge. The human merges.**
