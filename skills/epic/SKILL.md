---
name: epic
description: Plan an epic interactively - turn a goal into well-specced tasks with acceptance criteria, disjoint file scopes, locked decisions and a wave plan that parallel workers can execute without conflicting. Run this before /factory:run.
---

# /factory:epic

Plan the epic described in `$ARGUMENTS`. This is the highest-leverage step in the
whole factory: every downstream cost is set here. Take your time and stay
interactive. **Do not write any product code in this skill.**

Read `docs/FACTORY.md` first if you have not this session.

## 1. Understand the goal, do not accept it

Read the codebase around the area first, then put these to the user, and answer
them yourself in writing before they do:

- What am I not considering here?
- What is unclear about this, specifically?
- What is a better way to do this?

Then ask for the negative cases explicitly: what should this *not* do, what
would make it wrong, what would a reasonable person expect that this does not
cover. A model left to extrapolate from the user's framing will agree with them.
That is the failure you are guarding against, so push.

Do not move on until you can state the goal in two sentences and the user agrees
that is what they meant.

## 2. Lock the decisions

Write down the choices that are now settled: the approach, the libraries, the
data shapes, the boundaries. These go into the plan as **Locked decisions** and
no worker reopens them without new evidence.

Being explicit here is what stops five workers each inventing their own version
of the same thing.

## 3. Decompose

Aim for tasks that are one focused sitting of work. If a task needs a long
session, it is too big: that is the reliable smell.

For each task:

- **Title** — specific and searchable.
- **Context** — enough that someone picking it up cold needs nothing else.
- **Acceptance criteria** — `- [ ]` items, each checkable *without reading the
  diff*. "Handles errors properly" is not a criterion. "Returns `no matches` and
  exit code 0 when nothing matches" is. A task without these is rejected at
  creation, by a hook, deliberately.
- **File scope** — the specific paths this task may write. Tasks in the same wave
  must not overlap.
- **Out of scope** — what it must leave alone. Usually the more useful half.
- **Dependencies** — task ids that must land first.

Use `${CLAUDE_PLUGIN_ROOT}/templates/task.md.tpl` for the body.

## 4. Wave the work

Group tasks into waves. Within a wave, file scopes are disjoint and tasks run in
parallel. A wave starts only when the previous one is merged, so nobody branches
from a stale base. That single rule prevents most of the merge pain that sinks
parallel agent runs.

List **shared resources** separately: files several tasks need (a registry, a
barrel export, a schema, a lockfile). Workers never touch these opportunistically.
The lead either serialises access or makes the edit itself between waves.

Cap wave width at `escalation.maxParallel` (default 3).

## 5. Write it down

```bash
factory task create --type epic --title "<epic title>" --body-file <f>
```

Then one task per sub-issue, with `--epic`, `--scope`, `--deps` and a body built
from the template. Then the plan:

```bash
mkdir -p docs/plans
# from ${CLAUDE_PLUGIN_ROOT}/templates/parallelization-plan.md.tpl
```

Commit the plan. It is the document the intent reviewer reads later, and it is
the only record of *why* the epic is shaped this way.

## 6. Check your own work

Before you hand this over, verify:

- [ ] Every task has criteria checkable without the diff.
- [ ] No two tasks in one wave share a file scope.
- [ ] Every shared resource is listed, and no task's scope includes one.
- [ ] Dependencies form a DAG, and `factory task ready --epic <id>` returns
      exactly the first wave. **Run it and check.**
- [ ] Locked decisions are written down, not just discussed.

Then show the user the wave plan and say the next step is
`/factory:run <epic-id>`.
