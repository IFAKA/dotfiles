#!/usr/bin/env bash
set -euo pipefail

plugin_root="${TMUX_PLUGIN_MANAGER_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins}"
plugin_dir="${plugin_root%/}/tmux-easy-motion"
semantic_action="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/smart-actions.py"
mode="${1:-action}"

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

apply_span() {
  local span_json="$1" state_level="$2"
  read -r start_row start_col end_row end_col selected_level selected_kind <<<"$(python3 -c 'import json,sys; s=json.load(sys.stdin); print(s["start_row"], s["start_column"], s["end_row"], s["end_column"], s["expansion_level"], s["kind"])' <<<"$span_json")"
  tmux send-keys -X clear-selection
  tmux send-keys -X goto-line "$((start_row + 1))"
  tmux send-keys -X start-of-line
  for ((i=0; i<start_col; i++)); do tmux send-keys -X cursor-right; done
  tmux send-keys -X start-selection
  tmux send-keys -X goto-line "$((end_row + 1))"
  tmux send-keys -X start-of-line
  for ((i=0; i<end_col; i++)); do tmux send-keys -X cursor-right; done
  tmux set-option -p -t "$pane_id" @smart-select-level "$state_level"
  tmux set-option -p -t "$pane_id" @smart-select-active 1
  tmux set-option -p -t "$pane_id" @smart-select-anchor "$start_row:$start_col"
  tmux display-message "Smart Select: $selected_kind" >/dev/null 2>&1 || true
}

select_semantic_span() {
  local cursor="$1"
  local level anchor span_json selected_level
  level=$(tmux show-options -pqv -t "$pane_id" @smart-select-level 2>/dev/null || true)
  level=${level:-0}
  span_json=$(python3 "$semantic_action" --input-file "$capture_file" \
    --semantic-select "$cursor" --expansion-level "$level")
  anchor=$(tmux show-options -pqv -t "$pane_id" @smart-select-anchor 2>/dev/null || true)
  if [[ -n "$anchor" ]]; then
    span_json=$(python3 "$semantic_action" --input-file "$capture_file" \
      --semantic-select "$anchor" --expansion-level "$level")
  fi
  if [[ -n "$span_json" ]]; then
    read -r selected_level <<<"$(python3 -c 'import json,sys; print(json.load(sys.stdin)["expansion_level"])' <<<"$span_json")"
    apply_span "$span_json" "$((selected_level + 1))"
  fi
}

if [[ "$mode" == move-up || "$mode" == move-down ]]; then
  active=$(tmux show-options -pqv -t "$pane_id" @smart-select-active 2>/dev/null || true)
  if [[ "$active" == 1 ]]; then
    level=$(tmux show-options -pqv -t "$pane_id" @smart-select-level 2>/dev/null || true)
    level=${level:-1}
    cursor=$(tmux display-message -p -t "$pane_id" '#{copy_cursor_y}:#{copy_cursor_x}')
    anchor=$(tmux show-options -pqv -t "$pane_id" @smart-select-anchor 2>/dev/null || true)
    anchor=${anchor:-$cursor}
    direction=1
    [[ "$mode" == move-up ]] && direction=-1
    span_json=$(python3 "$semantic_action" --input-file "$capture_file" \
      --semantic-sibling "$anchor" --direction "$direction" --expansion-level "$((level - 1))")
    if [[ -n "$span_json" ]]; then
      apply_span "$span_json" "$level"
    fi
    exit 0
  fi
  [[ "$mode" == move-up ]] && tmux send-keys -X cursor-up || tmux send-keys -X cursor-down
  exit 0
fi

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

if [[ -n "$raw_label" ]]; then
  cursor=$(tmux display-message -p -t "$pane_id" '#{copy_cursor_y}:#{copy_cursor_x}')
  if [[ "$mode" == "smart" && ! "${raw_label: -1}" =~ [A-Z] ]]; then
    select_semantic_span "$cursor"
  elif [[ "${raw_label: -1}" =~ [A-Z] ]]; then
    action_target=$(python3 "$semantic_action" --input-file "$capture_file" \
      --smart-action-target "$cursor")
    if [[ -n "$action_target" ]]; then
      python3 "$semantic_action" --input-file "$capture_file" \
        --smart-action "$cursor" --pane-id "$pane_id" || true
    elif [[ "$mode" == "smart" ]]; then
      select_semantic_span "$cursor"
    fi
  fi
fi
