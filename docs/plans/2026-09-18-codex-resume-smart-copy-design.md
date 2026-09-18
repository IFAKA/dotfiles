# Codex resume Smart Copy

## Goal

Make a terminal command such as `codex resume 01a0b088-587b-7383-b2dd-bf18fc0eb11b` easy to reuse from tmux Smart Copy.

## Design

Smart Copy will recognize a shell command consisting of `codex resume` followed by a Codex session UUID and expose the complete command as one `codex-resume` target. Selecting any character in that target copies the full command, including `codex resume`, rather than only the session ID.

Existing command, URL, hash, response, and other target detection remains unchanged. Detection is limited to the explicit command shape to avoid treating arbitrary UUIDs as Codex sessions.

## Verification

Tests will verify exact detection and value, including the full command, and retain the existing detector matrix and adversarial cases.
