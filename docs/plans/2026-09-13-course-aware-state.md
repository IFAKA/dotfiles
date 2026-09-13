# Course-Aware State Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `course` discover courses, restore the last course and lesson, and maintain minimal external progress state while preserving Yazi and mpv as the browser and player.

**Architecture:** Replace the launcher’s shell-only path forwarding with a Python standard-library command that discovers immediate child directories, provides a small keyboard selector, stores atomic JSON under XDG state, and launches Yazi at the saved lesson. Add a thin blocking mpv wrapper that records the active lesson and marks it complete only after sufficient forward playback near the end; use mpv’s native watch-later state for timestamps.

**Tech Stack:** Python 3 standard library, Bash installer, Yazi TOML, mpv.

---

### Task 1: Add stateful course launcher and playback wrapper

**Files:** Modify `bin/course`; Create `bin/course-play`.

Implement automatic discovery, single-course bypass, selector/query behavior, current-lesson restoration, atomic JSON state, deleted/moved lesson tolerance, and a blocking mpv wrapper with conservative completion detection.

### Task 2: Integrate managed files and maximize mpv

**Files:** Modify `install`, `yazi/yazi.toml`, `mpv/mpv.conf`.

Install the new wrapper, update the Yazi opener to call it, preserve migration/idempotency, and enable native mpv window maximization.

### Task 3: Add fixture coverage and concise documentation

**Files:** Modify `tests/test.sh`, `README.md`.

Cover zero/one/multiple courses, spaces, nested videos, new/deleted entries, persisted state, progress, query selection, path overrides, and native mpv configuration. Document the automatic state behavior and completion limitation.

### Task 4: Verify against real local courses

Run syntax checks, fixture tests, TOML parsing, mpv option validation, installer idempotency, and a read-only launch/discovery check against `~/Documents/Courses` without modifying course contents.
