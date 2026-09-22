# Keep tmux's shell window name in sync with directory changes. tmux's
# automatic-rename mechanism does not reliably refresh on `cd` alone, so the
# shell asks the same directory-only resolver to update the current window.
autoload -Uz add-zsh-hook

dotfiles-refresh-tmux-window-name() {
  [[ -n "$TMUX" && -n "$TMUX_PANE" ]] || return 0
  command -v tmux >/dev/null 2>&1 || return 0

  local helper="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/program-name.sh"
  [[ -x "$helper" ]] || return 0

  local title name
  title="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_title}' 2>/dev/null)"
  name="$($helper "$$" "$PWD" "$title" 2>/dev/null)"
  [[ -n "$name" ]] || return 0
  tmux rename-window -t "$TMUX_PANE" "$name" 2>/dev/null
}

add-zsh-hook chpwd dotfiles-refresh-tmux-window-name

# The worker decides whether this is an SFCC ODS project.  Keeping this hook
# asynchronous means `cd` remains instant and browser authentication is never
# initiated from a shell hook.
dotfiles-refresh-dw-sandbox() {
  local helper="$HOME/.local/bin/dw-sandbox"
  [[ -x "$helper" ]] || return 0
  "$helper" --path "$PWD" --background </dev/null >/dev/null 2>&1 &!
}

add-zsh-hook chpwd dotfiles-refresh-dw-sandbox

# Context-aware backward deletion shared with the Codex PTY wrapper.
dotfiles-backward-kill-path-component() {
  local prefix="${BUFFER[1,CURSOR]}" suffix="${BUFFER[CURSOR+1,-1]}"
  local length=${#prefix} i char escaped=false quote='' token_start=1

  for ((i = 1; i <= length; i++)); do
    char="${prefix[i]}"
    if [[ "$escaped" == true ]]; then escaped=false; continue; fi
    if [[ "$char" == \\ && "$quote" != "'" ]]; then escaped=true; continue; fi
    if [[ -n "$quote" ]]; then
      [[ "$char" == "$quote" ]] && quote=''
    elif [[ "$char" == \" || "$char" == "'" ]]; then
      quote="$char"
    elif [[ "$char" == $' ' || "$char" == $'\t' || "$char" == $'\n' ]]; then
      token_start=$((i + 1))
    fi
  done

  if (( length == 0 )) || [[ "${prefix[-1]}" == $' ' || "${prefix[-1]}" == $'\t' || "${prefix[-1]}" == $'\n' ]]; then
    zle backward-kill-word
    return
  fi

  local token="${prefix[token_start,-1]}" separator_chars='/.:@?&=#{}[],"'

  if [[ "$token" =~ '^-[[:alpha:]]{2,}$' ]]; then
    prefix="${prefix%?}"
    BUFFER="${prefix}${suffix}"; CURSOR=${#prefix}; return
  fi

  local separator_position=-1 previous_separator=-1
  for ((i = ${#token}; i >= 1; i--)); do
    if [[ "$separator_chars" == *"${token[i]}"* ]]; then
      separator_position=$i
      break
    fi
  done
  if (( separator_position >= 1 )); then
    if (( separator_position == ${#token} )); then
      for ((i = separator_position - 1; i >= 1; i--)); do
        if [[ "$separator_chars" == *"${token[i]}"* ]]; then
          previous_separator=$i
          break
        fi
      done
      if (( previous_separator >= 1 )); then
        prefix="${prefix[1,token_start + previous_separator - 1]}"
      else
        prefix="${prefix[1,token_start - 1]}"
      fi
    else
      prefix="${prefix[1,token_start + separator_position - 1]}"
    fi
    BUFFER="${prefix}${suffix}"; CURSOR=${#prefix}; return
  fi

  zle backward-kill-word
}

zle -N dotfiles-backward-kill-path-component
bindkey -M emacs '^W' dotfiles-backward-kill-path-component
bindkey -M emacs -r '^[w'
