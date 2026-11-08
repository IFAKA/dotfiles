---
name: fast-search
description: Run any search, training, tuning, sweep or evaluation by simulation (AI/bot training, self-play leagues, hyperparameter or balance tuning, parameter sweeps, "which size/setting is best", A/B of policies, Monte Carlo checks) the fastest way that keeps accuracy. Use BEFORE starting such a job in any project, and copy the rules into the prompt of every agent you hand such a job to. Not for build or test speed (that is speed-up).
---

# Fast search: spend compute only where the answer is still open

Brute force (every candidate, the same big fixed number of runs) is not allowed. The rules below are a must, not an option.
Each one keeps accuracy, because it skips only runs whose answer is already clear.

## 1. Measure first
Time one candidate at one budget. Print the time per stage (per round, per run, per check) before and after each change.

## 2. The methods (use all that fit)
1. **Successive halving (knock-out rounds, Hyperband).** All candidates get a tiny budget. Keep the best half and double their budget. Repeat.
   Example: 12 mutants at 1, 2, 4 runs is 36 runs instead of 48, and the winner still got the full test.
2. **Common random numbers.** Every candidate runs on the SAME seeds, boards or deals. Compare by paired differences (like
   duplicate poker). The noise drops a lot, so you need far fewer runs.
3. **Sequential stopping.** Run in batches. Stop as soon as a 95 % interval (Wilson, or a paired bootstrap) clearly says in or out.
   Never use a fixed big count.
4. **Use the shape.** If the result against a setting is smooth (size, budget, strength), fit the coarse points. Then search only
   near the knee or the optimum (golden-section or ternary search). Do not fill the whole table.
5. **Warm start.** Start from the current best (mind, weights, parameters), never from scratch.
6. **Build once.** Make the setting a runtime input, not one build per value, when that is a small change.
7. **Parallel, fairly.** Use the free cores of a shared machine (`sysctl -n hw.ncpu`, `uptime`). Leave room for other
   sessions. Keep each PID; never pkill.

## 3. Keep the test honest
- Register the bands and the decision rule in the file header BEFORE the first run. Never loosen them after you see the data.
- Hold-out: choose on train or validation seeds, and report on test seeds that were never used to choose.
- A band smaller than the noise of one seed has no power. Pool the seeds with paired differences and an interval.
  Do not judge it seed by seed.
- Watch for saturation: if every candidate scores near 0 or 1 against the opponent or test, the measure says nothing.
  Make the test harder (a stronger, matched opponent) before you compare.
- When a fair before/after is wanted, run the same amount of work both ways. Otherwise say what part of the speed-up came
  from doing less.

## 4. Delegating
An agent you hand a search or training job to knows none of this. Paste section 2 and section 3 into its prompt, and ask for
the time per stage before and after.
