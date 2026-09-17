#!/usr/bin/env bash
set -euo pipefail

plugin_root="${TMUX_PLUGIN_MANAGER_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins}"
fetch_script="$plugin_root/agent-usage-tmux/scripts/fetch_codex_usage.py"

[[ -f "$fetch_script" ]] || exit 0

format_reset() {
  local seconds="$1"
  local days hours minutes
  days=$(( seconds / 86400 ))
  hours=$(( (seconds % 86400) / 3600 ))
  minutes=$(( (seconds % 3600) / 60 ))
  if (( days > 0 )); then
    printf '%dd%02dh' "$days" "$hours"
  else
    printf '%dh%02dm' "$hours" "$minutes"
  fi
}

remaining_color() {
  local value="$1"
  # The fetcher returns remaining capacity: 100 means a full window and 0
  # means exhausted. Keep the color scale aligned with that meaning.
  if (( value <= 10 )); then
    printf 'colour217'
  elif (( value <= 25 )); then
    printf 'colour223'
  elif (( value <= 40 )); then
    printf 'colour226'
  elif (( value <= 60 )); then
    printf 'colour186'
  elif (( value <= 80 )); then
    printf 'colour150'
  else
    printf 'colour114'
  fi
}

usage_value() {
  local window="$1"
  local percent reset
  percent=$(python3 "$fetch_script" --window "$window" 2>/dev/null) || return 0
  reset=$(python3 "$fetch_script" --window "$window" --field reset_in 2>/dev/null) || reset=0
  printf '#[bg=colour238,fg=%s,bold]%s%%#[bg=colour238,fg=colour255,bold] %s' \
    "$(remaining_color "$percent")" "$percent" "$(format_reset "$reset")"
}

printf '#[bg=colour238,fg=colour238]#[bg=colour238,fg=colour255,bold] 5h #[bg=colour238,fg=colour255]%s#[bg=colour238,fg=colour255] | #[bg=colour238,fg=colour255,bold]wk #[bg=colour238,fg=colour255]%s#[bg=colour238] #[default]' \
  "$(usage_value primary)" "$(usage_value secondary)"
