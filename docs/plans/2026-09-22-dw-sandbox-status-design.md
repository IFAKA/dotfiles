# DW sandbox status label

## Decision

Keep the code version in the Dev status label and all Sandbox status labels
except `READY`. Omit it from the Sandbox `READY` label, including its compact
post-ready label.

## Rationale

When a Sandbox is ready, its number is the only status-bar information needed;
the version is normally shared with Dev. During transitional and error states,
retain the version for troubleshooting context.

## Verification

The test suite asserts that Dev retains its version, Sandbox `READY` and its
compact label omit it, and Sandbox transitional/error states retain it.
