#!/usr/bin/env bash

vercel_find_root() {
  local current
  current=$(cd -P "$1" 2>/dev/null && pwd) || return 1
  while [[ "$current" != "/" ]]; do
    [[ -f "$current/.vercel/project.json" ]] && { printf '%s\n' "$current"; return 0; }
    current=${current%/*}
    [[ -n "$current" ]] || current=/
  done
  [[ -f /.vercel/project.json ]] && printf '%s\n' /
}

vercel_json_value() {
  local key=$1 file=$2
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -n 1
}

vercel_cache_dir() {
  printf '%s\n' "${TMUX_VERCEL_STATUS_CACHE_DIR:-${TMUX_TMPDIR:-/tmp}/dotfiles-vercel-status-${UID}}"
}

vercel_cache_file() {
  local root=$1 project_id=$2 key
  key=$(printf '%s\t%s' "$root" "$project_id" | cksum | awk '{print $1}')
  printf '%s/%s\n' "$(vercel_cache_dir)" "$key"
}

vercel_write_state() {
  local file=$1 state=$2 temporary
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 1
  temporary=$(mktemp "$(dirname "$file")/.vercel.XXXXXX") || return 1
  printf '%s\n' "$state" > "$temporary" && mv -f "$temporary" "$file"
}
