---
name: gap-pipeline
description: The recursive gap method for any non-trivial goal (a design, a feature, a hard or unknown problem, "research online and your own criteria", "fill the gaps", "from idea to alpha"). Not for one-line fixes or plain questions.
---

# The recursive gap pipeline

Goal: reach the end with no gap left, or prove a step is actually impossible. Hard or unknown is not impossible.

## 1. Goal and criteria
- State the goal in one sentence and my own criteria for "done": what must be true, and the command or model
  that checks each one. A criterion with no check is itself a gap.
- Start bias-free: what is the best solution to the goal, not to the current code. No legacy unless there are users.

## 2. Research, then judge
- Look for how others solved it: prior art, docs, papers, postmortems, tools. Cite each source.
- Triangulate: a claim needs two independent sources or a local experiment. One source is a lead, not a fact.
- Synthesis beats any one source: combining the research with my criteria may show a better solution nobody has
  built. Take it, but it must pass a model, a measurement or a check before it is trusted.
- Pick one design. Not a menu.

## 3. Atomic steps
- Break the goal down only until each step has a check you can run (exit 0/1, a number in a band, a screenshot
  you look at). Don't plan every leaf up front: plans go stale and cost tokens.
- Order steps by dependency; run independent steps in parallel when they don't touch the same files.
- Write the step list where it survives the session (PLAN.md, or the project's progress file).

## 4. Do each step; recurse on each gap
For each step: do it, run its check.
- Passes: commit (atomic, what and why), mark it done, next step.
- A gap shows (check fails, criterion unmet, no prior art, a new constraint): treat the gap as a new goal and run
  1-4 on it. Split the step further only now, when it failed. Keep going until the gap is filled or reveals the next.
- Stop rule: a step is **impossible** only with evidence of a hard limit (physics, RAM/CPU budget, a missing API,
  a proof). Otherwise, after 3 truly different approaches fail, write `BLOCKED: <step> - <exact reason, what was
  tried>` in the progress file, then move on to steps that don't depend on it.

## 5. Learn
- After each gap, save what was learned to the project's memory: what worked, what failed and **why** (negative
  results save the next session from repeating them). Update or delete a memory that turned out wrong.
- If a manual action happened twice, turn it into a tool (script with flags, one-line output, log on disk, cached)
  or a skill, so the next recursion is cheaper.

## 6. Report
- The gaps found and what filled each; anything BLOCKED with its reason.
- Plainly: which gaps only real use (the user playing, a real device) can close.
- End with status: done / left / needs me.
