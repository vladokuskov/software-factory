# Evals

Five cases covering the behaviours that only the prompts can carry: escalating
instead of widening scope, criteria that are checkable without the diff, review
findings that come with a concrete failure scenario, claiming before working, and
never merging.

    claude plugin eval . --runs 3 --trust-plugin --judge-model sonnet

**Use `--judge-model sonnet`.** The default judge is haiku, and it misgraded
these rubrics: it voted unanimously to fail a response that satisfied every
listed check, three runs in a row. Sonnet grades the same responses correctly.
Rubrics here are written as numbered yes/no checks for the same reason.

## What these can and cannot tell you

Each case runs a generic Claude with the plugin installed, in an **empty sandbox
with no git**, so they measure what the plugin's skills and documentation carry
into a fresh session. They do **not** exercise `agents/*.md`, because those apply
only when the agent is actually invoked, and they cannot run against a real
factory project on this machine: the sandbox has no working `git`, so a
`scaffold_script` that builds one fails.

So read a failure as "a fresh session would not know this from the plugin alone",
not as "the worker agent gets this wrong". The agents are verified by the real
runs recorded in `docs/VERIFICATION.md` instead.

## Current numbers

3 runs per case, sonnet judge: **13/15 responses pass, 4 of 5 cases clean.**

`epic-writes-checkable-criteria` sits at 1–2 of 3 and is expected to stay noisy.
It asks a genuinely fuzzy question, and the borderline cases are real judgement
calls: is "registered through the same command-registration path as the existing
commands" a checkable criterion or a restatement of "follows existing patterns"?
Reasonable graders disagree. Treat a swing there as noise and a drop to 0/3 as
signal.

## History

The first full run scored 2/5, and the failures were useful. Two were real:
in a bare sandbox the model read the task before claiming it and put its worktree
outside the repository, which is the placement that breaks the gates. Both are
now called out in `skills/task/SKILL.md` and `docs/FACTORY.md` rather than only
in the agent prompt. The rest were the suite's own fault: cases written as free
text, and a judge too weak for the rubrics.
