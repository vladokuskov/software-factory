# shellcheck shell=bash
# Shared hook plumbing. Hooks read one JSON object on stdin and answer with a
# JSON object on stdout; see docs/FACTORY.md for which events can actually block.

FACTORY_HOME="${FACTORY_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$FACTORY_HOME/lib/common.sh"
. "$FACTORY_HOME/lib/config.sh"
. "$FACTORY_HOME/lib/glob.sh"
. "$FACTORY_HOME/lib/cycle.sh"

FACTORY="$FACTORY_HOME/bin/factory"

hook_input() { cat; }

# Work from the session's cwd so project_root resolves correctly.
hook_cd() {
  local cwd; cwd="$(printf '%s' "$1" | jq -r '.cwd // empty')"
  [ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" || true
}

# A hook must never take the session down. If anything here is broken, say so
# and get out of the way rather than blocking every edit in the repo.
hook_guard() { trap 'printf "{\"systemMessage\":\"factory hook %s failed; continuing unguarded\"}\n" "$(basename "$0")"; exit 0' ERR; }

emit_allow()  { jq -nc --arg e "$1" '{hookSpecificOutput:{hookEventName:$e,permissionDecision:"allow"}}'; }
emit_deny()   { jq -nc --arg e "$1" --arg r "$2" '{hookSpecificOutput:{hookEventName:$e,permissionDecision:"deny",permissionDecisionReason:$r}}'; }
emit_msg()    { jq -nc --arg e "$1" --arg m "$2" '{hookSpecificOutput:{hookEventName:$e},systemMessage:$m}'; }
