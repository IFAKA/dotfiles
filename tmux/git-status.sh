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
files=()
file_states=()
if (( staged + unstaged + untracked + conflicts == 0 )); then
  :
else
  (( conflicts > 0 )) && status+=" !${conflicts}"
  (( staged > 0 )) && status+=" +${staged}"
  (( unstaged > 0 )) && status+=" ~${unstaged}"
  (( untracked > 0 )) && status+=" ?${untracked}"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path=${line:3}
    if [[ "$path" == *' -> '* ]]; then
      path=${path##* -> }
    fi
    filename=${path##*/}
    [[ -n "$filename" ]] || continue
    files+=("$filename")
    if [[ ${line:0:2} == '??' ]]; then
      file_states+=(untracked)
    elif [[ ${line:0:1} == 'U' || ${line:1:1} == 'U' ||
            ${line:0:2} == 'DD' || ${line:0:2} == 'AA' ]]; then
      file_states+=(conflict)
    elif [[ ${line:0:1} != ' ' ]]; then
      file_states+=(staged)
    else
      file_states+=(unstaged)
    fi
  done <<< "$git_status"
fi

if git -C "$directory" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  divergence=$(git -C "$directory" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null || printf '0 0')
  read -r ahead behind <<< "$divergence"
  (( ahead > 0 )) && status+=" ↑${ahead}"
  (( behind > 0 )) && status+=" ↓${behind}"
fi

stash_count=$(git -C "$directory" stash list 2>/dev/null | wc -l | tr -d ' ')
(( stash_count > 0 )) && status+=" *${stash_count}"

filename_color() {
  case "$1" in
    staged) printf '114' ;;    # green
    unstaged) printf '221' ;;  # yellow
    untracked) printf '244' ;; # dim gray
    conflict) printf '255' ;;  # white on the conflict background
    *) printf '255' ;;         # neutral / ellipsis
  esac
}

filename_background() {
  [[ "$1" == conflict ]] && printf 'colour124' || printf 'colour238'
}

filename_attributes() {
  [[ "$1" == conflict ]] && printf ',bold' || true
}

# Keep the changed-file group first, followed by the branch/status group.
# The file group uses a contrasting background, while each filename is split
# by a high-contrast vertical rule for quick scanning in the status line. The
# filename color shows Git state directly: staged, unstaged, untracked, or
# conflicted. The branch/status counters remain useful for the totals.
if (( ${#files[@]} > 0 )); then
  timestamp=${TMUX_GIT_STATUS_TIMESTAMP:-$(date +%s)}
  [[ "$timestamp" =~ ^[0-9]+$ ]] || timestamp=$(date +%s)
  page_size=3
  page_count=$(( (${#files[@]} + page_size - 1) / page_size ))
  page=$(( (timestamp / 3) % page_count ))
  page_start=$(( page * page_size ))
  page_end=$(( page_start + page_size ))
  (( page_end > ${#files[@]} )) && page_end=${#files[@]}

  display_files=()
  for filename in "${files[@]}"; do
    display_files+=( "$filename" )
  done

  printf '#[fg=colour255,bg=colour238]'
  rendered=0
  for (( index = page_start; index < page_end; index++ )); do
    filename=${display_files[index]}
    if (( rendered == 0 && page > 0 )); then
      filename="…$filename"
    fi
    if (( index == page_end - 1 && page < page_count - 1 )); then
      filename="${filename}…"
    fi
    state=${file_states[index]}
    color=$(filename_color "$state")
    background=$(filename_background "$state")
    attributes=$(filename_attributes "$state")

    if (( rendered == 0 )); then
      printf ' '
    else
      printf ' #[fg=colour250,bg=colour238]│'
      printf '#[fg=colour%s,bg=%s%s]' "$color" "$background" "$attributes"
      printf ' %s' "$filename"
    fi
    if (( rendered == 0 )); then
      printf '#[fg=colour%s,bg=%s%s]' "$color" "$background" "$attributes"
      printf '%s' "$filename"
    fi
    rendered=$((rendered + 1))
  done
  printf ' #[fg=colour250,bg=colour238]│#[fg=colour255,bg=colour24,bold] %s' "$status"
else
  printf '#[fg=colour255,bg=colour24,bold] %s ' "$status"
fi
printf '#[default]\n'
