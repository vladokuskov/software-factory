# shellcheck shell=bash
# `factory init` -- wire an existing repository up as a factory project.
# Idempotent: safe to re-run after the harness moves or gains new hooks.

# Guess the project's gates from whatever build system is present.
detect_gates() {
  local root="$1"
  if [ -f "$root/package.json" ]; then
    local runner=npm
    [ -f "$root/pnpm-lock.yaml" ] && runner=pnpm
    [ -f "$root/yarn.lock" ] && runner=yarn
    [ -f "$root/bun.lockb" ] && runner=bun
    jq -r --arg r "$runner" '
      (.scripts // {}) as $s
      | {format:"fmt", lint:"lint", typecheck:"typecheck", test:"test", build:"build"}
      | with_entries(select($s[.value] != null))
      | with_entries(.value = ($r + " run --silent " + .value))
      | (if ($s["type-check"] != null and .typecheck == null) then .typecheck = ($r + " run --silent type-check") else . end)
      | (if ($s["format:check"] != null and .format == null) then .format = ($r + " run --silent format:check") else . end)
    ' "$root/package.json"
    return
  fi
  if [ -f "$root/Cargo.toml" ]; then
    jq -nc '{format:"cargo fmt --check", lint:"cargo clippy -- -D warnings", test:"cargo test", build:"cargo build"}'; return
  fi
  if [ -f "$root/go.mod" ]; then
    jq -nc '{format:"gofmt -l .", lint:"go vet ./...", test:"go test ./...", build:"go build ./..."}'; return
  fi
  if [ -f "$root/pyproject.toml" ]; then
    jq -nc '{format:"ruff format --check .", lint:"ruff check .", typecheck:"mypy .", test:"pytest -q"}'; return
  fi
  if [ -f "$root/Makefile" ]; then
    local t out='{}'
    for t in fmt lint typecheck test build; do
      grep -qE "^$t:" "$root/Makefile" && out="$(printf '%s' "$out" | jq -c --arg t "$t" '.[$t] = ("make " + $t)')"
    done
    printf '%s' "$out"; return
  fi
  printf '{}'
}

detect_tracker() {
  local root="$1"
  if [ -d "$root/.beads" ] && command -v bd >/dev/null 2>&1; then printf 'beads'; return; fi
  if command -v gh >/dev/null 2>&1 && git -C "$root" remote get-url origin 2>/dev/null | grep -q github.com; then
    printf 'github'; return
  fi
  printf 'file'
}

cmd_init() {
  local tracker="" teams=1 repo="" force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --tracker) tracker="$2"; shift 2;;
      --teams) [ "$2" = off ] && teams=0; shift 2;;
      --repo) repo="$2"; shift 2;;
      --force) force=1; shift;;
      *) die "init: unknown arg $1";;
    esac
  done

  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] || die "init: run this inside a git repository"
  # Guard against initialising the home directory, which is itself a git repo here.
  [ "$root" = "$HOME" ] && die "init: refusing to initialise \$HOME as a factory project"

  mkdir -p "$root/.factory"/{cycles,scope,current,locks} "$root/.claude"

  # Hooks are a symlink, not a copy, so the harness stays the single source of
  # truth and settings.json can reference a stable in-project path.
  rm -f "$root/.factory/hooks"
  ln -s "$FACTORY_HOME/hooks" "$root/.factory/hooks"

  printf 'locks/\ncurrent/\nscope/\ntmp/\n.last-gate\nhooks\n' > "$root/.factory/.gitignore"

  # --- config -------------------------------------------------------------
  local cfg="$root/.factory/config.json"
  if [ ! -f "$cfg" ] || [ "$force" -eq 1 ]; then
    [ -n "$tracker" ] || tracker="$(detect_tracker "$root")"
    [ -n "$repo" ] || repo="$(git -C "$root" remote get-url origin 2>/dev/null | sed -E 's|.*github.com[:/]||; s|\.git$||' || true)"
    local gates; gates="$(detect_gates "$root")"
    jq -n --arg tracker "$tracker" --arg repo "$repo" --argjson gates "$gates" \
      --arg home "$FACTORY_HOME" '{
        tracker: $tracker,
        trackerOptions: { repo: $repo },
        gates: $gates,
        factoryHome: $home
      }' > "$cfg"
    printf 'wrote   %s (tracker: %s, gates: %s)\n' "$cfg" "$tracker" \
      "$(printf '%s' "$gates" | jq -r 'keys | join(", ") | if . == "" then "none detected, add them by hand" else . end')"
  else
    # Keep the recorded harness location current even on a re-init.
    jq --arg home "$FACTORY_HOME" '.factoryHome = $home' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
    printf 'kept    %s (re-run with --force to regenerate)\n' "$cfg"
  fi

  # --- tracker bootstrap --------------------------------------------------
  local chosen; chosen="$(FACTORY_PROJECT_ROOT="$root" config_tracker)"
  if [ "$chosen" = beads ]; then
    if ! command -v bd >/dev/null 2>&1; then
      printf 'note    tracker is beads but bd is not installed: brew install beads\n' >&2
    elif [ ! -d "$root/.beads" ]; then
      ( cd "$root" && bd init >/dev/null 2>&1 ) \
        && printf 'wrote   %s/.beads (bd init)\n' "$root" \
        || printf 'note    bd init failed; run it by hand in %s\n' "$root" >&2
    fi
  fi

  # --- settings.json ------------------------------------------------------
  local tpl settings="$root/.claude/settings.json"
  tpl="$(sed "s/__TEAMS__/$teams/" "$FACTORY_HOME/templates/settings.json.tpl")"
  if [ -f "$settings" ]; then
    # Merge rather than overwrite: keep the project's own env and hooks, and
    # replace only factory hook entries (matched by path) so re-init is safe.
    printf '%s' "$tpl" | jq -s '
      .[0] as $cur | .[1] as $new
      | $cur
      | .env = (($cur.env // {}) + ($new.env // {}))
      | .hooks = (
          (($cur.hooks // {}) | with_entries(
             .value = (.value | map(
               .hooks = ((.hooks // []) | map(select((.command // "") | test("/.factory/hooks/") | not)))
             ) | map(select((.hooks // []) | length > 0)))
          ))
          as $kept
          | reduce (($new.hooks // {}) | to_entries[]) as $e ($kept;
              .[$e.key] = ((.[$e.key] // []) + $e.value))
        )
      | .hooks |= with_entries(select(.value | length > 0))
    ' "$settings" - > "$settings.tmp" && mv "$settings.tmp" "$settings"
    printf 'merged  %s\n' "$settings"
  else
    printf '%s\n' "$tpl" > "$settings"
    printf 'wrote   %s\n' "$settings"
  fi

  # --- CLAUDE.md ----------------------------------------------------------
  local claudemd="$root/CLAUDE.md"
  if ! grep -q '^## Software factory' "$claudemd" 2>/dev/null; then
    { [ -f "$claudemd" ] && { cat "$claudemd"; printf '\n'; }
      cat "$FACTORY_HOME/templates/CLAUDE.md.tpl"; } > "$claudemd.tmp"
    mv "$claudemd.tmp" "$claudemd"
    printf 'wrote   %s\n' "$claudemd"
  else
    printf 'kept    %s (already has a Software factory section)\n' "$claudemd"
  fi

  printf '\n'
  FACTORY_PROJECT_ROOT="$root" cmd_doctor
}

# A worktree needs its own .factory/hooks symlink, because settings.json
# references ${CLAUDE_PROJECT_DIR}/.factory/hooks and CLAUDE_PROJECT_DIR is the
# worktree. State (cycles, locks, scope) still lives in the main worktree.
cmd_link() {
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] || die "link: run this inside a git repository"
  mkdir -p "$root/.factory"
  rm -f "$root/.factory/hooks"
  ln -s "$FACTORY_HOME/hooks" "$root/.factory/hooks"
  printf 'locks/\ncurrent/\nscope/\ntmp/\n.last-gate\nhooks\n' > "$root/.factory/.gitignore"
  jq -nc --arg root "$root" --arg state "$(factory_dir)" '{ok:true,worktree:$root,state:$state}'
}
