#!/usr/bin/env bash
set -u

# Show the active Prophet/DW target for the pane's project. The connectivity
# result is cached because tmux refreshes the status bar every second.
directory=${1:-}
[[ -n "$directory" && -d "$directory" ]] || exit 0

find_root() {
  local current=$1
  while [[ "$current" != "/" ]]; do
    [[ -f "$current/dw.json" ]] && {
      printf '%s\n' "$current"
      return 0
    }
    current=${current%/*}
    [[ -n "$current" ]] || current=/
  done
  [[ -f /dw.json ]] && printf '%s\n' /
}

json_value() {
  local key=$1 file=$2
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -n 1
}

root=$(find_root "$directory") || exit 0
config="$root/dw.json"
hostname=$(json_value hostname "$config")
[[ -n "$hostname" ]] || exit 0

label=$hostname
case "${hostname,,}" in
  *development*|*dev*) label=dev ;;
  *)
    if [[ $hostname =~ (^|[-.])([0-9]{3})([-.]|$) ]]; then
      label=${BASH_REMATCH[2]}
    elif [[ "${hostname,,}" == *sandbox* || "${hostname,,}" == *sbx* ]]; then
      label=sbx
    else
      label=XXX
    fi
    ;;
esac

state=offline
cache_dir=${TMUX_DW_STATUS_CACHE_DIR:-${TMUX_TMPDIR:-/tmp}/dotfiles-dw-status-${UID}}
mkdir -p "$cache_dir" 2>/dev/null || true
code_version=$(json_value 'code-version' "$config")
cache_key=$(printf '%s\t%s\t%s' "$root" "$hostname" "$code_version" | cksum | awk '{print $1}')
cache_file="$cache_dir/$cache_key"
now=$(date +%s)
cache_ttl=${TMUX_DW_STATUS_CACHE_TTL:-15}

if [[ -r "$cache_file" ]]; then
  read -r cached_at cached_state < "$cache_file" || true
  if [[ "${cached_at:-0}" =~ ^[0-9]+$ ]] && (( now - cached_at < cache_ttl )); then
    state=${cached_state:-offline}
  fi
fi

if [[ "$state" == offline ]] && command -v curl >/dev/null 2>&1; then
  username=$(json_value username "$config")
  password=$(json_value password "$config")
  if [[ -n "$username" && -n "$password" && -n "$code_version" ]]; then
    url="https://${hostname}/on/demandware.servlet/webdav/Sites/Cartridges/${code_version}/"
    if curl -fsS --max-time 3 -X PROPFIND -H 'Depth: 1' -u "$username:$password" "$url" >/dev/null 2>&1; then
      state=online
    fi
  fi
  printf '%s %s\n' "$now" "$state" > "$cache_file" 2>/dev/null || true
fi

if [[ "$state" == online ]]; then
  printf '#[fg=colour255,bg=#166534,bold] %s #[default]\n' "$label"
else
  printf '#[fg=colour255,bg=colour124,bold] %s #[default]\n' "$label"
fi
