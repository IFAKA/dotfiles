#!/usr/bin/env bash

# Use the client that triggered the hook instead of always selecting the
# narrowest connected client. This lets a wide desktop client restore the
# one-row layout when it attaches or resizes.
set -u

client_width=${1:-}
threshold=$(tmux show-option -gqv @status-overflow-width 2>/dev/null || true)
status_details='#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/dw-status.sh" "#{pane_current_path}")#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/git-status.sh" "#{pane_current_path}")#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/vercel-status.sh" "#{pane_current_path}")#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/agent-usage.sh" "#{pane_pid}" "#{window_id}")#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/resource-status.sh")'

[[ "$client_width" =~ ^[0-9]+$ ]] || exit 0
[[ "$threshold" =~ ^[0-9]+$ ]] || threshold=160

state=0
(( client_width < threshold )) && state=1

current=$(tmux show-option -gqv @dotfiles-status-overflow 2>/dev/null || true)
if [[ "$current" != "$state" ]]; then
  tmux set-option -gq @dotfiles-status-overflow "$state"
  if (( state == 1 )); then
    tmux set-option -g status 2
    tmux set-option -gq status-right ''
    tmux set-option -gq @dotfiles-status-details "$status_details"
    tmux set-option -g status-format[1] '#[align=right]#{E:@dotfiles-status-details}'
  else
    tmux set-option -g status on
    tmux set-option -g status-right "$status_details"
    tmux set-option -gu status-format[1]
  fi
  tmux refresh-client -S >/dev/null 2>&1 || true
fi
