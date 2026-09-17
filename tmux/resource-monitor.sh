#!/usr/bin/env bash
set -euo pipefail

if ! command -v btop >/dev/null 2>&1; then
  printf 'btop is not installed. Run: dotfiles install tmux --yes\n\n'
  printf 'Press q or Ctrl-C to close this popup.\n'
  read -r _ || true
  exit 0
fi

config_root=${XDG_CONFIG_HOME:-$HOME/.config}
exec btop --config "$config_root/btop/btop.conf"
