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

bash -n "$repo_root"/{bootstrap,install,update,uninstall} "$repo_root/bin/dw" || fail "shell syntax"
node --check "$repo_root/bin/dw-setup.js" || fail "DW setup helper syntax"
bash -n "$repo_root/tmux/git-status.sh" || fail "git status script syntax"
bash -n "$repo_root/tmux/resource-status.sh" || fail "resource status script syntax"
bash -n "$repo_root/tmux/dw-status.sh" || fail "DW status script syntax"
bash -n "$repo_root/tmux/program-name.sh" || fail "program name script syntax"
bash -n "$repo_root/tmux/codex-status.sh" || fail "codex status script syntax"
bash -n "$repo_root/tmux/codex-usage.sh" || fail "codex usage script syntax"
bash -n "$repo_root/tmux/vercel-status.sh" || fail "Vercel status script syntax"
bash -n "$repo_root/tmux/vercel-deploy-common.sh" "$repo_root/tmux/vercel-deploy-watch.sh" "$repo_root/tmux/post-push" || fail "Vercel event scripts syntax"

vercel_project="$test_home/vercel-project"
mkdir -p "$vercel_project/nested/deeper" "$vercel_project/.vercel" "$vercel_project/.git/hooks"
git -C "$vercel_project" init -q
printf '%s\n' '{"projectId":"prj_test"}' > "$vercel_project/.vercel/project.json"
printf '#!/usr/bin/env bash\nprintf chained > "%s"\n' "$test_home/user-hook-ran" > "$vercel_project/.git/hooks/post-push"
chmod +x "$vercel_project/.git/hooks/post-push"
vercel_cache="$test_home/vercel-cache"
vercel_bin="$test_home/vercel-bin"
mkdir -p "$vercel_bin"
cat > "$vercel_bin/vercel" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${VERCEL_STATE:-READY}" >> "${VERCEL_CALLS:?}"
printf 'Age Deployment Status\n  1m example %s\n' "${VERCEL_STATE:-READY}"
SH
chmod +x "$vercel_bin/vercel"
vercel_calls="$test_home/vercel-calls"
: > "$vercel_calls"
common_env=(TMUX_VERCEL_STATUS_CACHE_DIR="$vercel_cache" TMUX_VERCEL_CLI="$vercel_bin/vercel" VERCEL_CALLS="$vercel_calls" PATH="$vercel_bin:$PATH")
! env "${common_env[@]}" "$repo_root/tmux/vercel-status.sh" "$vercel_project/nested" | grep -q . || fail "status rendered without an event"
! grep -q . "$vercel_calls" || fail "tmux rendering called Vercel"
vercel_root=$(git -C "$vercel_project" rev-parse --show-toplevel)
cache_file=$(TMUX_VERCEL_STATUS_CACHE_DIR="$vercel_cache" bash -c 'source "$1/tmux/vercel-deploy-common.sh"; vercel_cache_file "$2" prj_test' _ "$repo_root" "$vercel_root")
(cd "$vercel_project" && env "${common_env[@]}" "$repo_root/tmux/post-push") >/dev/null
assert_file "$test_home/user-hook-ran"
assert_output "$(cat "$cache_file")" deploying
for _ in {1..40}; do
  grep -q . "$vercel_calls" && break
  sleep 0.05
done
grep -q . "$vercel_calls" || fail "post-push did not start the watcher"
for _ in {1..40}; do
  [[ "$(cat "$cache_file" 2>/dev/null)" == ready ]] && break
  sleep 0.05
done
ready_output=$(env "${common_env[@]}" VERCEL_STATE=READY "$repo_root/tmux/vercel-status.sh" "$vercel_project")
assert_output "$ready_output" '#[fg=colour255,bg=#166534,bold] ▲ #[default]'
for state in ERROR; do
  state_cache="$test_home/vercel-cache-$state"
  state_calls="$test_home/vercel-calls-$state"
  : > "$state_calls"
  state_env=(TMUX_VERCEL_STATUS_CACHE_DIR="$state_cache" TMUX_VERCEL_CLI="$vercel_bin/vercel" VERCEL_CALLS="$state_calls" VERCEL_STATE="$state" PATH="$vercel_bin:$PATH")
  (cd "$vercel_project" && env "${state_env[@]}" "$repo_root/tmux/post-push") >/dev/null
  for _ in {1..40}; do
    state_file=$(find "$state_cache" -type f ! -name '*.lock' -print -quit 2>/dev/null || true)
    [[ -n "$state_file" ]] && [[ "$(cat "$state_file")" == failed ]] && break
    sleep 0.05
  done
  assert_output "$(cat "$state_file")" failed
done
timeout_cache="$test_home/vercel-cache-timeout"
timeout_calls="$test_home/vercel-calls-timeout"
: > "$timeout_calls"
timeout_env=(TMUX_VERCEL_STATUS_CACHE_DIR="$timeout_cache" TMUX_VERCEL_CLI="$vercel_bin/vercel" VERCEL_CALLS="$timeout_calls" VERCEL_STATE=UNKNOWN TMUX_VERCEL_STATUS_TIMEOUT=1 TMUX_VERCEL_STATUS_POLL_INTERVAL=0.05 PATH="$vercel_bin:$PATH")
(cd "$vercel_project" && env "${timeout_env[@]}" "$repo_root/tmux/post-push") >/dev/null
for _ in {1..40}; do
  timeout_file=$(find "$timeout_cache" -type f ! -name '*.lock' -print -quit 2>/dev/null || true)
  [[ -n "$timeout_file" ]] && [[ "$(cat "$timeout_file")" == unavailable ]] && break
  sleep 0.05
done
assert_output "$(cat "$timeout_file")" unavailable
grep -q 'TMUX_VERCEL_CLI' "$repo_root/tmux/vercel-deploy-watch.sh" || fail "watcher CLI is not configurable"
codex_usage_plugin="$test_home/codex-usage-plugin"
mkdir -p "$codex_usage_plugin/agent-usage-tmux/scripts"
cat > "$codex_usage_plugin/agent-usage-tmux/scripts/fetch_codex_usage.py" <<'PY'
#!/usr/bin/env python3
import sys

if '--field' in sys.argv:
    print('3600')
else:
    print('75')
PY
fake_process_bin="$test_home/fake-process-bin"
mkdir -p "$fake_process_bin"
cat > "$fake_process_bin/ps" <<'SH'
#!/usr/bin/env bash
case "${@: -1}" in
  4242) printf 'zsh\n' ;;
  4343) printf 'codex --resume abc\n' ;;
  *) exit 1 ;;
esac
SH
cat > "$fake_process_bin/pgrep" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$fake_process_bin/ps" "$fake_process_bin/pgrep"
ordinary_usage=$(PATH="$fake_process_bin:$PATH" TMUX_PLUGIN_MANAGER_PATH="$codex_usage_plugin" "$repo_root/tmux/codex-usage.sh" 4242 '@1')
[[ -z "$ordinary_usage" ]] || fail "Codex usage appeared in an ordinary shell window"
codex_usage=$(PATH="$fake_process_bin:$PATH" TMUX_PLUGIN_MANAGER_PATH="$codex_usage_plugin" "$repo_root/tmux/codex-usage.sh" 4343 '@2')
grep -q '5h' <<<"$codex_usage" || fail "Codex usage disappeared from a Codex window"
grep -q 'codex-status.sh' "$repo_root/tmux/tmux.conf" || fail "Codex status icon is missing from window tabs"
grep -q 'codex-usage.sh' "$repo_root/tmux/tmux.conf" || fail "Codex usage status is missing from the status bar"
grep -q 'vim.opt.title = true' "$repo_root/nvim/lua/options.lua" || fail "Neovim terminal titles are disabled"
grep -q 'vim.opt.titlestring' "$repo_root/nvim/lua/options.lua" || fail "Neovim filename title is missing"
grep -q 'dw-status.sh' "$repo_root/tmux/tmux.conf" || fail "DW environment status is missing from the status bar"
grep -q '^bind e if-shell' "$repo_root/tmux/tmux.conf" || fail "DW environment toggle binding is missing"
! grep -q 'display-message.*DW environment' "$repo_root/tmux/tmux.conf" || fail "DW toggle still shows a toast"
dw_without_config=$(TMUX_DW_STATUS_CACHE_DIR="$test_home/dw-cache-empty" "$repo_root/tmux/dw-status.sh" "$test_home")
[[ -z "$dw_without_config" ]] || fail "DW status appeared without dw.json"
mkdir -p "$test_home/dw-project/nested"
printf '%s\n' '{' '  "hostname": "development-eu01.example.test",' '  "code-version": "version_test"' '}' > "$test_home/dw-project/dw.json"
dw_project_output=$(TMUX_DW_STATUS_CACHE_DIR="$test_home/dw-cache-project" TMUX_DW_STATUS_CACHE_TTL=0 "$repo_root/tmux/dw-status.sh" "$test_home/dw-project/nested")
grep -q ' version_test dev ' <<<"$dw_project_output" || fail "DW status did not expose the code version and environment"
printf '%s\n' '{' '  "hostname": "bdlq-018.dx.commercecloud.salesforce.com"' '}' > "$test_home/dw-project/dw.json"
dw_sandbox_output=$(TMUX_DW_STATUS_CACHE_DIR="$test_home/dw-cache-sandbox" TMUX_DW_STATUS_CACHE_TTL=0 "$repo_root/tmux/dw-status.sh" "$test_home/dw-project")
grep -q ' 018 ' <<<"$dw_sandbox_output" || fail "DW status did not expose the sandbox number"
grep -q 'fg=colour255,bg=colour124,bold' <<<"$dw_sandbox_output" || fail "Unavailable DW sandbox status is not red"
printf '%s\n' '{' '  "hostname": "bdlq-018.dx.commercecloud.salesforce.com",' '  "code-version": "version_test"' '}' > "$test_home/dw-project/dw.json"
online_cache="$test_home/dw-cache-online"
mkdir -p "$online_cache"
online_key=$(printf '%s\t%s\t%s' "$test_home/dw-project" 'bdlq-018.dx.commercecloud.salesforce.com' 'version_test' | cksum | awk '{print $1}')
printf '%s online\n' "$(date +%Y-%m-%d)" > "$online_cache/$online_key"
dw_online_output=$(TMUX_DW_STATUS_CACHE_DIR="$online_cache" "$repo_root/tmux/dw-status.sh" "$test_home/dw-project")
grep -q ' version_test 018 ' <<<"$dw_online_output" || fail "DW online status did not expose the code version"
grep -q 'fg=colour255,bg=#166534,bold' <<<"$dw_online_output" || fail "DW online status is not dark green"
bash -n "$repo_root/tmux/easy-motion-default.sh" || fail "easy motion wrapper syntax"
python3 -m py_compile "$repo_root/tmux/smart-actions.py" || fail "smart actions detector syntax"
python3 - "$repo_root/tmux/smart-actions.py" <<'PY' || fail "smart actions detector matrix"
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("smart_actions", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

sample = """URL https://example.com/docs.
Location src/main.py:42:8
Path ./README.md
Git 3f2a1bc branch feature/smart-actions PR #123
$ git status --short
ERROR src/server.ts:88:14: refused
IP 192.168.1.25 at 12:30:45
```python
print('ok')
```
{"enabled":true}
assistant: finished successfully
$ codex resume 01a0b088-587b-7383-b2dd-bf18fc0eb11b
"""
targets = module.detect(sample)
types = {target.type for target in targets}
expected = {"url", "location", "path", "git-hash", "git-ref", "command", "codex-resume", "error", "ip", "timestamp", "code", "json", "codex-response"}
assert expected <= types, (expected - types, targets)
resume = next(target for target in targets if target.type == "codex-resume")
assert resume.value == "codex resume 01a0b088-587b-7383-b2dd-bf18fc0eb11b", resume
location = next(target for target in targets if target.value == "src/main.py:42:8")
assert (location.row, location.column) == (1, 9), location
assert module.parse_location("src/main.py:42:8") == ("src/main.py", 42, 8)
assert module.open_command(next(target for target in targets if target.type == "url"))[1] == "https://example.com/docs"
repository = next(target for target in module.detect("IFAKA/dotfiles.git") if target.type == "repository")
assert module.repository_url(repository, None) == "https://github.com/IFAKA/dotfiles", repository
os.environ["EDITOR"] = "nvim"
assert any("+call cursor(42,8)" in part for part in module.edit_command(location, None))
command = next(target for target in targets if target.type == "command")
code = next(target for target in targets if target.type == "code")
assert module.target_contains(command, command.row, command.column + len(command.text) - 1)
assert module.target_contains(code, 8, 3)
assert module.smart_action(sample, 99, 99, None) == 0
PY
python3 - "$repo_root/tmux/smart-actions.py" <<'PY' || fail "smart actions adversarial cases"
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("smart_actions_stress", sys.argv[1])
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
assert values.count("https://example.com/a?q=1") == 2, values
assert "999.1.1.1" not in values, values
assert "10.0.0.1:8080" in values, values
assert "github.com" not in values, values
assert "e0910bc..3ec830f" not in values, values
assert "main...origin/main" not in values, values
assert "HOME/.config/tmux/smart-actions.py" not in values, values
response = next(target for target in targets if target.type == "codex-response")
assert response.value == "latest response\nline two", response.value
assert not any(target.type == "codex-resume" for target in module.detect("$ codex resume not-a-uuid"))
bare_resume = next(target for target in module.detect("codex resume 01a0b088-587b-7383-b2dd-bf18fc0eb11b") if target.type == "codex-resume")
assert bare_resume.value == "codex resume 01a0b088-587b-7383-b2dd-bf18fc0eb11b", bare_resume
assert module.detect("") == []
assert module.detect("😀 https://example.com/😀!")[0].column == 3
PY
python3 - "$repo_root/tmux/smart-actions.py" <<'PY' || fail "smart action side effects"
import importlib.util
import sys
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("smart_actions_side_effects", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

module.shutil.which = lambda name: None
ran = []
copied = []
module.subprocess.run = lambda command, **kwargs: ran.append(command) or SimpleNamespace(returncode=1)
module.copy_value = copied.append

assert module.smart_action("https://example.com", 0, 8, None) == 0
assert ran == [["open", "https://example.com"]], ran
assert copied == [], copied

ran.clear()
assert module.smart_action("10.0.0.1", 0, 4, None) == 0
assert module.smart_action_target("plain text", 0, 2) is None
assert module.smart_action_target("https://example.com", 0, 8).type == "url"
assert ran == [], ran
assert copied == ["10.0.0.1"], copied

targets = module.detect("src/main.py image.png recording.mp4 notes.txt")
assert next(target for target in targets if target.value == "src/main.py").action == "edit", targets
assert next(target for target in targets if target.value == "image.png").action == "open", targets
assert next(target for target in targets if target.value == "recording.mp4").action == "open", targets
assert next(target for target in targets if target.value == "notes.txt").action == "edit", targets
assert next(target for target in module.detect("README.md") if target.value == "README.md").action == "edit"
PY
python3 - "$repo_root/tmux/smart-actions.py" <<'PY' || fail "smart selection matrix"
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("smart_selection", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

assert module.semantic_select("first second", 0, 0).text == "first"
assert module.semantic_select("😀 wide", 0, 3).column == 3
assert module.semantic_select("import os.path", 0, 8, 3).text == "import os.path"
assert module.semantic_select("a paragraph\ncontinues here\n\nnext", 1, 3, 2).text == "a paragraph\ncontinues here"
assert module.semantic_select("- one\n- two\n\nend", 1, 2, 2).kind == "list-item"
assert module.semantic_select("- one\n- two\n\nend", 1, 2, 3).text == "- one\n- two"
assert module.semantic_select("> quote\n> block", 1, 2, 2).text == "> quote\n> block"
code = "```python\ndef hello():\n    return 1\n```"
assert module.semantic_select(code, 1, 5, 2).kind == "function"
assert module.semantic_select("value = important_name", 0, 18).text == "important_name"
assert module.detect("$ echo hello")[0].value == "echo hello"
assert not any(target.type == "command" for target in module.detect("```\n$ echo no\n```"))
resume = module.detect("$ codex resume 01a0b088-587b-7383-b2dd-bf18fc0eb11b")
assert next(target for target in resume if target.type == "codex-resume")
assert len([target for target in module.detect("https://example.com https://example.com") if target.type == "url"]) == 2
assert module.semantic_sibling("- one\n- two", 0, 2, 1, 2).text == "two"
assert module.semantic_sibling("one\n\ntwo\n\nthree", 0, 0, -1, 2) is None
assert module.semantic_sibling("one\n\ntwo\n\nthree", 2, 0, 1, 2).text == "three"
PY
help=$("$repo_root/install" --help)
grep -q 'zsh|tmux|btop|nvim|mpv|course|dw' <<<"$help" || fail "help output"

dw_project="$test_home/dw-project"
printf '%s\n' '{"hostname":"dev.example.test","username":"user","password":"dev-secret","nested":{"password":"nested-secret"}}' > "$dw_project/dw.dev.json"
printf '%s\n' '{"hostname":"sandbox.example.test","username":"user","password":"sbx-secret"}' > "$dw_project/dw.sbx.json"
printf '%s\n' '{"hostname":"dev.example.test","username":"user","password":"dev-secret"}' > "$dw_project/dw.json"
assert_output "$(cd "$dw_project/nested" && "$repo_root/bin/dw")" 'DW environment: sbx'
grep -q 'sandbox.example.test' "$dw_project/dw.json" || fail "DW toggle did not select sbx"
assert_output "$("$repo_root/bin/dw" --path "$dw_project" dev)" 'DW environment: dev'
grep -q 'dev.example.test' "$dw_project/dw.json" || fail "DW explicit selection did not select dev"
dw_print=$("$repo_root/bin/dw" --path "$dw_project" --print)
grep -q '"password": "\*\*\*\*\*\*\*\*"' <<<"$dw_print" || fail "DW print did not redact password"
! grep -q 'dev-secret\|sbx-secret\|nested-secret' <<<"$dw_print" || fail "DW print leaked a password"
if "$repo_root/bin/dw" --path "$test_home" >/dev/null 2>&1; then fail "DW launcher accepted a directory without dw.json"; fi

"$repo_root/install" install dw --yes
assert_file "$test_home/.local/bin/dw"
assert_file "$test_home/.local/bin/dw-setup.js"
assert_file "$test_home/.local/bin/.dotfiles-dw-managed"
"$repo_root/install" uninstall dw --yes
[[ ! -e "$test_home/.local/bin/dw" ]] || fail "DW uninstall failed"
[[ ! -e "$test_home/.local/bin/dw-setup.js" ]] || fail "DW setup helper uninstall failed"

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
assert_file "$XDG_CONFIG_HOME/tmux/vercel-status.sh"
assert_file "$XDG_CONFIG_HOME/tmux/vercel-deploy-common.sh"
assert_file "$XDG_CONFIG_HOME/tmux/easy-motion-default.sh"
assert_file "$XDG_CONFIG_HOME/tmux/smart-actions.py"
[[ ! -e "$XDG_CONFIG_HOME/tmux/smart-copy.py" ]] || fail "legacy smart-copy helper was not removed"
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
grep -q "^bind -T copy-mode-vi Escape run-shell.*smart-select-active.*cancel" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "Smart Select cancellation binding missing"
grep -q "^bind -T copy-mode-vi j run-shell.*easy-motion-default.sh.*move-down" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "Smart Select down binding missing"
grep -q "^bind -T copy-mode-vi k run-shell.*easy-motion-default.sh.*move-up" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "Smart Select up binding missing"
! grep -q "^bind -T copy-mode-vi S " "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "standalone S binding must not overlap Smart Select"
! grep -q "^bind -T copy-mode-vi \(Up\|Down\) " "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "arrow bindings must not overlap Smart Select"
grep -q "^bind -T copy-mode-vi V send-keys -X select-line$" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "line selection binding missing"
grep -Fq "bind v copy-mode \\; run-shell -b 'bash \"\${XDG_CONFIG_HOME:-\$HOME/.config}/tmux/easy-motion-default.sh\" smart'" "$XDG_CONFIG_HOME/tmux/tmux.conf" || fail "prefix v Smart Select binding missing"
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
assert_output "$(git_status_output "$git_repo")" '~1 main '
printf 'staged\n' > "$git_repo/staged.txt"
git -C "$git_repo" add staged.txt
printf 'untracked\n' > "$git_repo/untracked.txt"
mkdir -p "$git_repo/nested"
printf 'nested\n' > "$git_repo/nested/inner.txt"
printf 'fourth\n' > "$git_repo/fourth.txt"
assert_output "$(git_status_output "$git_repo")" '?3 ~1 +1 main '
git_status_raw=$(TMUX_GIT_STATUS_TIMESTAMP=0 "$repo_root/tmux/git-status.sh" "$git_repo")
[[ "$git_status_raw" != *'tracked.txt'* ]] || fail "changed filenames are still rendered"
grep -Fq '[fg=colour114]+#[fg=colour255]1' <<<"$git_status_raw" || fail "staged symbol/value color missing"
grep -Fq '[fg=colour220]~#[fg=colour255]1' <<<"$git_status_raw" || fail "modified symbol/value color missing"
grep -Fq '[fg=colour250]?#[fg=colour255]3' <<<"$git_status_raw" || fail "untracked symbol/value color missing"
! grep -qE '[~+?] \[[0-9]' <<<"$git_status_raw" || fail "Git status symbol and value are separated"
[[ $(grep -o 'bg=colour24' <<<"$git_status_raw" | wc -l | tr -d ' ') == 1 ]] || fail "Git status is split into multiple background components"

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
grep -Fq '[fg=colour203]!#[fg=colour255]1' <<<"$conflict_status_raw" || fail "conflict symbol/value color missing"

git -C "$git_repo" stash push -uqm changed
assert_output "$(git_status_output "$git_repo")" '⚑1 main '
git -C "$git_repo" checkout --detach -q
assert_output "$(git_status_output "$git_repo")" "⚑1 $(git -C "$git_repo" rev-parse --short HEAD) "
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
    777) echo '-zsh' ;;
    778) echo '/bin/zsh' ;;
    779) echo '/bin/bash' ;;
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
usage_env=(TMUX_PLUGIN_MANAGER_PATH="$test_home/tmux-plugins" TMUX_CODEX_USAGE_CACHE_DIR="$usage_cache" CODEX_USAGE_CALLS="$usage_calls" TERM=xterm-256color LC_ALL=en_US.UTF-8 PATH="$fake_bin:$PATH")
first_usage=$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456)
env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" --trigger
for _ in {1..40}; do
  [[ -f "$usage_cache/usage" ]] && break
  sleep 0.05
done
assert_file "$usage_cache/usage"
assert_output "$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 | sed -E 's/#\[[^]]*\]//g; s/  +/ /g')" ' 5h ⣶ 1m | wk ⣶ 1m |'
colored_usage=$(env -u NO_COLOR "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456)
! grep -q 'bg=' <<<"${colored_usage%% |*}" || fail "progress indicator changed its background"
grep -q 'fg=#' <<<"$colored_usage" || fail "progress indicator color missing"
assert_output "$(cat "$usage_calls")" '4'
printf '0 80 86400 80 43200\n' > "$usage_cache/usage"
assert_output "$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 | sed -E 's/#\[[^]]*\]//g; s/  +/ /g')" ' 5h ⣶ 1d | wk ⣶ 12h |'
printf '0 80 3600 80 0\n' > "$usage_cache/usage"
assert_output "$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 | sed -E 's/#\[[^]]*\]//g; s/  +/ /g')" ' 5h ⣶ 1h | wk ⣶ 0m |'
assert_output "$(cat "$usage_calls")" '4'

usage_indicator() {
  local value="$1"
  printf '0 %s 60 %s 60\n' "$value" "$value" > "$usage_cache/usage"
  env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 |
    sed -E 's/#\[[^]]*\]//g' | sed -E 's/^ 5h (.) 1m \| wk . 1m \|$/\1/'
}

expected_indicators=('⠀' '⠀' '⡀' '⣀' '⣤' '⣶' '⣷' '⣷' '⣿' '⣿')
indicator_values=(0 1 12.5 25 50 75 87.5 90 99 100)
for index in "${!indicator_values[@]}"; do
  indicator=$(usage_indicator "${indicator_values[index]}")
  assert_output "$indicator" "${expected_indicators[index]}"
done

exact_values=(100 99 87.5 75 62.5 50 37.5 25 12.5 1 0)
exact_glyphs=('⣿' '⣿' '⣷' '⣶' '⣦' '⣤' '⣄' '⣀' '⡀' '⠀' '⠀')
for index in "${!exact_values[@]}"; do
  assert_output "$(usage_indicator "${exact_values[index]}")" "${exact_glyphs[index]}"
done

color_at() {
  local value="$1"
  printf '0 %s 60 %s 60\n' "$value" "$value" > "$usage_cache/usage"
  env -u NO_COLOR "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 |
    grep -o '\[fg=#[^,]*' | head -1 | sed 's/\[fg=//'
}
[[ "$(color_at 49)" != "$(color_at 50)" ]] || fail "color does not change continuously"
[[ "$(color_at 50)" != "$(color_at 51)" ]] || fail "color does not change continuously"

printf '0 80 60 80 60\n' > "$usage_cache/usage"
no_color_output=$(NO_COLOR=1 env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 |
  sed -E 's/#\[[^]]*\]//g')
assert_output "$no_color_output" ' 5h ⣶ 1m | wk ⣶ 1m |'
[[ "$no_color_output" != *%* ]] || fail "numeric percentage leaked into indicator"
fallback_output=$(env "${usage_env[@]}" TERM=dumb NO_COLOR=1 "$repo_root/tmux/codex-usage.sh" 456 |
  sed -E 's/#\[[^]]*\]//g')
assert_output "$fallback_output" ' 5h ⣶ 1m | wk ⣶ 1m |'
python3 - "$no_color_output" <<'PY' || fail "progress indicator width"
import re
import sys
import unicodedata
import ctypes
import locale

value = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", sys.argv[1])
fields = re.findall(r"(?:5h|wk) (.)", value)
assert fields == ["⣶", "⣶"], repr(value)
assert all(unicodedata.east_asian_width(char) in "NAH" for char in fields)
assert len(fields) == 2
locale.setlocale(locale.LC_CTYPE, "")
libc = ctypes.CDLL(None)
libc.wcwidth.argtypes = [ctypes.c_wchar]
libc.wcwidth.restype = ctypes.c_int
assert all(libc.wcwidth(char) == 1 for char in fields), fields
PY
printf '0 -- 60 -- 60\n' > "$usage_cache/usage"
unknown_output=$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 | sed -E 's/#\[[^]]*\]//g')
assert_output "$unknown_output" ' 5h ? | wk ? |'
env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 >/dev/null
assert_output "$(cat "$usage_calls")" '4'
for _ in {1..40}; do
  [[ ! -d "$usage_cache/.refresh.lock" ]] && break
  sleep 0.05
done
env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" --trigger @2
for _ in {1..40}; do
  [[ "$(cat "$usage_calls")" == 8 ]] && break
  sleep 0.05
done
assert_file "$usage_cache/usage"
assert_output "$(cat "$usage_calls")" '8'
env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 456 @2 >/dev/null
assert_output "$(cat "$usage_calls")" '8'
assert_output "$(env "${usage_env[@]}" "$repo_root/tmux/codex-usage.sh" 102 | sed -E 's/#\[[^]]*\]//g; s/  +/ /g')" ''
assert_output "$(PATH="$fake_bin:$PATH" resource_status_output)" ' CPU MEM '
resource_status_raw=$(PATH="$fake_bin:$PATH" env -u TMUX "$repo_root/tmux/resource-status.sh")
grep -Fq 'fg=colour186,bg=colour237,bold]CPU#[fg=colour255,bg=colour237,bold] ' <<<"$resource_status_raw" || fail "CPU color or readable label missing"
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
directory_root="$test_home/code/work/projects/ikp-digi-wcp-custom-sfra"
mkdir -p "$directory_root/src/components" "$test_home/code/customer-success-platform-v3.14" "$test_home/code/foo_bar_checkout_service/tests"
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 777 "$directory_root")" 'sfra'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 778 "$directory_root/src/components")" 'sfra'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 779 "$test_home/code/customer-success-platform-v3.14")" 'platform'
assert_output "$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" 777 "$test_home/code/foo_bar_checkout_service/tests")" 'checkout'
grep -q '"#{pane_current_path}" #{q:pane_title})' "$repo_root/tmux/tmux.conf" || fail "pane title shell quoting changed"
grep -q '^bind c new-window -a -c "#{pane_current_path}"$' "$repo_root/tmux/tmux.conf" || fail "new-window binding does not insert after the active window"
status_right=$(grep '^set -g status-right ' "$repo_root/tmux/tmux.conf")
git_position=${status_right%%git-status.sh*}
vercel_position=${status_right%%vercel-status.sh*}
resource_position=${status_right%%resource-status.sh*}
codex_position=${status_right%%codex-usage.sh*}
[[ "$resource_position" != "$status_right" && "$git_position" != "$status_right" && "$vercel_position" != "$status_right" && "$codex_position" != "$status_right" && ${#git_position} -lt ${#vercel_position} && ${#vercel_position} -lt ${#codex_position} && ${#codex_position} -lt ${#resource_position} ]] || fail "status bar ordering changed"
grep -q 'vercel-status.sh' "$repo_root/tmux/tmux.conf" || fail "Vercel status is missing from the status bar"
grep -q 'bg=#166534' "$repo_root/tmux/vercel-status.sh" || fail "ready Vercel status color is missing"
grep -q 'bg=#a16207' "$repo_root/tmux/vercel-status.sh" || fail "deploying Vercel status color is missing"
grep -q 'bg=#991b1b' "$repo_root/tmux/vercel-status.sh" || fail "failed Vercel status color is missing"
grep -q 'bg=colour238' "$repo_root/tmux/vercel-status.sh" || fail "unavailable Vercel status color is missing"

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
  nvim --headless --clean >/dev/null 2>&1 &
  nvim_pid=$!
  nvim_label=''
  for _ in {1..20}; do
    nvim_label=$(PATH="$fake_bin:$PATH" "$repo_root/tmux/program-name.sh" "$nvim_pid" "$test_home" ' init.lua')
    if [[ "$nvim_label" == ' init.lua' ]]; then
      break
    fi
    sleep 0.05
  done
  kill "$nvim_pid" 2>/dev/null || true
  wait "$nvim_pid" 2>/dev/null || true
  assert_output "$nvim_label" ' init.lua'
fi

"$repo_root/install" uninstall tmux --yes
[[ ! -e "$XDG_CONFIG_HOME/tmux/tmux.conf" && ! -e "$XDG_CONFIG_HOME/tmux/resource-status.sh" && ! -e "$XDG_CONFIG_HOME/tmux/git-status.sh" && ! -e "$XDG_CONFIG_HOME/tmux/program-name.sh" && ! -e "$XDG_CONFIG_HOME/tmux/codex-status.sh" && ! -e "$XDG_CONFIG_HOME/tmux/codex-usage.sh" && ! -e "$XDG_CONFIG_HOME/tmux/vercel-status.sh" && ! -e "$XDG_CONFIG_HOME/tmux/easy-motion-default.sh" && ! -e "$XDG_CONFIG_HOME/tmux/smart-actions.py" ]] || fail "tmux uninstall failed"
assert_file "$XDG_CONFIG_HOME/nvim/init.lua"
"$repo_root/install" uninstall nvim --yes
[[ ! -e "$XDG_CONFIG_HOME/nvim/init.lua" ]] || fail "nvim uninstall failed"
assert_file "$XDG_CONFIG_HOME/nvim/unrelated.lua"

echo "dotfiles isolated tests passed"
