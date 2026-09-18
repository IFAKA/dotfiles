#!/usr/bin/env bash
set -u

directory=${1:-}
[[ -n "$directory" && -d "$directory" ]] || exit 0

find_root() {
  local current=$1
  while [[ "$current" != "/" ]]; do
    [[ -f "$current/.vercel/project.json" ]] && {
      printf '%s\n' "$current"
      return 0
    }
    current=${current%/*}
    [[ -n "$current" ]] || current=/
  done
  [[ -f /\.vercel/project.json ]] && printf '%s\n' /
}

json_value() {
  local key=$1 file=$2
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "$file" | head -n 1
}

render() {
  case "$1" in
    ready) printf '#[fg=colour255,bg=#166534,bold] ▲ #[default]\n' ;;
    deploying)
      local frames=(▲ ▶ ▼ ◀)
      printf '#[fg=colour232,bg=#a16207,bold] %s #[default]\n' "${frames[$(( $(date +%s) % 4 ))]}"
      ;;
    failed) printf '#[fg=colour255,bg=#991b1b,bold] ▲ #[default]\n' ;;
    unavailable) printf '#[fg=colour255,bg=colour238,bold] ▲ #[default]\n' ;;
  esac
}

root=$(find_root "$directory") || exit 0
project_file="$root/.vercel/project.json"
project_id=$(json_value projectId "$project_file")
[[ -n "$project_id" ]] || exit 0

cache_dir=${TMUX_VERCEL_STATUS_CACHE_DIR:-${TMUX_TMPDIR:-/tmp}/dotfiles-vercel-status-${UID}}
ttl=${TMUX_VERCEL_STATUS_TTL:-30}
[[ "$ttl" =~ ^[0-9]+$ ]] || ttl=30
mkdir -p "$cache_dir" 2>/dev/null || exit 0
cache_key=$(printf '%s\t%s' "$root" "$project_id" | cksum | awk '{print $1}')
cache_file="$cache_dir/$cache_key"
lock="$cache_file.lock"

cache_is_fresh() {
  local modified now
  [[ -r "$cache_file" ]] || return 1
  if stat -f %m "$cache_file" >/dev/null 2>&1; then
    modified=$(stat -f %m "$cache_file" 2>/dev/null) || return 1
  else
    modified=$(stat -c %Y "$cache_file" 2>/dev/null) || return 1
  fi
  now=$(date +%s)
  (( now - modified < ttl )) || return 1
  case "$(cat "$cache_file" 2>/dev/null)" in
    ready|deploying|failed|unavailable) return 0 ;;
  esac
  return 1
}

refresh() {
  local result=unavailable response state temporary cli
  cli=${TMUX_VERCEL_CLI:-vercel}
  if command -v "$cli" >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    # Vercel CLI 48.x has no `api` subcommand despite newer documentation
    # listing it. `list` is the stable, authenticated CLI interface and its
    # first row is the newest deployment. Keep the JSON parser as a compatible
    # fallback for newer/mock CLIs that return structured output.
    response=$("$cli" list --cwd "$root" --no-color 2>&1) || response=''
    if [[ -n "$response" ]]; then
      state=$(printf '%s' "$response" | python3 -c '
import json, re, sys
raw = sys.stdin.read()
state_names = {"READY": "ready", "BUILDING": "deploying", "QUEUED": "deploying", "INITIALIZING": "deploying", "ERROR": "failed", "CANCELED": "failed"}
try:
    decoder = json.JSONDecoder()
    start = next(i for i, char in enumerate(raw) if char in "[{ ")
    value, _ = decoder.raw_decode(raw[start:])
except (StopIteration, ValueError, TypeError):
    value = None
if value is not None:
    items = value.get("deployments", []) if isinstance(value, dict) else value
    if isinstance(items, dict):
        items = [items]
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, dict):
            continue
        result = state_names.get(str(item.get("state", item.get("status", ""))).upper())
        if result:
            print(result)
            break
else:
    in_rows = False
    for line in raw.splitlines():
        if line.startswith("Age "):
            in_rows = True
            continue
        if not in_rows:
            continue
        match = re.search(r"\b(Ready|Building|Queued|Initializing|Error|Canceled)\b", line, re.IGNORECASE)
        if match:
            print(state_names[match.group(1).upper()])
            break
')
      [[ "$state" == ready || "$state" == deploying || "$state" == failed ]] && result=$state
    fi
  fi
  temporary=$(mktemp "$cache_dir/.vercel.XXXXXX") || return 0
  printf '%s\n' "$result" > "$temporary" && mv -f "$temporary" "$cache_file"
  tmux refresh-client -S >/dev/null 2>&1 || true
}

schedule_refresh() {
  mkdir "$lock" 2>/dev/null || return 0
  (trap 'rmdir "$lock" 2>/dev/null || true' EXIT; refresh) </dev/null >/dev/null 2>&1 &
}

if cache_is_fresh; then
  render "$(cat "$cache_file")"
  exit 0
fi

if [[ -r "$cache_file" ]]; then
  case "$(cat "$cache_file" 2>/dev/null)" in
    ready|deploying|failed|unavailable) render "$(cat "$cache_file")" ;;
  esac
fi
schedule_refresh
