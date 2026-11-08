#!/usr/bin/env python3
# Remembers which Claude chat runs in each tmux pane, and reopens it after a tmux restore.
# Modes: record (SessionStart hook), forget (SessionEnd hook), restore (tmux post-restore hook).
import json
import os
import subprocess
import sys
import time
from pathlib import Path

STATE = Path(os.environ.get("CLAUDE_PANES_DIR", str(Path.home() / ".local/state/claude-panes")))
SHELLS = {"zsh", "bash", "sh", "fish", "-zsh", "-bash", "-sh"}


def tmux(*args):
    r = subprocess.run(["tmux", *args], capture_output=True, text=True)
    return r.returncode, r.stdout.strip()


def pane_target(pane_id):
    # session:window.pane index. A tmux restore recreates panes with the same indexes.
    code, out = tmux("display-message", "-p", "-t", pane_id, "#{session_name}:#{window_index}.#{pane_index}")
    return out if code == 0 else ""


def slot_file(target):
    return STATE / (target.replace(":", "_").replace(".", "-") + ".json")


def hook_input():
    try:
        return json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return {}


def record():
    data = hook_input()
    pane = os.environ.get("TMUX_PANE", "")
    sid = data.get("session_id", "")
    if not pane or not sid:
        return
    target = pane_target(pane)
    if not target:
        return
    STATE.mkdir(parents=True, exist_ok=True)
    slot = {"target": target, "session_id": sid, "cwd": data.get("cwd", ""),
            "time": time.strftime("%Y-%m-%d %H:%M:%S")}
    slot_file(target).write_text(json.dumps(slot))


def forget():
    # Only a clean exit removes the entry. After a crash the entry stays, so restore can use it.
    data = hook_input()
    pane = os.environ.get("TMUX_PANE", "")
    target = pane_target(pane) if pane else ""
    f = slot_file(target) if target else None
    if f and f.exists() and json.loads(f.read_text()).get("session_id") == data.get("session_id"):
        f.unlink()


def restore():
    time.sleep(3)  # give the restored shells a moment to start
    STATE.mkdir(parents=True, exist_ok=True)
    log = STATE / "restore.log"
    done = skipped = 0
    for f in sorted(STATE.glob("*.json")):
        slot = json.loads(f.read_text())
        target = slot["target"]
        code, cmd = tmux("display-message", "-p", "-t", target, "#{pane_current_command}")
        if code != 0 or cmd not in SHELLS:
            skipped += 1
            with log.open("a") as fh:
                fh.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} skip {target} (pane={cmd or 'missing'})\n")
            continue
        tmux("send-keys", "-t", target, f"claude --resume {slot['session_id']}", "Enter")
        done += 1
        with log.open("a") as fh:
            fh.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} resume {target} {slot['session_id']} in {slot['cwd']}\n")
    print(f"claude-panes: resumed {done}, skipped {skipped} (details in {log})")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    {"record": record, "forget": forget, "restore": restore}.get(mode, lambda: None)()
