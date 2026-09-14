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
  (( conflicts > 0 )) && status+=" conflict ${conflicts}"
  (( staged > 0 )) && status+=" staged ${staged}"
  (( unstaged > 0 )) && status+=" modified ${unstaged}"
  (( untracked > 0 )) && status+=" untracked ${untracked}"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path=${line:3}
    if [[ "$path" == *' -> '* ]]; then
      path=${path##* -> }
    fi
    filename=${path##*/}
    [[ -n "$filename" ]] || continue
    files+=("$path")
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
  (( ahead > 0 )) && status+=" ahead ${ahead}"
  (( behind > 0 )) && status+=" behind ${behind}"
fi

stash_count=$(git -C "$directory" stash list 2>/dev/null | wc -l | tr -d ' ')
(( stash_count > 0 )) && status+=" stash ${stash_count}"

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

display_candidate_for() {
  local index=$1
  local path=${files[index]}
  local basename=${path##*/}
  local other_path other_basename parent candidate

  for other_path in "${files[@]}"; do
    other_basename=${other_path##*/}
    [[ "$other_basename" == "$basename" && "$other_path" != "$path" ]] || continue

    parent=${path%/*}
    while [[ -n "$parent" && "$parent" != "$path" ]]; do
      candidate="${parent##*/}/$basename"
      local collision=false
      local compare_path compare_parent compare_candidate
      for compare_path in "${files[@]}"; do
        [[ "$compare_path" == "$path" ]] && continue
        [[ "${compare_path##*/}" == "$basename" ]] || continue
        compare_parent=${compare_path%/*}
        compare_candidate="${compare_parent##*/}/$basename"
        [[ "$compare_candidate" == "$candidate" ]] && collision=true
      done
      [[ "$collision" == false ]] && { printf '%s' "$candidate"; return; }
      [[ "$parent" == */* ]] || break
      parent=${parent%/*}
    done
    break
  done

  printf '%s' "$basename"
}

hash_for_path() {
  local path=$1
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$path" | shasum -a 256 | cut -c1-12
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$path" | sha256sum | cut -c1-12
  else
    printf '%s' "$path" | cksum | cut -d' ' -f1
  fi
}

fragment_is_unique() {
  local index=$1
  local direction=$2
  local width=$3
  local candidate=${display_candidates[index]}
  local key other_index other key_length

  (( width > 1 )) || return 1
  key_length=$((width - 1))
  if [[ "$direction" == suffix ]]; then
    key=${candidate: -key_length}
  else
    key=${candidate:0:key_length}
  fi

  for (( other_index = 0; other_index < ${#display_candidates[@]}; other_index++ )); do
    (( other_index == index )) && continue
    other=${display_candidates[other_index]}
    if [[ "$direction" == suffix ]]; then
      [[ "${other: -key_length}" == "$key" ]] && return 1
    else
      [[ "${other:0:key_length}" == "$key" ]] && return 1
    fi
  done
  return 0
}

shorten_filename() {
  local index=$1
  local width=$2
  local candidate=${display_candidates[index]}
  local hash

  (( width > 0 )) || { printf ''; return; }
  (( ${#candidate} <= width )) && { printf '%s' "$candidate"; return; }

  if fragment_is_unique "$index" suffix "$width"; then
    printf '…%s' "${candidate: -$((width - 1))}"
  elif fragment_is_unique "$index" prefix "$width"; then
    printf '%s…' "${candidate:0:$((width - 1))}"
  else
    hash=$(hash_for_path "${files[index]}")
    if (( width == 1 )); then
      printf '%s' "${hash:0:1}"
    elif (( width <= ${#hash} + 1 )); then
      printf '…%s' "${hash:0:$((width - 1))}"
    else
      printf '…%s' "$hash"
    fi
  fi
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

  display_candidates=()
  for (( index = 0; index < ${#files[@]}; index++ )); do
    display_candidates+=( "$(display_candidate_for "$index")" )
  done

  visible_count=$((page_end - page_start))
  marker_count=0
  (( page > 0 )) && marker_count=$((marker_count + 1))
  (( page < page_count - 1 )) && marker_count=$((marker_count + 1))
  # Account for the leading/trailing spaces and the space after each divider.
  separator_width=$((3 * visible_count + 1))
  filename_budget=$((120 - ${#status} - separator_width - marker_count))
  (( filename_budget < 0 )) && filename_budget=0

  filename_widths=()
  remaining_width=$filename_budget
  remaining_entries=$visible_count
  for (( index = page_start; index < page_end; index++ )); do
    width=$((remaining_width / remaining_entries))
    candidate_length=${#display_candidates[index]}
    if (( candidate_length < width )); then
      width=$candidate_length
    fi
    filename_widths[index]=$width
    remaining_width=$((remaining_width - width))
    remaining_entries=$((remaining_entries - 1))
  done

  printf '#[fg=colour255,bg=colour238]'
  rendered=0
  for (( index = page_start; index < page_end; index++ )); do
    filename=$(shorten_filename "$index" "${filename_widths[index]}")
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
