#!/usr/bin/env bash
# PreToolUse on Edit|Write|NotebookEdit.
# Denies writes outside the task's declared file scope, and any write to a
# sensitive path. Both are escalation triggers, not things a worker decides
# for itself.
set -uo pipefail
. "$(dirname "$0")/_hooklib.sh"
hook_guard

IN="$(hook_input)"; hook_cd "$IN"
EVENT=PreToolUse

path="$(printf '%s' "$IN" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -n "$path" ] || { emit_allow "$EVENT"; exit 0; }

# Outside a factory project this hook has no opinion.
project_root >/dev/null 2>&1 || { emit_allow "$EVENT"; exit 0; }

task="$("$FACTORY" current get 2>/dev/null | head -1)"
result="$("$FACTORY" scope check ${task:+--task "$task"} --path "$path" 2>/dev/null || true)"
ok="$(printf '%s' "$result" | jq -r '.ok // false' 2>/dev/null || echo false)"
[ "$ok" = "true" ] && { emit_allow "$EVENT"; exit 0; }

reason="$(printf '%s' "$result" | jq -r '.reason // "out of scope"')"
pattern="$(printf '%s' "$result" | jq -r '.pattern // empty')"

if [ "$reason" = "sensitive" ]; then
  emit_deny "$EVENT" "$path matches the sensitive path '$pattern'. Changes here are a human decision, not an agent one. Stop, and run:
  factory escalate --to human --task ${task:-<task>} --reason 'needs a change under $pattern' --detail '<what you want to change and why>'"
else
  emit_deny "$EVENT" "$path is outside the declared file scope for task ${task:-<unknown>}.
Either it genuinely belongs to another task (leave it alone and say so), or the scope was specced too narrowly. If it is the latter, escalate rather than widening it yourself:
  factory escalate --to lead --task ${task:-<task>} --reason 'scope too narrow' --detail 'need to touch $path because <reason>'
Current scope: $("$FACTORY" scope show --task "${task:-none}" 2>/dev/null | jq -c '.scope' 2>/dev/null || echo '[]')"
fi
exit 0
