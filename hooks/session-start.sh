#!/usr/bin/env bash
# SessionStart. Puts the factory's ground rules and the current state of play
# into context, so a fresh session (or one that just compacted) does not have to
# rediscover them.
set -uo pipefail
. "$(dirname "$0")/_hooklib.sh"
hook_guard

IN="$(hook_input)"; hook_cd "$IN"
project_root >/dev/null 2>&1 || exit 0

task="$("$FACTORY" current get 2>/dev/null | head -1)"
ready="$("$FACTORY" task ready --limit 5 2>/dev/null | jq -r '.[] | "  \(.id)  \(.title)"' 2>/dev/null || true)"

{
  printf 'This is a software factory project (tracker: %s).\n\n' "$(config_tracker)"
  printf 'Non-negotiables:\n'
  printf '  - Every task needs acceptance criteria before work starts.\n'
  printf '  - Stay inside the declared file scope. Out-of-scope or sensitive paths mean escalate, not widen.\n'
  printf '  - Do not relitigate a locked decision unless you have new evidence; if you do, state the evidence.\n'
  printf '  - Write findings and decisions back to the task, so the task alone is enough to hand it over.\n'
  printf '  - More than %s review cycles means the process is wrong, not the worker. Escalate.\n\n' "$(config_get escalation.maxReviewCycles)"
  if [ -n "$task" ]; then
    printf 'This working tree is on task %s (%s).\n' "$task" "$("$FACTORY" task show "$task" 2>/dev/null | jq -r '.title // "?"')"
    printf 'Review rounds so far: %s\n\n' "$("$FACTORY" cycle count --task "$task" 2>/dev/null || echo 0)"
  fi
  if [ -n "$ready" ]; then printf 'Ready work:\n%s\n\n' "$ready"; fi
  printf 'Commands: factory task ready | factory task claim <id> --agent <name> | factory gate | factory escalate\n'
  printf 'Skills: /factory:epic  /factory:run  /factory:task  /factory:review  /factory:signoff  /factory:status\n'
} | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart"},systemMessage:.}'
exit 0
