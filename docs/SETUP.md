# Setup

## Requirements

- Claude Code 2.1.224 or later (cross-session messaging), 2.1.178+ for agent teams
- `jq`, `git`
- `gh`, authenticated, if you want the GitHub tracker or the PR loop
- optionally `bd` (`brew install beads`) for the beads tracker
- optionally `tmux` if you want agent-team split panes. Without it teammates run
  in the in-process panel, which works in any terminal. Ghostty does not support
  split panes at all, so on Ghostty the in-process panel is the only option.

## Install the plugin

```bash
claude plugin marketplace add ~/projects/software-factory
claude plugin install factory@software-factory
```

The plugin's `bin/` goes on PATH, so `factory` is available in any session with
the plugin enabled. To use it outside Claude Code as well:

```bash
echo 'export PATH="$HOME/projects/software-factory/bin:$PATH"' >> ~/.zshrc
```

## Initialise a project

```
/factory:init
```

or non-interactively:

```bash
factory init --tracker github --teams on
factory doctor
```

Then check `.factory/config.json` by hand. Two fields are worth real thought:

- **`gates`** — these are what every worker trusts. If `factory gate` fails on a
  clean checkout, fix it before running anything.
- **`sensitivePaths`** — anything in this list is denied to agents outright and
  needs a human. Being generous here is cheap.

## Agent teams

`/factory:run` needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, which
`/factory:init --teams on` writes into the project's `.claude/settings.json`.

Side effect worth knowing: while that is set, any subagent Claude names launches
as a teammate rather than a plain subagent, **in that project**. If you only want
the single-worker loop (`/factory:task`), use `--teams off`.

## The unattended jobs

```bash
factory schedule add ~/projects/my-project
factory schedule install
factory schedule status
```

- `com.unicrew.factory.scan` — daily 08:47
- `com.unicrew.factory.retro` — Mondays 09:13

Both run every registered project through `claude -p` with an explicit tool
allowlist and `--max-budget-usd` from the project's `budget` config. Logs land in
`~/.factory/logs/`, pruned after 30 days. A failed run raises a macOS
notification, because an unattended job nobody hears about is a job that is not
running.

Test before trusting:

```bash
factory schedule run scan
```

To remove: `factory schedule uninstall`.

## Worktrees

Workers run in git worktrees. A fresh worktree has no `.factory/hooks` symlink,
so the first thing a worker does inside one is:

```bash
factory link
```

State (cycle logs, claims, scope, locks) always resolves to the **main**
worktree, so every worker and the lead share one view. `factory doctor` shows
which state directory is in use and warns when the hook link is missing.

## Uninstall

```bash
factory schedule uninstall
claude plugin uninstall factory@software-factory
```

Per project: remove `.factory/`, the factory hook entries from
`.claude/settings.json`, and the `## Software factory` section from `CLAUDE.md`.
