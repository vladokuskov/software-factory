# shellcheck shell=bash
# Tracker adapter: Jira Cloud, over REST.
#
# A shell adapter rather than the Atlassian MCP connector, because MCP tools only
# exist inside a Claude session and the hooks, the launchd jobs and
# tests/conformance.sh all need to reach the tracker without one.
#
# Configure with, in the environment:
#   JIRA_BASE_URL    https://your-site.atlassian.net
#   JIRA_EMAIL       the account the API token belongs to
#   JIRA_API_TOKEN   https://id.atlassian.com/manage-profile/security/api-tokens
# and in .factory/config.json:
#   trackerOptions.jiraProject   the project key, e.g. ENG
#
# Uses REST v2 for issues so descriptions stay plain text; v3 would require
# Atlassian Document Format for every body, which buys nothing here.
#
# STATUS: written against the documented API and not yet run against a live
# instance. Verify before trusting it:
#   FACTORY_CONFORMANCE_REPO=$PWD FACTORY_TRACKER=jira tests/conformance.sh

_jira_env() {
  [ -n "${JIRA_BASE_URL:-}" ] || die "jira: JIRA_BASE_URL is not set"
  [ -n "${JIRA_EMAIL:-}" ] || die "jira: JIRA_EMAIL is not set"
  [ -n "${JIRA_API_TOKEN:-}" ] || die "jira: JIRA_API_TOKEN is not set"
}

_jira_project() {
  local k; k="$(config_get trackerOptions.jiraProject)"
  [ -n "$k" ] || die "jira: set trackerOptions.jiraProject in .factory/config.json"
  printf '%s' "$k"
}

# _jira <METHOD> <path> [json-body]
_jira() {
  _jira_env
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -u "$JIRA_EMAIL:$JIRA_API_TOKEN" -X "$method"
              -H 'Accept: application/json' -H 'Content-Type: application/json')
  [ -n "$body" ] && args+=(-d "$body")
  curl "${args[@]}" "${JIRA_BASE_URL%/}/rest/api$path"
}

_jira_search() { # <jql> [maxResults]
  local jql="$1" max="${2:-100}" out
  out="$(_jira GET "/2/search?maxResults=$max&fields=summary,description,status,assignee,parent,priority,labels&jql=$(printf '%s' "$jql" | jq -sRr @uri)")"
  # v2 /search is deprecated on Jira Cloud; fall back to the v3 replacement.
  if printf '%s' "$out" | jq -e '.errorMessages? // .errors?' >/dev/null 2>&1; then
    out="$(_jira POST "/3/search/jql" "$(jq -nc --arg jql "$jql" --argjson max "$max" \
      '{jql:$jql,maxResults:$max,fields:["summary","description","status","assignee","parent","priority","labels"]}')")"
  fi
  printf '%s' "$out"
}

_jira_body_field() { printf '%s' "$1" | grep -iE "^$2:" | head -1 | sed -E "s/^$2: *//I" || true; }

_CLAIM_RE='<!-- factory-claim agent='

# Map a Jira status category onto the contract's statuses.
_jira_normalise() {
  local raw="$1" desc
  desc="$(printf '%s' "$raw" | jq -r '.fields.description // ""')"
  printf '%s' "$raw" | jq -c \
    --argjson acceptance "$(printf '%s' "$desc" \
        | awk '/^#+ *[Aa]cceptance/{f=1;next} /^#+ /{f=0} f && /^[-*] *\[[ x]\]/' \
        | sed -E 's/^[-*] *\[[ x]\] *//' | jq -R -s 'split("\n") | map(select(length>0))')" \
    --argjson scope "$(_jira_body_field "$desc" 'Scope' | jq -R -s 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))')" \
    --argjson deps "$(_jira_body_field "$desc" 'Depends-on' | jq -R -s 'split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))')" \
    '{
       id: .key,
       title: (.fields.summary // ""),
       body: (.fields.description // ""),
       acceptance: $acceptance,
       type: (if ((.fields.issuetype.name // "") | ascii_downcase) == "epic" then "epic" else "task" end),
       epic: (.fields.parent.key // null),
       status: (
         ((.fields.labels // []) | index("factory-review")) as $rev
         | (.fields.status.statusCategory.key // "") as $cat
         | if $cat == "done" then "done"
           elif $rev then "review"
           elif $cat == "indeterminate" then "in_progress"
           else "pending" end),
       assignee: (((.fields.labels // []) | map(select(startswith("factory-agent-"))) | first // "") | sub("^factory-agent-"; "")),
       deps: $deps,
       scope: $scope,
       priority: (if (.fields.priority.name // "") | test("High|Highest") then 1
                  elif (.fields.priority.name // "") | test("Low|Lowest") then 3 else 2 end),
       pr: (((((.fields.description // "") | capture("^PR: *#(?<n>[0-9]+)"; "im")).n) // null)
            | if . == null then null else tonumber end)
     }'
}

_jira_issue() { _jira GET "/2/issue/$1?fields=summary,description,status,assignee,parent,priority,labels,issuetype"; }

_jira_transition_to() { # <key> <status-category-or-name>
  local key="$1" want="$2" id
  id="$(_jira GET "/2/issue/$key/transitions" \
      | jq -r --arg w "$want" '[.transitions[] | select((.to.name // "" | ascii_downcase) == ($w | ascii_downcase)
                                 or (.to.statusCategory.key // "") == $w)] | .[0].id // empty')"
  [ -n "$id" ] || return 1
  _jira POST "/2/issue/$key/transitions" "$(jq -nc --arg id "$id" '{transition:{id:$id}}')" >/dev/null
}

# ---------------------------------------------------------------------------

adapter_create() {
  local epic="" title="" bodyfile="" deps="" scope="" type="task" priority=2
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic) epic="$2"; shift 2;; --title) title="$2"; shift 2;;
      --body-file) bodyfile="$2"; shift 2;; --deps) deps="$2"; shift 2;;
      --scope) scope="$2"; shift 2;; --type) type="$2"; shift 2;;
      --priority) priority="$2"; shift 2;; --acceptance-file) shift 2;;
      *) die "create: unknown arg $1";;
    esac
  done
  [ -n "$title" ] || die "create: --title is required"

  local body=""
  [ -n "$bodyfile" ] && [ -f "$bodyfile" ] && body="$(cat "$bodyfile")"
  local header=""
  [ -n "$deps" ]  && header="${header}Depends-on: $deps"$'\n'
  [ -n "$scope" ] && header="${header}Scope: $scope"$'\n'
  [ -n "$header" ] && header="${header}"$'\n'

  local itype=Task; [ "$type" = epic ] && itype=Epic
  local payload
  payload="$(jq -nc --arg p "$(_jira_project)" --arg s "$title" \
      --arg d "${header}${body}" --arg t "$itype" --arg parent "$epic" '
      {fields: ({project:{key:$p}, summary:$s, description:$d, issuetype:{name:$t}}
                + (if $parent == "" then {} else {parent:{key:$parent}} end))}')"
  local out; out="$(_jira POST "/2/issue" "$payload")"
  local key; key="$(printf '%s' "$out" | jq -r '.key // empty')"
  [ -n "$key" ] || { json_err "jira create failed: $(printf '%s' "$out" | jq -c '.errors // .errorMessages // .')"; return 1; }
  jq -nc --arg id "$key" '{ok:true,id:$id}'
}

adapter_show() {
  local id="${1:-}"; [ -n "$id" ] || die "show: issue key required"
  local raw; raw="$(_jira_issue "$id")"
  printf '%s' "$raw" | jq -e '.key' >/dev/null 2>&1 || { json_err "no such issue: $id"; return 1; }
  _jira_normalise "$raw"
}

adapter_list() {
  local epic=""
  while [ $# -gt 0 ]; do case "$1" in --epic) epic="$2"; shift 2;; *) shift;; esac; done
  local jql="project = $(_jira_project) ORDER BY created ASC"
  [ -n "$epic" ] && jql="project = $(_jira_project) AND (parent = $epic OR key = $epic) ORDER BY created ASC"
  local out="[]" row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    out="$(printf '%s' "$out" | jq -c --argjson r "$(_jira_normalise "$row")" '. + [$r]')"
  done <<< "$(_jira_search "$jql" 200 | jq -c '.issues[]?')"
  printf '%s\n' "$out"
}

adapter_ready() {
  local epic="" limit=0
  while [ $# -gt 0 ]; do
    case "$1" in --epic) epic="$2"; shift 2;; --limit) limit="$2"; shift 2;; *) shift;; esac
  done
  adapter_list ${epic:+--epic "$epic"} | jq -c --argjson limit "$limit" '
    . as $all
    | map(select(.type != "epic" and .status == "pending" and (.assignee // "") == ""))
    | map(select([.deps[]? | . as $d | ($all[] | select(.id == $d) | .status)] | all(. == "done")))
    | sort_by(.priority, .id)
    | (if $limit > 0 then .[:$limit] else . end)'
}

# Jira has no compare-and-set either, so this is the same earliest-comment-wins
# protocol the github adapter uses. See docs/TRACKER-ADAPTERS.md.
adapter_claim() {
  local id="${1:-}"; shift || true
  local agent=""
  while [ $# -gt 0 ]; do case "$1" in --agent) agent="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "claim: issue key required"
  [ -n "$agent" ] || die "claim: --agent is required"

  local existing
  existing="$(_jira GET "/2/issue/$id/comment?maxResults=200" \
    | jq -c --arg re "$_CLAIM_RE" '[.comments[]? | select((.body // "") | startswith($re))] | sort_by(.created) | .[0] // empty')"
  if [ -n "$existing" ]; then
    local holder; holder="$(printf '%s' "$existing" | jq -r '.body | capture("agent=(?<a>[^ ]+)").a')"
    if [ "$holder" = "$agent" ]; then jq -nc --arg id "$id" --arg a "$agent" '{ok:true,id:$id,assignee:$a,note:"already held"}'
    else jq -nc --arg id "$id" --arg h "$holder" '{ok:false,id:$id,assignee:$h,error:"already claimed"}'; fi
    return 0
  fi

  local mine
  mine="$(_jira POST "/2/issue/$id/comment" \
      "$(jq -nc --arg b "$_CLAIM_RE$agent ts=$(now_iso) -->" '{body:$b}')" | jq -r '.id // empty')"

  local winner
  winner="$(_jira GET "/2/issue/$id/comment?maxResults=200" \
    | jq -c --arg re "$_CLAIM_RE" '[.comments[]? | select((.body // "") | startswith($re))] | sort_by(.created, .id) | .[0]')"
  if [ "$(printf '%s' "$winner" | jq -r '.id')" = "$mine" ]; then
    _jira PUT "/2/issue/$id" "$(jq -nc --arg l "factory-agent-$agent" '{update:{labels:[{add:$l}]}}')" >/dev/null
    _jira_transition_to "$id" indeterminate || true
    jq -nc --arg id "$id" --arg a "$agent" '{ok:true,id:$id,assignee:$a}'
  else
    [ -n "$mine" ] && _jira DELETE "/2/issue/$id/comment/$mine" >/dev/null 2>&1 || true
    jq -nc --arg id "$id" --arg h "$(printf '%s' "$winner" | jq -r '.body | capture("agent=(?<a>[^ ]+)").a')" \
      '{ok:false,id:$id,assignee:$h,error:"already claimed"}'
  fi
}

adapter_release() {
  local id="${1:-}"; [ -n "$id" ] || die "release: issue key required"
  _jira GET "/2/issue/$id/comment?maxResults=200" \
    | jq -r --arg re "$_CLAIM_RE" '.comments[]? | select((.body // "") | startswith($re)) | .id' \
    | while read -r cid; do _jira DELETE "/2/issue/$id/comment/$cid" >/dev/null 2>&1 || true; done
  local labels; labels="$(_jira_issue "$id" | jq -c '[.fields.labels[]? | select(startswith("factory-agent-")) | {remove:.}]')"
  _jira PUT "/2/issue/$id" "$(jq -nc --argjson l "$labels" '{update:{labels:$l}}')" >/dev/null 2>&1 || true
  _jira_transition_to "$id" new || true
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_update() {
  local id="${1:-}"; shift || true
  local status=""
  while [ $# -gt 0 ]; do case "$1" in --status) status="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "update: issue key required"
  case "$status" in
    pending)     _jira PUT "/2/issue/$id" '{"update":{"labels":[{"remove":"factory-review"}]}}' >/dev/null 2>&1 || true
                 _jira_transition_to "$id" new || true;;
    in_progress) _jira PUT "/2/issue/$id" '{"update":{"labels":[{"remove":"factory-review"}]}}' >/dev/null 2>&1 || true
                 _jira_transition_to "$id" indeterminate || true;;
    # Many Jira workflows have no distinct review state, so review is
    # in-progress plus a label, the same shape the beads adapter uses.
    review)      _jira PUT "/2/issue/$id" '{"update":{"labels":[{"add":"factory-review"}]}}' >/dev/null 2>&1 || true
                 _jira_transition_to "$id" indeterminate || true;;
    done)        _jira_transition_to "$id" done || die "update: no transition to a done status from here";;
    blocked)     _jira PUT "/2/issue/$id" '{"update":{"labels":[{"add":"factory-blocked"}]}}' >/dev/null 2>&1 || true;;
    *) die "update: invalid status '$status'";;
  esac
  jq -nc --arg id "$id" --arg s "$status" '{ok:true,id:$id,status:$s}'
}

adapter_comment() {
  local id="${1:-}"; shift || true
  local bodyfile=""
  while [ $# -gt 0 ]; do case "$1" in --body-file) bodyfile="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "comment: issue key required"
  [ -f "$bodyfile" ] || die "comment: --body-file must point at a readable file"
  _jira POST "/2/issue/$id/comment" "$(jq -nc --rawfile b "$bodyfile" '{body:$b}')" >/dev/null
  jq -nc --arg id "$id" '{ok:true,id:$id}'
}

adapter_link_pr() {
  local id="${1:-}"; shift || true
  local pr=""
  while [ $# -gt 0 ]; do case "$1" in --pr) pr="$2"; shift 2;; *) shift;; esac; done
  [ -n "$id" ] || die "link-pr: issue key required"
  [ -n "$pr" ] || die "link-pr: --pr is required"
  local desc; desc="$(_jira_issue "$id" | jq -r '.fields.description // ""')"
  if printf '%s' "$desc" | grep -qiE '^PR: *#[0-9]+'; then
    desc="$(printf '%s' "$desc" | sed -E "s|^PR: *#[0-9]+|PR: #$pr|I")"
  else
    desc="PR: #$pr
$desc"
  fi
  _jira PUT "/2/issue/$id" "$(jq -nc --arg d "$desc" '{fields:{description:$d}}')" >/dev/null
  adapter_update "$id" --status review >/dev/null
  jq -nc --arg id "$id" --argjson pr "$pr" '{ok:true,id:$id,pr:$pr}'
}
