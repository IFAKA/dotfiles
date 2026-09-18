# Codex usage visibility design

## Context

The tmux status bar invokes `codex-usage.sh` for every window, but the script
currently ignores the pane PID passed by tmux. As a result, Codex capacity is
shown while the active window is an ordinary shell.

## Decision

Keep the status-bar wiring unchanged and make `codex-usage.sh` gate its normal
output on the active pane process tree. The script will recursively inspect the
pane PID and its children, and print nothing unless a process command contains
`codex` (case-insensitive). Internal `--refresh` and `--trigger` modes remain
available to the Codex status watcher and are not subject to this display gate.

## Verification

The shell test suite will cover both an ordinary shell pane, which must produce
no usage output, and a pane whose process is Codex, which must retain the usage
output. Shell syntax and the installer’s tmux copy are also verified.
