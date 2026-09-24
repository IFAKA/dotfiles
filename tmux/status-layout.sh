#!/usr/bin/env bash

# Keep the status bar on one line until the client is narrow enough that the
# right-side indicators are likely to be truncated.
set -u

client_width=${1:-}
threshold=$(tmux show-option -gqv @status-overflow-width 2>/dev/null || true)

[[ "$client_width" =~ ^[0-9]+$ ]] || exit 0
[[ "$threshold" =~ ^[0-9]+$ ]] || threshold=160

state=0
(( client_width < threshold )) && state=1

current=$(tmux show-option -gqv @dotfiles-status-overflow 2>/dev/null || true)
if [[ "$current" != "$state" ]]; then
  tmux set-option -gq @dotfiles-status-overflow "$state"
  if (( state == 1 )); then
    tmux set-option -g status-format[1] '#[align=right]#{?@dotfiles-status-overflow,#{@dotfiles-status-right},}'
  else
    tmux set-option -gu status-format[1]
  fi
  tmux refresh-client -S >/dev/null 2>&1 || true
fi
