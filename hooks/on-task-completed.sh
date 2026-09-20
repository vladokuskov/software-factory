#!/usr/bin/env bash
# TaskCompleted. Informational: records completion in the cycle log so the
# weekly retro can correlate "how many rounds did this take" with "did it land".
set -uo pipefail
. "$(dirname "$0")/_hooklib.sh"
hook_guard

IN="$(hook_input)"; hook_cd "$IN"
project_root >/dev/null 2>&1 || exit 0

task="$("$FACTORY" current get 2>/dev/null | head -1)"
[ -n "$task" ] || task="$(printf '%s' "$IN" | jq -r '.tool_input.task_id // .task.id // "unknown"')"
rounds="$("$FACTORY" cycle count --task "$task" 2>/dev/null || echo 0)"
cycle_append "$task" "$(jq -nc --argjson r "${rounds:-0}" '{event:"task_completed",rounds:$r}')" 2>/dev/null || true

max="$(config_get escalation.maxReviewCycles)"
if [ "${rounds:-0}" -gt "${max:-2}" ]; then
  emit_msg TaskCompleted "Task $task landed, but it took $rounds review rounds (limit $max). That is a signal about the instructions, docs or codebase, not about the worker. It is now flagged for the weekly retro."
else
  emit_msg TaskCompleted "Task $task landed in ${rounds:-0} review round(s)."
fi
exit 0
