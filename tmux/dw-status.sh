#!/usr/bin/env bash
set -u

# Render the active DW target. Network activity belongs to bin/dw-sandbox;
# tmux refreshes this script too often to be a safe place for lifecycle calls.
directory=${1:-}
[[ -n "$directory" && -d "$directory" ]] || exit 0

find_root() {
  local current=$1
  while :; do
    [[ -f "$current/dw.json" ]] && {
      printf '%s\n' "$current"
      return 0
    }
    [[ "$current" == / ]] && return 1
    current=${current%/*}
    [[ -n "$current" ]] || current=/
  done
}

json_value() {
  local key=$1 file=$2
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -n 1
}

root=$(find_root "$directory") || exit 0
config="$root/dw.json"
hostname=$(json_value hostname "$config")
[[ -n "$hostname" ]] || exit 0

code_version=$(json_value 'code-version' "$config")
host=${hostname,,}
if [[ "$host" == *development* || "$host" == *dev* ]]; then
  printf '#[fg=colour255,bg=colour237,bold] %s #[default]\n' "${code_version:+$code_version }dev"
  exit 0
fi
[[ "$host" =~ ^([a-z0-9]{4})-([0-9]{3})\.dx\.commercecloud\.salesforce\.com$ ]] || exit 0
id="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
number=${BASH_REMATCH[2]}
state_root=${DW_SANDBOX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/dw-sandbox}
state_file="$state_root/$id.state"
state=CHECKING
[[ -r "$state_file" ]] && state=$(sed -n 's/^state=//p' "$state_file" | head -n 1)
updated=
[[ -r "$state_file" ]] && updated=$(sed -n 's/^updated=//p' "$state_file" | head -n 1)

# Terminal states are useful confirmation, but their text should not
# permanently consume tmux status-bar space. Older cache files without a
# timestamp stay visible.
terminal_ttl=${TMUX_DW_TERMINAL_STATE_TTL:-3}
hide_terminal_label=false
if [[ "$state" =~ ^(READY|STOPPED|FAILED)$ && "$updated" =~ ^[0-9]+$ && "$terminal_ttl" =~ ^[0-9]+$ ]]; then
  (( $(date +%s) - updated >= terminal_ttl )) && hide_terminal_label=true
fi
case "$state" in
  STARTING) frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); label="$code_version $number STARTING ${frames[$(($(date +%s) % ${#frames[@]}))]}"; background='#1d4ed8' ;;
  READY) label="$code_version $number READY"; background='#166534' ;;
  STOPPED) label="$code_version $number STOPPED"; background='#a16207' ;;
  FAILED) label="$code_version $number FAILED"; background='colour124' ;;
  LOGIN) label="$code_version $number LOGIN"; background='#7e22ce' ;;
  *) frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); label="$code_version $number CHECKING ${frames[$(($(date +%s) % ${#frames[@]}))]}"; background='colour237' ;;
esac
[[ "$hide_terminal_label" == true ]] && label="$code_version $number"
printf '#[fg=colour255,bg=%s,bold] %s #[default]\n' "$background" "$label"
