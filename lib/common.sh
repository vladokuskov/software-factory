# shellcheck shell=bash
# Shared helpers for the factory CLI. Sourced, never executed.

set -euo pipefail

FACTORY_HOME="${FACTORY_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export FACTORY_HOME

die()  { printf 'factory: %s\n' "$*" >&2; exit 1; }
warn() { printf 'factory: %s\n' "$*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

# Walk up from $PWD looking for .factory/config.json, then fall back to the git root.
project_root() {
  if [ -n "${FACTORY_PROJECT_ROOT:-}" ]; then printf '%s\n' "$FACTORY_PROJECT_ROOT"; return; fi
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/.factory/config.json" ] && { printf '%s\n' "$d"; return; }
    d="$(dirname "$d")"
  done
  git rev-parse --show-toplevel 2>/dev/null || die "not in a factory project (no .factory/config.json found above $PWD)"
}

factory_dir() { printf '%s/.factory\n' "$(project_root)"; }

# ---------------------------------------------------------------------------
# Locking. mkdir is atomic on every POSIX filesystem; macOS has no flock(1).
# ---------------------------------------------------------------------------
lock_acquire() {
  local name="$1" timeout="${2:-10}" dir waited=0
  dir="$(factory_dir)/locks/$name.lock"
  mkdir -p "$(dirname "$dir")"
  while ! mkdir "$dir" 2>/dev/null; do
    # Reap a lock whose owning process is gone.
    if [ -f "$dir/pid" ]; then
      local owner; owner="$(cat "$dir/pid" 2>/dev/null || echo 0)"
      if [ "$owner" != "$$" ] && ! kill -0 "$owner" 2>/dev/null; then
        rm -rf "$dir"; continue
      fi
    fi
    waited=$((waited + 1))
    [ "$waited" -ge $((timeout * 20)) ] && return 1
    sleep 0.05
  done
  printf '%s' "$$" > "$dir/pid"
  return 0
}

lock_release() { rm -rf "$(factory_dir)/locks/$1.lock"; }

# Run a command while holding a named lock. Releases on any exit path.
with_lock() {
  local name="$1"; shift
  lock_acquire "$name" || die "could not acquire lock '$name' within timeout"
  local rc=0
  "$@" || rc=$?
  lock_release "$name"
  return "$rc"
}

# ---------------------------------------------------------------------------
# JSON helpers
# ---------------------------------------------------------------------------
json_err() { jq -nc --arg m "$1" '{ok:false,error:$m}'; }
json_ok()  { jq -nc '{ok:true}'; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Slugify for branch names and ids.
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-48; }
