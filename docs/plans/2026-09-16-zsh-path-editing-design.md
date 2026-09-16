# zsh path editing design

## Goal

Provide a repeatable zsh shortcut that deletes only the path component before
the cursor while preserving the normal `Ctrl-W` behavior.

## Design

The repository owns a small zsh widget at `zsh/path-navigation.zsh`. The widget
binds `Alt-W` (`^[w`) in zsh's Emacs keymap and updates the interactive command
buffer without changing the current working directory or executing the command.

The installer exposes a `zsh` component. It copies the widget into the user's
XDG config directory and adds a marked source block to `~/.zshrc`. Existing
`.zshrc` content is backed up before the block is added. Installation is
idempotent, and uninstall removes only the marked block and managed widget.

The behavior is intentionally scoped to interactive zsh line editing. Terminal
applications such as Codex receive their own key events and are not changed by
this zsh widget.

## Verification

The test suite checks shell syntax, dry-run output, installation, source-block
idempotency, widget behavior, and uninstall cleanup.
