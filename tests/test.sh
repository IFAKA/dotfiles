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
python3 - "$repo_root/bin/course" "$repo_root/bin/course-play" <<'PY' || fail "course Python syntax"
import pathlib
import sys
for filename in sys.argv[1:]:
    compile(pathlib.Path(filename).read_text(), filename, "exec")
PY
python3 "$repo_root/tests/course_test.py" || fail "course state tests"
help=$("$repo_root/install" --help)
grep -q 'Install both components' <<<"$help" || fail "help output"

"$repo_root/install" --dry-run
[[ ! -e "$XDG_CONFIG_HOME" ]] || fail "dry-run changed config"

"$repo_root/install" install tmux --yes

fake_mpv_bin=$(mktemp -d "$test_home/fake-mpv-bin.XXXXXX")
cat > "$fake_mpv_bin/mpv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${MPV_ARGS_FILE:?}"
for arg in "$@"; do
  case "$arg" in --playlist=*) [[ -z "${MPV_PLAYLIST_FILE:-}" ]] || cp "${arg#--playlist=}" "$MPV_PLAYLIST_FILE" ;; esac
done
EOF
chmod +x "$fake_mpv_bin/mpv"
course_path="$test_home/Documents/Courses/AI Engineering Buildcamp"
override_path="$test_home/Other Courses/Override Course"
mkdir -p "$course_path"
mkdir -p "$override_path"
touch "$course_path/001 Intro.mp4" "$override_path/001 Override.mp4"
course_path=$(cd "$course_path" && pwd -P)
course_root=$(cd "$(dirname "$course_path")" && pwd -P)
override_path=$(cd "$override_path" && pwd -P)
override_root=$(cd "$(dirname "$override_path")" && pwd -P)
mkdir -p "$XDG_CONFIG_HOME/mpv"
printf 'audio-device=auto\n' > "$XDG_CONFIG_HOME/mpv/mpv.conf"
"$repo_root/install" install course --yes
assert_file "$XDG_CONFIG_HOME/mpv/mpv.conf"
assert_file "$test_home/.local/bin/course"
assert_file "$test_home/.local/bin/course-play"
grep -q '^audio-device=auto$' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "existing mpv config was not preserved"
grep -q '^save-position-on-quit=yes$' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "mpv resume option missing"
PATH="$fake_mpv_bin:$test_home/.local/bin:$PATH" MPV_ARGS_FILE="$test_home/mpv-args" "$test_home/.local/bin/course" "$course_path"
grep -q -- '--playlist-start=auto' "$test_home/mpv-args" || fail "course did not use native auto playlist resume"
grep -q -- '--window-maximized=yes' "$test_home/mpv-args" || fail "course did not maximize mpv"
PATH="$fake_mpv_bin:$test_home/.local/bin:$PATH" MPV_ARGS_FILE="$test_home/mpv-args" MPV_PLAYLIST_FILE="$test_home/mpv-playlist" COURSE_DIR="$override_root" "$test_home/.local/bin/course"
grep -q "$override_path" "$test_home/mpv-playlist" || fail "COURSE_DIR override was not used"
PATH="$fake_mpv_bin:$test_home/.local/bin:$PATH" MPV_ARGS_FILE="$test_home/mpv-args" MPV_PLAYLIST_FILE="$test_home/mpv-playlist" COURSE_DIR="$override_root" "$test_home/.local/bin/course" "$course_path"
grep -q "$course_path" "$test_home/mpv-playlist" || fail "explicit course path was not used"
missing_path="$test_home/missing"
missing_output="$test_home/course-missing.out"
if PATH="$fake_mpv_bin:$test_home/.local/bin:$PATH" MPV_ARGS_FILE="$test_home/mpv-args" "$test_home/.local/bin/course" "$missing_path" >"$missing_output" 2>&1; then
  fail "missing course directory was accepted"
fi
grep -q "Course directory not found: $(cd "$(dirname "$missing_path")" && pwd -P)/missing" "$missing_output" || fail "missing directory error was unclear"
! grep -Eq -- '--vo=kitty|vo=kitty' "$XDG_CONFIG_HOME/mpv/mpv.conf" || fail "Kitty video output configured"
"$repo_root/install" install course --yes
assert_file "$XDG_CONFIG_HOME/tmux/tmux.conf"
assert_file "$XDG_CONFIG_HOME/tmux/git-status.sh"
assert_file "$XDG_CONFIG_HOME/tmux/program-name.sh"
assert_file "$XDG_CONFIG_HOME/tmux/codex-status.sh"
[[ ! -e "$XDG_CONFIG_HOME/nvim" ]] || fail "tmux install touched nvim"
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
assert_output "$(git_status_output "$git_repo")" 'main ~1 tracked'
printf 'staged\n' > "$git_repo/staged.txt"
git -C "$git_repo" add staged.txt
printf 'untracked\n' > "$git_repo/untracked.txt"
mkdir -p "$git_repo/nested"
printf 'nested\n' > "$git_repo/nested/inner.txt"
printf 'fourth\n' > "$git_repo/fourth.txt"
assert_output "$(git_status_output "$git_repo")" 'main +1 ~1 ?3 staged │ tracked │ fourth…'
git_status_raw=$($repo_root/tmux/git-status.sh "$git_repo")
grep -q 'fg=colour114,bg=colour238.*staged' <<<"$git_status_raw" || fail "staged filename color missing"
grep -q 'fg=colour221,bg=colour238.*tracked' <<<"$git_status_raw" || fail "unstaged filename color missing"
printf 'typescript\n' > "$git_repo/index.ts"
printf 'javascript\n' > "$git_repo/index.js"
assert_output "$(git_status_output "$git_repo")" 'main +1 ~1 ?5 staged │ tracked │ fourth…'
git_status_raw=$("$repo_root/tmux/git-status.sh" "$git_repo")
grep -q 'fg=colour244,bg=colour238' <<<"$git_status_raw" || fail "untracked files are not muted"

collision_repo=$(mktemp -d "$test_home/collision-repo.XXXXXX")
git -C "$collision_repo" init -q
git -C "$collision_repo" branch -M main
git -C "$collision_repo" config user.email test@example.com
git -C "$collision_repo" config user.name test
printf 'typescript\n' > "$collision_repo/index.ts"
printf 'javascript\n' > "$collision_repo/index.js"
collision_status_raw=$("$repo_root/tmux/git-status.sh" "$collision_repo")
grep -q 'index.ts' <<<"$collision_status_raw" || fail "collision extension missing"
grep -q 'index.js' <<<"$collision_status_raw" || fail "collision extension missing"
grep -q 'fg=colour244,bg=colour238.*index.ts' <<<"$collision_status_raw" || fail "untracked filename color missing"
git -C "$git_repo" stash push -uqm changed
assert_output "$(git_status_output "$git_repo")" 'main *1 '
git -C "$git_repo" checkout --detach -q
assert_output "$(git_status_output "$git_repo")" "$(git -C "$git_repo" rev-parse --short HEAD) *1 "
assert_output "$(git_status_output "$test_home")" ''

fake_bin=$(mktemp -d "$test_home/fake-bin.XXXXXX")
cat > "$fake_bin/ps" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == '-o' && "$2" == 'command=' ]]; then
  echo 'node /fake/path/codex'
fi
EOF
chmod +x "$fake_bin/ps"
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 123 "$git_repo" 'First conversation')" '✦ First conversation'
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
