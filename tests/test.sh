#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_home=$(mktemp -d /tmp/dotfiles-test.XXXXXX)
trap 'rm -rf "$test_home"' EXIT
export HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" XDG_DATA_HOME="$test_home/.local/share"
export DOTFILES_REPO_DIR="$repo_root" DOTFILES_SKIP_PACKAGES=true

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_output() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"; }
git_status_output() {
  "$repo_root/tmux/git-status.sh" "$1" | sed -E 's/#\[[^]]*\]//g; s/^ //; s/  +/ /g'
}

bash -n "$repo_root"/{bootstrap,install,update,uninstall} || fail "shell syntax"
bash -n "$repo_root/tmux/git-status.sh" || fail "git status script syntax"
bash -n "$repo_root/tmux/program-name.sh" || fail "program name script syntax"
bash -n "$repo_root/tmux/codex-status.sh" || fail "codex status script syntax"
help=$("$repo_root/install" --help)
grep -q 'tmux|nvim|mpv|course' <<<"$help" || fail "help output"

"$repo_root/install" --dry-run
[[ ! -e "$XDG_CONFIG_HOME" ]] || fail "dry-run changed config"
dry_run=$(PATH="$test_home/minimal-bin:/usr/bin:/bin" DOTFILES_SKIP_PACKAGES=false "$repo_root/install" install tmux --dry-run 2>&1)
grep -q 'lazygit' <<<"$dry_run" || fail "tmux dry-run does not provision lazygit"

"$repo_root/install" install tmux --yes

mkdir -p "$XDG_CONFIG_HOME/mpv"
printf 'audio-device=auto\n' > "$XDG_CONFIG_HOME/mpv/mpv.conf"
fake_mpv_bin=$(mktemp -d "$test_home/fake-mpv-bin.XXXXXX")
cat > "$fake_mpv_bin/mpv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${MPV_ARGS_FILE:?}"
printf '%s\n' "$PWD" > "${MPV_PWD_FILE:-/dev/null}"
EOF
chmod +x "$fake_mpv_bin/mpv"
"$repo_root/install" install mpv --yes
assert_file "$XDG_CONFIG_HOME/mpv/mpv.conf"
assert_file "$test_home/.local/bin/mpv"
grep -q '^audio-device=auto$' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "existing mpv config was not preserved"
grep -q '^save-position-on-quit=yes$' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "mpv resume option missing"
grep -q '^auto-window-resize=no$' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "mpv window resize option missing"
grep -q '^directory-mode=recursive$' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "mpv directory mode missing"
grep -q '^directory-filter-types=video$' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "mpv directory filter missing"
mkdir -p "$test_home/Courses/Old Course" "$test_home/Courses/New Course"
touch -t 202001010000 "$test_home/Courses/Old Course"
touch -t 202501010000 "$test_home/Courses/New Course"
"$repo_root/install" install course --yes
assert_file "$test_home/.local/bin/course"
rm -f "$test_home/mpv-args" "$test_home/mpv-pwd"
(PATH="$fake_mpv_bin:$PATH" COURSE_DIR="$test_home/Courses" MPV_ARGS_FILE="$test_home/mpv-args" MPV_PWD_FILE="$test_home/mpv-pwd" "$test_home/.local/bin/course")
grep -qxF "$test_home/Courses/New Course" "$test_home/mpv-pwd" || fail "course did not launch mpv in the latest course"
touch -t 202601010000 "$test_home/Courses/Old Course"
rm -f "$test_home/mpv-pwd"
(PATH="$fake_mpv_bin:$PATH" COURSE_DIR="$test_home/Courses" MPV_ARGS_FILE="$test_home/mpv-args" MPV_PWD_FILE="$test_home/mpv-pwd" "$test_home/.local/bin/course")
grep -qxF "$test_home/Courses/New Course" "$test_home/mpv-pwd" || fail "course did not reuse the last watched course"
mkdir -p "$test_home/videos"
(cd "$test_home/videos" && PATH="$test_home/.local/bin:$fake_mpv_bin:$PATH" MPV_ARGS_FILE="$test_home/mpv-args" mpv)
grep -qxF '.' "$test_home/mpv-args" || fail "mpv wrapper did not open the current directory"
PATH="$test_home/.local/bin:$fake_mpv_bin:$PATH" MPV_ARGS_FILE="$test_home/mpv-args" mpv --version
grep -qxF -- '--version' "$test_home/mpv-args" || fail "mpv wrapper did not forward arguments"
"$repo_root/install" install mpv --yes
grep -q '^directory-mode=recursive$' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "mpv config was not idempotent"
assert_file "$XDG_CONFIG_HOME/tmux/tmux.conf"
assert_file "$XDG_CONFIG_HOME/tmux/git-status.sh"
assert_file "$XDG_CONFIG_HOME/tmux/program-name.sh"
assert_file "$XDG_CONFIG_HOME/tmux/codex-status.sh"
[[ ! -e "$XDG_CONFIG_HOME/nvim" ]] || fail "tmux install touched nvim"
grep -q '^bind g display-popup -E -w 95% -h 95% -d "#{pane_current_path}" lazygit$' "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "lazygit popup binding missing"
"$repo_root/install" install tmux --yes

git_repo=$(mktemp -d "$test_home/git-repo.XXXXXX")
git -C "$git_repo" init -q
git -C "$git_repo" branch -M main
git -C "$git_repo" config user.email test@example.com
git -C "$git_repo" config user.name test
printf 'tracked\n' > "$git_repo/tracked.txt"
git -C "$git_repo" add tracked.txt
git -C "$git_repo" commit -qm initial
assert_output "$(git_status_output "$git_repo")" 'main '
printf 'changed\n' >> "$git_repo/tracked.txt"
assert_output "$(git_status_output "$git_repo")" 'main │ modified 1 '
printf 'staged\n' > "$git_repo/staged.txt"
git -C "$git_repo" add staged.txt
printf 'untracked\n' > "$git_repo/untracked.txt"
mkdir -p "$git_repo/nested"
printf 'nested\n' > "$git_repo/nested/inner.txt"
printf 'fourth\n' > "$git_repo/fourth.txt"
assert_output "$(git_status_output "$git_repo")" 'main │ staged 1 │ modified 1 │ untracked 3 '
git_status_raw=$(TMUX_GIT_STATUS_TIMESTAMP=0 "$repo_root/tmux/git-status.sh" "$git_repo")
[[ "$git_status_raw" != *'tracked.txt'* ]] || fail "changed filenames are still rendered"
grep -q 'fg=colour255,bg=colour22.*staged 1' <<<"$git_status_raw" || fail "staged status color missing"
grep -q 'bg=colour136.*modified 1' <<<"$git_status_raw" || fail "modified status color missing"
grep -q 'fg=colour255,bg=colour238.*untracked 3' <<<"$git_status_raw" || fail "untracked status color missing"

conflict_repo=$(mktemp -d "$test_home/conflict-repo.XXXXXX")
git -C "$conflict_repo" init -q
git -C "$conflict_repo" branch -M main
git -C "$conflict_repo" config user.email test@example.com
git -C "$conflict_repo" config user.name test
printf '%s' base > "$conflict_repo/conflict.txt"
git -C "$conflict_repo" add conflict.txt
git -C "$conflict_repo" commit -qm initial
git -C "$conflict_repo" checkout -qb side
printf '%s' side > "$conflict_repo/conflict.txt"
git -C "$conflict_repo" commit -qam side
git -C "$conflict_repo" checkout -q main
printf '%s' main > "$conflict_repo/conflict.txt"
git -C "$conflict_repo" commit -qam main
git -C "$conflict_repo" merge side >/dev/null 2>&1 || true
conflict_status_raw=$("$repo_root/tmux/git-status.sh" "$conflict_repo")
grep -q 'fg=colour255,bg=colour124,bold] conflict 1' <<<"$conflict_status_raw" || fail "conflict status color missing"

git -C "$git_repo" stash push -uqm changed
assert_output "$(git_status_output "$git_repo")" 'main │ stash 1 '
git -C "$git_repo" checkout --detach -q
assert_output "$(git_status_output "$git_repo")" "$(git -C "$git_repo" rev-parse --short HEAD) │ stash 1 "
assert_output "$(git_status_output "$test_home")" ''

fake_bin=$(mktemp -d "$test_home/fake-bin.XXXXXX")
cat > "$fake_bin/ps" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == '-o' && "$2" == 'command=' ]]; then
  case "$4" in
    123) echo 'nvim --embed' ;;
    124) echo '/usr/bin/neovim --embed' ;;
    125) echo 'vim' ;;
    *) echo 'node /fake/path/codex' ;;
  esac
fi
EOF
chmod +x "$fake_bin/ps"
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 123)" ''
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 124)" ''
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 125)" 'vim'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 456 "$git_repo" 'Second conversation')" '✦ Second conversation'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 789 "$git_repo" "⠼ First conversation | ${git_repo##*/}")" '✦ First conversation'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 999 "$git_repo")" '✦ Codex'
grep -q '"#{pane_current_path}" #{q:pane_title})' "$repo_root/tmux/tmux.conf" || fail "pane title shell quoting changed"
grep -q '^bind c new-window -a -c "#{pane_current_path}"$' "$repo_root/tmux/tmux.conf" || fail "new-window binding does not insert after the active window"

if command -v tmux >/dev/null 2>&1; then
  tmux -L dotfiles-test -f "$XDG_CONFIG_HOME/tmux/tmux.conf" new-session -d -s verify
  tmux -L dotfiles-test new-window -t verify -n second
  tmux -L dotfiles-test select-window -t verify:1
  tmux -L dotfiles-test new-window -a -t verify:1 -n inserted
  windows=$(tmux -L dotfiles-test list-windows -F '#{window_index}:#{window_name}')
  [[ "$(sed -n '2p' <<<"$windows")" == '2:inserted' && "$(sed -n '3p' <<<"$windows")" == '3:second' ]] || fail "new window was not inserted after the active window"
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
[[ ! -e "$XDG_CONFIG_HOME/tmux/tmux.conf" && ! -e "$XDG_CONFIG_HOME/tmux/git-status.sh" && ! -e "$XDG_CONFIG_HOME/tmux/program-name.sh" && ! -e "$XDG_CONFIG_HOME/tmux/codex-status.sh" ]] || fail "tmux uninstall failed"
assert_file "$XDG_CONFIG_HOME/nvim/init.lua"
"$repo_root/install" uninstall nvim --yes
[[ ! -e "$XDG_CONFIG_HOME/nvim/init.lua" ]] || fail "nvim uninstall failed"
assert_file "$XDG_CONFIG_HOME/nvim/unrelated.lua"

echo "dotfiles isolated tests passed"
