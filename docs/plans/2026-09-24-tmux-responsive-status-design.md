# Responsive tmux status bar design

## Goal

Keep the existing one-line tmux status bar at normal widths, but move the
right-side environment indicators to a second line when the client becomes
narrow enough that the status bar is likely to be truncated.

## Design

- Keep the existing session and window list as the first status line.
- Keep the right-side indicator commands directly in each status format so
  tmux executes their `#(...)` commands instead of treating them as literal
  text.
- In the one-line layout, render the indicators on line 1.
- In the two-line layout, suppress it on line 1 and add a right-aligned
  `status-format[1]` line.
- A small shell helper compares `#{client_width}` with a configurable
  `@status-overflow-width` threshold and toggles `@dotfiles-status-overflow`.
- The helper runs on client attach and resize, and the threshold defaults to
  160 columns. The existing status interval continues to refresh dynamic
  indicators.

## Failure handling and compatibility

If the helper cannot run, tmux keeps the default one-line layout. The existing
status scripts are not changed. The second format line is removed when the
client is wide again, so terminal height is only consumed while needed.

## Validation

- Shell syntax-check the helper.
- Load the configuration in an isolated tmux server with plugins disabled.
- Verify one-line and two-line transitions at widths above and below the
  threshold.
- Run the repository test suite.
