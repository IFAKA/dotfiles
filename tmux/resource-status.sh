#!/usr/bin/env bash
set -euo pipefail

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

IFS=$'\t' read -r cpu cpu_command memory memory_command <<< "$usage"
printf '#[fg=colour81]CPU %s%% %s#[default] #[fg=colour213]MEM %s%% %s#[default] ' \
  "$cpu" "$cpu_command" "$memory" "$memory_command"
