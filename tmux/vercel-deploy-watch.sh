#!/usr/bin/env bash
set -u

script_dir=$(cd -P "$(dirname "$0")" && pwd)
source "$script_dir/vercel-deploy-common.sh"
root=${1:?}; project_id=${2:?}; cache_file=${3:?}; lock=${4:?}
cli=${TMUX_VERCEL_CLI:-vercel}
poll=${TMUX_VERCEL_STATUS_POLL_INTERVAL:-2}
timeout=${TMUX_VERCEL_STATUS_TIMEOUT:-300}
[[ "$poll" =~ ^[0-9]+([.][0-9]+)?$ ]] || poll=2
[[ "$timeout" =~ ^[0-9]+$ ]] || timeout=300
cleanup() { rmdir "$lock" 2>/dev/null || true; }
trap cleanup EXIT

query_state() {
  local response
  command -v "$cli" >/dev/null 2>&1 || return 1
  response=$("$cli" list --cwd "$root" --no-color 2>/dev/null) || return 1
  printf '%s' "$response" | python3 -c '
import json, re, sys
raw = sys.stdin.read()
states = {"READY":"ready", "BUILDING":"deploying", "QUEUED":"deploying", "INITIALIZING":"deploying", "ERROR":"failed", "CANCELED":"failed"}
try:
    decoder = json.JSONDecoder()
    start = next(i for i, c in enumerate(raw) if c in "[{ ")
    value, _ = decoder.raw_decode(raw[start:])
except (StopIteration, ValueError, TypeError):
    value = None
if value is not None:
    items = value.get("deployments", []) if isinstance(value, dict) else value
    if isinstance(items, dict): items = [items]
    for item in items if isinstance(items, list) else []:
        if isinstance(item, dict):
            state = states.get(str(item.get("state", item.get("status", ""))).upper())
            if state: print(state); break
else:
    for line in raw.splitlines():
        match = re.search(r"\b(Ready|Building|Queued|Initializing|Error|Canceled)\b", line, re.I)
        if match:
            print(states[match.group(1).upper()]); break
'
}

started=$(date +%s)
while :; do
  state=$(query_state || true)
  case "$state" in
    ready|failed)
      vercel_write_state "$cache_file" "$state"
      tmux refresh-client -S >/dev/null 2>&1 || true
      exit 0 ;;
    deploying)
      vercel_write_state "$cache_file" deploying
      tmux refresh-client -S >/dev/null 2>&1 || true ;;
  esac
  now=$(date +%s)
  if (( now - started >= timeout )); then
    vercel_write_state "$cache_file" unavailable
    tmux refresh-client -S >/dev/null 2>&1 || true
    exit 0
  fi
  sleep "$poll"
done
