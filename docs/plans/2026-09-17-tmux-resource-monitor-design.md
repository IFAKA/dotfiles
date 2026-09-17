# tmux Resource Monitor Design

## Goal

Make resource pressure glanceable in the tmux status bar while providing a
keyboard-first process manager for deciding whether to keep or terminate a
resource-heavy process.

## UX

- Keep the status bar compact: CPU and memory percentages remain visible even
  when process names are long.
- Bind `C-Space M` to a large popup, analogous to the existing LazyGit popup.
- Run `btop` in the popup with Vim navigation enabled: `j/k` move through
  processes, `h/l` navigate panels, and `g/G` move through lists.
- Keep process termination explicit and inside btop; with Vim navigation,
  `Shift-K` is used for killing the selected process.
- Preserve the existing `C-Space g` LazyGit and `C-Space r` reload bindings.

## Integration

- Add a managed `btop/btop.conf` containing only the Vim-navigation setting;
  btop's built-in layout and help remain the source of truth for other keys.
- Provision `btop` with the tmux component using the existing platform package
  manager flow.
- Copy and back up the btop configuration with the tmux component, and remove
  it through the existing managed-file uninstall path.

## Verification

- Shell syntax checks continue to cover the tmux configuration and scripts.
- Tests verify btop is requested by the tmux installer, the config is managed,
  and the popup binding invokes btop.
- Run the full existing test suite after the change.
