## Software factory

This repository is run as a software factory. The rules below are not style
preferences; the hooks in `.claude/settings.json` enforce most of them.

**Before work starts**
- Every task carries acceptance criteria that are checkable without reading the diff.
  A task without them is rejected at creation.
- Every task declares a file scope. Writes outside it are denied. If the scope is
  genuinely too narrow, escalate instead of widening it yourself.

**While working**
- Stay on your own task. If you notice something broken elsewhere, file a task, do not fix it.
- Do not relitigate a decision that is already locked unless you have new evidence.
  If you do have new evidence, say what it is.
- Write findings and decisions back to the task as you go. The task alone should be
  enough for someone else to pick the work up cold.
- Gates run on every edit. A red gate is a stop, not a warning.

**When to escalate rather than push on**
- More than `escalation.maxReviewCycles` review rounds on one PR.
- The same gate failing `escalation.maxGateRetries` times.
- Needing to touch a sensitive path.
- Believing a locked decision is wrong.
- Running long enough that you are near the context handoff threshold and not close to done.

  `factory escalate --to lead|human --task <id> --reason '<short>' --detail '<what you tried>'`

**Commands**

    factory task ready                      what is available to work on
    factory task claim <id> --agent <name>  take it (first caller wins)
    factory gate                            run every gate
    factory cycle count --task <id>         review rounds so far
    factory doctor                          check the wiring

**Skills**: `/factory:epic` `/factory:run` `/factory:task` `/factory:review` `/factory:signoff` `/factory:status` `/factory:scan` `/factory:retro`
