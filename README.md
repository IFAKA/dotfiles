# dotfiles

Small, independent tmux and Neovim configuration for macOS and Linux.

Install the dotfiles components on a new machine:

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
dotfiles install mpv
dotfiles update [tmux|nvim|mpv]
dotfiles uninstall [tmux|nvim|mpv]
dotfiles --dry-run
```

Only files listed by `install` are managed. Existing managed files are copied
to timestamped backups before replacement or removal; unrelated files in the
configuration directories are left alone. tmux does not require Neovim, and
Neovim does not require tmux.

tmux shows the top CPU and memory-consuming processes immediately before Git
information on the right side of the status bar. Git information is for the
active pane's working directory: it displays the branch (or detached commit)
and named, color-coded change counts. Filenames are intentionally omitted so
the status remains stable and glanceable. The stash count is shown when one
exists. Resource figures are sampled every five seconds by default while the
status bar continues refreshing once per second for interactive state. Set
`TMUX_RESOURCE_STATUS_INTERVAL` to change the sampling interval. Reinstall
after pulling changes with:

```bash
dotfiles install tmux --yes
```

Press `C-Space` then `g` from any tmux pane to open LazyGit in a large popup rooted
in that pane's current directory. Close LazyGit to return to the underlying
pane. The tmux installer provisions LazyGit with the same native package
manager used for tmux. Reload an active tmux server with `C-Space` then `r`.

tmux also names windows from the application running in the active pane. For a
Codex pane, the managed helper uses that pane's Codex title and displays the
conversation name, such as
`codex: Show tmux session names`. Other recognized applications receive stable
labels; this keeps simultaneous Codex conversations in the same repository
independent. If no pane title is available, it falls back to the active
working directory in Codex's local session database. Unknown applications use
their executable name. Codex windows also show a compact pane-state icon: `✦`
while idle, a one-character-at-a-time Braille marquee while active, `⚠` when
confirmation appears to be required, and `✓` when ready for the next prompt in
a background window. The completion check disappears while you are viewing
that window.
The managed Neovim setup includes native startup navigation plus `mini.pick`
for fuzzy file, grep, recent-file, and project selection, and `flash.nvim` for
jump motions.

## mpv playback

Install mpv and its managed configuration:

```bash
dotfiles install mpv --yes
dotfiles install course --yes
```

From inside a directory, run `mpv` with no arguments; it will build a recursive
video playlist from the current directory. Passing a directory explicitly works
the same way:

```bash
cd "/path/to/videos"
mpv

mpv "/path/to/videos"
```

Use `g` then `p` to open mpv's built-in searchable playlist picker and select a
video by name. mpv also remembers playback positions, keeps the window
maximized, and does not resize it when changing between videos.

Run `course` to enter the last course you watched under `~/Documents/Courses`
(or `$COURSE_DIR`) and launch its recursive mpv playlist. On the first run, it
uses the most recently modified course directory; deleted courses are skipped.
