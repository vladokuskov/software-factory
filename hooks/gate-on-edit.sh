#!/usr/bin/env bash
# PostToolUse on Edit|Write.
# Runs the quick gates (format, lint, typecheck) so a break surfaces on the turn
# that caused it instead of at PR time. Debounced, because a batch of edits
# should cost one gate run, not one per file.
set -uo pipefail
. "$(dirname "$0")/_hooklib.sh"
hook_guard

IN="$(hook_input)"; hook_cd "$IN"
EVENT=PostToolUse
project_root >/dev/null 2>&1 || { emit_allow "$EVENT"; exit 0; }

DEBOUNCE="${FACTORY_GATE_DEBOUNCE:-8}"
stamp="$(factory_dir)/.last-gate"
now="$(date +%s)"
if [ -f "$stamp" ]; then
  last="$(cat "$stamp" 2>/dev/null || echo 0)"
  [ $((now - last)) -lt "$DEBOUNCE" ] && { emit_allow "$EVENT"; exit 0; }
fi
printf '%s' "$now" > "$stamp"

task="$("$FACTORY" current get 2>/dev/null | head -1)"
out="$("$FACTORY" gate --quick ${task:+--task "$task"} 2>&1)" && { emit_allow "$EVENT"; exit 0; }

# exit 2 wakes the session when this hook is registered with asyncRewake.
printf '%s\n' "$(jq -nc --arg e "$EVENT" --arg m "Gates are failing after that edit. Fix this before moving on.

$out" '{hookSpecificOutput:{hookEventName:$e},systemMessage:$m}')"
exit 2
