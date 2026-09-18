#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_home=$(mktemp -d /tmp/dotfiles-test.XXXXXX)
trap 'rm -rf "$test_home"' EXIT
export HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" XDG_DATA_HOME="$test_home/.local/share"
export DOTFILES_REPO_DIR="$repo_root" DOTFILES_SKIP_PACKAGES=true DOTFILES_SKIP_TMUX_PLUGINS=true

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_output() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"; }
git_status_output() {
  "$repo_root/tmux/git-status.sh" "$1" | sed -E 's/#\[[^]]*\]//g; s/^ //; s/  +/ /g'
}
resource_status_output() {
  env -u TMUX "$repo_root/tmux/resource-status.sh" | sed -E 's/#\[[^]]*\]//g; s/  +/ /g'
}

bash -n "$repo_root"/{bootstrap,install,update,uninstall} || fail "shell syntax"
bash -n "$repo_root/tmux/git-status.sh" || fail "git status script syntax"
bash -n "$repo_root/tmux/resource-status.sh" || fail "resource status script syntax"
bash -n "$repo_root/tmux/program-name.sh" || fail "program name script syntax"
bash -n "$repo_root/tmux/codex-status.sh" || fail "codex status script syntax"
bash -n "$repo_root/tmux/codex-usage.sh" || fail "codex usage script syntax"
grep -q 'codex-status.sh' "$repo_root/tmux/tmux.conf" || fail "Codex status icon is missing from window tabs"
grep -q 'codex-usage.sh' "$repo_root/tmux/tmux.conf" || fail "Codex usage status is missing from the status bar"
bash -n "$repo_root/tmux/easy-motion-default.sh" || fail "easy motion wrapper syntax"
python3 -m py_compile "$repo_root/tmux/smart-copy.py" || fail "smart copy detector syntax"
python3 - "$repo_root/tmux/smart-copy.py" <<'PY' || fail "smart copy detector matrix"
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("smart_copy", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

sample = """URL https://example.com/docs.
Location src/main.py:42:8
Path ./README.md
Git 3f2a1bc branch feature/smart-copy PR #123
$ git status --short
ERROR src/server.ts:88:14: refused
IP 192.168.1.25 at 12:30:45
```python
print('ok')
```
{"enabled":true}
assistant: finished successfully
"""
targets = module.detect(sample)
types = {target.type for target in targets}
expected = {"url", "location", "path", "git-hash", "git-ref", "command", "error", "ip", "timestamp", "code", "json", "codex-response"}
assert expected <= types, (expected - types, targets)
location = next(target for target in targets if target.value == "src/main.py:42:8")
assert (location.row, location.column) == (1, 9), location
assert module.parse_location("src/main.py:42:8") == ("src/main.py", 42, 8)
assert module.open_command(next(target for target in targets if target.type == "url"))[1] == "https://example.com/docs"
os.environ["EDITOR"] = "nvim"
assert any("+call cursor(42,8)" in part for part in module.edit_command(location, None))
command = next(target for target in targets if target.type == "command")
code = next(target for target in targets if target.type == "code")
assert module.target_contains(command, command.row, command.column + len(command.text) - 1)
assert module.target_contains(code, 8, 3)
assert module.smart_action(sample, 99, 99, None) == 0
PY
python3 - "$repo_root/tmux/smart-copy.py" <<'PY' || fail "smart copy adversarial cases"
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("smart_copy_stress", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

text = """punctuation (https://example.com/a?q=1), https://example.com/a?q=1.
bad location file.py:nope and bad IP 999.1.1.1
good IP 10.0.0.1:8080; duplicate 10.0.0.1:8080
› new prompt must stop the response
assistant: first response
line one
› Ask Codex to do anything
assistant: latest response
line two
"""
targets = module.detect(text)
values = [target.value for target in targets]
assert values.count("https://example.com/a?q=1") == 1, values
assert "999.1.1.1" not in values, values
assert "10.0.0.1:8080" in values, values
response = next(target for target in targets if target.type == "codex-response")
assert response.value == "latest response\nline two", response.value
assert module.detect("") == []
assert module.detect("😀 https://example.com/😀!")[0].column == 3
PY
help=$("$repo_root/install" --help)
grep -q 'zsh|tmux|btop|nvim|mpv|course' <<<"$help" || fail "help output"

"$repo_root/install" --dry-run
[[ ! -e "$XDG_CONFIG_HOME" ]] || fail "dry-run changed config"
dry_run=$(PATH="$test_home/minimal-bin:/usr/bin:/bin" DOTFILES_SKIP_PACKAGES=false DOTFILES_SKIP_TMUX_PLUGINS=false "$repo_root/install" install tmux --dry-run 2>&1)
grep -q 'lazygit' <<<"$dry_run" || fail "tmux dry-run does not provision lazygit"
grep -q 'btop' <<<"$dry_run" || fail "tmux dry-run does not provision btop"
grep -q 'Would install tmux plugins' <<<"$dry_run" || fail "tmux dry-run does not provision plugins"
btop_dry_run=$(PATH="$test_home/minimal-bin:/usr/bin:/bin" DOTFILES_SKIP_PACKAGES=false "$repo_root/install" install btop --dry-run 2>&1)
grep -q 'btop' <<<"$btop_dry_run" || fail "btop dry-run does not provision btop"
! grep -q 'lazygit' <<<"$btop_dry_run" || fail "btop install unexpectedly provisions lazygit"

"$repo_root/install" install btop --yes
assert_file "$XDG_CONFIG_HOME/btop/btop.conf"
"$repo_root/install" uninstall btop --yes
[[ ! -e "$XDG_CONFIG_HOME/btop/btop.conf" ]] || fail "btop uninstall failed"

"$repo_root/install" install tmux --yes

"$repo_root/install" install zsh --yes
assert_file "$XDG_CONFIG_HOME/zsh/path-navigation.zsh"
assert_file "$test_home/.zshrc"
grep -q '^# >>> dotfiles zsh >>>$' "$test_home/.zshrc" || fail "zsh source block missing"
grep -q '^source "\${XDG_CONFIG_HOME:-\$HOME/.config}/zsh/path-navigation.zsh"$' "$test_home/.zshrc" || fail "zsh source path missing"
grep -q "bindkey -M emacs '\^W' dotfiles-backward-kill-path-component" "$repo_root/zsh/path-navigation.zsh" || fail "smart Ctrl-W binding missing"
grep -q "bindkey -M emacs -r '\^\[w'" "$repo_root/zsh/path-navigation.zsh" || fail "Alt-W binding was not removed"
before_zshrc=$(wc -l < "$test_home/.zshrc")
"$repo_root/install" install zsh --yes
after_zshrc=$(wc -l < "$test_home/.zshrc")
[[ "$before_zshrc" == "$after_zshrc" ]] || fail "zsh installation is not idempotent"
zsh_result=$(zsh -f -c 'zle() { :; }; source "$1"; BUFFER="cd metaData/systemObjects/20260903_CXO-4148.xml"; CURSOR=${#BUFFER}; dotfiles-backward-kill-path-component; print -r -- "$BUFFER"' _ "$repo_root/zsh/path-navigation.zsh")
[[ "$zsh_result" == 'cd metaData/systemObjects/20260903_CXO-4148.' ]] || fail "zsh dotted component deletion"
zsh_result=$(zsh -f -c 'zle() { :; }; source "$1"; BUFFER="cd metaData/systemObjects/20260903_CXO-4148.xml"; CURSOR=${#BUFFER}; repeat 3 { dotfiles-backward-kill-path-component }; print -r -- "$BUFFER"' _ "$repo_root/zsh/path-navigation.zsh")
[[ "$zsh_result" == 'cd metaData/' ]] || fail "zsh path deletion did not remove consecutive components"
widget_sequence() {
  local input="$1" count="$2"
  zsh -f -c 'zle() { [[ "$1" == backward-kill-word ]] || return; if [[ "$BUFFER" == *" "* ]]; then BUFFER="${BUFFER% *}"; else BUFFER=""; fi; CURSOR=${#BUFFER}; }; source "$1"; BUFFER="$2"; CURSOR=${#BUFFER}; repeat "$3" { dotfiles-backward-kill-path-component; print -r -- "$BUFFER" }' _ "$repo_root/zsh/path-navigation.zsh" "$input" "$count"
}
[[ "$(widget_sequence 'archive.tar.gz' 3)" == $'archive.tar.\narchive.' ]] || fail "multi-dot path deletion"
[[ "$(widget_sequence 'filename.txt' 2)" == 'filename.' ]] || fail "single-extension deletion"
[[ "$(widget_sequence 'curl --output=build/result.json' 3)" == $'curl --output=build/result.\ncurl --output=build/\ncurl --output=' ]] || fail "equals flag value deletion"
[[ "$(widget_sequence 'curl --output build/result.json' 2)" == $'curl --output build/result.\ncurl --output build/' ]] || fail "separate flag value deletion"
[[ "$(widget_sequence 'tar -xzvf archive.tar.gz' 8)" == $'tar -xzvf archive.tar.\ntar -xzvf archive.\ntar -xzvf \ntar -xzvf\ntar -xzv\ntar -xz\ntar -x\ntar' ]] || fail "grouped short flag deletion"
[[ "$(widget_sequence 'https://example.com/users?id=42&sort=name' 4)" == $'https://example.com/users?id=42&sort=\nhttps://example.com/users?id=42&\nhttps://example.com/users?id=\nhttps://example.com/users?' ]] || fail "URL query deletion"
[[ "$(widget_sequence 'ghcr.io/company/backend:v1.2.3' 8)" == $'ghcr.io/company/backend:v1.2.\nghcr.io/company/backend:v1.\nghcr.io/company/backend:\nghcr.io/company/\nghcr.io/\nghcr.' ]] || fail "Docker image deletion"
json_input='{"user":{"name":"Facundo","id":42}}'
json_expected=$'{"user":{"name":"Facundo","id":42}\n{"user":{"name":"Facundo","id":\n{"user":{"name":"Facundo","id"'
[[ "$(widget_sequence "$json_input" 3)" == "$json_expected" ]] || fail "JSON-like deletion"
quoted_input='cd "My Folder/file.txt"'
[[ "$(widget_sequence "$quoted_input" 2)" == $'cd "My Folder/file.\ncd "My Folder/' ]] || fail "quoted path deletion"
[[ "$(widget_sequence 'cd My\ Folder/file.txt' 2)" == $'cd My\\ Folder/file.\ncd My\\ Folder/' ]] || fail "escaped path deletion"

"$repo_root/install" uninstall zsh --yes
[[ ! -e "$XDG_CONFIG_HOME/zsh/path-navigation.zsh" ]] || fail "zsh file was not removed"
if grep -q 'dotfiles zsh' "$test_home/.zshrc"; then fail "zsh source block was not removed"; fi

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
assert_file "$XDG_CONFIG_HOME/tmux/resource-status.sh"
assert_file "$XDG_CONFIG_HOME/tmux/git-status.sh"
assert_file "$XDG_CONFIG_HOME/tmux/program-name.sh"
assert_file "$XDG_CONFIG_HOME/tmux/codex-status.sh"
assert_file "$XDG_CONFIG_HOME/tmux/codex-usage.sh"
assert_file "$XDG_CONFIG_HOME/tmux/easy-motion-default.sh"
assert_file "$XDG_CONFIG_HOME/tmux/smart-copy.py"
assert_file "$XDG_CONFIG_HOME/tmux/resource-monitor.sh"
assert_file "$XDG_CONFIG_HOME/btop/btop.conf"
[[ ! -e "$XDG_CONFIG_HOME/nvim" ]] || fail "tmux install touched nvim"
grep -q '^bind g display-popup -E -w 95% -h 95% -d "#{pane_current_path}" lazygit$' "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "lazygit popup binding missing"
grep -q '^bind M display-popup -E -w 95% -h 95% -d "#{pane_current_path}"' "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "resource monitor popup binding missing"
grep -q '^vim_keys = true$' "$XDG_CONFIG_HOME/btop/btop.conf" || fail "btop Vim navigation config missing"
grep -q '^set -g prefix C-Space$' "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "tmux prefix binding missing"
grep -q '^unbind C-b$' "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "legacy tmux prefix was not unbound"
grep -q "^set -g mode-keys vi$" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "tmux vi mode missing"
grep -q "^bind -T copy-mode-vi Space run-shell" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "EasyMotion Space binding missing"
grep -q "^bind -T copy-mode-vi v send-keys -X begin-selection$" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "character selection binding missing"
grep -q "^bind -T copy-mode-vi V send-keys -X select-line$" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "line selection binding missing"
grep -Fq "bind v copy-mode \\; run-shell" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "prefix v EasyMotion binding missing"
grep -Fq "bind a copy-mode \\; run-shell" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "prefix a EasyMotion alias missing"
grep -q "^set -g @plugin 'IngoMeyer441/tmux-easy-motion'$" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "tmux-easy-motion plugin missing"
grep -q "^set -g @easy-motion-copy-mode-prefix 'M-Space'$" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "advanced EasyMotion binding missing"
grep -q '^set -g @easy-motion-auto-begin-selection "true"$' "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "EasyMotion auto-selection missing"
grep -q "^set -g @easy-motion-binding-bd-w 'm'$" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "bidirectional word motion missing"

fake_tmux_bin=$(mktemp -d "$test_home/fake-tmux-bin.XXXXXX")
fake_plugin_dir="$XDG_CONFIG_HOME/tmux/plugins/tmux-easy-motion/scripts"
mkdir -p "$fake_plugin_dir"
cat > "$fake_tmux_bin/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"#{selection_start_x}"* ]]; then
  printf '%s\n' "${FAKE_TMUX_SELECTION_START_X:-}"
elif [[ "$*" == *"#{session_id}"* ]]; then
  printf 'session-id\n'
elif [[ "$*" == *"#{window_id}"* ]]; then
  printf 'window-id\n'
elif [[ "$*" == *"#{pane_id}"* ]]; then
  printf 'pane-id\n'
fi
EOF
chmod +x "$fake_tmux_bin/tmux"
cat > "$fake_plugin_dir/easy_motion.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${EASY_MOTION_ARGS_FILE:?}"
EOF
chmod +x "$fake_plugin_dir/easy_motion.sh"
FAKE_TMUX_SELECTION_START_X= EASY_MOTION_ARGS_FILE="$test_home/easy-motion-start.args" \
  TMUX_PLUGIN_MANAGER_PATH="$XDG_CONFIG_HOME/tmux/plugins" \
  TMUX='tmux,123,0' PATH="$fake_tmux_bin:$PATH" \
  bash "$XDG_CONFIG_HOME/tmux/easy-motion-default.sh"
grep -q ' pane-id bd-w$' "$test_home/easy-motion-start.args" || fail "EasyMotion START motion is not bd-w"
FAKE_TMUX_SELECTION_START_X=0 EASY_MOTION_ARGS_FILE="$test_home/easy-motion-end.args" \
  TMUX_PLUGIN_MANAGER_PATH="$XDG_CONFIG_HOME/tmux/plugins" \
  TMUX='tmux,123,0' PATH="$fake_tmux_bin:$PATH" \
  bash "$XDG_CONFIG_HOME/tmux/easy-motion-default.sh"
grep -q ' pane-id bd-E$' "$test_home/easy-motion-end.args" || fail "EasyMotion END motion is not bd-E"
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
assert_output "$(git_status_output "$git_repo")" '~ 1 main '
printf 'staged\n' > "$git_repo/staged.txt"
git -C "$git_repo" add staged.txt
printf 'untracked\n' > "$git_repo/untracked.txt"
mkdir -p "$git_repo/nested"
printf 'nested\n' > "$git_repo/nested/inner.txt"
printf 'fourth\n' > "$git_repo/fourth.txt"
assert_output "$(git_status_output "$git_repo")" '? 3 ~ 1 + 1 main '
git_status_raw=$(TMUX_GIT_STATUS_TIMESTAMP=0 "$repo_root/tmux/git-status.sh" "$git_repo")
[[ "$git_status_raw" != *'tracked.txt'* ]] || fail "changed filenames are still rendered"
grep -q 'fg=colour255,bg=colour22.*+ 1' <<<"$git_status_raw" || fail "staged status color missing"
grep -q 'bg=colour136.*~ 1' <<<"$git_status_raw" || fail "modified status color missing"
grep -q 'fg=colour255,bg=colour238.*? 3' <<<"$git_status_raw" || fail "untracked status color missing"

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
grep -q 'fg=colour255,bg=colour124,bold] ! 1' <<<"$conflict_status_raw" || fail "conflict status color missing"

git -C "$git_repo" stash push -uqm changed
assert_output "$(git_status_output "$git_repo")" '⚑ 1 main '
git -C "$git_repo" checkout --detach -q
assert_output "$(git_status_output "$git_repo")" "⚑ 1 $(git -C "$git_repo" rev-parse --short HEAD) "
assert_output "$(git_status_output "$test_home")" ''

fake_bin=$(mktemp -d "$test_home/fake-bin.XXXXXX")
cat > "$fake_bin/ps" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == '-eo' ]]; then
  cat <<'PROCESS_LIST'
  101  42.4  3.2 node /fake/path/codex.js --server
  102   7.1 18.4 /System/Library/WindowServer
  103  12.9  4.0 /bin/bash
PROCESS_LIST
elif [[ "$1" == '-o' && "$2" == 'command=' ]]; then
  case "$4" in
    123) echo 'nvim --embed' ;;
    124) echo '/usr/bin/neovim --embed' ;;
    125) echo 'vim' ;;
    102) echo '/System/Library/WindowServer' ;;
    *) echo 'node /fake/path/codex' ;;
  esac
fi
EOF
chmod +x "$fake_bin/ps"
usage_plugin="$test_home/tmux-plugins/agent-usage-tmux/scripts"
usage_cache="$test_home/codex-usage-cache"
usage_calls="$test_home/codex-usage-calls"
printf '0\n' > "$usage_calls"
mkdir -p "$usage_plugin"
cat > "$usage_plugin/fetch_codex_usage.py" <<'EOF'
#!/usr/bin/env python3
import os
from pathlib import Path
import sys

calls = Path(os.environ["CODEX_USAGE_CALLS"])
calls.write_text(str(int(calls.read_text()) + 1))
print('80' if '--field' not in sys.argv else '80')
EOF
chmod +x "$usage_plugin/fetch_codex_usage.py"
usage_env=(TMUX_PLUGIN_MANAGER_PATH="$test_home/tmux-plugins" TMUX_CODEX_USAGE_CACHE_DIR="$usage_cache" TMUX_CODEX_USAGE_REFRESH_INTERVAL=60 CODEX_USAGE_CALLS="$usage_calls" PATH="$fake_bin:$PATH")
first_usage=$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456)
env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" --trigger
for _ in {1..40}; do
  [[ -f "$usage_cache/default/usage" ]] && break
  sleep 0.05
done
assert_file "$usage_cache/default/usage"
assert_output "$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 | sed -E 's/#\[[^]]*\]//g; s/  +/ /g')" ' 5h 80% 0h01m | wk 80% 0h01m | '
assert_output "$(cat "$usage_calls")" '4'
env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 >/dev/null
assert_output "$(cat "$usage_calls")" '4'
env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" --trigger @2
for _ in {1..40}; do
  [[ -f "$usage_cache/2/usage" ]] && break
  sleep 0.05
done
assert_file "$usage_cache/2/usage"
assert_output "$(cat "$usage_calls")" '8'
env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 @2 >/dev/null
assert_output "$(cat "$usage_calls")" '8'
assert_output "$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 102)" ''
assert_output "$(PATH="$fake_bin:$PATH" resource_status_output)" 'CPU | MEM '
resource_status_raw=$(PATH="$fake_bin:$PATH" env -u TMUX "$repo_root/tmux/resource-status.sh")
grep -q 'fg=colour186,bg=colour237,bold]CPU ' <<<"$resource_status_raw" || fail "CPU color or readable label missing"
grep -q 'fg=colour114,bg=colour237,bold]MEM ' <<<"$resource_status_raw" || fail "memory color or trailing spacing missing"
grep -q 'bg=colour237,fg=colour255,bold]#\[default\]$' <<<"$resource_status_raw" || fail "resource status trailing reset missing"
! grep -q 'bg=colour238' "$repo_root/tmux/codex-usage.sh" || fail "Codex usage still overrides the status background"
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 123)" ''
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 124)" ''
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 125)" 'vim'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 456 "$git_repo" 'renaming...')" 'Codex'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 456 "$git_repo" 'Second conversation')" 'Second conversation'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 789 "$git_repo" "⠼ First conversation | ${git_repo##*/}")" 'First conversation'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 999 "$git_repo")" 'Codex'
grep -q '"#{pane_current_path}" #{q:pane_title})' "$repo_root/tmux/tmux.conf" || fail "pane title shell quoting changed"
grep -q '^bind c new-window -a -c "#{pane_current_path}"$' "$repo_root/tmux/tmux.conf" || fail "new-window binding does not insert after the active window"
status_right=$(grep '^set -g status-right ' "$repo_root/tmux/tmux.conf")
git_position=${status_right%%git-status.sh*}
resource_position=${status_right%%resource-status.sh*}
codex_position=${status_right%%codex-usage.sh*}
[[ "$resource_position" != "$status_right" && "$git_position" != "$status_right" && "$codex_position" != "$status_right" && ${#git_position} -lt ${#codex_position} && ${#codex_position} -lt ${#resource_position} ]] || fail "resource status is not rightmost"

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
[[ ! -e "$XDG_CONFIG_HOME/tmux/tmux.conf" && ! -e "$XDG_CONFIG_HOME/tmux/resource-status.sh" && ! -e "$XDG_CONFIG_HOME/tmux/git-status.sh" && ! -e "$XDG_CONFIG_HOME/tmux/program-name.sh" && ! -e "$XDG_CONFIG_HOME/tmux/codex-status.sh" && ! -e "$XDG_CONFIG_HOME/tmux/codex-usage.sh" && ! -e "$XDG_CONFIG_HOME/tmux/easy-motion-default.sh" && ! -e "$XDG_CONFIG_HOME/tmux/smart-copy.py" ]] || fail "tmux uninstall failed"
assert_file "$XDG_CONFIG_HOME/nvim/init.lua"
"$repo_root/install" uninstall nvim --yes
[[ ! -e "$XDG_CONFIG_HOME/nvim/init.lua" ]] || fail "nvim uninstall failed"
assert_file "$XDG_CONFIG_HOME/nvim/unrelated.lua"

echo "dotfiles isolated tests passed"
