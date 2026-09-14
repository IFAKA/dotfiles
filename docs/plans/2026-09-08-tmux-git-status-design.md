# tmux Git status design

## Goal

Show compact Git repository information for the pane's current working
directory in the tmux status bar.

## Design

`tmux/git-status.sh` accepts a directory, exits silently when it is not inside
a Git work tree, and prints the current branch (or abbreviated detached
commit). A clean tree shows only the branch; otherwise named counts identify
`conflict`, `staged`, `modified`, and `untracked` changes. Non-zero upstream
divergence is shown with `ahead`/`behind`, and stashes with `stash`. Each status
kind is rendered as its own color-coded segment; filenames are omitted. Long
branch names are truncated to keep the segment compact. Foreground/background
pairs meet a 4.5:1 WCAG AA contrast target for the bold status labels. The
script uses Git and standard shell tools only and never changes repository
state.

`tmux/tmux.conf` renders the script output on the right side of the status bar.
The status segments are emitted in reverse visual order so the branch remains
the far-right anchor: `stash`, `behind`, `ahead`, `untracked`, `modified`,
`staged`, `conflict`, then branch. No divider characters are used; spacing and
contrasting colors provide the separation. The installer manages the script alongside
`tmux.conf`, preserving the existing backup and uninstall behavior.

Tests cover script output for clean, counted changes, stashed, detached, and
non-Git directories, tmux configuration loading, and installation/uninstallation.
