# Delete the path component immediately before the cursor.
dotfiles-backward-kill-path-component() {
  local prefix="${BUFFER[1,CURSOR]}"
  local suffix="${BUFFER[CURSOR+1,-1]}"

  if [[ "$prefix" == */ ]]; then
    prefix="${prefix%/}"
  fi

  if [[ "$prefix" == */* ]]; then
    prefix="${prefix%/*}/"
  elif [[ "$prefix" == *' '* ]]; then
    prefix="${prefix% *} "
  else
    prefix=""
  fi

  BUFFER="${prefix}${suffix}"
  CURSOR=${#prefix}
}

zle -N dotfiles-backward-kill-path-component
bindkey '^[w' dotfiles-backward-kill-path-component
