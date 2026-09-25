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
    -bash|-zsh|-fish|-sh|-dash|-ksh) echo "${executable#-}" ;;
    bash|zsh|fish|sh|dash|ksh) echo "$executable" ;;
    *) echo "$executable" ;;
  esac
}

is_ignored_directory_token() {
  case "$1" in
    src|app|apps|lib|libs|bin|dist|build|target|coverage|vendor|packages|package|modules|services|components|pages|tests|test|testing|unit|integration|e2e|generated|output|cache|tmp|temp|workspace|work|projects|project|repos|repo|repositories|repository|node_modules|dev|development|test|staging|stage|prod|production|local|sandbox|debug|release|latest|current|api|web|frontend|backend|server|client|service|services|application|v[0-9]*|[0-9]*|[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
      return 0
      ;;
    *) return 1 ;;
  esac
}

shorten_directory_label() {
  local value="$1" limit="${DOTFILES_WINDOW_NAME_MAX:-24}"
  (( ${#value} <= limit )) && { printf '%s\n' "$value"; return; }

  local head=$(( (limit - 1) / 2 ))
  local tail=$(( limit - head - 1 ))
  printf '%s…%s\n' "${value:0:head}" "${value: -tail}"
}

directory_label() {
  local path="$1" component token candidate="" index token_index
  local -a components tokens

  [[ -n "$path" ]] || return 1
  while [[ "$path" == */ && "$path" != / ]]; do path=${path%/}; done
  [[ "$path" == "$HOME" ]] && { printf '~\n'; return; }
  [[ "$path" == / ]] && { printf '/\n'; return; }

  IFS='/' read -r -a components <<<"${path#/}"
  index=$((${#components[@]} - 1))
  while (( index >= 0 )); do
    component=${components[index]}
    if [[ -n "$component" ]]; then
      tokens=($(sed -E 's/([a-z0-9])([A-Z])|([A-Z])([A-Z][a-z])/\1\3 \2\4/g; s/[^[:alnum:]]+/ /g' <<<"$component"))
      token_index=$((${#tokens[@]} - 1))
      while (( token_index >= 0 )); do
        token=${tokens[token_index]}
        if [[ ${#token} -ge 2 ]] && ! is_ignored_directory_token "${token,,}"; then
          candidate="$token"
          break
        fi
        token_index=$((token_index - 1))
      done
    fi
    [[ -n "$candidate" ]] && break
    index=$((index - 1))
  done

  [[ -n "$candidate" ]] || candidate="${components[-1]}"
  shorten_directory_label "$candidate"
}

is_shell_label() {
  case "$1" in
    bash|zsh|fish|sh|dash|ksh) return 0 ;;
    *) return 1 ;;
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
  printf '__codex__%s\n' "$name"
}

clean_codex_title() {
  local title="$pane_title" pane_name
  title=$(sed -E 's/^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏][[:space:]]+//' <<<"$title")
  pane_name=${pane_path##*/}
  if [[ -n "$pane_name" && "$title" == *" | $pane_name" ]]; then
    title=${title%" | $pane_name"}
  fi
  # Codex uses this transient title while it updates the conversation name;
  # agent-status.sh already exposes the active loading state in the status bar.
  [[ "$title" == 'renaming...' ]] && return 0
  [[ -n "$title" ]] && printf '%s' "$title"
}

is_claude_command() {
  local command="$1" executable argument
  executable=${command%%[[:space:]]*}
  argument=${command#"$executable"}
  argument=${argument#"${argument%%[![:space:]]*}"}
  argument=${argument%%[[:space:]]*}
  [[ "${executable##*/}" == claude || "${argument##*/}" == claude || "$command" == *@anthropic-ai/claude-code* ]]
}

clean_claude_title() {
  local title
  # Claude prefixes its conversation title with an idle mark or a spinner frame.
  title=$(sed -E 's/^(✳|✶|✻|✽|✢|✺|\*|·|⠂|⠐|⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏)[[:space:]]+//' <<<"$pane_title")
  [[ -n "$title" && "$title" != 'Claude Code' ]] && printf '%s' "$title"
}

find_application() {
  local pid="$1" command child result cleaned_title
  command=$(process_command "$pid")

  if is_claude_command "$command"; then
    cleaned_title=$(clean_claude_title)
    printf '__agent__%s\n' "${cleaned_title:-Claude}"
    return 0
  fi

  case "$command" in
    *[Cc]odex*)
      cleaned_title=$(clean_codex_title)
      if [[ -n "$cleaned_title" ]]; then
        printf '__codex__%s\n' "$cleaned_title"
      else
        codex_session_label || echo '__codex__Codex'
      fi
      return 0
      ;;
    *nvim*|*neovim*)
      # Neovim publishes the active buffer basename through the terminal title.
      # Keep the icon-only fallback for dashboards, terminals, and unnamed buffers.
      title=$(sed -E 's/[[:space:]]+$//' <<<"$pane_title")
      if [[ "$title" == * ]]; then
        printf '__nvim__%s\n' "$title"
      else
        echo '__nvim__'
      fi
      return 0
      ;;
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
if [[ "$label" == __codex__* || "$label" == __agent__* ]]; then
  label=${label#__codex__}
  printf '%s\n' "${label#__agent__}" | sed -E 's/[[:space:]]+/ /g; s/[[:space:]]+$//'
elif [[ "$label" == __nvim__* ]]; then
  printf '%s\n' "${label#__nvim__}"
elif is_shell_label "$label" && [[ -n "$pane_path" ]]; then
  directory_label "$pane_path"
else
  printf '%s\n' "$label" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]]+/-/g'
fi
