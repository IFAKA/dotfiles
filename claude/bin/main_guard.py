#!/usr/bin/env python3 -I
"""Claude Code PreToolUse hook: never work in a repo's main worktree (the shared tree, where `lane` takes its base).
Edit/Write/NotebookEdit: deny when the target file is inside a main worktree.
Bash: deny changing git commands (commit, merge, cherry-pick, revert, am, apply, rebase, pull) and `sed -i` run there.
Allowed: `lane ...` (lane new/land/drop/gc), read-only git, files outside git, repos with no commit yet,
and repos that opt out with `git config lane.allowmain true`.
Fix offered: `lane new <task>` (own worktree + branch from the current HEAD), work there, then `lane land`."""
import json, os, re, subprocess, sys
d = json.load(sys.stdin)
cwd, tool, ti = d.get("cwd", "."), d.get("tool_name", ""), d.get("tool_input", {})

def git(where, *a):
    r = subprocess.run(["git", "-C", where, *a], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None

def main_tree(where):
    """Top of the main worktree if `where` is inside one (and guarded), else None."""
    while where and not os.path.isdir(where): where = os.path.dirname(where)
    if not where: return None
    gd, cd = git(where, "rev-parse", "--absolute-git-dir"), git(where, "rev-parse", "--git-common-dir")
    if not gd or not cd: return None
    if os.path.realpath(gd) != os.path.realpath(os.path.join(where, cd)): return None  # a linked worktree (lane): fine
    if git(where, "rev-parse", "--verify", "-q", "HEAD") is None: return None  # no commit yet: first commit is allowed
    if (git(where, "config", "--bool", "lane.allowmain") or "") == "true": return None
    return git(where, "rev-parse", "--show-toplevel")

def deny(top, what):
    b = git(top, "symbolic-ref", "--short", "-q", "HEAD") or "detached"
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": f"{what} in the main worktree {top} (branch {b}) is not allowed: other sessions share it."
        " Run `~/.claude/bin/lane new <task>` (own worktree + branch from the current HEAD), cd there, work and commit"
        " there, finish with `lane land`. Opt out per repo only if the user asks: git config lane.allowmain true."}}))
    sys.exit(0)

if tool in ("Edit", "Write", "NotebookEdit"):
    p = ti.get("file_path") or ti.get("notebook_path") or ""
    if p:
        p = os.path.realpath(os.path.join(cwd, os.path.expanduser(p)))
        top = main_tree(os.path.dirname(p))
        if top: deny(top, f"{tool} of {p}")
elif tool == "Bash":
    cmd = ti.get("command", "")
    for part in re.split(r"&&|\|\||;|\||\n", cmd):
        s = part.strip()
        if re.match(r"(\S*/)?lane\b", s): continue
        m = re.match(r"(?:\S+=\S+\s+)*git((?:\s+-[Cc]\s+\S+|\s+--?[\w-]+(?:=\S+)?)*)\s+(commit|merge|cherry-pick|revert|am|apply|rebase|pull)\b", s)
        where = cwd
        if m:
            c = re.search(r"-C\s+(\S+)", m.group(1))
            if c: where = os.path.join(cwd, os.path.expanduser(c.group(1).strip("'\"")))
            top = main_tree(where)
            if top: deny(top, f"`git {m.group(2)}`")
        elif re.match(r"sed\b.*\s-i", s):
            top = main_tree(cwd)
            if top: deny(top, "`sed -i`")
sys.exit(0)
