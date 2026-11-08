---
name: speed-up
description: Make slow, repeated work fast (builds, test suites, installs, renders, emulator runs, anything you wait on more than about 20 s or run more than twice). Use BEFORE starting such work in any project, when a command is slow, when several agents or worktrees share a machine, or when asked to speed up builds or tests. Gives the checklist, the measure-first loop and the guard.
---

# Speed up slow work: measure, cache, parallelise, guard

Proven on LIGHTKEEP (C, Make, many worktrees): a new worktree's build+checks went from about 152 s wall to about 4 s.

## 0. Rule zero: numbers, not memory
- A question like "why is it slow" is answered from a log or a timer, never from memory. Read the timing file
  first; if there is none, measure first. (Trap: on the Zaragoza ad I named capture as the slow part with no
  number; the measured render was only 86 s and I had said it was big.)
- Paste these rules into every agent prompt that runs slow work. A skill nobody opens does nothing.

## 1. Measure first (never guess)
- Write `speed.sh` (or the project's equivalent): one line out, per-step wall AND CPU seconds (CPU is steadier on a
  shared machine), full log on disk, `--save` writes a tracked base file, `--vs-base` exits 1 if a step is >20% slower.
- Time: cold start (fresh worktree, empty build dir), warm start, incremental rebuild after touching one file,
  the full test run. Save the base BEFORE changing anything.

## 2. Checklist, in order of usual payoff
1. **Shared result cache across worktrees/lanes/agents**: a new checkout must not redo work another one did.
   - Compiles: `ccache` (C/C++/ObjC), `sccache` (Rust/C), one shared CCACHE_DIR outside the worktrees, big max size.
     Guard it so the build still works if the tool is missing. Compile each file separately so each is cacheable
     (a one-call compile of 45 files is one cache entry). Make images depend on headers.
   - Tests/checks: cache a pass under a hash of (test binary or inputs + command line) in a shared dir; atomic writes;
     an env var to force a full run (NOCACHE=1) and use it once before trusting a new cache.
   - Verify: built binaries byte-identical with and without the cache (`cmp`), and across worktree vs fresh copy.
2. **Incremental builds**: dependency tracking (-MMD), no needless rebuilds, no stamp files that always change.
3. **Parallelism**: `-j$(ncpu)`; one test process per core, longest tests first; do not let several agents all run
   full suites at once (the machine is shared: check load first, run long jobs in the background with a PID).
4. **Skip work nobody looks at**: headless/no-draw simulation for frames or steps a test does not inspect; write
   only the diffs in test setup; do not regenerate unchanged fixtures.
5. **Per language**: TypeScript (`tsc --incremental`, `esbuild`/`swc`, `vitest` with threads, project references),
   Python (`pytest -n auto`, `uv` caches, no repeated installs), Node (pnpm store, `npm ci` with cache),
   Docker (layer order: deps before source, BuildKit cache mounts), Rust (`sccache`, `cargo nextest`, shared target dir
   only if flags match), Go/Gradle (build cache, daemon).
6. **Slow end-to-end tests (device, browser, UI)** (proven on Invisible OS: 20 phone scenarios took 139 s, mostly
   waiting for speech; the same flows on the laptop take ~6 s):
   - Split by where a check must run: flow logic on the host in fake time (fake clock + fake slow I/O, ms per test;
     Robolectric/jsdom for platform parts); the device keeps only what needs it (real sound, radio, permissions).
   - Fake the slow output, keep the logic's timing real: an instant voice/animation that logs the same lines and
     reports "done" through the same callback; never shorten the timings under test (click gaps, holds, debounce).
     Keep a few scenarios on the real slow path so the real engine is still proven.
   - Test the real code, not a copy: if host tests must mirror glue lines, move that glue into a class both use.
   - Start each scenario at its state (a debug hook that opens a screen with given data), not by walking there,
     unless the walk is what it tests. Wait on log events, never fixed sleeps; one persistent device connection.
   - Result cache key must include the outside world, not only code: installed build hash + scenario source +
     device/OS fingerprint. Never cache a fail; `--all`/NOCACHE=1 forces a run; full run before a release.
7. **Do less**: run only the focused check while working, the whole suite once at the end; never copy a build dir to a
   new worktree (stale paths); drop dead targets.

## 3. The loop
One change, rerun `speed.sh`, keep it only if a number improves (repeat a surprising number), commit the new base.
Rejected without measurement: -O3 / LTO (they slowed the edit-rebuild loop 5-20x in LIGHTKEEP). Say so in the
notes when something is measured and not taken.

## 4. Guard and record
- Put the rules where agents read them (AGENTS.md: "Build speed" + "Agent prompt rules for builds"): run
  `./speed.sh --vs-base` before and after any build or Makefile change.
- Add what you learned to this skill when you find a new trick or a trap (keep it short, with the number).
