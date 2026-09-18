# tmux Git status unified background design

## Goal

Make the Git status segment read as one compact unit alongside the branch name.

## Design

`tmux/git-status.sh` keeps the existing status categories and symbols, but renders
the complete Git segment with the branch's `colour24` background. Each status is
shown compactly as a symbol immediately followed by its count (`~3`, not `~ 3`).
Symbols use semantic foreground colors while counts use a consistent high-contrast
foreground, preserving glanceable meaning without breaking the unified background.
The branch remains the rightmost item and existing ordering, truncation, and empty
state behavior remain unchanged.

## Verification

Update shell assertions for symbols, compact formatting, the shared background, and
symbol/count foreground styling. Run the full test script and shell syntax checks.
