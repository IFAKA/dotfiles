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

if [[ -n "$(git -C "$directory" status --porcelain=v1 --untracked-files=normal 2>/dev/null)" ]]; then
  state='±'
else
  state='✓'
fi

stash_count=$(git -C "$directory" stash list 2>/dev/null | wc -l | tr -d ' ')
status="$branch $state"
[[ "$stash_count" -gt 0 ]] && status+=" stash:$stash_count"
printf '%s\n' "$status"
