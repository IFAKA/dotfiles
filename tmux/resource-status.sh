#!/usr/bin/env bash
set -euo pipefail

sample_interval=${TMUX_RESOURCE_STATUS_INTERVAL:-5}
[[ "$sample_interval" =~ ^[1-9][0-9]*$ ]] || sample_interval=5

# tmux redraws every second so Codex state can animate, but resource usage is
# deliberately sampled less often. This keeps the numbers readable without
# making them look frozen. Outside tmux (including tests), always sample.
cache_dir=${TMUX_RESOURCE_STATUS_CACHE_DIR:-${TMUX_TMPDIR:-/tmp}/dotfiles-resource-status-${UID}}
cache_file="$cache_dir/sample"
usage=''
if [[ -n "${TMUX:-}" ]]; then
  now=$(date +%s)
  if [[ -f "$cache_file" ]]; then
    read -r cached_at cached_usage < "$cache_file" || true
    if [[ "$cached_at" =~ ^[0-9]+$ ]] && (( now - cached_at < sample_interval )) && [[ -n "${cached_usage:-}" ]]; then
      usage=$cached_usage
    fi
  fi
fi

if [[ -z "$usage" ]]; then
  processes=$(LC_ALL=C ps -eo pid=,pcpu=,pmem=,comm= 2>/dev/null) || exit 0
  [[ -n "$processes" ]] || exit 0

  usage=$(printf '%s\n' "$processes" | awk '
  $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+(\.[0-9]+)?$/ && $3 ~ /^[0-9]+(\.[0-9]+)?$/ && $4 != "" {
    command = $4
    sub(".*/", "", command)
    if (cpu_command == "" || ($2 + 0) > cpu) {
      cpu = $2 + 0
      cpu_command = command
    }
    if (memory_command == "" || ($3 + 0) > memory) {
      memory = $3 + 0
      memory_command = command
    }
  }
  END {
    if (cpu_command == "" || memory_command == "") exit 1
    printf "%.0f\t%s\t%.0f\t%s\n", cpu, cpu_command, memory, memory_command
  }
') || exit 0

  if [[ -n "${TMUX:-}" ]]; then
    mkdir -p "$cache_dir"
    temporary=$(mktemp "$cache_dir/.sample.XXXXXX")
    printf '%s %s\n' "$(date +%s)" "$usage" > "$temporary"
    mv -f "$temporary" "$cache_file"
  fi
fi

IFS=$'\t' read -r cpu cpu_command memory memory_command <<< "$usage"
printf '#[fg=colour81]CPU %s%% %s#[default] #[fg=colour213]MEM %s%% %s#[default] ' \
  "$cpu" "$cpu_command" "$memory" "$memory_command"
