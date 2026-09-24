#!/usr/bin/env bash

# tmux status options are global, so use the narrowest connected client. This
# keeps a phone client usable even when a desktop client is attached too.
set -u

threshold=$(tmux show-option -gqv @status-overflow-width 2>/dev/null || true)
status_details='#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/dw-status.sh" "#{pane_current_path}")#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/git-status.sh" "#{pane_current_path}")#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/vercel-status.sh" "#{pane_current_path}")#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/codex-usage.sh" "#{pane_pid}" "#{window_id}")#(bash "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/resource-status.sh")'

[[ "$threshold" =~ ^[0-9]+$ ]] || threshold=160

min_width=
while IFS= read -r client_width; do
  [[ "$client_width" =~ ^[0-9]+$ ]] || continue
  if [[ -z "$min_width" || "$client_width" -lt "$min_width" ]]; then
    min_width=$client_width
  fi
done < <(tmux list-clients -F '#{client_width}' 2>/dev/null || true)

# Keep direct/manual invocations useful when tmux has no client list yet.
[[ -n "$min_width" ]] || min_width=${1:-}
[[ "$min_width" =~ ^[0-9]+$ ]] || exit 0

state=0
(( min_width < threshold )) && state=1

current=$(tmux show-option -gqv @dotfiles-status-overflow 2>/dev/null || true)
if [[ "$current" != "$state" ]]; then
  tmux set-option -gq @dotfiles-status-overflow "$state"
  if (( state == 1 )); then
    tmux set-option -gq status-right ''
    tmux set-option -gq @dotfiles-status-details "$status_details"
    tmux set-option -g status-format[1] '#[align=right]#{E:@dotfiles-status-details}'
  else
    tmux set-option -g status-right "$status_details"
    tmux set-option -gu status-format[1]
  fi
  tmux refresh-client -S >/dev/null 2>&1 || true
fi
