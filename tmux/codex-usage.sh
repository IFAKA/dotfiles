#!/usr/bin/env bash
set -euo pipefail

plugin_root="${TMUX_PLUGIN_MANAGER_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins}"
fetch_script="$plugin_root/agent-usage-tmux/scripts/fetch_codex_usage.py"

mode=${1:-}
[[ -f "$fetch_script" ]] || exit 0

process_command() {
  ps -o command= -p "$1" 2>/dev/null | sed 's/^ *//'
}

has_codex_process() {
  local pid="$1" child command
  command=$(process_command "$pid")
  [[ "$command" == *[Cc]odex* ]] && return 0
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    has_codex_process "$child" && return 0
  done
  return 1
}

if [[ "$mode" != --refresh && "$mode" != --trigger ]]; then
  pane_pid="$mode"
  [[ "$pane_pid" =~ ^[0-9]+$ ]] || exit 0
  has_codex_process "$pane_pid" || exit 0
fi

cache_root="${TMUX_CODEX_USAGE_CACHE_DIR:-${TMUX_TMPDIR:-/tmp}/dotfiles-codex-usage-${UID}}"
cache_dir="$cache_root"
cache_file="$cache_dir/usage"
refresh_lock="$cache_dir/.refresh.lock"
braille_states=('⣿' '⣷' '⣶' '⣦' '⣤' '⣄' '⣀' '⡀' '⠀')

format_reset() {
  local seconds="$1"
  local days hours minutes
  days=$(( seconds / 86400 ))
  hours=$(( (seconds % 86400) / 3600 ))
  minutes=$(( (seconds % 3600) / 60 ))
  if (( days > 0 )); then
    printf '%dd' "$days"
  elif (( hours > 0 )); then
    printf '%dh' "$hours"
  else
    printf '%dm' "$minutes"
  fi
}

remaining_color() {
  local value="$1"
  # Interpolate a luminance-ordered, colour-vision-deficiency-friendly ramp
  # continuously so color adds resolution between the geometric states.
  awk -v value="$value" 'BEGIN {
    if (value < 0) value = 0
    if (value > 100) value = 100
    split("239,68,68 245,158,11 250,204,21 163,230,53 103,232,249", stops, " ")
    position = value / 25
    segment = int(position)
    if (segment >= 4) segment = 3
    fraction = position - segment
    split(stops[segment + 1], start, ",")
    split(stops[segment + 2], finish, ",")
    red = int(start[1] + (finish[1] - start[1]) * fraction + 0.5)
    green = int(start[2] + (finish[2] - start[2]) * fraction + 0.5)
    blue = int(start[3] + (finish[3] - start[3]) * fraction + 0.5)
    printf "#%02x%02x%02x", red, green, blue
  }'
}

remaining_block() {
  local value="$1" index
  index=$(awk -v value="$value" 'BEGIN {
    if (value < 0) value = 0
    if (value > 100) value = 100
    printf "%d", int(value * 8 / 100 + 0.5)
  }')
  printf '%s' "${braille_states[8 - index]}"
}

remaining_indicator() {
  local value="$1" block color
  block=$(remaining_block "$value")
  if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == dumb ]]; then
    printf '%s' "$block"
    return
  fi
  color=$(remaining_color "$value")
  # Preserve the caller's background; the indicator itself has no background.
  printf '#[fg=%s,bold]%s#[fg=colour255,bold]' "$color" "$block"
}

usage_value() {
  local percent="$1" reset="$2" reset_value
  if [[ "$percent" == -- ]]; then
    printf '?'
    return
  fi
  reset_value=$(format_reset "$reset")
  if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == dumb ]]; then
    printf '%s %s' "$(remaining_indicator "$percent")" "$reset_value"
  else
    printf '%s #[fg=colour250,nobold,nodim]%s#[fg=colour255,bold,nodim]' \
      "$(remaining_indicator "$percent")" "$reset_value"
  fi
}

refresh_usage() {
  local primary_percent primary_reset secondary_percent secondary_reset temporary
  primary_percent=$(python3 "$fetch_script" --window primary 2>/dev/null) || return 1
  primary_reset=$(python3 "$fetch_script" --window primary --field reset_in 2>/dev/null) || return 1
  secondary_percent=$(python3 "$fetch_script" --window secondary 2>/dev/null) || return 1
  secondary_reset=$(python3 "$fetch_script" --window secondary --field reset_in 2>/dev/null) || return 1
  [[ "$primary_percent" =~ ^[0-9]+([.][0-9]+)?$ && "$primary_reset" =~ ^[0-9]+$ &&
    "$secondary_percent" =~ ^[0-9]+([.][0-9]+)?$ && "$secondary_reset" =~ ^[0-9]+$ ]] || return 1
  temporary=$(mktemp "$cache_dir/.usage.XXXXXX")
  printf '%s %s %s %s %s\n' "$(date +%s)" "$primary_percent" "$primary_reset" \
    "$secondary_percent" "$secondary_reset" > "$temporary"
  mv -f "$temporary" "$cache_file"
}

schedule_refresh() {
  mkdir -p "$cache_dir"
  mkdir "$refresh_lock" 2>/dev/null || return 0
  nohup bash "$0" --refresh >/dev/null 2>&1 &
}

if [[ "$mode" == --refresh ]]; then
  trap 'rmdir "$refresh_lock" 2>/dev/null || true' EXIT
  refresh_usage || exit 0
  exit 0
fi

if [[ "$mode" == --trigger ]]; then
  schedule_refresh
  exit 0
fi

fetched_at=0
primary_percent=--
primary_reset=0
secondary_percent=--
secondary_reset=0
if [[ -f "$cache_file" ]]; then
  read -r fetched_at primary_percent primary_reset secondary_percent secondary_reset < "$cache_file" || true
  [[ "$fetched_at" =~ ^[0-9]+$ && "$primary_percent" =~ ^[0-9]+([.][0-9]+)?$ &&
    "$primary_reset" =~ ^[0-9]+$ && "$secondary_percent" =~ ^[0-9]+([.][0-9]+)?$ &&
    "$secondary_reset" =~ ^[0-9]+$ ]] || {
    fetched_at=0
    primary_percent=--
    secondary_percent=--
  }
fi

printf '#[fg=colour255,bold] 5h #[fg=colour255]%s#[fg=colour255] | #[fg=colour255,bold]wk #[fg=colour255]%s#[fg=colour255]#[fg=colour255,bold] |#[default]' \
  "$(usage_value "$primary_percent" "$primary_reset")" \
  "$(usage_value "$secondary_percent" "$secondary_reset")"
