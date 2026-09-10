# Fast Braille Spinner Design

## Goal

Make the Codex Braille activity indicator animate at a normal terminal-spinner
speed instead of advancing only once per second.

## Design

Keep the existing Braille frame set and tmux `status-interval 1` setting for
ordinary status updates. When the status script detects an active Codex turn,
it starts one lightweight background refresher for that window's state file.
The refresher calls `tmux refresh-client -S` every 100 ms while the state says
the turn is busy, causing the existing `#()` status command to be reevaluated.
It exits automatically when the busy state clears or tmux is unavailable.

The state file gains a watcher PID field. Startup is guarded so repeated tmux
refreshes do not create multiple refresher processes. Existing notification
and busy-state behavior remains unchanged.

## Verification

Run the isolated shell test suite and shell syntax checks. Confirm the working
tree changes are limited to the spinner implementation and this design note;
preserve unrelated user edits.
