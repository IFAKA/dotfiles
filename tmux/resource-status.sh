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
  # Keep the full command line so interpreter-backed processes such as
  # `node /path/to/codex` can be identified more precisely than just `node`.
  processes=$(LC_ALL=C ps -eo pid=,pcpu=,pmem=,command= 2>/dev/null) || exit 0
  [[ -n "$processes" ]] || exit 0

  usage=$(printf '%s\n' "$processes" | awk '
  function basename(path, parts, count) {
    count = split(path, parts, "/")
    return parts[count]
  }
  function process_label(command, executable, argument, i) {
    executable = basename($4)
    # The executable name is generic for runtimes; include the first script or
    # jar they are running when it is present.
    if (executable ~ /^(node|nodejs|bun|deno|python|python[0-9.]+|ruby|java)$/) {
      for (i = 5; i <= NF; i++) {
        if ($i !~ /^-/ && $i != "") {
          argument = basename($i)
          sub(/\.(cjs|js|mjs|py|rb|jar|ts)$/, "", argument)
          return executable ":" argument
        }
      }
    }
    return executable
  }
  $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+(\.[0-9]+)?$/ && $3 ~ /^[0-9]+(\.[0-9]+)?$/ && $4 != "" {
    command = process_label($0)
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
label_max=${TMUX_RESOURCE_STATUS_LABEL_MAX:-16}
[[ "$label_max" =~ ^[1-9][0-9]*$ ]] || label_max=16
shorten_label() {
  local label="$1"
  if (( ${#label} > label_max )); then
    printf '%s…' "${label:0:label_max-1}"
  else
    printf '%s' "$label"
  fi
}
cpu_command=$(shorten_label "$cpu_command")
memory_command=$(shorten_label "$memory_command")
severity_color() {
  local value="$1"
  if (( value >= 80 )); then
    printf 'colour196'
  elif (( value >= 50 )); then
    printf 'colour226'
  else
    printf '%s' "$2"
  fi
}
cpu_color=$(severity_color "$cpu" colour81)
memory_color=$(severity_color "$memory" colour213)
printf '#[fg=%s]CPU %s%% %s#[default] #[fg=%s]MEM %s%% %s#[default] ' \
  "$cpu_color" "$cpu" "$cpu_command" "$memory_color" "$memory" "$memory_command"
