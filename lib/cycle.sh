# shellcheck shell=bash
# The cycle log: every review round, gate failure and escalation, per task.
# This is the dataset the weekly retro mines, and the basis of the "more than
# two cycles means fix the process" rule. Without it the factory is blind.

cycle_file() { printf '%s/cycles/%s.jsonl\n' "$(factory_dir)" "$1"; }

# cycle_append <task-id> <json-object>
cycle_append() {
  local task="$1" obj="$2" f
  f="$(cycle_file "$task")"
  mkdir -p "$(dirname "$f")"
  printf '%s' "$obj" \
    | jq -c --arg ts "$(now_iso)" --arg task "$task" --arg agent "${FACTORY_AGENT:-unknown}" \
        '. + {ts:$ts, task:$task, agent:(.agent // $agent)}' >> "$f"
}

cycle_cmd_append() {
  local task="" round="" reviewer="" model="" findings="" outcome="" tokens=0 resolved=0 pr="" event=review
  while [ $# -gt 0 ]; do
    case "$1" in
      --task) task="$2"; shift 2;;
      --round) round="$2"; shift 2;;
      --reviewer) reviewer="$2"; shift 2;;
      --model) model="$2"; shift 2;;
      --findings) findings="$2"; shift 2;;
      --outcome) outcome="$2"; shift 2;;
      --tokens) tokens="$2"; shift 2;;
      --resolved) resolved="$2"; shift 2;;
      --pr) pr="$2"; shift 2;;
      --event) event="$2"; shift 2;;
      *) die "cycle append: unknown arg $1";;
    esac
  done
  [ -n "$task" ] || die "cycle append: --task is required"
  [ -n "$findings" ] || findings='{"critical":0,"important":0,"minor":0}'
  # A round is one review CYCLE, not one reviewer. Several reviewers run in
  # parallel and all belong to the same round, so reuse the current round until
  # this reviewer has already reported in it.
  if [ -z "$round" ]; then round="$(_cycle_next_round "$task" "$reviewer")"; fi
  cycle_append "$task" "$(jq -nc \
    --arg event "$event" --arg reviewer "$reviewer" --arg model "$model" \
    --arg outcome "$outcome" --argjson findings "$findings" \
    --argjson round "$round" --argjson tokens "$tokens" --argjson resolved "$resolved" \
    --arg pr "$pr" \
    '{event:$event,round:$round,reviewer:$reviewer,model:$model,findings:$findings,
      outcome:$outcome,tokens:$tokens,resolved:$resolved,
      pr:(if $pr == "" then null else ($pr|tonumber) end)}')"
  jq -nc --arg t "$task" --argjson r "$round" '{ok:true,task:$t,round:$r}'
}

# The round a reviewer's next entry belongs to: the current round if it has not
# reported in it yet, otherwise the next one.
_cycle_next_round() {
  local task="$1" reviewer="$2" f
  f="$(cycle_file "$task")"
  [ -f "$f" ] || { echo 1; return; }
  jq -s --arg r "$reviewer" '
    [.[] | select(.event == "review")] as $rev
    | ($rev | map(.round // 0) | max // 0) as $cur
    | if $cur == 0 then 1
      elif ($rev | any(.round == $cur and .reviewer == $r)) then $cur + 1
      else $cur end' "$f"
}

# Number of review rounds recorded for a task (distinct rounds, not entries).
cycle_cmd_count() {
  local task="" f
  while [ $# -gt 0 ]; do case "$1" in --task) task="$2"; shift 2;; *) shift;; esac; done
  [ -n "$task" ] || die "cycle count: --task is required"
  f="$(cycle_file "$task")"
  [ -f "$f" ] || { echo 0; return; }
  jq -s '[.[] | select(.event == "review") | .round // 0] | unique | length' "$f"
}

cycle_cmd_log() {
  local task=""
  while [ $# -gt 0 ]; do case "$1" in --task) task="$2"; shift 2;; *) shift;; esac; done
  [ -n "$task" ] || die "cycle log: --task is required"
  cat "$(cycle_file "$task")" 2>/dev/null || true
}

# Aggregate across every task. Input to /factory:retro.
cycle_cmd_summary() {
  local since=""
  while [ $# -gt 0 ]; do case "$1" in --since) since="$2"; shift 2;; *) shift;; esac; done
  local dir; dir="$(factory_dir)/cycles"
  # A missing directory is not the same as a quiet week. `factory init` creates
  # it, so if it is gone something deleted it, and the retro must not read the
  # zeros below as "nothing happened".
  [ -d "$dir" ] || {
    jq -nc --arg d "$dir" '{tasks:0,rounds:0,byTask:[],escalations:[],
      warning:("no cycle log at " + $d + ": the directory is missing, not empty. If any PR was reviewed in this window, the log was deleted; check git history for .factory/cycles before concluding the week was quiet.")}'
    return
  }
  # shellcheck disable=SC2046
  cat $(find "$dir" -name '*.jsonl' 2>/dev/null) 2>/dev/null \
    | jq -s --arg since "$since" '
        map(select($since == "" or .ts >= $since))
        | . as $all
        | {
            tasks: ([$all[].task] | unique | length),
            rounds: ([$all[] | select(.event=="review") | {task, round}] | unique | length),
            byTask: ([$all[] | select(.event=="review")] | group_by(.task) | map({
              task: .[0].task,
              rounds: ([.[].round // 0] | unique | length),
              reviews: length,
              critical: ([.[].findings.critical // 0] | add),
              important: ([.[].findings.important // 0] | add),
              minor: ([.[].findings.minor // 0] | add),
              tokens: ([.[].tokens // 0] | add),
              reviewers: ([.[].reviewer] | unique)
            }) | sort_by(-.rounds)),
            overCycleLimit: ([$all[] | select(.event=="review")] | group_by(.task)
                             | map(select(([.[].round // 0] | unique | length) > 2) | .[0].task)),
            escalations: ([$all[] | select(.event=="escalation")]
                          | map({task,to,reason,agent,ts})),
            gateRetryLimits: ([$all[] | select(.event=="gate_retry_limit")] | map({task,retries,ts})),
            handoffs: ([$all[] | select(.event=="handoff")] | map({task,from,reason,rounds,ts}))
          }'
}
