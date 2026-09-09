#!/usr/bin/env bash
# Print a compact best-effort status icon for a Codex pane.
set -euo pipefail

pane_id=${1:-}
pane_pid=${2:-}
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
recent=$(tail -n 25 <<<"$screen")

# Confirmation takes precedence because Codex can leave progress text above it.
if grep -Eiq 'allow|approve|confirmation required|run this command\?|continue\?|\[y/n\]|\(y/n\)' <<<"$recent"; then
  printf '⚠\n'
  exit 0
fi

if grep -Eiq 'error|failed|failure|exception|traceback' <<<"$recent"; then
  printf '!\n'
  exit 0
fi

# These phrases are emitted by the Codex TUI while a turn or MCP tool is active.
if grep -Eiq 'esc to interrupt|starting mcp servers|working|thinking|searching|reading|running|applying|exploring|implementing|testing|verifying' <<<"$recent"; then
  frames=('·' '••' '•••' '••')
  printf '%s\n' "${frames[$(( $(date +%s) % ${#frames[@]} ))]}"
  exit 0
elif grep -Fq 'Ask Codex to do anything' <<<"$recent" || grep -Eq '^[[:space:]]*›' <<<"$recent"; then
  # A visible input prompt means the turn is complete and ready for the next one.
  printf '✓\n'
else
  printf '•\n'
fi
