---
name: scan
description: Scan CI failures, error trackers and logs for problems, deduplicate against open work, and file specced tasks for what is worth fixing. Runs daily and unattended via launchd; also usable on demand.
---

# /factory:scan

Find what is broken and file it. Usually runs unattended, so the bar is: **file
nothing you would not want to wake up to.**

## 1. What is enabled

```bash
factory config get observability.githubActions
factory config get observability.sentry
factory config get observability.logPaths
```

## 2. Collect

**GitHub Actions**, if enabled:

```bash
gh run list --status failure --limit 30 --json databaseId,name,headBranch,conclusion,createdAt,event
# then, for the ones from the last 24h on the default branch:
gh run view <id> --log-failed 2>/dev/null | tail -80
```

Ignore a single failure that passed on retry. Care about the same failure three
times, and about anything failing on the default branch.

**Sentry**, if enabled and a connector is available: unresolved issues from the
last 24 hours, ranked by event count and users affected.

**Log paths**, if configured: stack traces, `ERROR` and `FATAL`, and repeated
warnings. A single occurrence of anything is not a finding.

## 3. Deduplicate — this is the part that matters

Group by **error class**, not by occurrence. Twenty crashes from one missing
null check is one task, not twenty.

Then drop anything already known:

```bash
factory task list | jq -r '.[] | select(.status != "done") | "\(.id)  \(.title)"'
```

Drop it if it matches an open task, or a task closed in the last two weeks, or a
documented known issue. When in doubt, drop it and mention it in the summary. A
scanner that files duplicates gets ignored within a week, and then it is worse
than having no scanner.

## 4. File what survives

```bash
factory task create --title "<specific and searchable>" \
  --body-file <f> --scope "<files that actually have to change>" \
  --priority <1|2|3>
```

The body needs:

- what fails, with the exact error text and the call site
- frequency, over what window, affecting how many runs or users
- first seen, and the commit or deploy it correlates with
- **acceptance criteria** as `- [ ]` items (a task without them is rejected)
- a reproduction, or an honest statement that you could not construct one

`--priority 1` only for something actively breaking users or the default branch.
You are not the one being paged. Calibrate down.

## 5. Summarise

- what you looked at, and over what window
- distinct error classes found
- what you filed, with ids
- **what you deliberately skipped, and why**

That last list is the important one. It is how a human notices the scanner is
suppressing something it should not be.

If nothing is wrong, say so in one line. Do not manufacture work.
