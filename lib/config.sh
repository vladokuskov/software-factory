# shellcheck shell=bash
# Config resolution. User config is merged over these defaults, so every key
# always resolves and adapters never have to null-check.

FACTORY_DEFAULTS='{
  "tracker": "file",
  "trackerOptions": {
    "repo": "",
    "epicLabel": "factory:epic",
    "taskLabel": "factory:task",
    "claimLabel": "factory:claimed",
    "jiraProject": ""
  },
  "gates": {},
  "gateOrder": ["format", "lint", "typecheck", "test", "build"],
  "models": {
    "lead": "opus[1m]",
    "worker": "opus",
    "reviewAdversarial": "opus",
    "reviewQuality": "sonnet",
    "reviewIntent": "fable",
    "scanner": "sonnet",
    "retro": "fable"
  },
  "effort": {
    "lead": "max",
    "worker": "high",
    "reviewAdversarial": "high",
    "reviewQuality": "medium",
    "reviewIntent": "high",
    "scanner": "medium",
    "retro": "high"
  },
  "escalation": {
    "maxReviewCycles": 2,
    "maxGateRetries": 3,
    "handoffAtTokens": 500000,
    "maxParallel": 3
  },
  "sensitivePaths": [
    "**/auth/**", "**/payments/**", "**/billing/**",
    "migrations/**", "**/*secret*", "**/*credential*",
    ".github/workflows/**", ".factory/config.json"
  ],
  "observability": {
    "githubActions": true,
    "sentry": false,
    "logPaths": []
  },
  "budget": { "scanUsd": 2, "retroUsd": 5, "taskUsd": 0 },
  "defaultBranch": ""
}'

config_file() { printf '%s/config.json\n' "$(factory_dir)"; }

# Full merged config on stdout.
config_json() {
  local f; f="$(config_file)"
  if [ -f "$f" ]; then
    jq -s '.[0] * .[1]' <(printf '%s' "$FACTORY_DEFAULTS") "$f"
  else
    printf '%s' "$FACTORY_DEFAULTS" | jq .
  fi
}

# config_get <jq-path-without-leading-dot> [fallback]
config_get() {
  local path="$1" fallback="${2:-}" out
  out="$(config_json | jq -r ".${path} // empty" 2>/dev/null || true)"
  if [ -z "$out" ] && [ -n "$fallback" ]; then printf '%s\n' "$fallback"; else printf '%s\n' "$out"; fi
}

# Raw (JSON-typed) read, for arrays and objects.
config_get_raw() { config_json | jq -c ".${1}"; }

config_tracker() {
  local t; t="${FACTORY_TRACKER:-$(config_get tracker)}"
  [ -n "$t" ] || t="file"
  printf '%s\n' "$t"
}

# Repo slug for the github adapter: explicit config wins, else ask gh.
config_repo() {
  local r; r="$(config_get trackerOptions.repo)"
  if [ -z "$r" ]; then
    r="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  fi
  printf '%s\n' "$r"
}

config_default_branch() {
  local b; b="$(config_get defaultBranch)"
  if [ -z "$b" ]; then
    b="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  fi
  [ -n "$b" ] || b="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  printf '%s\n' "$b"
}
