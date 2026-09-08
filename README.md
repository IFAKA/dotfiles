# dotfiles

Small, independent tmux and Neovim configuration for macOS and Linux.

Install both components on a new machine:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/IFAKA/dotfiles/main/bootstrap)
```

The bootstrap keeps a checkout in `~/.local/share/dotfiles` and installs the
`dotfiles` command in `~/.local/bin`. Add that directory to `PATH` if needed.
Each user has their own checkout, configuration, backups, and package state.

```bash
dotfiles install tmux
dotfiles install nvim
dotfiles install
dotfiles update [tmux|nvim]
dotfiles uninstall [tmux|nvim]
dotfiles --dry-run
```

Only files listed by `install` are managed. Existing managed files are copied
to timestamped backups before replacement or removal; unrelated files in the
configuration directories are left alone. tmux does not require Neovim, and
Neovim does not require tmux.

tmux shows Git information for the active pane's working directory in the
right side of the status bar. It displays the branch (or detached commit), a
clean/dirty marker, and the stash count when one exists. Reinstall after
pulling changes with:

```bash
dotfiles install tmux --yes
```

tmux also names windows from the application running in the active pane. The
managed helper recognizes common applications and maps Codex's Node.js
process to `Codex`; unknown applications use their executable name.
Labels are normalized to lowercase, with spaces replaced by hyphens.
