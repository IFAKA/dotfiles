#!/usr/bin/env bash
# Print the 5h/weekly usage of the coding agent (Codex or Claude) running in a
# tmux pane. Renders only read the per-agent cache; --trigger refreshes it.
set -euo pipefail

plugin_root="${TMUX_PLUGIN_MANAGER_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins}"
script_dir="$plugin_root/agent-usage-tmux/scripts"

mode=${1:-}

process_command() {
  ps -o command= -p "$1" 2>/dev/null | sed 's/^ *//'
}

agent_for_command() {
  local command="$1" executable argument
  executable=${command%%[[:space:]]*}
  argument=${command#"$executable"}
  argument=${argument#"${argument%%[![:space:]]*}"}
  argument=${argument%%[[:space:]]*}
  if [[ "${executable##*/}" == claude || "${argument##*/}" == claude || "$command" == *@anthropic-ai/claude-code* ]]; then
    echo claude
  elif [[ "$command" == *[Cc]odex* ]]; then
    echo codex
  fi
}

detect_agent() {
  local pid="$1" child agent
  agent=$(agent_for_command "$(process_command "$pid")")
  [[ -n "$agent" ]] && { echo "$agent"; return 0; }
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    detect_agent "$child" && return 0
  done
  return 1
}

if [[ "$mode" == --refresh || "$mode" == --trigger ]]; then
  agent=${2:-codex}
  [[ "$agent" == codex || "$agent" == claude ]] || agent=codex
else
  pane_pid="$mode"
  [[ "$pane_pid" =~ ^[0-9]+$ ]] || exit 0
  agent=$(detect_agent "$pane_pid") || exit 0
fi

fetch_script="$script_dir/fetch_${agent}_usage.py"
[[ -f "$fetch_script" ]] || exit 0

cache_root="${TMUX_AGENT_USAGE_CACHE_DIR:-${TMUX_TMPDIR:-/tmp}/dotfiles-agent-usage-${UID}}"
cache_dir="$cache_root"
cache_file="$cache_dir/$agent"
refresh_lock="$cache_dir/.refresh-$agent.lock"
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

remaining_percentage() {
  local value="$1"
  awk -v value="$value" 'BEGIN {
    if (value < 0) value = 0
    if (value > 100) value = 100
    printf "%d%%", int(value)
  }'
}

remaining_indicator() {
  local value="$1" percentage color
  percentage=$(remaining_percentage "$value")
  if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == dumb ]]; then
    printf '%s' "$percentage"
    return
  fi
  color=$(remaining_color "$value")
  # Preserve the caller's background; the indicator itself has no background.
  printf '#[fg=%s,bold]%s#[fg=colour255,bold]' "$color" "$percentage"
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

claude_credentials() {
  local credentials_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
  if [[ -f "$credentials_file" ]]; then
    cat "$credentials_file"
  elif command -v security >/dev/null 2>&1; then
    # Claude Code keeps its OAuth credentials in the macOS login keychain.
    security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null
  else
    return 1
  fi
}

fetch_codex_usage() {
  local primary_percent primary_reset secondary_percent secondary_reset
  primary_percent=$(python3 "$fetch_script" --window primary 2>/dev/null) || return 1
  primary_reset=$(python3 "$fetch_script" --window primary --field reset_in 2>/dev/null) || return 1
  secondary_percent=$(python3 "$fetch_script" --window secondary 2>/dev/null) || return 1
  secondary_reset=$(python3 "$fetch_script" --window secondary --field reset_in 2>/dev/null) || return 1
  printf '%s %s %s %s\n' "$primary_percent" "$primary_reset" "$secondary_percent" "$secondary_reset"
}

fetch_claude_usage() {
  local credentials headers
  credentials=$(claude_credentials) || return 1
  [[ -n "$credentials" ]] || return 1
  # One request returns both windows as rate-limit headers.
  headers=$(python3 "$fetch_script" --credentials-file /dev/stdin --raw <<<"$credentials" 2>/dev/null) || return 1
  awk -v now="$(date +%s)" '
    function remaining(utilization) { value = 100 - utilization * 100; return value < 0 ? 0 : value }
    function reset_in(epoch) { value = epoch - now; return value < 0 ? 0 : value }
    $1 == "anthropic-ratelimit-unified-5h-utilization:" { primary = remaining($2) }
    $1 == "anthropic-ratelimit-unified-5h-reset:" { primary_reset = reset_in($2) }
    $1 == "anthropic-ratelimit-unified-7d-utilization:" { secondary = remaining($2) }
    $1 == "anthropic-ratelimit-unified-7d-reset:" { secondary_reset = reset_in($2) }
    END {
      if (primary == "" || primary_reset == "" || secondary == "" || secondary_reset == "") exit 1
      printf "%g %d %g %d\n", primary, primary_reset, secondary, secondary_reset
    }' <<<"$headers"
}

refresh_usage() {
  local usage primary_percent primary_reset secondary_percent secondary_reset temporary
  usage=$("fetch_${agent}_usage") || return 1
  read -r primary_percent primary_reset secondary_percent secondary_reset <<<"$usage"
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
  nohup bash "$0" --refresh "$agent" >/dev/null 2>&1 &
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

printf '#[fg=colour255,bold] 5h #[fg=colour255]%s#[fg=colour255] · #[fg=colour255,bold]wk #[fg=colour255]%s#[fg=colour255]#[fg=colour255,bold] |#[default]' \
  "$(usage_value "$primary_percent" "$primary_reset")" \
  "$(usage_value "$secondary_percent" "$secondary_reset")"
