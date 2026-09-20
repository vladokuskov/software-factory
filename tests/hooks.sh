#!/usr/bin/env bash
# Hook behaviour. These run against a throwaway project, because a hook that
# blocks the wrong thing is worse than no hook at all.

set -uo pipefail
FACTORY_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$FACTORY_HOME/bin/factory"
H="$FACTORY_HOME/hooks"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n       %s\n' "$1" "${2:-}"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got [$2] want [$3]"; fi; }

TMP="$(mktemp -d)"
cd "$TMP" || exit 1
git init -q; git config user.email t@t; git config user.name t
mkdir -p src/components src/lib src/auth migrations
cat > package.json <<'JSON'
{"name":"hooktest","scripts":{"lint":"true","typecheck":"test ! -f BROKEN","test":"true"}}
JSON
printf 'x\n' > src/lib/store.ts
git add -A >/dev/null; git commit -qm init
"$F" init --tracker file >/dev/null 2>&1
"$F" current set --task t-1 >/dev/null
"$F" scope set --task t-1 --paths "src/components/**,src/lib/store.ts" >/dev/null

pre() { jq -nc --arg c "$TMP" --arg p "$1" '{cwd:$c,hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$p}}'; }
decision() { jq -r '.hookSpecificOutput.permissionDecision // "none"'; }
reason()   { jq -r '.hookSpecificOutput.permissionDecisionReason // ""'; }

printf '\nguard-scope\n'
check "in scope allowed"        "$(pre src/components/A.tsx | "$H/guard-scope.sh" | decision)" "allow"
check "exact file in scope"     "$(pre src/lib/store.ts     | "$H/guard-scope.sh" | decision)" "allow"
check "out of scope denied"     "$(pre src/lib/other.ts     | "$H/guard-scope.sh" | decision)" "deny"
check "sensitive denied"        "$(pre src/auth/login.ts    | "$H/guard-scope.sh" | decision)" "deny"
check "migrations denied"       "$(pre migrations/001.sql   | "$H/guard-scope.sh" | decision)" "deny"
check "ci config denied"        "$(pre .github/workflows/ci.yml | "$H/guard-scope.sh" | decision)" "deny"
check "sensitive beats scope"   "$(pre src/components/auth/x.ts | "$H/guard-scope.sh" | reason | grep -c sensitive)" "1"
check "denial names escalation" "$(pre src/lib/other.ts | "$H/guard-scope.sh" | reason | grep -c 'factory escalate')" "1"
# A tool call with no file path is none of this hook's business.
check "no path -> allow"        "$(jq -nc --arg c "$TMP" '{cwd:$c,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"ls"}}' | "$H/guard-scope.sh" | decision)" "allow"
# Outside a factory project the hook must have no opinion at all.
check "non-project -> allow"    "$(jq -nc --arg p "/tmp/x.ts" '{cwd:"/tmp",hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$p}}' | "$H/guard-scope.sh" | decision)" "allow"

printf '\nrequire-acceptance\n'
acc() { jq -nc --arg c "$TMP" --arg d "$1" '{cwd:$c,hook_event_name:"TaskCreated",tool_input:{description:$d}}' | "$H/require-acceptance.sh"; }
check "with criteria"    "$(acc 'Do a thing

## Acceptance Criteria
- [ ] it prints ok' | decision)" "allow"
check "without criteria" "$(acc 'Just do a thing' | decision)" "deny"
check "denial explains"  "$(acc 'Just do a thing' | reason | grep -c 'Acceptance Criteria')" "1"
# An unrecognised payload must nudge, never block every task in the session.
check "unknown payload fails open" \
  "$(jq -nc --arg c "$TMP" '{cwd:$c,hook_event_name:"TaskCreated",mystery:1}' | "$H/require-acceptance.sh" | decision)" "none"

printf '\ngate-on-edit\n'
post() { rm -f .factory/.last-gate; jq -nc --arg c "$TMP" '{cwd:$c,hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:"src/lib/store.ts"}}' | "$H/gate-on-edit.sh"; }
out="$(post)"; rc=$?
check "green gates -> exit 0" "$rc" "0"
touch BROKEN
out="$(post)"; rc=$?
check "red gates -> exit 2"  "$rc" "2"
check "red gates -> reports the failing gate" "$(printf '%s' "$out" | jq -r '.systemMessage' | grep -c 'typecheck')" "1"
rm -f BROKEN
# The debounce must hold, or a batch of edits costs one gate run per file.
printf '%s' "$(date +%s)" > .factory/.last-gate
before="$(cat .factory/.last-gate)"
jq -nc --arg c "$TMP" '{cwd:$c,hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:"src/lib/store.ts"}}' | "$H/gate-on-edit.sh" >/dev/null
check "debounced within window" "$(cat .factory/.last-gate)" "$before"

printf '\nsession-start\n'
msg="$(jq -nc --arg c "$TMP" '{cwd:$c,hook_event_name:"SessionStart"}' | "$H/session-start.sh" | jq -r '.systemMessage')"
check "states the tracker"    "$(printf '%s' "$msg" | grep -c 'tracker: file')" "1"
check "states the cycle rule" "$(printf '%s' "$msg" | grep -c 'review cycles')" "1"
check "names the current task" "$(printf '%s' "$msg" | grep -c 't-1')" "1"

printf '\na broken hook must not wedge the session\n'
payload="$(pre src/lib/other.ts)"
( PATH=/usr/bin:/bin; export PATH
  printf '%s' "$payload" | "$H/guard-scope.sh" >/dev/null 2>&1; exit $? ) ; rc=$?
if [ "$rc" -eq 0 ]; then ok "fails open when jq is missing (exit 0, edit not blocked)"
else bad "fails open when jq is missing" "exit $rc, which would block the edit"; fi

cd /; rm -rf "$TMP"
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
