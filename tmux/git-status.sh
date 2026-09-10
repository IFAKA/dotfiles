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

status="$branch"
if (( staged + unstaged + untracked + conflicts == 0 )); then
  status+=' ✓'
else
  (( conflicts > 0 )) && status+=" !${conflicts}"
  (( staged > 0 )) && status+=" +${staged}"
  (( unstaged > 0 )) && status+=" ~${unstaged}"
  (( untracked > 0 )) && status+=" ?${untracked}"

  filenames=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path=${line:3}
    if [[ "$path" == *' -> '* ]]; then
      path=${path##* -> }
    fi
    filename=${path##*/}
    [[ -n "$filename" ]] || continue
    filenames+=("$filename")
    (( ${#filenames[@]} >= 3 )) && break
  done <<< "$git_status"

  if (( ${#filenames[@]} > 0 )); then
    status+=' ·'
    for filename in "${filenames[@]}"; do
      status+=" $filename"
    done
    changed_count=$(printf '%s\n' "$git_status" | awk 'NF { count++ } END { print count + 0 }')
    (( ${#filenames[@]} == 3 && changed_count > 3 )) && status+=' …'
  fi
fi

if git -C "$directory" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  divergence=$(git -C "$directory" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || printf '0 0')
  read -r ahead behind <<< "$divergence"
  (( ahead > 0 )) && status+=" ↑${ahead}"
  (( behind > 0 )) && status+=" ↓${behind}"
fi

stash_count=$(git -C "$directory" stash list 2>/dev/null | wc -l | tr -d ' ')
(( stash_count > 0 )) && status+=" *${stash_count}"
printf '%s\n' "$status"
