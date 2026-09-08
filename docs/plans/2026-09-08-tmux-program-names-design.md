# tmux automatic program names design

## Goal

Make tmux window labels easier to understand by recognizing the application
behind wrapper processes such as Node.js running Codex.

## Design

tmux keeps automatic window renaming enabled and calls a managed helper with
the active pane PID. The helper walks child processes, checks recognizable
commands first, and returns a short accessible label. Codex is detected from
its command line and displayed as `Codex`; common tools receive stable labels;
unknown processes fall back to their executable name.

The helper must be silent when the PID is invalid or unavailable, work on
macOS and Linux using `ps` and `pgrep`, and remain independent of external
plugins. The installer manages it alongside the tmux configuration and Git
status helper.

## Verification

Shell syntax, installer file management, a shell-process fallback, and the
existing tmux smoke test cover the behavior. The active tmux server is
reloaded after installation.
