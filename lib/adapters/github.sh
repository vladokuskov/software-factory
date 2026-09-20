# shellcheck shell=bash
# Tracker adapter: GitHub Issues via gh.
#
# Mapping:
#   epic            issue labelled factory:epic
#   task            issue labelled factory:task
#   epic link       "Epic: #12" line in the body
#   dependencies    "Depends-on: #13, #14" line in the body
#   file scope      "Scope: src/**, lib/**" line in the body
#   acceptance      "- [ ]" items under an "## Acceptance Criteria" heading
#   status          open+unlabelled = pending, factory:in-progress, factory:review, closed = done
#
# Claiming: GitHub has no compare-and-set, so we use an earliest-comment-wins
# protocol. Each claimant posts an HTML-comment marker, re-reads the thread, and
# the earliest marker wins; losers delete their own marker. See
# docs/TRACKER-ADAPTERS.md for why this is the best available guarantee here.

_gh_repo() {
  local r; r="$(config_repo)"
  [ -n "$r" ] || die "github adapter: cannot determine repo (set trackerOptions.repo or run inside a gh-linked clone)"
  printf '%s' "$r"
}

_gh() { gh "$@" --repo "$(_gh_repo)"; }

_CLAIM_RE='<!-- factory-claim agent='

# Body helpers -------------------------------------------------------------
_body_field() { printf '%s' "$1" | grep -iE "^$2:" | head -1 | sed -E "s/^$2: *//I" || true; }

_body_refs() { # "Depends-on: #3, #4" -> 3\n4
  _body_field "$1" "$2" | tr ',' '\n' | sed -e 's/[^0-9]//g' | grep -E '^[0-9]+$' || true
}

_body_acceptance() {
  printf '%s' "$1" \
    | awk '/^#+ *[Aa]cceptance/{f=1;next} /^#+ /{f=0} f && /^[-*] *\[[ x]\]/' \
    | sed -E 's/^[-*] *\[[ x]\] *//'
}

_status_of() { # <state> <labels-json>
  local state="$1" labels="$2"
  [ "$state" = "CLOSED" ] && { printf 'done'; return; }
  if printf '%s' "$labels" | jq -e 'any(.name == "factory:review")' >/dev/null; then printf 'review'; return; fi
  if printf '%s' "$labels" | jq -e 'any(.name == "factory:in-progress")' >/dev/null; then printf 'in_progress'; return; fi
  printf 'pending'
}

# Normalise one `gh issue view --json ...` blob into the adapter contract shape.
_normalise() {
  local raw="$1" body status assignee
  body="$(printf '%s' "$raw" | jq -r '.body // ""')"
  status="$(_status_of "$(printf '%s' "$raw" | jq -r '.state')" "$(printf '%s' "$raw" | jq -c '.labels')")"
  # Claim markers live in comments, not the body, so `list`/`ready` only learn
  # *whether* a task is claimed. adapter_show resolves the actual agent name.
  assignee="$(printf '%s' "$raw" | jq -r '
      if (.labels | any(.name == "factory:claimed"))
      then ((.assignees // []) | map(.login) | first // "claimed")
      else "" end')"
  printf '%s' "$raw" | jq -c \
    --arg status "$status" \
    --arg assignee "${assignee:-}" \
    --argjson acceptance "$(_body_acceptance "$body" | jq -R -s 'split("\n") | map(select(length>0))')" \
    --argjson deps "$(_body_refs "$body" 'Depends-on' | sed 's/^/"#/;s/$/"/' | jq -s 'map(ltrimstr("#"))')" \
    --argjson scope "$(_body_field "$body" 'Scope' | jq -R -s 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))')" \
    '{
       id: (.number | tostring),
       title: .title,
       body: (.body // ""),
       acceptance: $acceptance,
       type: (if (.labels | any(.name == "factory:epic")) then "epic" else "task" end),
       epic: ((((.body // "") | capture("^Epic: *#(?<n>[0-9]+)"; "im")).n) // null),
       status: $status,
       assignee: $assignee,
       deps: $deps,
       scope: $scope,
       priority: (if (.labels | any(.name == "priority:high")) then 1
                  elif (.labels | any(.name == "priority:low")) then 3 else 2 end),
       pr: null,
       url: .url
     }'
}

_issue_json() { _gh issue view "$1" --json number,title,body,labels,state,url,assignees 2>/dev/null; }

_ensure_labels() {
  local l
  for l in factory:epic factory:task factory:in-progress factory:review factory:claimed; do
    _gh label create "$l" --color ededed --description "software factory" >/dev/null 2>&1 || true
  done
}

# Contract -----------------------------------------------------------------

adapter_create() {
  local epic="" title="" bodyfile="" deps="" scope="" type="task" priority=2
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic) epic="$2"; shift 2;;
      --title) title="$2"; shift 2;;
      --body-file) bodyfile="$2"; shift 2;;
      --deps) deps="$2"; shift 2;;
      --scope) scope="$2"; shift 2;;
      --type) type="$2"; shift 2;;
      --priority) priority="$2"; shift 2;;
      --acceptance-file) shift 2;;
      *) die "create: unknown arg $1";;
    esac
  done
  [ -n "$title" ] || die "create: --title is required"
  _ensure_labels

  local tmp; tmp="$(mktemp)"
  { [ -n "$epic" ] && printf 'Epic: #%s\n' "$epic"
    [ -n "$deps" ] && printf 'Depends-on: %s\n' "$(printf '%s' "$deps" | sed 's/\([0-9][0-9]*\)/#\1/g')"
    [ -n "$scope" ] && printf 'Scope: %s\n' "$scope"
    [ -n "$epic$deps$scope" ] && printf '\n'
    [ -n "$bodyfile" ] && [ -f "$bodyfile" ] && cat "$bodyfile"
  } > "$tmp"

  local label=factory:task; [ "$type" = epic ] && label=factory:epic
  local url num
  url="$(_gh issue create --title "$title" --body-file "$tmp" --label "$label")"
  rm -f "$tmp"
  num="$(printf '%s' "$url" | sed 's|.*/||')"

  # Keep the epic's checklist current so a human can read progress at a glance.
  if [ -n "$epic" ]; then
    local ebody; ebody="$(_gh issue view "$epic" --json body -q .body 2>/dev/null || true)"
    printf '%s\n- [ ] #%s %s\n' "$ebody" "$num" "$title" | _gh issue edit "$epic" --body-file - >/dev/null 2>&1 || true
  fi
  jq -nc --arg id "$num" --arg url "$url" '{ok:true,id:$id,url:$url}'
}

adapter_show() {
  local id="${1:-}"; [ -n "$id" ] || die "show: issue number required"
  local raw; raw="$(_issue_json "$id")"
  [ -n "$raw" ] || { json_err "no such issue: $id"; return 1; }
  local agent
  agent="$(gh api "repos/$(_gh_repo)/issues/$id/comments" --paginate \
    --jq "[.[] | select(.body | startswith(\"$_CLAIM_RE\"))] | sort_by(.created_at) | .[0].body // empty" 2>/dev/null \
    | sed -E 's/.*agent=([^ ]+).*/\1/' || true)"
  _normalise "$raw" | jq -c --arg a "${agent:-}" 'if $a != "" then .assignee = $a else . end'
}

adapter_list() {
  local epic=""
  while [ $# -gt 0 ]; do case "$1" in --epic) epic="$2"; shift 2;; *) shift;; esac; done
  local raws; raws="$(_gh issue list --state all --limit 200 \
      --json number,title,body,labels,state,url,assignees \
      | jq -c '[.[] | select(.labels | any(.name == "factory:task"))]')"
  local out="[]" row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    out="$(printf '%s' "$out" | jq -c --argjson r "$(_normalise "$row")" '. + [$r]')"
  done <<< "$(printf '%s' "$raws" | jq -c '.[]')"
  printf '%s' "$out" | jq -c --arg epic "$epic" 'map(select($epic == "" or .epic == $epic))'
}

adapter_ready() {
  local epic="" limit=0
  while [ $# -gt 0 ]; do
    case "$1" in --epic) epic="$2"; shift 2;; --limit) limit="$2"; shift 2;; *) shift;; esac
  done
  local all; all="$(adapter_list ${epic:+--epic "$epic"})"
  printf '%s' "$all" | jq -c --argjson limit "$limit" '
    . as $all
    | map(select(.type != "epic" and .status == "pending" and (.assignee // "") == ""))
    | map(select([.deps[]? | . as $d | ($all[] | select(.id == $d) | .status)] | all(. == "done")))
    | sort_by(.priority, (.id | tonumber))
    | (if $limit > 0 then .[:$limit] else . end)'
}

# Earliest claim marker wins. Losers withdraw their own marker.
adapter_claim() {
  local id="${1:-}"; shift || true
  local agent=""
  while [ $# -gt 0 ]; do case "$1" in --agent) agent="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "claim: issue number required"
  [ -n "$agent" ] || die "claim: --agent is required"
  _ensure_labels
  local repo; repo="$(_gh_repo)"

  local existing
  existing="$(gh api "repos/$repo/issues/$id/comments" --paginate \
    --jq "[.[] | select(.body | startswith(\"$_CLAIM_RE\")) | {id, body, created_at}] | sort_by(.created_at) | .[0] // empty" 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    local holder; holder="$(printf '%s' "$existing" | jq -r '.body | capture("agent=(?<a>[^ ]+)") | .a')"
    if [ "$holder" = "$agent" ]; then
      jq -nc --arg id "$id" --arg a "$agent" '{ok:true,id:$id,assignee:$a,note:"already held"}'
    else
      jq -nc --arg id "$id" --arg h "$holder" '{ok:false,id:$id,assignee:$h,error:"already claimed"}'
    fi
    return 0
  fi

  local mine
  mine="$(gh api "repos/$repo/issues/$id/comments" -f body="$_CLAIM_RE$agent ts=$(now_iso) -->" --jq '.id')"

  local winner
  winner="$(gh api "repos/$repo/issues/$id/comments" --paginate \
    --jq "[.[] | select(.body | startswith(\"$_CLAIM_RE\")) | {id, body, created_at}] | sort_by(.created_at, .id) | .[0]")"
  local winner_id; winner_id="$(printf '%s' "$winner" | jq -r '.id')"

  if [ "$winner_id" = "$mine" ]; then
    _gh issue edit "$id" --add-label factory:claimed --add-label factory:in-progress >/dev/null
    _gh issue edit "$id" --add-assignee @me >/dev/null 2>&1 || true
    jq -nc --arg id "$id" --arg a "$agent" '{ok:true,id:$id,assignee:$a}'
  else
    gh api -X DELETE "repos/$repo/issues/comments/$mine" >/dev/null 2>&1 || true
    local holder; holder="$(printf '%s' "$winner" | jq -r '.body | capture("agent=(?<a>[^ ]+)") | .a')"
    jq -nc --arg id "$id" --arg h "$holder" '{ok:false,id:$id,assignee:$h,error:"already claimed"}'
  fi
}

adapter_release() {
  local id="${1:-}"; [ -n "$id" ] || die "release: issue number required"
  local repo; repo="$(_gh_repo)"
  gh api "repos/$repo/issues/$id/comments" --paginate \
    --jq "[.[] | select(.body | startswith(\"$_CLAIM_RE\")) | .id] | .[]" 2>/dev/null \
    | while read -r cid; do gh api -X DELETE "repos/$repo/issues/comments/$cid" >/dev/null 2>&1 || true; done
  _gh issue edit "$id" --remove-label factory:claimed --remove-label factory:in-progress >/dev/null 2>&1 || true
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_update() {
  local id="${1:-}"; shift || true
  local status=""
  while [ $# -gt 0 ]; do case "$1" in --status) status="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "update: issue number required"
  case "$status" in
    pending)     _gh issue edit "$id" --remove-label factory:in-progress --remove-label factory:review >/dev/null 2>&1 || true;;
    in_progress) _gh issue edit "$id" --add-label factory:in-progress --remove-label factory:review >/dev/null 2>&1 || true;;
    review)      _gh issue edit "$id" --add-label factory:review --remove-label factory:in-progress >/dev/null 2>&1 || true;;
    done)        _gh issue close "$id" >/dev/null;;
    blocked)     _gh issue edit "$id" --add-label factory:blocked >/dev/null 2>&1 || true;;
    *) die "update: invalid status '$status'";;
  esac
  jq -nc --arg id "$id" --arg s "$status" '{ok:true,id:$id,status:$s}'
}

adapter_comment() {
  local id="${1:-}"; shift || true
  local bodyfile=""
  while [ $# -gt 0 ]; do case "$1" in --body-file) bodyfile="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "comment: issue number required"
  [ -f "$bodyfile" ] || die "comment: --body-file must point at a readable file"
  _gh issue comment "$id" --body-file "$bodyfile" >/dev/null
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_link_pr() {
  local id="${1:-}"; shift || true
  local pr=""
  while [ $# -gt 0 ]; do case "$1" in --pr) pr="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "link-pr: issue number required"
  [ -n "$pr" ] || die "link-pr: --pr is required"
  _gh issue comment "$id" --body "Pull request: #$pr" >/dev/null
  adapter_update "$id" --status review >/dev/null
  jq -nc --arg id "$id" --argjson pr "$pr" '{ok:true,id:$id,pr:$pr}'
}
