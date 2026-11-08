---
name: optimize
description: Performance work in any project - "make it faster", profile/optimize loops, cutting cycles, time or memory over many small changes. Not for one-off tweaks. Uses the `opt` tool (stopwatch and judge) and the project's `## Optimize` section in AGENTS.md.
---

# Optimize: measure, zoom into the hottest box, one change, keep only if better

Heat camera idea: a flame graph shows time as width. Find the widest box, zoom into it, change that. A function that
calls itself is another zoom, not a new problem. Never optimize a thin box.

`~/.claude/bin/opt` measures and judges; it never edits source. You (or a Sonnet agent) make the edits.

## Loop
1. `opt init`: baseline median, noise band, protect hashes. Log goes to `<repo>/.opt/` (add it to .gitignore).
2. `opt hot`: top 10 hotspots plus `unaccounted: X%`. If X > 5%, fix the measuring first, then continue.
3. ONE change aimed at the top line. Nothing else in the same edit.
4. `opt try --note "what I changed"`: runs `prove`, then `measure` N times. ACCEPT only if the median beats the noise
   band and no scene got worse. REJECT prints the exact `git checkout -- files` to undo; run it yourself.
5. ACCEPT: commit that change alone, numbers in the message (`before->after unit`). Then `opt hot` again (heat moves).
6. `opt stop?` after every try. It says STOP or CONTINUE. `opt budget N` caps the number of tries.
7. `opt final`: fresh 2x-repeat measure against the ORIGINAL baseline. Best-of-many is optimistic; say so.

## Rules
- Shared repo: work in a lane/worktree. Implementation by Agent with `model: "sonnet"`; the main model judges.
- Give the editing agent ONLY the top-10 `opt hot` output and the one target, never a raw profile.
- One change per try. Never edit `protect` files (measure/prove scripts, tests); `opt try` refuses if they changed.
- Keep the 2-3 best rejected-but-close patches (branch or note in the log); return to them when stalled. On a stall
  `opt stop?` asks for a different kind of change (algorithm, not micro-tweak) or another hotspot.
- A proxy number (instruction count, simulator cycles) must be confirmed once by the real number `measure` names.
- At the end do an anti-cheat review of the diff: caching inside the measured loop, removed work, special-cased inputs.
- Report what was NOT measured (real hardware, other inputs, memory, cold start).

## Add `## Optimize` to a project (in AGENTS.md)
```markdown
## Optimize
- measure: `./bench.sh`   (last stdout line: one number, lower is better; or JSON {"total":N,"scenes":{"a":N}})
- prove: `./check.sh`     (exit 0 = behaviour unchanged: tests, or byte-exact output compare)
- scene_tol: `0.3`  (optional, percent: one scene may get this much worse if the total gains; for deterministic simulators where code layout shifts move a scene a little. Default 0)
- hot: `./profile.sh`     (optional; lines "<self_pct> <path;a;b;c>", then optionally "unaccounted <pct>"; a "total" line is ignored)
- protect: bench.sh check.sh tests/   (paths the agent must not edit)
- unit: cycles
- repeats: 5
```
Prefer a deterministic measure (instruction or cycle count, simulator): noise 0 means any real gain counts.
