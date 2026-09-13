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
clean/dirty marker, compact change counts, and up to three changed filenames
without their paths when the worktree is dirty. The stash count is shown when
one exists. Reinstall after pulling changes with:

```bash
dotfiles install tmux --yes
```

tmux also names windows from the application running in the active pane. For a
Codex pane, the managed helper uses that pane's Codex title and displays the
conversation name, such as
`codex: Show tmux session names`. Other recognized applications receive stable
labels; this keeps simultaneous Codex conversations in the same repository
independent. If no pane title is available, it falls back to the active
working directory in Codex's local session database. Unknown applications use
their executable name. Codex windows also show
a compact pane-state icon: an animated single-character Braille spinner while
active, `⚠` when confirmation appears to be required, `✓` when ready for the
next prompt in a background window, and nothing when there is no active state.
The completion check disappears while you are viewing that window.
The managed Neovim setup includes native startup navigation plus `mini.pick`
for fuzzy file, grep, recent-file, and project selection, and `flash.nvim` for
jump motions.

## Terminal-first course workflow

Install the course workflow and its Homebrew dependencies on macOS:

```bash
dotfiles install course --yes
```

This installs Ghostty, tmux, mpv, and ffmpeg when they are missing. The
workflow uses native, maximized mpv for smooth GPU-accelerated playback; Kitty
inline video is intentionally not configured because it became laggy at useful
viewport sizes and was less efficient.

The normal workflow selects a course and opens every supported video beneath
it as one native mpv playlist, including nested `BONUSES` and `AUDIO` folders:

```bash
course
course <query>
course "/path/to/course"
```

With multiple courses, `course` shows a small selector with discovered video
counts and remembers the last course. It restores the last played lesson when
possible. `course <query>` filters course names, while an explicit directory
still opens directly. mpv uses native `--playlist-start=auto` and watch-later
files to resume the last video and timestamp. State is stored atomically
outside the course folders at `~/.local/state/course/state.json` (or
`$XDG_STATE_HOME`), and
downloaded courses are never modified.

The thin `course-play` wrapper records the current video and marks it complete
only after roughly 90% playback plus a minimum amount of continuous watching;
mpv remains responsible for timestamp resume through its native watch-later
files. Seeking near the end briefly will not count as completion.

Set `COURSE_DIR` to change the default directory. In mpv, `Enter` advances to
the next lesson, `Space` pauses/plays, `Left/Right` seeks, `Up/Down` seek
farther, `[` and `]` change playback speed, `Backspace` resets speed, `f`
toggles fullscreen, and `q` quits. mpv saves playback positions. All `.mp4`
files remain eligible lessons; `AUDIO` is not silently discarded and `BONUSES`
remains in playlist order.
