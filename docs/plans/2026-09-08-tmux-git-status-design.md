# tmux Git status design

## Goal

Show compact Git repository information for the pane's current working
directory in the tmux status bar.

## Design

`tmux/git-status.sh` accepts a directory, exits silently when it is not inside
a Git work tree, and prints the current branch (or abbreviated detached
commit). A clean tree is marked with `✓`; otherwise compact counts identify
conflicts (`!`), staged changes (`+`), unstaged changes (`~`), and untracked
files (`?`). Non-zero upstream divergence is shown with `↑`/`↓`, and stashes
with `*`. Long branch names are truncated to keep the segment compact. The
script uses Git and standard shell tools only and never changes repository
state.

`tmux/tmux.conf` renders the script output on the right side of the status bar
and refreshes it every five seconds. The installer manages the script alongside
`tmux.conf`, preserving the existing backup and uninstall behavior.

Tests cover script output for clean, counted changes, stashed, detached, and
non-Git directories, tmux configuration loading, and installation/uninstallation.
