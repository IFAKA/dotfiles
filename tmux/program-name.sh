#!/usr/bin/env bash
# Print a readable name for the application running in a tmux pane.
set -euo pipefail

pane_pid=${1:-}
[[ "$pane_pid" =~ ^[0-9]+$ ]] || exit 0

process_command() {
  ps -o command= -p "$1" 2>/dev/null | sed 's/^ *//'
}

label_for_command() {
  local command="$1" executable
  executable=${command%%[[:space:]]*}
  executable=${executable##*/}
  case "$executable" in
    bash|zsh|fish|sh|dash|ksh) echo "$executable" ;;
    *) echo "$executable" ;;
  esac
}

find_application() {
  local pid="$1" command child result
  command=$(process_command "$pid")

  case "$command" in
    *[Cc]odex*) echo "Codex"; return 0 ;;
    *nvim*|*neovim*) echo "nvim"; return 0 ;;
    *vim*) echo "vim"; return 0 ;;
    *lazygit*) echo "lazygit"; return 0 ;;
    *python*|*pyright*) echo "python"; return 0 ;;
    *ruby*) echo "ruby"; return 0 ;;
    *perl*) echo "perl"; return 0 ;;
    *ssh*) echo "ssh"; return 0 ;;
    *git*) echo "git"; return 0 ;;
    *docker*) echo "docker"; return 0 ;;
  esac

  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    result=$(find_application "$child")
    [[ -n "$result" ]] && { echo "$result"; return 0; }
  done

  [[ -n "$command" ]] && label_for_command "$command"
}

find_application "$pane_pid"
