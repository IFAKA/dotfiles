# Git status numeric display

## Goal

Keep the Git branch name visible in tmux while making status categories glanceable through color and counts alone.

## Design

The existing status categories and colors remain unchanged. Their symbolic labels (`!`, `+`, `~`, `?`, `↑`, `↓`, `⚑`) are removed; each colored segment displays only its numeric count. Segment ordering, spacing, branch truncation, and empty-state behavior remain unchanged.

## Verification

Update the shell tests to assert numeric-only output, preserve color assertions, and run the full test script plus `bash -n` for the status script.
