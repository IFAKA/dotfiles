---
name: project-setup
description: Make a repository agent-friendly with the shared layout: AGENTS.md (+ CLAUDE.md importing it), doc roles, one check entry point, fast atomic tests, logs on disk. Use when a project has no AGENTS.md, or when asked to set up, restructure or speed up a project's build and tests.
---

# Project setup: the same shape in every repo

Read the repo first (`krn context --json`), then add only what is missing. Never rewrite working conventions
the project already has; map them onto these roles instead.

## Files
- `CLAUDE.md`: one line, `@AGENTS.md` (Claude Code reads only CLAUDE.md when both exist; the import makes it read
  both, and other agents read AGENTS.md).
- `AGENTS.md`: under 150 lines. Facts an agent needs every session; nothing it can find in a second. Template below.
- `README.md` run it · `DESIGN.md` (or `RULES.md`) what it is now · `PLAN.md` what is being built, its steps ·
  `HISTORY.md` (or `PROGRESS.md`) why, by date. Change DESIGN.md in the same commit as the behaviour it describes.
- Rules that only matter for part of the code go in `.claude/rules/<topic>.md` with `paths:`, not in AGENTS.md.
- Repeated procedures go in `.claude/skills/<name>/SKILL.md`.

## AGENTS.md template
```markdown
# <Project> (for AI agents and people)
Read this first, then only the files your task names.

## What is here
<2-5 lines: what it is, the main directories, which doc says what>

## Build and check
- `<check>`: fast, only what changed (cached by input hash). Run while working.
- `<check-all>`: everything; run before a commit. One line per check, logs in `<log dir>/`.
- `<run>`: start it. `<shots>`: screenshot every screen to a folder.
| You changed | Run |
|---|---|
| <area> | <its focused check> |

## Find your way
<where each kind of code lives; the one command that lists files with their first comment>

## Rules (enforced by <lint/check> where possible)
- <the project's real invariants; each one with the check that refuses it>
- Commits: one change per commit, message says what and why.
```

## Tooling rules
- One entry point (`make`, `./init.sh`, `npm run`) with the same verbs everywhere: check, check-all, run, shots.
- Every script prints ONE summary line; details go to a log file. Exit 1 on failure.
- Cache deterministic slow steps by input hash (`krn exec --cache` or the build system's own cache).
- Generated, vendored and log files: list them in AGENTS.md as "never read whole; query them".
- If anything is performance-sensitive, give AGENTS.md an `## Optimize` section (measure/prove/hot/protect; see the `optimize` skill).
- A number that tunes behaviour comes from a model or simulation with a check, before/after recorded.
- Saved user data keeps loading after changes (versioned or append-only formats).

## Files and code size
- One purpose per file, named after that purpose, so an agent finds it by name. Length follows the purpose:
  no hard cap, and never split a file only to hit a number (scattered code costs more reads than long code).
- Past ~1,000 lines, check whether the file has two jobs; if so, split along that line. Many sessions editing the
  same big file is also a reason to split.
- The file's first comment says what it is; its API lives in a header or index the agent can read instead of
  the body. Agents read ranges (search, then the lines they need), so what makes a file cheap is being easy to
  find and having stable names, not being short.

## Speed (build and tests are where the time goes)
- Incremental builds that use every core; measure the slowest step before optimising, then fix that one.
- Tests follow `~/.claude/rules/testing.md`: atomic, start in the state under test, parallel, only what changed.
- If a check is slow because of its layer (a browser, a full app boot), add a lower-level driver: an in-process
  or headless harness that calls the same code directly.
