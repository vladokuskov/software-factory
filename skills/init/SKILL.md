---
name: init
description: Wire the current repository up as a software factory project. Detects the build gates and the tracker, installs the guardrail hooks, and writes the factory rules into CLAUDE.md. Run once per repo, and again after changing gates or moving the harness.
---

# /factory:init

Set this repository up as a factory project. Idempotent: safe to re-run.

## 1. Look before you write

```bash
factory doctor 2>&1 || true
```

If it already reports a project root and green hooks, this repo is initialised.
Ask what the user wants changed rather than re-running blindly.

## 2. Check what will be detected

```bash
git rev-parse --show-toplevel
ls -a | head -30
[ -f package.json ] && jq -r '.scripts // {} | keys | join(", ")' package.json
git remote -v | head -2
```

Confirm with the user before writing:

- **Tracker.** `github` if there is a GitHub remote and `gh` is authed, `beads`
  if `.beads/` exists and `bd` is installed, otherwise `file`. Say which you are
  choosing and why. If the project tracks work in Jira, say so now: that needs
  `JIRA_BASE_URL`, `JIRA_EMAIL` and `JIRA_API_TOKEN` in the environment.
- **Gates.** Which commands are lint, typecheck, test, build. Detection covers
  npm/pnpm/yarn/bun scripts, Cargo, Go, pyproject and Makefile targets. If it
  finds nothing, the gates have to be filled in by hand and you should say so
  plainly rather than leaving an empty object.
- **Agent teams.** `--teams on` (the default) sets
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in this project's settings. That is
  required for `/factory:run`, and it has a side effect worth stating: while it
  is on, any subagent Claude names launches as a teammate rather than a plain
  subagent, in this project. Use `--teams off` if the user only wants the
  single-worker loop.

## 3. Initialise

```bash
factory init --tracker <choice> --teams <on|off>
```

This writes `.factory/config.json`, symlinks `.factory/hooks`, merges the
guardrail hooks into `.claude/settings.json` (preserving anything already
there), and appends the factory section to `CLAUDE.md`.

## 4. Fill in what detection could not

Open `.factory/config.json` and check with the user:

- **`gates`** — anything missing, and anything detected wrongly.
- **`sensitivePaths`** — the defaults cover auth, payments, migrations, secrets
  and CI config. Add whatever is genuinely a human decision in *this* codebase.
  Being too generous here is cheap; being too narrow is how an agent rewrites
  your deploy pipeline at 3am.
- **`escalation.maxParallel`** — 3 unless the user has a reason. More parallel
  workers means more merge risk and more tokens, not proportionally more output.
- **`observability`** — turn on what actually exists for this project.

## 5. Prove it works

```bash
factory doctor
factory gate
```

Both must be green. If `gate` fails on an untouched checkout, the gate commands
are wrong, not the code: fix them now, because every worker is about to trust them.

Then show the user what they have:

```bash
factory task ready
```

Tell them the next step is `/factory:epic` to plan the first epic, or
`/factory:task <id>` if there is already work to pick up.
