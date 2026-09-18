# dotfiles

Small, independent zsh, tmux, DW, btop, Neovim, and mpv configuration for macOS and Linux.

Install the dotfiles components on a new machine:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/IFAKA/dotfiles/main/bootstrap)
```

The bootstrap keeps a checkout in `~/.local/share/dotfiles` and installs the
`dotfiles` command in `~/.local/bin`. Add that directory to `PATH` if needed.
Each user has their own checkout, configuration, backups, and package state.

```bash
dotfiles install tmux
dotfiles install btop
dotfiles install zsh
dotfiles install nvim
dotfiles install
dotfiles install mpv
dotfiles install dw
dotfiles update [tmux|btop|nvim|mpv]
dotfiles uninstall [tmux|btop|nvim|mpv|dw]
dotfiles --dry-run
```

Only files listed by `install` are managed. Existing managed files are copied
to timestamped backups before replacement or removal; unrelated files in the
configuration directories are left alone. tmux does not require Neovim, and
Neovim does not require tmux.

tmux shows Git, Vercel deployment, and Codex usage information followed by compact, color-graded
`CPU MEM` labels at the rightmost edge of the status bar. Each label changes color based
on its current usage; the full process list and process names are available in the btop
popup. Git information is for the
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

The Vercel chip appears only for directories inside a linked project with
`.vercel/project.json`. Its colored triangle icon shows the latest deployment
state and rotates while a deployment is in progress. Checks run asynchronously
and reuse a 30-second
per-project cache; set `TMUX_VERCEL_STATUS_CACHE_DIR` or
`TMUX_VERCEL_STATUS_TTL` to override the cache location or TTL.

## DW environments

Install the global DW launcher with `dotfiles install dw`. It works with a
project that has only its ignored Prophet file `dw.json`; legacy projects may
also keep `dw.dev.json` and `dw.sbx.json`:

```bash
dw              # toggle dev ↔ sbx
dw dev          # select a profile explicitly
dw sbx
dw --print      # print active config with passwords redacted
dw --migrate    # import legacy profiles before removing them
```

For an existing project, run `dw --migrate` while `dw.json`, `dw.dev.json`, and
`dw.sbx.json` still exist. It copies both legacy profiles (and the active
configuration) into `~/.config/dotfiles/dw/` without changing the project.
After verifying the import, you can remove `dw.dev.json` and `dw.sbx.json`;
`dw.json` remains for Prophet.nvim. If a legacy profile is incomplete or has
invalid JSON, migration stops before writing that profile.

If the project has only `dw.json`, the first toggle opens a keyboard form and
stores the Dev/Sandbox profiles outside the repository under
`~/.config/dotfiles/dw/`. The current `dw.json` is preserved before asking for
the target environment's missing values. The form focuses the first missing
field, uses Enter to advance through missing fields, Tab/Shift-Tab to edit any
field, and accepts pasted passwords. Pasting the only missing password submits
immediately; in a Sandbox setup it advances to the next missing field and
submits when that field completes the form. Cancelling leaves `dw.json`
unchanged.

The tmux status bar shows the code version and compact environment label (for
example `version_test 018`). It starts neutral, checks the configured remote
target once per project/target/code version per day, then uses calm dark green
when it is reachable and authenticated or red when it is unavailable or
authentication fails.
Press `C-Space` then `e` to toggle the active pane's project and show the
selected environment. `C-Space` then `d` remains tmux detach.

The right side shows Codex's `5h` and `wk` usage windows only while the active
tmux pane belongs to a Codex window. Codex windows read the same latest cached
value. The API is queried only when a Codex session opens, an action is
required, or a response finishes; status-bar renders only read the cache. The
usage helper comes from
`artischocki/agent-usage-tmux`; before the first refresh it shows an empty
placeholder.

Press `C-Space` then `g` from any tmux pane to open LazyGit in a large popup rooted
in that pane's current directory. Close LazyGit to return to the underlying
pane. The tmux installer provisions LazyGit with the same native package
manager used for tmux. Press `C-Space` then `M` to open the keyboard-first btop
resource monitor in the same style of popup. Its `j/k` process navigation and
`h/l` panel navigation match Vim; `Shift-K` kills the selected process. Reload
an active tmux server with `C-Space` then `r`.

Press `C-Space` then `v`, or `C-Space` then `a`, for the normal EasyMotion copy-mode
overlay. `C-Space` then `[` followed by `Space` reaches the same wrapper from
copy mode. All three entry paths use identical behavior. Lowercase
labels behave exactly as EasyMotion always has. If the final label character is
uppercase, the selection completes and copy mode exits; the selected URL is opened,
a code file or `path:line:column` location is opened in a new tmux Neovim window;
media and other non-code files open with the system default application; and other
useful terminal values (commands, errors, Git references, JSON/code blocks,
timestamps, IPs, or the latest Codex response) are copied. There is no Smart Actions
popup or separate menu. The detector is local and deterministic.

tmux names windows from the active pane. For an ordinary shell pane, it derives
a short name from the current directory only: structural, environment, and
version-like directory components are ignored, and the shortest meaningful
name is retained. For example, `ikp-digi-wcp-custom-sfra` becomes `sfra`.
Opening a file does not change a shell window's name. For a Codex pane, the
managed helper uses that pane's Codex title and displays the
conversation name, such as
`codex: Show tmux session names`. Other recognized applications receive stable
labels; this keeps simultaneous Codex conversations in the same repository
independent. If no pane title is available, it falls back to the active
working directory in Codex's local session database. Unknown applications use
their executable name. Codex windows also show a compact pane-state icon: `✦`
while idle and caught up, a one-character-at-a-time Braille marquee while
active, `⚠` when confirmation appears to be required, and `✓` when ready for
the next prompt in a background window. The completion check disappears while
you are viewing that window.
Neovim windows show `` plus the active file's basename when a file is open,
and update as you move between buffers; unnamed buffers keep the icon-only label.
The managed Neovim setup includes native startup navigation plus `mini.pick`
for fuzzy file, grep, recent-file, and project selection, and `flash.nvim` for
jump motions.

## zsh path editing

Install the managed zsh widget with:

```bash
dotfiles install zsh --yes
```

At an interactive zsh prompt, press `Ctrl-W` to delete the context-aware unit
before the cursor. For example, `metaData/systemObjects/file.xml` becomes
`metaData/systemObjects/`. `Alt-W` is left unbound. The zsh installer adds a
managed source block to `~/.zshrc` and backs up that file before changing it.

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
