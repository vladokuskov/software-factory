# Evals

Five cases covering the behaviours that only the prompts can carry: escalating
instead of widening scope, criteria that are checkable without the diff, review
findings that come with a concrete failure scenario, claiming before working, and
never merging.

    claude plugin eval . --runs 3 --trust-plugin

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

The first full run scored 2/5, and the failures were useful: in a bare sandbox
the model read the task before claiming it, and put its worktree outside the
repository, which is the placement that breaks the gates. Both are now called out
explicitly in `skills/task/SKILL.md` and `docs/FACTORY.md` rather than only in
the agent prompt.
