#!/usr/bin/env bash
# Print a compact best-effort status icon for a Codex pane.
set -euo pipefail

pane_id=${1:-}
pane_pid=${2:-}
window_active=${3:-0}
window_id=${4:-}
[[ "$pane_id" =~ ^%[0-9]+$ ]] || exit 0
[[ "$pane_pid" =~ ^[0-9]+$ ]] || exit 0
[[ "$window_id" =~ ^@[0-9]+$ ]] || exit 0

state_dir="${TMUX_TMPDIR:-/tmp}/codex-status-${UID}"
state_file="$state_dir/${window_id#@}"
mkdir -p "$state_dir"

read_state() {
  notified=0
  busy=0
  if [[ -f "$state_file" ]]; then
    read -r notified busy < "$state_file" || true
    [[ "$notified" =~ ^[01]$ ]] || notified=0
    [[ "$busy" =~ ^[01]$ ]] || busy=0
  fi
}

write_state() {
  local temporary
  temporary=$(mktemp "$state_dir/.state.XXXXXX")
  printf '%s %s\n' "$notified" "$busy" >"$temporary"
  mv -f "$temporary" "$state_file"
}

read_state

# Visiting a window acknowledges its completion notification. Keep the busy
# flag so a turn that is still running can notify when it later finishes in
# the background.
if [[ "$window_active" == 1 ]]; then
  notified=0
  write_state
fi

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

has_codex_process "$pane_pid" || exit 0

screen=$(tmux capture-pane -p -t "$pane_id" -S -80 2>/dev/null || true)
[[ -n "$screen" ]] || exit 0
recent=$(tail -n 12 <<<"$screen")
current_prompt=$(tail -n 8 <<<"$screen" | grep -E '^[[:space:]]*›' | tail -n 1 || true)
status_line=$(tail -n 12 <<<"$screen" | grep -E '^[[:space:]]*[•·—][[:space:]]' | tail -n 1 || true)

# While the user is typing, leave the tab clean. The empty input prompt is
# also rendered while Codex is working, so it must not take precedence over
# confirmation or activity text in the captured pane.
if [[ "$current_prompt" =~ ^[[:space:]]*›[[:space:]]+[^[:space:]] && ! "$current_prompt" =~ ^[[:space:]]*›[[:space:]]*Ask[[:space:]]Codex[[:space:]]to[[:space:]]do[[:space:]]anything[[:space:]]*$ ]]; then
  busy=1
  write_state
  exit 0
fi

# Only inspect the live prompt/status area. Searching the whole transcript
# makes ordinary words in Codex's explanations look like state changes.
if grep -Eiq '^[[:space:]]*(Allow|Approve|Run this command|Would you like to|Continue)[^[:cntrl:]]*(\?|$)|^[[:space:]]*[\[(][Yy]/[Nn][\])]' <<<"$recent"; then
  busy=1
  write_state
  printf '⚠\n'
  exit 0
fi

# These phrases are emitted in the live status line while a turn or MCP tool
# is active.
if grep -Eiq '^[[:space:]]*[•·][[:space:]]*(Working|Thinking|Searching|Reading|Running|Applying|Exploring|Implementing|Testing|Verifying)([[:space:]]|\(|$)|^[[:space:]]*[•·].*esc to interrupt' <<<"$status_line"; then
  busy=1
  write_state
  frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  printf '%s\n' "${frames[$(( $(date +%s) % ${#frames[@]} ))]}"
  exit 0
fi

if [[ "$current_prompt" =~ ^[[:space:]]*›[[:space:]]*(Ask[[:space:]]Codex[[:space:]]to[[:space:]]do[[:space:]]anything)?[[:space:]]*$ ]]; then
  if [[ "$busy" == 1 ]]; then
    busy=0
    if [[ "$window_active" == 1 ]]; then
      notified=0
    else
      notified=1
    fi
    write_state
  fi
  [[ "$notified" == 1 ]] && printf '✓\n'
else
  exit 0
fi
