#!/usr/bin/env python3
"""PreToolUse hook, all projects: talk to the other Claude sessions in the same repo BEFORE changing anything.
SendMessage: remember that this session told its peers (marker per session). Edit/Write/NotebookEdit, or Bash `lane new`,
`git commit`, `sed -i`: if other live Claude sessions work in the same git repo (any worktree/lane: same git common dir)
and this session has sent no SendMessage yet, deny once with who they are. One message opens the gate; replies are not awaited."""
import glob, json, os, re, subprocess, sys
d = json.load(sys.stdin)
sid, cwd, tool, ti = d.get("session_id", ""), d.get("cwd", "."), d.get("tool_name", ""), d.get("tool_input") or {}
M = os.path.expanduser(f"~/.claude/coord/{sid}")
def common(dirpath):
    r = subprocess.run(["git", "-C", dirpath, "rev-parse", "--git-common-dir"], capture_output=True, text=True)
    return os.path.realpath(os.path.join(dirpath, r.stdout.strip())) if r.returncode == 0 else None
def project(dirpath):   # same project = same git repo (any worktree/lane); outside git = the same directory
    return common(dirpath) or os.path.realpath(dirpath)
def session_cwd(to):    # SendMessage target (name, pid, socket path or session id) -> its cwd, or None
    for f in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try: j = json.load(open(f))
        except Exception: continue
        if to in (j.get("name"), j.get("sessionId"), str(j.get("pid")), j.get("messagingSocketPath"), "uds:" + str(j.get("messagingSocketPath"))):
            return j.get("cwd")
if tool == "SendMessage":
    tc = session_cwd(str(ti.get("to", "")))
    if tc and os.path.isdir(tc) and project(tc) != project(cwd):
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason":
            f"BLOCKED: {ti.get('to')} works in another project ({tc}); you are in {cwd}. Only message sessions of the same project (same git repo, or the same directory outside git). Do not send this message."}}))
        sys.exit(0)
    os.makedirs(os.path.dirname(M), exist_ok=True); open(M, "a").write(str(ti.get("to", "")) + "\n"); sys.exit(0)
if os.path.exists(M): sys.exit(0)
if tool == "Bash" and not re.search(r"\blane\s+new\b|\bgit\s+commit\b|\bsed\s+-i\b", ti.get("command", "")): sys.exit(0)
path = ti.get("file_path") or ti.get("notebook_path") or ""
here = os.path.dirname(os.path.realpath(path)) if path else cwd
mine = common(here)
if not mine: sys.exit(0)
me, p = None, os.getppid()   # this session's claude process
for _ in range(8):
    out = subprocess.run(["ps", "-o", "ppid=,comm=", "-p", str(p)], capture_output=True, text=True).stdout.split(None, 1)
    if len(out) < 2: break
    if out[1].strip().endswith("claude"): me = p; break
    p = int(out[0])
others = []
for s in glob.glob("/tmp/cc-socks/*.sock"):
    try: pid = int(os.path.basename(s)[:-5])
    except ValueError: continue
    if pid == me: continue
    try: os.kill(pid, 0)
    except Exception: continue
    o = subprocess.run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], capture_output=True, text=True).stdout
    c = next((l[1:] for l in o.splitlines() if l.startswith("n")), None)
    if c and os.path.isdir(c) and common(c) == mine: others.append(f"pid {pid} in {c}")
if not others: sys.exit(0)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason":
    f"Other Claude sessions work in this repo ({'; '.join(others)}). Before your first change: ListAgents, then SendMessage each of them "
    "what you will change (files, branch/lane) and ask them to say if it clashes. Then retry; you need not wait for replies."}}))
