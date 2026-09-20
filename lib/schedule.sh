# shellcheck shell=bash
# Install / remove the unattended launchd jobs.
# launchd rather than CronCreate: CronCreate lives in one Claude session's
# memory, only fires while that REPL is idle, and dies with the session.

LAUNCH_DIR="$HOME/Library/LaunchAgents"

_plist_path() { printf '%s/com.unicrew.factory.%s.plist\n' "$LAUNCH_DIR" "$1"; }

_render_plist() {
  sed -e "s|__FACTORY_HOME__|$FACTORY_HOME|g" -e "s|__HOME__|$HOME|g" \
    "$FACTORY_HOME/launchd/com.unicrew.factory.$1.plist"
}

cmd_schedule() {
  local verb="${1:-status}"; shift || true
  mkdir -p "$HOME/.factory/logs"
  local jobs="scan retro" j p

  case "$verb" in
    install)
      [ -f "$HOME/.factory/repos.txt" ] || {
        printf '# One factory project path per line. Lines starting with # are ignored.\n' > "$HOME/.factory/repos.txt"
        printf 'created %s -- add your projects with: factory schedule add <path>\n' "$HOME/.factory/repos.txt"
      }
      mkdir -p "$LAUNCH_DIR"
      for j in $jobs; do
        p="$(_plist_path "$j")"
        _render_plist "$j" > "$p"
        launchctl unload "$p" >/dev/null 2>&1 || true
        if launchctl load "$p" 2>/dev/null; then
          printf 'installed  com.unicrew.factory.%s  (%s)\n' "$j" \
            "$([ "$j" = scan ] && echo 'daily 08:47' || echo 'Mondays 09:13')"
        else
          printf 'FAILED to load %s -- try: launchctl load %s\n' "$j" "$p" >&2
        fi
      done
      printf '\nRegistered projects:\n'
      grep -v '^#' "$HOME/.factory/repos.txt" 2>/dev/null | grep -v '^$' | sed 's/^/  /' || printf '  (none yet)\n'
      ;;
    uninstall)
      for j in $jobs; do
        p="$(_plist_path "$j")"
        launchctl unload "$p" >/dev/null 2>&1 || true
        rm -f "$p"
        printf 'removed    com.unicrew.factory.%s\n' "$j"
      done
      ;;
    add)
      local path="${1:-$PWD}"
      path="$(cd "$path" 2>/dev/null && pwd)" || die "schedule add: no such directory"
      [ -d "$path/.factory" ] || die "schedule add: $path is not a factory project (run /factory:init there first)"
      mkdir -p "$HOME/.factory"
      touch "$HOME/.factory/repos.txt"
      if grep -qxF "$path" "$HOME/.factory/repos.txt" 2>/dev/null; then
        printf 'already registered: %s\n' "$path"
      else
        printf '%s\n' "$path" >> "$HOME/.factory/repos.txt"
        printf 'registered: %s\n' "$path"
      fi
      ;;
    remove)
      local path="${1:-$PWD}"
      path="$(cd "$path" 2>/dev/null && pwd)" || path="${1:-$PWD}"
      if [ -f "$HOME/.factory/repos.txt" ]; then
        grep -vxF "$path" "$HOME/.factory/repos.txt" > "$HOME/.factory/repos.txt.tmp" || true
        mv "$HOME/.factory/repos.txt.tmp" "$HOME/.factory/repos.txt"
      fi
      printf 'unregistered: %s\n' "$path"
      ;;
    run)
      local which="${1:-scan}"
      "$FACTORY_HOME/bin/factory-cron" "$which"
      ;;
    status)
      for j in $jobs; do
        p="$(_plist_path "$j")"
        if [ -f "$p" ]; then
          printf '%-6s installed  %s\n' "$j" \
            "$(launchctl list 2>/dev/null | awk -v n="com.unicrew.factory.$j" '$3==n{print "loaded (last exit "$2")"}' | head -1)"
        else
          printf '%-6s not installed\n' "$j"
        fi
      done
      printf '\nRegistered projects:\n'
      grep -v '^#' "$HOME/.factory/repos.txt" 2>/dev/null | grep -v '^$' | sed 's/^/  /' || printf '  (none)\n'
      printf '\nRecent runs:\n'
      ls -t "$HOME/.factory/logs"/*.log 2>/dev/null | head -5 | sed 's|^|  |' || printf '  (none)\n'
      ;;
    *) die "schedule: install|uninstall|add|remove|run|status";;
  esac
}
