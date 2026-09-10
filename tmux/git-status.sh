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
overflow_index=-1
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
    (( ${#files[@]} >= 3 )) && break
  done <<< "$git_status"

  if (( ${#files[@]} == 3 )); then
    changed_count=$(printf '%s\n' "$git_status" | awk 'NF { count++ } END { print count + 0 }')
    if (( changed_count > 3 )); then
      # Attach the overflow marker to the last visible filename instead of
      # rendering a nameless marker between filenames.
      overflow_index=2
    fi
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

filename_color() {
  case "$1" in
    staged) printf '114' ;;    # green
    unstaged) printf '221' ;;  # yellow
    untracked) printf '244' ;; # dim gray
    conflict) printf '196' ;;  # red
    *) printf '255' ;;         # neutral / ellipsis
  esac
}

# Keep the branch/status group visually separate from the changed-file group.
# The file group uses a contrasting background, while each filename is split
# by a high-contrast vertical rule for quick scanning in the status line. The
# filename color shows Git state directly: staged, unstaged, untracked, or
# conflicted. The branch/status counters remain useful for the totals.
printf '#[fg=colour255,bg=colour24,bold] %s ' "$status"
if (( ${#files[@]} > 0 )); then
  printf '#[fg=colour255,bg=colour238]'
  for index in "${!files[@]}"; do
    filename=${files[index]}
    stem=$filename
    if [[ "$filename" == *.* && "$filename" != .* ]]; then
      stem=${filename%.*}
    elif [[ "$filename" == .*.* ]]; then
      stem=${filename%.*}
    fi

    show_extension=0
    for other_index in "${!files[@]}"; do
      [[ "$other_index" == "$index" ]] && continue
      other=${files[other_index]}
      other_stem=$other
      if [[ "$other" == *.* && "$other" != .* ]]; then
        other_stem=${other%.*}
      elif [[ "$other" == .*.* ]]; then
        other_stem=${other%.*}
      fi
      if [[ "$stem" == "$other_stem" ]]; then
        show_extension=1
        break
      fi
    done

    if [[ "$filename" == *.* ]] && (( show_extension == 0 )); then
      filename=${filename%.*}
    fi

    color=$(filename_color "${file_states[index]}")

    if (( index == 0 )); then
      printf ' '
    else
      printf ' #[fg=colour250,bg=colour238]│'
      printf '#[fg=colour%s,bg=colour238]' "$color"
      printf ' %s' "$filename"
      if (( index == overflow_index )); then
        printf '…'
      fi
      continue
    fi
    printf '#[fg=colour%s,bg=colour238]' "$color"
    printf '%s' "$filename"
    if (( index == overflow_index )); then
      printf '…'
    fi
  done
fi
printf '#[default]\n'
