<!-- KRN:BEGIN -->
KRn (`krn`, in any Git repo) does exact, cheap repository work; you keep the reasoning.
- Search by plain words: `krn find QUERY --json --max-files N` before reading many files or repeating grep.
- Mechanical edits: `krn code replace|insert-before|insert-after|remove --file PATH --pattern P --content TEXT [--lang L]`
  (ast-grep pattern; `--literal` for exact text; must match once; content is verbatim).
- Repeated deterministic commands: `krn exec --cache --input PATH -- CMD` (no shell; wrap pipes in `sh -c`).
<!-- KRN:END -->

## Working method and project conventions
- For any non-trivial goal (a design, a feature, a hard problem; not a one-line fix or a plain question), use the
  `gap-pipeline` skill: criteria + research, atomic steps, recurse on every gap, record what worked and what failed.
- When a project has no AGENTS.md, or I ask to set one up or make it agent-friendly, use the `project-setup` skill.
- The second time you do something by hand, make it a script or skill (flags, one-line output, log on disk, cached).
- Before running slow or repeated work (builds, test suites, installs, renders, emulators; anything over ~20 s or run
  more than twice) use the `speed-up` skill: measure first, share caches across worktrees, parallelise, guard with a
  one-line timing script. If you wait on the same slow command twice, stop and speed it up.
- For any search, training, tuning, sweep or evaluation by simulation (bots, leagues, balance, "which setting is best") use
  the `fast-search` skill: no brute force; halving, same seeds, early stop, warm start; put it in every delegated prompt.
- For performance work (make it faster, cut cycles) use the `optimize` skill and the `opt` tool; a project declares
  measure/prove/hot/protect in its AGENTS.md `## Optimize` section.
- Context is the budget: load only what the task needs. Procedures live in skills, path-specific rules in
  `.claude/rules/` with `paths:`. Every token in context is re-read on every later turn (measured: that re-reading
  is ~70% of usage). So: if answering needs more than ~3 files or ~300 lines you won't edit, send it to the `reader`
  agent and read yourself only the `edit-targets` it returns; read line ranges, not whole files.

## How I want you to work (from my prompt history)
- **Who I am:** `~/.claude/me.md` is a model of me (how I think, what I love and quit, real-life needs). Read it
  before designing anything for me (games, tools, workflows) or when a choice depends on my taste; not for routine
  code tasks. Update it when I correct something about myself.
- **Implementation runs on Sonnet, not Opus.** Opus (the main session) does design, judgement and review; building
  is delegated to `Agent` with `model: "sonnet"` (default subagent model is sonnet via settings env
  `CLAUDE_CODE_SUBAGENT_MODEL`). Never use `fork` for implementation: a fork always inherits the parent model.
  A fresh agent has no context, so its prompt must be self-contained (repo path, rules, the task, how to check it).
- **Don't stop for confirmation** when the next step is clear and can be undone; do it. Ask only for real decisions,
  and give one recommendation with the ask, never a menu.
- **Plain words.** English is not my first language: use simple, common English words, short sentences (one idea
  each), no idioms, no rare words, and less text. No jargon, define any term you must use, use concrete examples. If I say
  "wdym"/"eh?"/"i dont get it", explain it again differently and more simply, don't just repeat it.
  How I understand best (learned from explaining a code change; applies to any topic):
  1. Start with the problem and why it matters, in everyday terms, before any mechanism or code.
  2. Use one small everyday picture (a school, a kitchen, a queue), then map each part of it to the real
     thing, one line each ("the school is X, a class is Y"). A picture without the mapping does not help me.
  3. Name the real object concretely: what exactly it is in this project (what was counted, what was slow),
     not a category word.
  4. Code or a diff alone does not explain. Give a tiny made-up example with small numbers first (10 rows,
     frame 1, 2, 3), then tie each real piece of code to a step of it ("this function is step 2").
  5. If I still don't get it, change the form (picture, tiny example, before/after, mapping), shrink to one
     part, and drop the technical words I did not use. Never restate the same text.
  6. When your first idea was wrong, say so in one line ("I guessed X; it was Y").
- **A question is not an order.** If I ask something, answer it; change nothing. "dont make changes yet" means
  read-only until I say go.
- **Never say "can't", "no room" or "not possible" without the recursive gap pass.** A limit (RAM, CPU, ids, bits,
  format) is a gap to recurse on: look for where else the resource is (flash vs RAM, computed vs stored, reuse), how
  others solved it, and what it would cost. Only after real approaches fail, state it as a limit, with what was tried.
  When reporting what is not done yet, say "not built yet" and the path, not "can't".
- **Verify before saying done.** Run it, test it, and for anything visual take a screenshot or render and look at it
  yourself. Don't make me the tester. If you couldn't check something, say so.
- **End every reply with status:** done / what's left / what needs me (one line each). The "What needs me" line is
  also read aloud by my earbud (Invisible OS): at most 12 words, plain, and put the reply I can send in quotes,
  e.g. `What needs me: say "go" for the design doc.` or `What needs me: nothing.`
- **Commits:** after a change passes its checks, commit it as an atomic commit (one change, message says what and why)
  without asking. Commit only files you changed. Push only when I ask.
- **Parallel sessions:** other Claude sessions may be editing the same repo. Check before committing, never commit
  or revert another session's changes, and if I say "hold", wait until the other one is done.
- **The usage pace guard is not a stop.** Work frugally when it warns, but never pause or ask because of it.
- **My typos:** I type fast. Read for intent; don't ask about spelling.
- **Default ambition:** best, not cheapest. Start without bias toward what already exists. No legacy constraints
  unless I say there are users. Think like a quant researcher taking an idea to alpha (max signal, measured, positive
  expected value). Once the design and plan are clear, build all of it without stopping.

## Parallel sessions (enforced by ~/.claude/bin/claims.py hook; tool: ~/.claude/bin/lane)
- Many Claude sessions may share one repo. One working tree = one index = one branch, so they overwrite each other.
- Never edit or commit in a repo's main worktree (enforced by `~/.claude/bin/main_guard.py`; opt out per repo only if I ask:
  `git config lane.allowmain true`). Work in your own worktree. Use `EnterWorktree` (or `claude -w`), or
  `~/.claude/bin/lane new <task>` (branches from the current HEAD, so unpushed commits are included). Commit only there.
- Finish with `~/.claude/bin/lane land` from the worktree: it rebases on the base branch, runs `git config lane.check`
  (this repo: `make test-lk`), and fast-forwards the base under a lock. A conflict or failed check stops it; fix and rerun.
- Cleanup: `lane new` runs `lane gc` first; `lane gc` drops lanes that are merged, older than 1 day, with no process in them and no edits. After `lane land`, run `lane drop <name>` when you are done with the lane. Never delete a lane by hand with `rm`.
- The phone is shared too (any project). It has ONE lease per Claude session: `~/.claude/bin/phone take MIN WHY` / `release` /
  `status`. Enforced: the `adb` shim (`~/.local/bin/adb`) takes or refuses the lease for every command that changes the phone
  (install, am, input, push...), and the `device_guard.py` hook does the same for gradle install. It also blocks full-path adb
  and faking or removing the lease. If BLOCKED, ask the holder with SendMessage; never force it. Build from a tree with master's
  latest commits: another session's dev hook lives only on master, so a stale build removes it.
- Talk before you change (enforced by `~/.claude/bin/coord.py`): if other live Claude sessions work in the same repo,
  your first change (Edit/Write, `lane new`, `git commit`, `sed -i`) is denied until you SendMessage them what you will
  change (files, lane). One message per session opens it; do not wait for replies.
- Talk only to sessions in the same project (same git repo, any worktree or lane; outside git, the same directory). `coord.py` now blocks SendMessage to any other project, also from a parent dir like `hardware` to the nested repo `invisible-os`. Never SendMessage a session from another
  project, even if ListAgents shows it; it has no context for your work and your message only distracts it.
- Lanes cost disk: an invisible-os lane is ~800 MB (its own app/os/build); 27 lanes were 22 GB. After `lane land`, always run
  `lane drop <name>`, and `lane gc` at the end of a task. If drop refuses because of dirt, look at it: if it is only regenerable
  (e.g. untracked `sound/tell/`), `git worktree remove --force` it. Reuse an idle merged lane instead of opening a new one.
- Hot shared files (lightkeep.h, tally.c, DESIGN.md) are merged by landing, not locked. Claims end with the session.
- If the hook denies an edit ("claimed by another session"), do not retry or work around it: make a lane.
- Never `git add -A`/`commit -a`/`stash`/`checkout --`/`restore`/`reset --hard` in a shared tree; commit files by path.
- Lanes split files, not processes: every session shares one process table. Never `pkill`/`killall`/`pgrep -f` by name or
  pattern (a `checks.sh` or `make` in another lane matches too). Run long jobs with `run_in_background`, keep the PID,
  and stop only that PID (`kill <pid>`, or TaskStop). Before killing, check its working directory (`lsof -p <pid> | grep cwd`).
  Waiting on "no checks.sh running" also waits on other sessions' runs: wait on your own task instead.
- Heavy jobs (bench, sweep, many workers): before you start one, look for a copy already running
  (`ps -axo pid,etime,command | grep NAME`, by eye, never to kill). Start it with `nice -n 15` and
  `run_in_background`. Worker pools use at most half the cores and must exit when the parent dies. At the end of
  your task, check that no worker of yours is left (`ps -axo pid,ppid,command`, PPID 1 means orphan).
- **Messages to send (email, chat, post):** make the message stand out with a bold label line above it (e.g. `**Reply to send on Reddit:**`), then a horizontal rule (`---`), then the message as plain text lines, then another `---`. No `>` quote, no `|` bar or other mark on the left side, no code fence, no list bullets inside the message. Put any note outside the message, before or after it. Never put a status or "What needs me" line between the label and the message.
