#!/usr/bin/env bash
set -euo pipefail

plugin_root="${TMUX_PLUGIN_MANAGER_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins}"
plugin_dir="${plugin_root%/}/tmux-easy-motion"

[[ -x "$plugin_dir/scripts/easy_motion.sh" ]] || exit 0
[[ "${TMUX:-}" =~ .*,([^,]+),.* ]] || exit 0

server_pid="${BASH_REMATCH[1]}"
session_id=$(tmux display-message -p '#{session_id}')
window_id=$(tmux display-message -p '#{window_id}')
pane_id=$(tmux display-message -p '#{pane_id}')

motion=bd-w
if [[ "$(tmux display-message -p -t "$pane_id" '#{selection_present}')" == 1 ]]; then
  motion=bd-e
fi

exec "$plugin_dir/scripts/easy_motion.sh" \
  "$server_pid" "$session_id" "$window_id" "$pane_id" "$motion"
