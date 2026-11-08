---
paths:
  - "**/*.{test,spec}.*"
  - "**/*_test.*"
  - "**/{test,tests,e2e,__tests__,spec}/**"
  - "**/playwright.config.*"
  - "**/{vitest,jest}.config.*"
  - "**/checks.sh"
---

# Tests: atomic and fast

- **Atomic:** one test proves one behaviour. Put the app straight into the state under test (fixture, saved file,
  seeded storage, URL/deep link, API call, Playwright `storageState`); do the one action; assert; stop. Never replay
  the user journey to reach the point under test, and never keep going after the assertion.
- A user flow that must be proven end to end gets one journey test; every step inside it gets its own atomic test.
- **Lowest layer that proves it:** pure function > in-process/headless driver > browser. Use a browser only for what
  only a browser shows (layout, real input, rendering).
- **Fast:** tests are independent so they run in parallel; no fixed sleeps (wait on a condition); fake clocks and
  network; deterministic seeds.
- **Only what changed:** while working, run the focused test for the touched area; cache passed checks by the hash
  of their inputs; the full suite runs before a commit.
- **Fail fast and readable:** fastest checks first; on failure print one line with the cause and the log path.
- A slow test is a bug: measure it, find which step costs the time, and fix that step (state seeding, a lower
  layer, a cache), not the timeout.
