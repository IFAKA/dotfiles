#!/usr/bin/env bash
# Print a readable name for the application running in a tmux pane.
set -euo pipefail

pane_pid=${1:-}
pane_path=${2:-}
pane_title=${3:-}
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

codex_session_label() {
  local db path_sql name
  [[ -n "$pane_path" ]] || return 1
  command -v sqlite3 >/dev/null 2>&1 || return 1

  db="${CODEX_HOME:-$HOME/.codex}/state_5.sqlite"
  [[ -f "$db" ]] || return 1
  path_sql=${pane_path//\'/\'\'}
  name=$(sqlite3 -noheader -batch "$db" \
    "SELECT name FROM threads WHERE cwd = '$path_sql' AND archived = 0 AND name <> '' ORDER BY updated_at_ms DESC, updated_at DESC LIMIT 1;" \
    2>/dev/null) || return 1
  [[ -n "$name" ]] || return 1
  printf '✦ %s\n' "$name"
}

clean_codex_title() {
  local title="$pane_title" pane_name
  title=$(sed -E 's/^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏][[:space:]]+//' <<<"$title")
  pane_name=${pane_path##*/}
  if [[ -n "$pane_name" && "$title" == *" | $pane_name" ]]; then
    title=${title%" | $pane_name"}
  fi
  [[ -n "$title" ]] && printf '%s' "$title"
}

find_application() {
  local pid="$1" command child result cleaned_title
  command=$(process_command "$pid")

  case "$command" in
    *[Cc]odex*)
      cleaned_title=$(clean_codex_title)
      if [[ -n "$cleaned_title" ]]; then
        printf '✦ %s\n' "$cleaned_title"
      else
        codex_session_label || echo "✦ Codex"
      fi
      return 0
      ;;
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

label=$(find_application "$pane_pid")
if [[ "$label" == ✦* ]]; then
  printf '%s\n' "$label" | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//'
else
  printf '%s\n' "$label" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/-/g'
fi
