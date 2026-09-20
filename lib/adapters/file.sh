# shellcheck shell=bash
# Tracker adapter: local JSONL file. Zero dependencies, offline, atomic claims.
# Reference implementation of the adapter contract (docs/TRACKER-ADAPTERS.md).

_tasks_file() { printf '%s/tasks.jsonl\n' "$(factory_dir)"; }

_ensure_store() {
  local f; f="$(_tasks_file)"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || : > "$f"
}

# Latest record wins, so updates are appends and reads collapse by id.
_all() {
  _ensure_store
  jq -s 'group_by(.id) | map(.[-1])' "$(_tasks_file)"
}

_get() { _all | jq -c --arg id "$1" '.[] | select(.id == $id)'; }

_next_id() {
  local prefix="$1" n
  n="$(_all | jq -r --arg p "$prefix" '[.[] | select(.id | startswith($p + "-")) | (.id | ltrimstr($p + "-") | tonumber?)] | max // 0')"
  printf '%s-%04d\n' "$prefix" "$((n + 1))"
}

_append() { printf '%s\n' "$1" >> "$(_tasks_file)"; }

# _patch <id> <jq-expr> -- rewrites the record through jq under the caller's lock.
_patch() {
  local id="$1" expr="$2" cur
  cur="$(_get "$id")"
  [ -n "$cur" ] || { json_err "no such task: $id"; return 1; }
  printf '%s' "$cur" | jq -c --arg ts "$(now_iso)" "$expr | .updated = \$ts" >> "$(_tasks_file)"
}

# ---------------------------------------------------------------------------

adapter_create() {
  local epic="" title="" bodyfile="" deps="" scope="" type="task" priority=2 acceptance=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic) epic="$2"; shift 2;;
      --title) title="$2"; shift 2;;
      --body-file) bodyfile="$2"; shift 2;;
      --deps) deps="$2"; shift 2;;
      --scope) scope="$2"; shift 2;;
      --type) type="$2"; shift 2;;
      --priority) priority="$2"; shift 2;;
      --acceptance-file) acceptance="$2"; shift 2;;
      *) die "create: unknown arg $1";;
    esac
  done
  [ -n "$title" ] || die "create: --title is required"
  _ensure_store

  local body="" acc='[]'
  [ -n "$bodyfile" ] && [ -f "$bodyfile" ] && body="$(cat "$bodyfile")"
  if [ -n "$acceptance" ] && [ -f "$acceptance" ]; then
    acc="$(jq -R -s 'split("\n") | map(select(length > 0))' < "$acceptance")"
  elif [ -n "$body" ]; then
    # Pull "- [ ] ..." lines out of an Acceptance Criteria section.
    acc="$(printf '%s' "$body" | awk '/^#+ *Acceptance/{f=1;next} /^#+ /{f=0} f && /^[-*] *\[ \]/' \
          | sed -e 's/^[-*] *\[ \] *//' | jq -R -s 'split("\n") | map(select(length > 0))')"
  fi

  local prefix=t; [ "$type" = epic ] && prefix=e
  local id; id="$(_next_id "$prefix")"
  local rec
  rec="$(jq -nc \
    --arg id "$id" --arg title "$title" --arg body "$body" --arg type "$type" \
    --arg epic "$epic" --arg ts "$(now_iso)" --argjson acc "$acc" \
    --argjson pri "$priority" \
    --argjson deps "$(printf '%s' "$deps" | jq -Rs 'split(",") | map(select(length > 0))')" \
    --argjson scope "$(printf '%s' "$scope" | jq -Rs 'split(",") | map(select(length > 0))')" \
    '{id:$id,title:$title,body:$body,acceptance:$acc,type:$type,
      epic:(if $epic == "" then null else $epic end),
      status:"pending",assignee:"",deps:$deps,scope:$scope,priority:$pri,
      pr:null,created:$ts,updated:$ts}')"
  _append "$rec"
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_show() {
  local id="${1:-}"; [ -n "$id" ] || die "show: task id required"
  local rec; rec="$(_get "$id")"
  [ -n "$rec" ] || { json_err "no such task: $id"; return 1; }
  printf '%s\n' "$rec"
}

adapter_ready() {
  local epic="" limit=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic) epic="$2"; shift 2;;
      --limit) limit="$2"; shift 2;;
      *) die "ready: unknown arg $1";;
    esac
  done
  _all | jq -c --arg epic "$epic" --argjson limit "$limit" '
    . as $all
    | map(select(.type != "epic"))
    | map(select(.status == "pending" and (.assignee // "") == ""))
    | map(select($epic == "" or .epic == $epic))
    | map(select([.deps[]? | . as $d | ($all[] | select(.id == $d) | .status)] | all(. == "done")))
    | sort_by(.priority, .id)
    | (if $limit > 0 then .[:$limit] else . end)'
}

adapter_claim() {
  local id="${1:-}"; shift || true
  local agent=""
  while [ $# -gt 0 ]; do
    case "$1" in --agent) agent="$2"; shift 2;; *) shift;; esac
  done
  [ -n "$id" ] || die "claim: task id required"
  [ -n "$agent" ] || die "claim: --agent is required"
  with_lock "tasks" _claim_locked "$id" "$agent"
}

_claim_locked() {
  local id="$1" agent="$2" cur holder
  cur="$(_get "$id")"
  [ -n "$cur" ] || { json_err "no such task: $id"; return 1; }
  holder="$(printf '%s' "$cur" | jq -r '.assignee // ""')"
  if [ -n "$holder" ] && [ "$holder" != "$agent" ]; then
    jq -nc --arg id "$id" --arg h "$holder" '{ok:false,id:$id,assignee:$h,error:"already claimed"}'
    return 0
  fi
  _patch "$id" ".assignee = \"$agent\" | .status = \"in_progress\"" >/dev/null
  jq -nc --arg id "$id" --arg a "$agent" '{ok:true,id:$id,assignee:$a}'
}

adapter_release() {
  local id="${1:-}"; [ -n "$id" ] || die "release: task id required"
  with_lock "tasks" _patch "$id" '.assignee = "" | .status = "pending"' >/dev/null
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_update() {
  local id="${1:-}"; shift || true
  local status=""
  while [ $# -gt 0 ]; do
    case "$1" in --status) status="$2"; shift 2;; *) shift;; esac
  done
  [ -n "$id" ] || die "update: task id required"
  [ -n "$status" ] || die "update: --status is required"
  case "$status" in
    pending|in_progress|review|done|blocked) ;;
    *) die "update: invalid status '$status'";;
  esac
  with_lock "tasks" _patch "$id" ".status = \"$status\"" >/dev/null
  jq -nc --arg id "$id" --arg s "$status" '{ok:true,id:$id,status:$s}'
}

adapter_comment() {
  local id="${1:-}"; shift || true
  local bodyfile=""
  while [ $# -gt 0 ]; do
    case "$1" in --body-file) bodyfile="$2"; shift 2;; *) shift;; esac
  done
  [ -n "$id" ] || die "comment: task id required"
  [ -f "$bodyfile" ] || die "comment: --body-file must point at a readable file"
  local body; body="$(cat "$bodyfile")"
  with_lock "tasks" _patch "$id" \
    ".body = (.body + \"\n\n---\n_[$(now_iso)]_\n\" + $(printf '%s' "$body" | jq -Rs .))" >/dev/null
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_link_pr() {
  local id="${1:-}"; shift || true
  local pr=""
  while [ $# -gt 0 ]; do
    case "$1" in --pr) pr="$2"; shift 2;; *) shift;; esac
  done
  [ -n "$id" ] || die "link-pr: task id required"
  [ -n "$pr" ] || die "link-pr: --pr is required"
  with_lock "tasks" _patch "$id" ".pr = ($pr) | .status = \"review\"" >/dev/null
  jq -nc --arg id "$id" --argjson pr "$pr" '{ok:true,id:$id,pr:$pr}'
}

adapter_list() {
  local epic=""
  while [ $# -gt 0 ]; do
    case "$1" in --epic) epic="$2"; shift 2;; *) shift;; esac
  done
  _all | jq -c --arg epic "$epic" 'map(select($epic == "" or .epic == $epic or .id == $epic))'
}
