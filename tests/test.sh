#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_home=$(mktemp -d /tmp/dotfiles-test.XXXXXX)
trap 'rm -rf "$test_home"' EXIT
export HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" XDG_DATA_HOME="$test_home/.local/share"
export DOTFILES_REPO_DIR="$repo_root" DOTFILES_SKIP_PACKAGES=true

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }

bash -n "$repo_root"/{bootstrap,install,update,uninstall} || fail "shell syntax"
help=$("$repo_root/install" --help)
grep -q 'Install both components' <<<"$help" || fail "help output"

"$repo_root/install" --dry-run
[[ ! -e "$XDG_CONFIG_HOME" ]] || fail "dry-run changed config"

"$repo_root/install" install tmux --yes
assert_file "$XDG_CONFIG_HOME/tmux/tmux.conf"
[[ ! -e "$XDG_CONFIG_HOME/nvim" ]] || fail "tmux install touched nvim"
"$repo_root/install" install tmux --yes

if command -v tmux >/dev/null 2>&1; then
  tmux -L dotfiles-test -f "$XDG_CONFIG_HOME/tmux/tmux.conf" new-session -d -s verify
  tmux -L dotfiles-test kill-server
fi

mkdir -p "$XDG_CONFIG_HOME/nvim/lua"
printf 'user config\n' > "$XDG_CONFIG_HOME/nvim/unrelated.lua"
printf 'old init\n' > "$XDG_CONFIG_HOME/nvim/init.lua"
"$repo_root/install" install nvim --yes
assert_file "$XDG_CONFIG_HOME/nvim/nvim-pack-lock.json"
assert_file "$XDG_CONFIG_HOME/nvim/.dotfiles-nvim-managed"
backup_init=$(find "$XDG_CONFIG_HOME" -path '*/nvim.backup.*/init.lua' -print -quit)
assert_file "$backup_init"
grep -q 'user config' "$XDG_CONFIG_HOME/nvim/unrelated.lua" || fail "unrelated config changed"

if command -v nvim >/dev/null 2>&1; then
  nvim --headless -u "$XDG_CONFIG_HOME/nvim/init.lua" -c 'qa!'
fi

"$repo_root/install" uninstall tmux --yes
[[ ! -e "$XDG_CONFIG_HOME/tmux/tmux.conf" ]] || fail "tmux uninstall failed"
assert_file "$XDG_CONFIG_HOME/nvim/init.lua"
"$repo_root/install" uninstall nvim --yes
[[ ! -e "$XDG_CONFIG_HOME/nvim/init.lua" ]] || fail "nvim uninstall failed"
assert_file "$XDG_CONFIG_HOME/nvim/unrelated.lua"

echo "dotfiles isolated tests passed"
