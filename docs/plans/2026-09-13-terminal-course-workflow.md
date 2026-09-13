# Terminal-first Course Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an idempotent macOS course-watching component that installs Yazi, native mpv, and a `course` launcher through the existing dotfiles installer.

**Architecture:** Extend the existing Bash installer with a `course` component. Manage `yazi/yazi.toml`, `mpv/mpv.conf`, and `bin/course`; merge the video opener into an existing Yazi config and preserve a timestamped backup. Do not add Ghostty or tmux settings because the current repo does not manage them and native mpv does not need terminal graphics passthrough.

**Tech Stack:** Bash, Homebrew, Yazi TOML, mpv, existing isolated installer tests.

---

### Task 1: Add managed course configuration and launcher

**Files:** Create `yazi/yazi.toml`, `mpv/mpv.conf`, and `bin/course`.

Add the native blocking mpv opener for `video/*`, mpv hardware-decoding/resume defaults, and a quoted path-aware launcher using `COURSE_DIR` with `~/Documents/Courses` as fallback.

### Task 2: Integrate the component with the existing installer

**Files:** Modify `install`.

Add `course` selection, Homebrew installation of Ghostty plus tmux/yazi/mpv/ffmpeg as needed, idempotent Yazi merge behavior, mpv/helper installation, and managed markers/backups consistent with existing components.

### Task 3: Test and document the workflow

**Files:** Modify `tests/test.sh` and `README.md`.

Exercise dry-run/install/idempotency and a spaced path through a fake Yazi executable. Document bootstrap, install, navigation, controls, and the native-mpv design decision.

### Task 4: Verify the final artifact

Run shell syntax checks, the isolated test suite, TOML parsing where available, and inspect the final diff and installed paths.
