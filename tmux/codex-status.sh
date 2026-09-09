#!/usr/bin/env bash
# Print a compact best-effort status icon for a Codex pane.
set -euo pipefail

pane_id=${1:-}
pane_pid=${2:-}
window_active=${3:-0}
[[ "$pane_id" =~ ^%[0-9]+$ ]] || exit 0
[[ "$pane_pid" =~ ^[0-9]+$ ]] || exit 0

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
status_line=$(tail -n 12 <<<"$screen" | grep -E '^[[:space:]]*[•·—✗!][[:space:]]' | tail -n 1 || true)

# While the user is typing, leave the tab clean. The empty input prompt is
# also rendered while Codex is working, so it must not take precedence over
# confirmation, error, or activity text in the captured pane.
if [[ "$current_prompt" =~ ^[[:space:]]*›[[:space:]]+[^[:space:]] && ! "$current_prompt" =~ ^[[:space:]]*›[[:space:]]*Ask[[:space:]]Codex[[:space:]]to[[:space:]]do[[:space:]]anything[[:space:]]*$ ]]; then
  exit 0
fi

# Only inspect the live prompt/status area. Searching the whole transcript
# makes ordinary words in Codex's explanations look like state changes.
if grep -Eiq '^[[:space:]]*(Allow|Approve|Run this command|Would you like to|Continue)[^[:cntrl:]]*(\?|$)|^[[:space:]]*[\[(][Yy]/[Nn][\])]' <<<"$recent"; then
  printf '⚠\n'
  exit 0
fi

if grep -Eiq '^[[:space:]]*[✗!][[:space:]]|^[[:space:]]*(Error|Failed|Failure|Exception|Traceback)(:|[[:space:]])' <<<"$status_line"; then
  printf '!\n'
  exit 0
fi

# These phrases are emitted in the live status line while a turn or MCP tool
# is active.
if grep -Eiq '^[[:space:]]*[•·][[:space:]]*(Working|Thinking|Searching|Reading|Running|Applying|Exploring|Implementing|Testing|Verifying)([[:space:]]|\(|$)|^[[:space:]]*[•·].*esc to interrupt' <<<"$status_line"; then
  frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  printf '%s\n' "${frames[$(( $(date +%s) % ${#frames[@]} ))]}"
  exit 0
fi

if [[ "$current_prompt" =~ ^[[:space:]]*›[[:space:]]*(Ask[[:space:]]Codex[[:space:]]to[[:space:]]do[[:space:]]anything)?[[:space:]]*$ ]]; then
  [[ "$window_active" == 1 ]] && exit 0
  printf '✓\n'
else
  printf '•\n'
fi
