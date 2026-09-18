#!/usr/bin/env bash
set -u

# Show the active Prophet/DW target for the pane's project. The remote check is
# performed once per project/target/code version per calendar day because tmux
# refreshes the status bar every second.
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
environment=unknown
case "${hostname,,}" in
  *development*|*dev*)
    label=dev
    environment=dev
    ;;
  *)
    if [[ $hostname =~ (^|[-.])([0-9]{3})([-.]|$) ]]; then
      label=${BASH_REMATCH[2]}
      environment=sandbox
    elif [[ "${hostname,,}" == *sandbox* || "${hostname,,}" == *sbx* ]]; then
      label=sbx
      environment=sandbox
    else
      label=XXX
    fi
    ;;
esac

state=unknown
cache_dir=${TMUX_DW_STATUS_CACHE_DIR:-${TMUX_TMPDIR:-/tmp}/dotfiles-dw-status-${UID}}
mkdir -p "$cache_dir" 2>/dev/null || true
code_version=$(json_value 'code-version' "$config")
cache_key=$(printf '%s\t%s\t%s' "$root" "$hostname" "$code_version" | cksum | awk '{print $1}')
cache_file="$cache_dir/$cache_key"
pending_file="$cache_file.pending"
today=$(date +%Y-%m-%d)

if [[ -r "$cache_file" ]]; then
  read -r cached_day cached_state < "$cache_file" || true
  if [[ "$cached_day" == "$today" && "$cached_state" == online ]]; then
    state=online
  elif [[ "$cached_day" == "$today" && "$cached_state" == offline ]]; then
    state=offline
  fi
fi

if [[ "$state" == unknown ]]; then
  username=$(json_value username "$config")
  password=$(json_value password "$config")
  if [[ -n "$username" && -n "$password" && -n "$code_version" ]] && command -v curl >/dev/null 2>&1; then
    if mkdir "$pending_file" 2>/dev/null; then
      (
        result=offline
        url="https://${hostname}/on/demandware.servlet/webdav/Sites/Cartridges/${code_version}/"
        if curl -fsS --max-time 3 -X PROPFIND -H 'Depth: 1' -u "$username:$password" "$url" >/dev/null 2>&1; then
          result=online
        fi
        tmp_file="$cache_file.$$"
        printf '%s %s\n' "$today" "$result" > "$tmp_file" 2>/dev/null && mv -f "$tmp_file" "$cache_file"
        rmdir "$pending_file" 2>/dev/null || true
      ) </dev/null >/dev/null 2>&1 &
    fi
  else
    printf '%s offline\n' "$today" > "$cache_file" 2>/dev/null || true
    state=offline
  fi
fi

status_text=$label
[[ -n "$code_version" ]] && status_text="$code_version $status_text"
if [[ "$state" == online ]]; then
  printf '#[fg=colour255,bg=#166534,bold] %s #[default]\n' "$status_text"
elif [[ "$state" == offline ]]; then
  printf '#[fg=colour255,bg=colour124,bold] %s #[default]\n' "$status_text"
else
  printf '#[fg=colour255,bg=colour237,bold] %s #[default]\n' "$status_text"
fi
