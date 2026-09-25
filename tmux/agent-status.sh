#!/usr/bin/env bash
# Print a compact best-effort status icon for a Codex or Claude pane.
set -euo pipefail

pane_id=${1:-}
pane_pid=${2:-}
window_active=${3:-0}
window_id=${4:-}
[[ "$pane_id" =~ ^%[0-9]+$ ]] || exit 0
[[ "$pane_pid" =~ ^[0-9]+$ ]] || exit 0
[[ "$window_id" =~ ^@[0-9]+$ ]] || exit 0

state_dir="${TMUX_TMPDIR:-/tmp}/agent-status-${UID}"
state_file="$state_dir/${window_id#@}"
mkdir -p "$state_dir"

read_state() {
  notified=0
  busy=0
  watcher_pid=0
  frame=0
  marquee_tick=0
  usage_triggered=0
  action_required=0
  if [[ -f "$state_file" ]]; then
    read -r notified busy watcher_pid frame marquee_tick usage_triggered action_required < "$state_file" || true
    [[ "$notified" =~ ^[01]$ ]] || notified=0
    [[ "$busy" =~ ^[01]$ ]] || busy=0
    [[ "$watcher_pid" =~ ^[0-9]+$ ]] || watcher_pid=0
    [[ "$frame" =~ ^[0-9]+$ ]] || frame=0
    [[ "$marquee_tick" =~ ^[0-9]+$ ]] || marquee_tick=0
    [[ "$usage_triggered" =~ ^[01]$ ]] || usage_triggered=0
    [[ "$action_required" =~ ^[01]$ ]] || action_required=0
  fi
}

write_state() {
  local temporary
  temporary=$(mktemp "$state_dir/.state.XXXXXX")
  printf '%s %s %s %s %s %s %s\n' "$notified" "$busy" "$watcher_pid" "$frame" "$marquee_tick" "$usage_triggered" "$action_required" >"$temporary"
  mv -f "$temporary" "$state_file"
}

request_usage_refresh() {
  local usage_script="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/agent-usage.sh"
  [[ -f "$usage_script" ]] || return 0
  nohup bash "$usage_script" --trigger "$agent" >/dev/null 2>&1 &
}

print_loading_marquee() {
  # Show one cell at a time from the compact FAKA sequence.
  local marquee='⠟⠁⠮⠵⠗⠪⠮⠵' viewport_width=1 marquee_end
  marquee_end=$(( ${#marquee} - viewport_width ))
  if (( marquee_tick >= 0 )); then
    printf ' %s\n' "${marquee:frame:viewport_width}"
    frame=$(( (frame + 1) % (marquee_end + 1) ))
    marquee_tick=0
  else
    marquee_tick=$((marquee_tick + 1))
  fi
  write_state
  start_refresh_watcher
}

start_refresh_watcher() {
  if [[ "$watcher_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$watcher_pid" 2>/dev/null; then
    return
  fi

  local watcher_lock="$state_dir/.watcher.lock"
  mkdir "$watcher_lock" 2>/dev/null || return 0
  local state_file_q watcher_lock_q
  printf -v state_file_q '%q' "$state_file"
  printf -v watcher_lock_q '%q' "$watcher_lock"
  tmux run-shell -b "
    state_file=$state_file_q
    watcher_lock=$watcher_lock_q
    trap 'rmdir \"\$watcher_lock\" 2>/dev/null || true' EXIT
    while :; do
      watcher_notified=0
      watcher_busy=0
      read -r watcher_notified watcher_busy < "\$state_file" 2>/dev/null || exit 0
      [[ "\$watcher_busy" == 1 ]] || exit 0
      tmux list-clients -F '#{client_name}' 2>/dev/null |
        while IFS= read -r client_name; do
          tmux refresh-client -S -t "$client_name" 2>/dev/null || true
        done
      sleep 0.18
    done
  "
  watcher_pid=0
  write_state
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

if ! agent=$(detect_agent "$pane_pid"); then
  usage_triggered=0
  write_state
  exit 0
fi

if [[ "$usage_triggered" == 0 ]]; then
  # The first observation means an agent has opened in this window. Switching
  # back to an already-observed window remains cache-only.
  request_usage_refresh
  usage_triggered=1
  write_state
fi

screen=$(tmux capture-pane -p -t "$pane_id" -S -80 2>/dev/null || true)
[[ -n "$screen" ]] || exit 0

# Print one of: action, typing, busy, idle, or nothing when the screen is not
# recognised. Only the live prompt/status area is inspected; searching the whole
# transcript makes ordinary words in explanations look like state changes.
codex_state() {
  local recent current_prompt status_line
  recent=$(tail -n 12 <<<"$screen")
  current_prompt=$(tail -n 8 <<<"$screen" | grep -E '^[[:space:]]*›' | tail -n 1 || true)
  status_line=$(tail -n 12 <<<"$screen" | grep -E '^[[:space:]]*[•·—][[:space:]]' | tail -n 1 || true)

  if grep -Eiq '^[[:space:]]*(Allow|Approve|Run this command|Would you like to|Continue)[^[:cntrl:]]*(\?|$)|^[[:space:]]*[\[(][Yy]/[Nn][\])]' <<<"$recent"; then
    echo action
  # A non-empty prompt can remain on screen while Codex is working.
  elif [[ "$current_prompt" =~ ^[[:space:]]*›[[:space:]]+[^[:space:]] && ! "$current_prompt" =~ ^[[:space:]]*›[[:space:]]*Ask[[:space:]]Codex[[:space:]]to[[:space:]]do[[:space:]]anything[[:space:]]*$ ]]; then
    echo typing
  # These phrases are emitted in the live status line while a turn or MCP tool
  # is active.
  elif grep -Eiq '^[[:space:]]*[•·][[:space:]]*(Working|Thinking|Searching|Reading|Running|Applying|Exploring|Implementing|Testing|Verifying)([[:space:]]|\(|$)|^[[:space:]]*[•·].*esc to interrupt' <<<"$status_line"; then
    echo busy
  elif [[ "$current_prompt" =~ ^[[:space:]]*›[[:space:]]*(Ask[[:space:]]Codex[[:space:]]to[[:space:]]do[[:space:]]anything)?[[:space:]]*$ ]]; then
    echo idle
  fi
}

claude_state() {
  local recent footer
  recent=$(tail -n 25 <<<"$screen")
  footer=$(tail -n 12 <<<"$screen")

  # Permission and question dialogs render a numbered selector instead of the
  # prompt box.
  if grep -Eq '^[[:space:]]*[│ ]*❯[[:space:]]+[0-9]+\.[[:space:]]' <<<"$recent" &&
    grep -Eiq 'Do you want|Would you like|Esc to cancel|Enter to select' <<<"$recent"; then
    echo action
  # While a turn runs, the footer offers to interrupt and a spinner line such
  # as "✽ Proofing… (46s)" sits above the prompt; narrow panes may cut the hint.
  elif grep -Eiq 'esc to interrupt' <<<"$footer" ||
    grep -Eq '^[[:space:]]*[^[:space:][:alnum:]][[:space:]]+[[:alpha:]][[:alpha:] -]*…' <<<"$footer"; then
    echo busy
  elif grep -Eq '^[[:space:]]*❯' <<<"$footer"; then
    echo idle
  fi
}

case "$("${agent}_state")" in
  action)
    if [[ "$action_required" == 0 ]]; then
      request_usage_refresh
      action_required=1
    fi
    busy=1
    write_state
    printf ' ⚠\n'
    ;;
  typing)
    # Preserve the existing busy state; otherwise keep the idle AI icon
    # visible while the user is composing a prompt.
    action_required=0
    if [[ "$busy" == 1 ]]; then
      print_loading_marquee
    else
      printf ' ✦\n'
    fi
    ;;
  busy)
    action_required=0
    if [[ "$busy" != 1 ]]; then
      frame=0
      marquee_tick=0
    fi
    busy=1
    print_loading_marquee
    ;;
  idle)
    action_required=0
    if [[ "$busy" == 1 ]]; then
      busy=0
      request_usage_refresh
      if [[ "$window_active" == 1 ]]; then
        notified=0
      else
        notified=1
      fi
      write_state
    fi
    if [[ "$notified" == 1 ]]; then
      printf ' ✓\n'
    else
      printf ' ✦\n'
    fi
    ;;
esac
