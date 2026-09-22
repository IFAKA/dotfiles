# DW sandbox status label

## Decision

Keep the code version in the Dev status label. Omit it from all Sandbox status
labels, including transient lifecycle states and the compact post-terminal-state
label.

## Rationale

The version is normally shared with Dev and consumes scarce tmux status-bar
space without helping distinguish a selected Sandbox. The Sandbox number and
lifecycle state remain the actionable information.

## Verification

The test suite asserts that Dev retains its version and Sandbox `CHECKING`,
`READY`, and compact terminal labels do not expose it.
