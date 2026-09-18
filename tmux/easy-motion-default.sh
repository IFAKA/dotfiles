#!/usr/bin/env bash
set -euo pipefail

plugin_root="${TMUX_PLUGIN_MANAGER_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins}"
plugin_dir="${plugin_root%/}/tmux-easy-motion"
semantic_action="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/smart-actions.py"

[[ -x "$plugin_dir/scripts/easy_motion.sh" ]] || exit 0
[[ -f "$semantic_action" ]] || exit 0
[[ "${TMUX:-}" =~ .*,([^,]+),.* ]] || exit 0

server_pid="${BASH_REMATCH[1]}"
session_id=$(tmux display-message -p '#{session_id}')
window_id=$(tmux display-message -p '#{window_id}')
pane_id=$(tmux display-message -p '#{pane_id}')

target_keys=$(tmux show-options -gqv @easy-motion-target-keys 2>/dev/null || true)
target_keys=${target_keys:-asdfghjklqwertyuiopzxcvbnm}
capture_file=$(mktemp "${TMPDIR:-/tmp}/dotfiles-easy-motion-smart.XXXXXX")
marker_file=$(mktemp "${TMPDIR:-/tmp}/dotfiles-easy-motion-keys.XXXXXX")
trap 'rm -f "$capture_file" "$marker_file"' EXIT
tmux capture-pane -p -J -t "$pane_id" > "$capture_file"

for key in $(printf '%s' "$target_keys" | fold -w1); do
  lower=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
  upper=$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')
  pipe="$plugin_dir/scripts/pipe_target_key.sh '$server_pid' '$session_id' '$lower'"
  tmux bind-key -T easy-motion-target "$key" run-shell -b "printf '%s' '$lower' >> '$marker_file'; $pipe"
  tmux bind-key -T easy-motion-target "$upper" run-shell -b "printf '%s' '$upper' >> '$marker_file'; $pipe"
  tmux bind-key -T easy-motion-target "S-$lower" run-shell -b "printf '%s' '$upper' >> '$marker_file'; $pipe"
done

motion=bd-w
if [[ -n "$(tmux display-message -p -t "$pane_id" '#{selection_start_x}')" ]]; then
  motion=bd-E
fi

"$plugin_dir/scripts/easy_motion.sh" \
  "$server_pid" "$session_id" "$window_id" "$pane_id" "$motion"

raw_label=""
for _ in {1..100}; do
  raw_label=$(cat "$marker_file" 2>/dev/null || true)
  [[ -n "$raw_label" ]] && break
  sleep 0.01
done

if [[ -n "$raw_label" && "${raw_label: -1}" =~ [A-Z] ]]; then
  cursor=$(tmux display-message -p -t "$pane_id" '#{copy_cursor_y}:#{copy_cursor_x}')
  python3 "$semantic_action" --input-file "$capture_file" \
    --smart-action "$cursor" --pane-id "$pane_id" || true
fi
