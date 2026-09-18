#!/usr/bin/env bash
set -euo pipefail

directory=${1:-}
[[ -n "$directory" && -d "$directory" ]] || exit 0

git_dir=$(git -C "$directory" rev-parse --git-dir 2>/dev/null) || exit 0
[[ -n "$git_dir" ]] || exit 0

branch=$(git -C "$directory" symbolic-ref --short HEAD 2>/dev/null || true)
if [[ -z "$branch" ]]; then
  branch=$(git -C "$directory" rev-parse --short HEAD 2>/dev/null || true)
fi
[[ -n "$branch" ]] || exit 0

branch_limit=24
if (( ${#branch} > branch_limit )); then
  branch="${branch:0:23}…"
fi

git_status=$(git -C "$directory" status --porcelain=v1 --untracked-files=normal 2>/dev/null || true)

read -r staged unstaged untracked conflicts < <(
  printf '%s' "$git_status" |
    awk '
      /^\?\?/ { untracked++; next }
      {
        x = substr($0, 1, 1)
        y = substr($0, 2, 1)
        if (x == "U" || y == "U" || (x == "D" && y == "D") ||
            (x == "A" && y == "A")) { conflicts++; next }
        if (x != " ") staged++
        if (y != " ") unstaged++
      }
      END { print staged + 0, unstaged + 0, untracked + 0, conflicts + 0 }
    '
)

status_kinds=()
status_symbols=()
status_counts=()
if (( staged + unstaged + untracked + conflicts == 0 )); then
  :
else
  (( conflicts > 0 )) && {
    status_kinds+=(conflict)
    status_symbols+=('!')
    status_counts+=("$conflicts")
  }
  (( staged > 0 )) && {
    status_kinds+=(staged)
    status_symbols+=('+')
    status_counts+=("$staged")
  }
  (( unstaged > 0 )) && {
    status_kinds+=(modified)
    status_symbols+=('~')
    status_counts+=("$unstaged")
  }
  (( untracked > 0 )) && {
    status_kinds+=(untracked)
    status_symbols+=('?')
    status_counts+=("$untracked")
  }
fi

if git -C "$directory" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  divergence=$(git -C "$directory" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || printf '0 0')
  read -r ahead behind <<< "$divergence"
  (( ahead > 0 )) && {
    status_kinds+=(ahead)
    status_symbols+=('↑')
    status_counts+=("$ahead")
  }
  (( behind > 0 )) && {
    status_kinds+=(behind)
    status_symbols+=('↓')
    status_counts+=("$behind")
  }
fi

stash_count=$(git -C "$directory" stash list 2>/dev/null | wc -l | tr -d ' ')
(( stash_count > 0 )) && {
  status_kinds+=(stash)
  status_symbols+=('⚑')
  status_counts+=("$stash_count")
}

symbol_foreground() {
  case "$1" in
    conflict) printf 'colour203' ;;
    staged) printf 'colour114' ;;
    modified) printf 'colour220' ;;
    untracked) printf 'colour250' ;;
    ahead) printf 'colour81' ;;
    behind) printf 'colour213' ;;
    stash) printf 'colour177' ;;
  esac
}

printf '#[bg=colour24,bold] '
for (( index = ${#status_kinds[@]} - 1; index >= 0; index-- )); do
  kind=${status_kinds[index]}
  symbol_color=$(symbol_foreground "$kind")
  (( index < ${#status_kinds[@]} - 1 )) && printf ' '
  printf '#[fg=%s]%s#[fg=colour255]%s' \
    "$symbol_color" "${status_symbols[index]}" "${status_counts[index]}"
done
(( ${#status_kinds[@]} > 0 )) && printf ' '
printf '#[fg=colour255]%s #[default]\n' "$branch"
