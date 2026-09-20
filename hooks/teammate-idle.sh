#!/usr/bin/env bash
# TeammateIdle.
# A teammate going idle with red gates or an unlinked PR is the most common way
# work silently stalls. Push back before it parks.
#
# NOTE: the agent-teams docs say exit 2 keeps the teammate working; the hooks
# reference lists TeammateIdle as informational-only. We emit both a
# systemMessage and exit 2, so whichever is true, the feedback lands.
set -uo pipefail
. "$(dirname "$0")/_hooklib.sh"
hook_guard

IN="$(hook_input)"; hook_cd "$IN"
project_root >/dev/null 2>&1 || exit 0

task="$("$FACTORY" current get 2>/dev/null | head -1)"
[ -n "$task" ] || exit 0

status="$("$FACTORY" task show "$task" 2>/dev/null | jq -r '.status // "unknown"')"
case "$status" in
  done|review) exit 0;;
esac

if ! out="$("$FACTORY" gate --quick --task "$task" 2>&1)"; then
  emit_msg TeammateIdle "Do not stop yet: task $task is still '$status' and the gates are red.

$out

Fix the gates, or if you are genuinely stuck, escalate rather than going idle:
  factory escalate --to lead --task $task --reason '<why>' --detail '<what you tried>'"
  exit 2
fi

emit_msg TeammateIdle "Task $task is still '$status' with green gates. Finish it: open the PR and run the review cycle, or escalate to the lead with what is blocking you."
exit 2
