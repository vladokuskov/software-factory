#!/usr/bin/env bash
# TaskCreated.
# A task without acceptance criteria is the single most reliable way to get work
# that technically finished and is still wrong. Reject it at creation.
#
# Fails open on an unrecognised payload shape: a hook that cannot read the task
# should nudge, not block every task in the session.
set -uo pipefail
. "$(dirname "$0")/_hooklib.sh"
hook_guard

IN="$(hook_input)"; hook_cd "$IN"
EVENT=TaskCreated

desc="$(printf '%s' "$IN" | jq -r '
  [.tool_input.description?, .tool_input.prompt?, .tool_input.content?,
   .task.description?, .task.body?, .description?, .prompt?, .subject?]
  | map(select(type == "string" and length > 0)) | first // empty')"

if [ -z "$desc" ]; then
  emit_msg "$EVENT" "factory: could not read this task's description, so acceptance criteria were not checked. Make sure it has an '## Acceptance Criteria' section with '- [ ]' items."
  exit 0
fi

if printf '%s' "$desc" | grep -qiE '^\s*[-*]\s*\[[ x]\]' ; then
  emit_allow "$EVENT"; exit 0
fi

emit_deny "$EVENT" "This task has no acceptance criteria, so nothing can tell us when it is done.

Add an '## Acceptance Criteria' section with '- [ ]' items that are checkable without reading the diff. Before you write them, answer these three about the task, which is where the good criteria come from:
  - what am I not considering here?
  - what is unclear about this?
  - what is a better way to do this?

Then create the task again."
exit 2
