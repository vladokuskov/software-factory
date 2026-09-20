# shellcheck shell=bash
# Tracker adapter: beads (https://github.com/gastownhall/beads).
#
# The strongest of the adapters for multi-agent work, because `bd update --claim`
# is a genuinely atomic first-wins claim rather than a convergence protocol, and
# because every git worktree in a repo shares one .beads workspace, which is
# exactly the sharing a factory needs.
#
# Mapping:
#   epic            issue with --type epic
#   task            issue with --type task, --parent <epic>
#   dependencies    real bd dependency edges (blocks), not description text
#   file scope      "Scope: src/**, lib/**" line in the description
#   acceptance      the native acceptance_criteria field
#   status          open = pending, in_progress, in_progress + factory:review
#                   label = review, blocked, closed = done
#   claim           bd update --claim, keyed on BEADS_ACTOR; the agent name is
#                   also stored in metadata so `show` can report it back
#   pr              external_ref, as "gh-<n>"

_bd() { bd "$@"; }

_bd_first() { jq -c 'if type=="array" then (.[0] // empty) else . end'; }

_bd_scope() { printf '%s' "$1" | grep -iE '^Scope:' | head -1 | sed -E 's/^Scope: *//I' || true; }

# Normalise one `bd show --json --long` record into the adapter contract.
_bd_normalise() {
  local raw="$1" desc
  desc="$(printf '%s' "$raw" | jq -r '.description // ""')"
  printf '%s' "$raw" | jq -c \
    --argjson scope "$(_bd_scope "$desc" | jq -R -s 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))')" \
    '{
       id: .id,
       title: .title,
       body: (.description // ""),
       acceptance: ((.acceptance_criteria // "")
                    | split("\n") | map(sub("^[-*] *\\[[ xX]\\] *"; "") | gsub("^\\s+|\\s+$";""))
                    | map(select(length > 0))),
       type: (if .issue_type == "epic" then "epic" else "task" end),
       epic: (.parent // null),
       status: (if .status == "closed" then "done"
                elif .status == "blocked" then "blocked"
                elif .status == "in_progress" then
                  (if ((.labels // []) | index("factory:review")) then "review" else "in_progress" end)
                else "pending" end),
       assignee: (((.metadata // {}).factory_agent)
                  // (if .status == "in_progress" then (.owner // "") else "" end)
                  // ""),
       deps: [ (.dependencies // [])[] | select(.dependency_type == "blocks") | .id ],
       scope: $scope,
       priority: (.priority // 2),
       pr: (((.external_ref // "") | capture("^gh-(?<n>[0-9]+)$").n // null)
            | if . == null then null else tonumber end)
     }'
}

_bd_show_raw() { _bd show "$1" --json --long 2>/dev/null | _bd_first; }

# ---------------------------------------------------------------------------

adapter_create() {
  local epic="" title="" bodyfile="" deps="" scope="" type="task" priority=2 accfile=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic) epic="$2"; shift 2;;
      --title) title="$2"; shift 2;;
      --body-file) bodyfile="$2"; shift 2;;
      --deps) deps="$2"; shift 2;;
      --scope) scope="$2"; shift 2;;
      --type) type="$2"; shift 2;;
      --priority) priority="$2"; shift 2;;
      --acceptance-file) accfile="$2"; shift 2;;
      *) die "create: unknown arg $1";;
    esac
  done
  [ -n "$title" ] || die "create: --title is required"

  local body="" acc=""
  [ -n "$bodyfile" ] && [ -f "$bodyfile" ] && body="$(cat "$bodyfile")"
  if [ -n "$accfile" ] && [ -f "$accfile" ]; then
    acc="$(cat "$accfile")"
  elif [ -n "$body" ]; then
    acc="$(printf '%s' "$body" | awk '/^#+ *[Aa]cceptance/{f=1;next} /^#+ /{f=0} f && /^[-*] *\[[ x]\]/')"
  fi

  local tmp; tmp="$(mktemp)"
  { [ -n "$scope" ] && printf 'Scope: %s\n\n' "$scope"
    printf '%s\n' "$body"; } > "$tmp"

  # Bare ids make THIS issue depend on them, which is the direction we want.
  local depargs=""
  [ -n "$deps" ] && depargs="$deps"

  local out
  out="$(_bd create "$title" --type "$type" --priority "$priority" \
        ${epic:+--parent "$epic"} \
        ${depargs:+--deps "$depargs"} \
        ${acc:+--acceptance "$acc"} \
        --body-file "$tmp" --json 2>&1)"
  rm -f "$tmp"
  local id; id="$(printf '%s' "$out" | _bd_first | jq -r '.id // empty' 2>/dev/null || true)"
  [ -n "$id" ] || { json_err "bd create failed: $(printf '%s' "$out" | tail -2)"; return 1; }
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_show() {
  local id="${1:-}"; [ -n "$id" ] || die "show: issue id required"
  local raw; raw="$(_bd_show_raw "$id")"
  [ -n "$raw" ] || { json_err "no such issue: $id"; return 1; }
  _bd_normalise "$raw"
}

adapter_list() {
  local epic=""
  while [ $# -gt 0 ]; do case "$1" in --epic) epic="$2"; shift 2;; *) shift;; esac; done
  local ids; ids="$(_bd list --all --json 2>/dev/null \
    | jq -r --arg e "$epic" '.[] | select($e == "" or .parent == $e or .id == $e) | .id')"
  local out="[]" id raw
  for id in $ids; do
    raw="$(_bd_show_raw "$id")"
    [ -n "$raw" ] || continue
    out="$(printf '%s' "$out" | jq -c --argjson r "$(_bd_normalise "$raw")" '. + [$r]')"
  done
  printf '%s\n' "$out"
}

adapter_ready() {
  local epic="" limit=0
  while [ $# -gt 0 ]; do
    case "$1" in --epic) epic="$2"; shift 2;; --limit) limit="$2"; shift 2;; *) shift;; esac
  done
  # bd ready already applies blocker-aware semantics and excludes in_progress,
  # so dependency handling is the tracker's job here rather than ours.
  local ids
  ids="$(_bd ready --json --exclude-type epic ${epic:+--parent "$epic"} \
        ${limit:+-n "$limit"} 2>/dev/null | jq -r '.[]?.id' 2>/dev/null || true)"
  local out="[]" id raw
  for id in $ids; do
    raw="$(_bd_show_raw "$id")"
    [ -n "$raw" ] || continue
    out="$(printf '%s' "$out" | jq -c --argjson r "$(_bd_normalise "$raw")" '. + [$r]')"
  done
  printf '%s' "$out" | jq -c 'map(select(.assignee == ""))'
}

adapter_claim() {
  local id="${1:-}"; shift || true
  local agent=""
  while [ $# -gt 0 ]; do case "$1" in --agent) agent="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "claim: issue id required"
  [ -n "$agent" ] || die "claim: --agent is required"

  local out rc=0
  out="$(BEADS_ACTOR="$agent" _bd update "$id" --claim --json 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    BEADS_ACTOR="$agent" _bd update "$id" --set-metadata "factory_agent=$agent" >/dev/null 2>&1 || true
    jq -nc --arg id "$id" --arg a "$agent" '{ok:true,id:$id,assignee:$a}'
    return 0
  fi
  local holder; holder="$(printf '%s' "$out" | sed -nE 's/.*already claimed by ([^"]*)".*/\1/p;s/.*already claimed by (.*)$/\1/p' | head -1)"
  [ -n "$holder" ] || holder="$(_bd_show_raw "$id" | jq -r '((.metadata // {}).factory_agent) // .owner // "unknown"')"
  jq -nc --arg id "$id" --arg h "$holder" '{ok:false,id:$id,assignee:$h,error:"already claimed"}'
}

adapter_release() {
  local id="${1:-}"; [ -n "$id" ] || die "release: issue id required"
  _bd unclaim "$id" >/dev/null 2>&1 || _bd update "$id" --assignee "" --status open >/dev/null 2>&1 || true
  _bd update "$id" --set-metadata "factory_agent=" --status open >/dev/null 2>&1 || true
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_update() {
  local id="${1:-}"; shift || true
  local status=""
  while [ $# -gt 0 ]; do case "$1" in --status) status="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "update: issue id required"
  case "$status" in
    pending)     _bd update "$id" --status open --remove-label factory:review >/dev/null 2>&1 || true;;
    in_progress) _bd update "$id" --status in_progress --remove-label factory:review >/dev/null 2>&1 || true;;
    # beads has no built-in review status, so review is in_progress plus a label.
    review)      _bd update "$id" --status in_progress --add-label factory:review >/dev/null 2>&1 || true;;
    done)        _bd close "$id" --force >/dev/null 2>&1 || _bd update "$id" --status closed --force >/dev/null 2>&1 || true;;
    blocked)     _bd update "$id" --status blocked >/dev/null 2>&1 || true;;
    *) die "update: invalid status '$status'";;
  esac
  jq -nc --arg id "$id" --arg s "$status" '{ok:true,id:$id,status:$s}'
}

adapter_comment() {
  local id="${1:-}"; shift || true
  local bodyfile=""
  while [ $# -gt 0 ]; do case "$1" in --body-file) bodyfile="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "comment: issue id required"
  [ -f "$bodyfile" ] || die "comment: --body-file must point at a readable file"
  _bd comment "$id" --file "$bodyfile" >/dev/null 2>&1 || { json_err "bd comment failed"; return 1; }
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_link_pr() {
  local id="${1:-}"; shift || true
  local pr=""
  while [ $# -gt 0 ]; do case "$1" in --pr) pr="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "link-pr: issue id required"
  [ -n "$pr" ] || die "link-pr: --pr is required"
  _bd update "$id" --external-ref "gh-$pr" >/dev/null 2>&1 || true
  adapter_update "$id" --status review >/dev/null
  jq -nc --arg id "$id" --argjson pr "$pr" '{ok:true,id:$id,pr:$pr}'
}
