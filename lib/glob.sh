# shellcheck shell=bash
# Glob matching for scope and sensitive-path rules.
# bash 3.2 on macOS has no globstar, so translate the pattern to an ERE.

glob_to_regex() {
  printf '%s' "$1" \
    | sed -e 's/[][\.^$+|(){}]/\\&/g' \
          -e 's|\*\*/|@@GSS@@|g' \
          -e 's|\*\*|@@GS@@|g' \
          -e 's|\*|[^/]*|g' \
          -e 's|?|[^/]|g' \
          -e 's|@@GSS@@|(.*/)?|g' \
          -e 's|@@GS@@|.*|g'
}

# glob_match <pattern> <path>  -> exit 0 on match
glob_match() {
  local re; re="$(glob_to_regex "$1")"
  printf '%s' "$2" | grep -Eq "^${re}$"
}

# Normalise any path (absolute, relative, ./-prefixed) to repo-relative.
path_relative_to_root() {
  local p="$1" root
  root="$(project_root)"
  case "$p" in
    /*) p="${p#"$root"/}";;
    ./*) p="${p#./}";;
  esac
  printf '%s' "$p"
}
