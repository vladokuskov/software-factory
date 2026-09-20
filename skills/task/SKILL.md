---
name: task
description: Take one specced task from claim to a reviewed pull request - claim, isolated worktree, implement, gates, PR, adversarial review cycle. The single-worker loop, usable on its own without an agent team.
---

# /factory:task

Take the task in `$ARGUMENTS` to a reviewed PR. If no id was given, run
`factory task ready` and ask which one.

Read `docs/FACTORY.md` if you have not this session.

## 1. Claim it

```bash
factory task claim <id> --agent worker-<id>
```

If this returns `ok:false`, someone else holds it. **Stop.** Report who and pick
something else. Working a contested task is how two agents produce two
conflicting PRs for the same thing.

## 2. Read the spec properly

```bash
factory task show <id> | jq '{title, acceptance, scope, deps, body}'
```

Restate the acceptance criteria in your own words and check each one is
verifiable without reading the diff. If any is not, say so **now**, before
writing code. A criterion you cannot check is a review round you are going to
spend later.

Read the epic's plan in `docs/plans/` for the locked decisions and the shared
resources. Do not reopen the former; do not touch the latter.

## 3. Isolate

Work in a worktree. This repository's `CLAUDE.md` authorises it, and parallel
work depends on it.

Enter a worktree named `factory/<id>-<short-slug>`, then immediately, inside it:

```bash
factory link                 # a fresh worktree has no hooks; without this the guardrails do not run
factory current set --task <id>
factory scope set --task <id> --paths "<scope from the task, comma-separated>"
factory doctor               # must show green hooks before you write anything
```

## 4. Implement

The smallest change that satisfies every criterion. Tests are part of the task,
not a follow-up.

The guardrails are working with you here, not against you:

- A **denied write** means the path is out of scope or sensitive. That is
  information. Either it belongs to another task, in which case leave it and say
  so, or the scope was too narrow, in which case escalate. Never widen your own
  scope.
- A **red gate after an edit** is a stop. Fix it on that turn. Gates that go red
  and stay red while you keep building are how a small mistake becomes a long
  review.

Record what you learn as you go:

```bash
factory task comment <id> --body-file <f>
```

Evidence, decisions, dead ends, why you abandoned an approach. The test: could
another agent pick this up cold from the task alone?

## 5. Gates, then PR

```bash
factory gate --task <id>
```

Green before you push. Then commit, push, and open the PR using
`${CLAUDE_PLUGIN_ROOT}/templates/pr-body.md.tpl`: what changed, each acceptance
criterion and how it is satisfied, **every deviation from the spec**, and the
gate results.

Deviations are the part a human actually reads. Do not bury them.

```bash
factory task link-pr <id> --pr <n>
```

## 6. Review cycle

```
/factory:review <pr>
```

Resolve every critical and important finding, or argue it down in a PR comment
with reasoning. Minor findings may be deferred, but only into a task you file.

Re-run `/factory:review` after your fixes. **If you reach a third round, stop
and escalate:**

```bash
factory escalate --to lead --task <id> --reason 'over cycle budget' \
  --detail '<what the reviewers keep finding, and what you have tried>'
```

Three rounds is not a signal that you should try harder. It is a signal that the
spec, the docs or the codebase is wrong, and that belongs to the lead.

## 7. Hand back

Report: the PR number, the round count, what deviated from the spec, and
anything you deferred and filed. Leave the task in `review`; the lead signs off
and the human merges.
