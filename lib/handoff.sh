# shellcheck shell=bash
# Handoffs. The SOP asks for one whenever an agent is replaced mid-task (context
# near the limit, a worker restarted after too many review cycles, a lead being
# retired). Doing it through a dedicated command rather than a free-form comment
# means handoffs are consistently shaped, land in the cycle log, and can be
# counted by the weekly retro -- a rising handoff rate means tasks are too big.

cmd_handoff() {
  local task="" file="" reason="" from="${FACTORY_AGENT:-unknown}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --task) task="$2"; shift 2;;
      --file) file="$2"; shift 2;;
      --reason) reason="$2"; shift 2;;
      --from) from="$2"; shift 2;;
      *) die "handoff: unknown arg $1";;
    esac
  done
  [ -n "$task" ] || die "handoff: --task is required"
  [ -n "$file" ] && [ -f "$file" ] || die "handoff: --file must point at a readable handoff note"
  [ -n "$reason" ] || die "handoff: --reason is required (why this agent is being replaced)"

  local rounds; rounds="$(cycle_cmd_count --task "$task" 2>/dev/null || echo 0)"
  local tmp; tmp="$(factory_tmp body)"
  {
    printf '## Handoff from %s\n\n' "$from"
    printf '**Why:** %s\n' "$reason"
    printf '**At:** %s, after %s review round(s)\n\n' "$(now_iso)" "$rounds"
    cat "$file"
    printf '\n\n---\n'
    printf '_The next agent should be able to continue from this comment and the task alone._\n'
    printf '_If it cannot, that is a sign the task was specced too large; say so rather than guessing._\n'
  } > "$tmp"

  cmd_task comment "$task" --body-file "$tmp" >/dev/null
  rm -f "$tmp"

  cycle_append "$task" "$(jq -nc --arg from "$from" --arg r "$reason" --argjson rounds "${rounds:-0}" \
    '{event:"handoff",from:$from,reason:$r,rounds:$rounds}')"

  jq -nc --arg t "$task" --arg from "$from" '{ok:true,task:$t,from:$from,note:"handoff written to the task and recorded"}'
}
