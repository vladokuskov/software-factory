#!/usr/bin/env bash
# Adapter conformance: every tracker must answer the same verbs with the same
# JSON shape. Runs hermetically against `file`; pass a repo path in
# FACTORY_CONFORMANCE_REPO to also exercise a live `github` project.

set -uo pipefail
FACTORY_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$FACTORY_HOME/bin/factory"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n       %s\n' "$1" "${2:-}"; }
check() { # check <name> <actual> <expected>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got [$2] want [$3]"; fi
}

# Every record an adapter returns must carry at least these keys.
REQUIRED_KEYS='["acceptance","assignee","body","deps","epic","id","priority","scope","status","title","type"]'

run_suite() {
  local label="$1" dir="$2"
  printf '\n%s\n' "$label"
  cd "$dir" || { bad "$label" "cannot cd"; return; }

  local epic task
  epic="$("$F" task create --type epic --title "Conformance epic" | jq -r .id)"
  [ -n "$epic" ] && ok "create epic" || bad "create epic"

  cat > "$dir/.conf-body.md" <<'MD'
Body text.

## Acceptance Criteria
- [ ] first criterion
- [ ] second criterion
MD
  task="$("$F" task create --epic "$epic" --title "Conformance task" \
      --body-file "$dir/.conf-body.md" --scope "src/**,tests/**" | jq -r .id)"
  [ -n "$task" ] && ok "create task" || bad "create task"

  local rec; rec="$("$F" task show "$task")"
  check "show: key set"     "$(printf '%s' "$rec" | jq -c '[keys_unsorted[]] | . as $k | '"$REQUIRED_KEYS"' | map(. as $r | $k | index($r) != null) | all')" "true"
  check "show: id"          "$(printf '%s' "$rec" | jq -r .id)"                "$task"
  check "show: epic link"   "$(printf '%s' "$rec" | jq -r .epic)"              "$epic"
  check "show: type"        "$(printf '%s' "$rec" | jq -r .type)"              "task"
  check "show: status"      "$(printf '%s' "$rec" | jq -r .status)"            "pending"
  check "show: acceptance"  "$(printf '%s' "$rec" | jq -r '.acceptance|length')" "2"
  check "show: scope"       "$(printf '%s' "$rec" | jq -r '.scope|join(",")')" "src/**,tests/**"
  check "show: priority"    "$(printf '%s' "$rec" | jq -r '.priority')"          "2"
  # --priority was parsed and silently dropped by the github adapter.
  hi="$("$F" task create --epic "$epic" --title "Urgent conformance task" --priority 1 | jq -r .id)"
  check "priority round-trips" "$("$F" task show "$hi" | jq -r .priority)" "1"
  "$F" task update "$hi" --status "done" >/dev/null

  check "ready: contains task" "$("$F" task ready --epic "$epic" | jq -r --arg t "$task" 'map(.id)|index($t) != null')" "true"
  check "ready: excludes epic" "$("$F" task ready --epic "$epic" | jq -r --arg e "$epic" 'map(.id)|index($e) == null')" "true"

  check "claim: first wins"  "$("$F" task claim "$task" --agent agent-a | jq -r .ok)" "true"
  check "claim: second loses" "$("$F" task claim "$task" --agent agent-b | jq -r .ok)" "false"
  check "claim: idempotent"  "$("$F" task claim "$task" --agent agent-a | jq -r .ok)" "true"
  check "ready: hides claimed" "$("$F" task ready --epic "$epic" | jq -r --arg t "$task" 'map(.id)|index($t) == null')" "true"

  check "release"            "$("$F" task release "$task" | jq -r .ok)" "true"
  check "ready: back after release" "$("$F" task ready --epic "$epic" | jq -r --arg t "$task" 'map(.id)|index($t) != null')" "true"

  "$F" task claim "$task" --agent agent-a >/dev/null
  check "update review"      "$("$F" task update "$task" --status review | jq -r .ok)" "true"
  check "status is review"   "$("$F" task show "$task" | jq -r .status)" "review"

  printf 'a comment\n' > "$dir/.conf-comment.md"
  check "comment"            "$("$F" task comment "$task" --body-file "$dir/.conf-comment.md" | jq -r .ok)" "true"
  check "link-pr"            "$("$F" task link-pr "$task" --pr 99 | jq -r .ok)" "true"
  # The round trip, not just the write: link-pr used to report ok and leave
  # `show` reading pr back as null.
  check "link-pr round-trips" "$("$F" task show "$task" | jq -r '.pr')" "99"
  check "update done"        "$("$F" task update "$task" --status "done" | jq -r .ok)" "true"
  check "status is done"     "$("$F" task show "$task" | jq -r .status)" "done"

  # The unattended scanner could not file anything because create shelled out to
  # the system mktemp, which a sandboxed agent may not write to.
  check "create uses no system temp dir" \
    "$(grep -rl 'mktemp' "$FACTORY_HOME/lib/adapters" 2>/dev/null | wc -l | tr -d ' ')" "0"

  rm -f "$dir/.conf-body.md" "$dir/.conf-comment.md"
}

current_suite() {
  local dir="$1"
  printf '\ncurrent-task binding\n'
  cd "$dir" || return
  local t; t="$("$F" task create --title "Binding probe" | jq -r .id)"
  "$F" task claim "$t" --agent agent-a >/dev/null
  "$F" current set --task "$t" >/dev/null
  check "binding is read back"        "$("$F" current get | head -1)" "$t"
  # A binding that outlives its task silently gates every write in the tree
  # against a stale scope. link-pr and a terminal status must release it.
  "$F" task link-pr "$t" --pr 77 >/dev/null
  check "link-pr releases the binding" "$("$F" current get | head -1)" ""
  "$F" current set --task "$t" >/dev/null
  check "stale binding self-expires"   "$("$F" current get | head -1)" ""
  "$F" task update "$t" --status "done" >/dev/null
}

concurrency_suite() {
  local dir="$1" n=12 task
  printf '\nconcurrency (%s parallel claims must yield exactly one winner)\n' "$n"
  cd "$dir" || return
  task="$("$F" task create --title "Race target" | jq -r .id)"
  local tmp; tmp="$(mktemp -d)"
  local i
  for i in $(seq 1 "$n"); do ( "$F" task claim "$task" --agent "w-$i" > "$tmp/$i.json" 2>&1 ) & done
  wait
  local winners; winners="$(cat "$tmp"/*.json | jq -s '[.[]|select(.ok==true)]|length')"
  rm -rf "$tmp"
  check "exactly one winner" "$winners" "1"
}

scope_suite() {
  local dir="$1"
  printf '\nscope and sensitive paths\n'
  cd "$dir" || return
  "$F" scope set --task s-1 --paths "src/components/**,src/hooks/**" >/dev/null
  "$F" scope check --task s-1 --path src/components/Toggle.tsx >/dev/null 2>&1 && ok "in scope allowed" || bad "in scope allowed"
  "$F" scope check --task s-1 --path src/api/server.ts  >/dev/null 2>&1 && bad "out of scope denied" || ok "out of scope denied"
  "$F" scope check --task s-1 --path src/components/auth/Login.tsx >/dev/null 2>&1 && bad "sensitive denied" || ok "sensitive denied"
  "$F" scope check --task s-1 --path migrations/001.sql >/dev/null 2>&1 && bad "sensitive glob denied" || ok "sensitive glob denied"
}

cycle_suite() {
  local dir="$1"
  printf '\ncycle log\n'
  cd "$dir" || return
  "$F" cycle append --task c-1 --reviewer review-adversarial --model opus \
      --findings '{"critical":1,"important":0,"minor":2}' --outcome changes_requested >/dev/null
  "$F" cycle append --task c-1 --reviewer review-quality --model sonnet \
      --findings '{"critical":0,"important":1,"minor":0}' --outcome changes_requested >/dev/null
  "$F" cycle append --task c-1 --reviewer review-intent --model fable \
      --findings '{"critical":0,"important":0,"minor":0}' --outcome approved >/dev/null
  # Three reviewers in one cycle is ONE round, not three.
  check "parallel reviewers = 1 round" "$("$F" cycle count --task c-1)" "1"
  "$F" cycle append --task c-1 --reviewer review-adversarial --model opus \
      --findings '{"critical":0,"important":1,"minor":0}' --outcome changes_requested >/dev/null
  check "same reviewer again = round 2" "$("$F" cycle count --task c-1)" "2"
  check "not over limit at 2 rounds" "$("$F" cycle summary | jq -r '.overCycleLimit|index("c-1") == null')" "true"
  "$F" cycle append --task c-1 --reviewer review-adversarial --model opus \
      --findings '{"critical":0,"important":1,"minor":0}' --outcome changes_requested >/dev/null
  "$F" escalate --to lead --task c-1 --reason "over cycle limit" >/dev/null
  check "over limit at 3 rounds" "$("$F" cycle summary | jq -r '.overCycleLimit|index("c-1") != null')" "true"
  check "escalation recorded" "$("$F" cycle summary | jq -r '[.escalations[]|select(.task=="c-1")]|length')" "1"
}

TMP="$(mktemp -d)"
mkdir -p "$TMP/.factory"
printf '{"tracker":"file"}\n' > "$TMP/.factory/config.json"
LIVE_TRACKER="${FACTORY_TRACKER:-}"
unset FACTORY_TRACKER
run_suite "file adapter" "$TMP"
concurrency_suite "$TMP"
current_suite "$TMP"
scope_suite "$TMP"
cycle_suite "$TMP"
rm -rf "$TMP"

if [ -n "${FACTORY_CONFORMANCE_REPO:-}" ]; then
  [ -n "$LIVE_TRACKER" ] && export FACTORY_TRACKER="$LIVE_TRACKER"
  tracker="${LIVE_TRACKER:-$(cd "$FACTORY_CONFORMANCE_REPO" && "$F" config get tracker)}"
  run_suite "$tracker adapter (live: $FACTORY_CONFORMANCE_REPO)" "$FACTORY_CONFORMANCE_REPO"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
