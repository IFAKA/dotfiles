# Smart Ctrl-W in Codex CLI

## Goal

Make `Ctrl-W` perform the existing context-aware deletion while composing a
Codex prompt, without compiling or modifying the official Codex installation.

## Design

Install a small macOS POSIX/C wrapper as `~/.local/bin/codex`. The wrapper
renames the currently installed official command to `codex-native`, starts it
under a pseudo-terminal with `forkpty(3)`, and transparently proxies terminal
input/output.

The proxy keeps a lightweight shadow of the current composer line and cursor.
It tracks printable input, deletion, cursor movement, home/end, common control
keys, and bracketed paste. On `Ctrl-W`, it applies the same backward scanner
rules as the zsh widget and sends only the required number of backspaces to
Codex. Text after the cursor is therefore retained by Codex itself.

When tracking becomes uncertain, the wrapper forwards `Ctrl-W` as the native
key rather than guessing. It never runs while another application is active,
does not use polling or a resident process, and exits with the child Codex
process.

## Installation and rollback

The dotfiles installer compiles the C wrapper with the system compiler, saves
the existing `codex` executable or symlink as `codex-native`, and installs the
wrapper in `~/.local/bin`. Re-running installation updates the wrapper without
replacing the official Codex binary. Uninstall restores the saved command when
possible and removes only files managed by dotfiles.

## Verification

Unit tests exercise the deletion scanner with paths, extensions, URLs, flags,
Docker references, JSON-like text, quotes, escapes, cursor offsets, and suffix
text. Installer tests verify idempotency, native-command preservation, and
cleanup. Shell syntax, C compilation, and `git diff --check` are required.
