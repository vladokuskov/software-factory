# Tracker adapters

Agents never call `gh`, `bd` or a Jira API directly. They call `factory task <verb>`,
and `.factory/config.json:tracker` decides which adapter answers. That keeps every
skill and agent prompt identical across projects that track work in different places.

## The contract

Every adapter implements these functions and emits the shapes below on stdout.
`tests/conformance.sh` enforces this; run it against any new adapter before using it.

| verb | args | stdout |
|---|---|---|
| `ready` | `[--epic ID] [--limit N]` | array of task records: open, unclaimed, all dependencies done |
| `show` | `ID` | one task record |
| `list` | `[--epic ID]` | array of task records |
| `create` | `--title T [--epic ID] [--body-file F] [--deps a,b] [--scope g,g] [--type task\|epic] [--priority N]` | `{ok,id[,url]}` |
| `claim` | `ID --agent NAME` | `{ok,id,assignee}` — first caller wins, idempotent for the holder |
| `release` | `ID` | `{ok,id}` |
| `update` | `ID --status pending\|in_progress\|review\|done\|blocked` | `{ok,id,status}` |
| `comment` | `ID --body-file F` | `{ok,id}` |
| `link-pr` | `ID --pr N` | `{ok,id,pr}` |

### The task record

```json
{
  "id": "2", "title": "...", "body": "...",
  "acceptance": ["...", "..."],
  "type": "task" | "epic",
  "epic": "1" | null,
  "status": "pending" | "in_progress" | "review" | "done" | "blocked",
  "assignee": "worker-1" | "",
  "deps": ["3"], "scope": ["src/**"],
  "priority": 1 | 2 | 3,
  "pr": 7 | null
}
```

`acceptance` is parsed out of a `## Acceptance Criteria` section containing `- [ ]` items.
A task with an empty `acceptance` array is rejected by the `require-acceptance` hook.

## Claiming, and how strong each guarantee is

Claiming is what stops two agents doing the same task. The guarantees differ:

- **`file`** — a `mkdir`-based lock around a read-modify-write. Genuinely atomic
  (`mkdir` is atomic on every POSIX filesystem; macOS has no `flock(1)`). Verified with
  12 concurrent claimants yielding exactly one winner.
- **`beads`** — `bd update --claim` is atomic first-wins in the backing store and
  idempotent for the holder; a losing claimant gets exit 1 and
  `already claimed by <agent>`. The strongest guarantee of the four, and the
  reason to pay the extra dependency for wide fan-out. Verified against bd 1.3.0.
- **`github`** — GitHub has no compare-and-set. We use an *earliest-comment-wins*
  protocol: each claimant posts an HTML-comment marker, re-reads the thread, and the
  marker with the earliest `created_at` (ties broken by comment id) wins. Losers delete
  their own marker. This is eventually consistent rather than atomic: every claimant
  converges on the same winner, but a loser may briefly believe it holds the task.
  Verified with 5 concurrent claimants yielding exactly one winner and one surviving marker.
- **`jira`** — optimistic, via assignee plus a status transition. Weakest of the four.

## Mapping per adapter

### `file`
`.factory/tasks.jsonl`, append-only, last record per id wins. Zero dependencies, offline.
Ids are `t-0001` / `e-0001`. Good for the scratch repo and for projects with no tracker.

### `github`
| concept | representation |
|---|---|
| epic | issue labelled `factory:epic` |
| task | issue labelled `factory:task` |
| epic link | `Epic: #12` line in the body |
| dependencies | `Depends-on: #13, #14` line in the body |
| file scope | `Scope: src/**, lib/**` line in the body |
| status | open+unlabelled = pending, `factory:in-progress`, `factory:review`, closed = done |
| claim | `factory:claimed` label + assignee + claim-marker comment |

`list` filters labels client-side rather than through `gh issue list --label`, because
GitHub's server-side label filter lags issue creation by a second or two and made
`ready` miss tasks that had just been created.

### `beads`
Opt-in: `brew install beads`, then `bd init` in the repo. Verified against bd 1.3.0.

| concept | representation |
|---|---|
| epic | `bd create --type epic` |
| task | `bd create --type task --parent <epic>` |
| dependencies | real `bd` dependency edges (`--deps blocked-by:<id>`), not description text |
| file scope | `Scope: src/**, lib/**` line in the description |
| acceptance | the native `acceptance_criteria` field |
| status | `open` = pending, `in_progress`, `in_progress` + `factory:review` label = review, `blocked`, `closed` = done |
| claim | `bd update --claim` keyed on `BEADS_ACTOR`; the agent name is also written to metadata so `show` reports it back |
| PR | `external_ref`, as `gh-<n>` |

Two reasons to prefer it when fan-out gets wide:

- **`bd ready` is blocker-aware in the tracker**, so dependency resolution is not
  the adapter's job and cannot drift from what the lead believes.
- **All git worktrees in a repo share one `.beads` workspace.** A worker in its own
  worktree sees the same queue as the lead, with no linking step.

Issues live in an embedded Dolt database under `.beads/` and sync over a separate
`refs/dolt/data` ref, so issue history never lands in your source branches.

Two things to know before adopting it: beads has no built-in `review` status, so
the adapter uses `in_progress` plus a `factory:review` label; and beads sends
anonymous command-usage metrics by default, which `bd metrics off` disables.

### `jira`
Jira Cloud REST over `curl`, configured with `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`
and `trackerOptions.jiraProject`. A shell adapter is used rather than the Atlassian MCP
because MCP tools only exist inside a Claude session, and hooks, launchd jobs and
`tests/conformance.sh` all need to reach the tracker without one.

## Adding an adapter

1. Copy `lib/adapters/file.sh` (the reference implementation).
2. Implement every `adapter_*` function in the table above.
3. The contract suite must pass against it:

       cd <a repo configured for your tracker>
       FACTORY_CONFORMANCE_REPO=$PWD FACTORY_TRACKER=yours tests/conformance.sh

   All 24 contract checks must be green, including `link-pr round-trips`, which
   exists because the github adapter once reported `ok:true` for a write that
   `show` could not read back.
4. Document the claim guarantee honestly in this file. An adapter that cannot make
   claiming safe should say so, because `escalation.maxParallel` depends on it.
