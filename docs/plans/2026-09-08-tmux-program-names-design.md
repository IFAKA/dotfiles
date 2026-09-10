# tmux automatic program names design

## Goal

Make tmux window labels easier to understand by recognizing the application
behind wrapper processes such as Node.js running Codex.

## Design

tmux keeps automatic window renaming enabled and calls a managed helper with
the active pane PID, working directory, and pane title. The helper walks child
processes, checks recognizable commands first, and returns a short accessible
label. Codex is detected from its command line and uses the pane-local title,
which Codex updates per conversation; this prevents simultaneous Codex panes in
one repository from sharing the newest database title. If the pane title is
unavailable, the helper falls back to the newest matching local session.
Common tools receive stable labels; unknown processes fall back to their
executable name.

The helper must be silent when the PID is invalid or unavailable, work on
macOS and Linux using `ps` and `pgrep`, and remain independent of external
plugins. The installer manages it alongside the tmux configuration and Git
status helper.

## Verification

Shell syntax, installer file management, independent mocked Codex pane-title
lookups, a shell-process fallback, and the existing tmux smoke test cover the
behavior. The active tmux server is reloaded after installation.
