#!/usr/bin/env python3 -I
"""Claude Code PreToolUse hook: stop parallel sessions from overwriting each other.
Edit/Write: claim the file for this session; deny if another live session claimed it in the same worktree.
Bash: deny git commands that sweep the whole tree (add -A/., commit -a, checkout/restore/stash/reset --hard/clean)
while another session has a live claim in this worktree. Claims expire after TTL seconds without a touch.
Fix offered every time: `lane new NAME` (own worktree + branch), then `lane land`."""
import json, os, re, subprocess, sys, time, hashlib
TTL = 1800
d = json.load(sys.stdin)
RELEASE = len(sys.argv) > 1 and sys.argv[1] == "release"
sid, cwd, tool, ti = d.get("session_id", "?"), d.get("cwd", "."), d.get("tool_name", ""), d.get("tool_input", {})

def git(*a):
    r = subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None

top = git("rev-parse", "--show-toplevel")
common = git("rev-parse", "--git-common-dir")
if not top or not common:
    sys.exit(0)
common = os.path.realpath(os.path.join(cwd, common))
cdir = os.path.join(common, "claims")
os.makedirs(cdir, exist_ok=True)
now = time.time()

if RELEASE:  # SessionEnd/Stop: drop this session's claims
    for n in os.listdir(cdir):
        try:
            if json.load(open(os.path.join(cdir, n)))["sid"] == sid: os.remove(os.path.join(cdir, n))
        except Exception: pass
    sys.exit(0)

def live_others():
    out = []
    for n in os.listdir(cdir):
        try:
            c = json.load(open(os.path.join(cdir, n)))
        except Exception:
            continue
        if now - c["ts"] > TTL: os.remove(os.path.join(cdir, n)); continue
        if c["sid"] != sid and c["top"] == top: out.append(c)
    return out

def deny(msg):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
        "permissionDecision": "deny", "permissionDecisionReason": msg}}))
    sys.exit(0)

FIX = (" Do not edit around it. Run `lane new <name>` (own worktree + branch, then cd there), work and commit"
       " there, finish with `lane land`. Or ask the user to wait for the other session.")

if tool in ("Edit", "Write", "NotebookEdit"):
    p = os.path.realpath(ti.get("file_path") or ti.get("notebook_path") or "")
    if not p.startswith(top + os.sep): sys.exit(0)
    f = os.path.join(cdir, hashlib.sha1(p.encode()).hexdigest())
    try:
        c = json.load(open(f))
        if c["sid"] != sid and now - c["ts"] <= TTL:
            deny(f"{os.path.relpath(p, top)} is claimed by another Claude session "
                 f"({int(now - c['ts'])}s ago, session {c['sid'][:8]}).{FIX}")
    except FileNotFoundError: pass
    except Exception: pass
    json.dump({"sid": sid, "ts": now, "top": top, "path": p}, open(f + "." + sid[:8], "w"))
    os.replace(f + "." + sid[:8], f)  # atomic: no half-written claim for a racing hook
elif tool == "Bash":
    cmd = ti.get("command", "")
    sweep = re.search(r"\bgit\s+(add\s+(-A|--all|\.|-u)\b|commit\b[^|;&]*\s-\w*a\b|checkout\s+(--\s|\.|-f)|restore\b|stash\b|reset\s+--hard|clean\b)", cmd)
    if sweep:
        o = live_others()
        if o:
            names = ", ".join(sorted({os.path.relpath(c["path"], top) for c in o})[:5])
            deny(f"Tree-wide git command while {len(o)} file(s) are claimed by another session ({names}). "
                 f"Stage/commit only your own files by path (`git commit -m .. -- file1 file2`).{FIX}")
