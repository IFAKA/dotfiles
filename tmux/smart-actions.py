#!/usr/bin/env python3
"""Detect useful terminal text and perform its safe, deterministic action."""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class Target:
    type: str
    text: str
    value: str
    row: int
    column: int
    action: str
    end_row: int = 0
    end_column: int = 0


URL = re.compile(r"(?<![\w@])(?:https?://|ftp://|www\.)[^\s<>\"']+")
LOCATION = re.compile(r"(?<![\w./-])(?:~?/|\.?\.?/|(?:[\w.-]+/)+)[^\s:,()<>\"']+:(\d+)(?::(\d+))?")
PATH = re.compile(r"(?<![\w@])(?:~?/|\.?\.?/)[^\s<>\"'`()\[\]{},;]+|(?<![\w@])(?:[\w.-]+/)+[\w.-]+")
FILE = re.compile(r"(?<![\w@])(?:[\w.-]+\.[a-z0-9][\w.-]*|Dockerfile|Justfile|Makefile)(?![\w.-])", re.I)
REPOSITORY = re.compile(r"(?<![\w@])(?:(?P<host>[\w.-]+):)?(?P<repo>[\w.-]+/[\w.-]+\.git)(?![\w.-])", re.I)
HASH = re.compile(r"(?<![\w])[0-9a-f]{7,40}(?![\w])", re.I)
REF = re.compile(r"(?<![\w])(?:#\d+|PRs?\s+#?\d+|issues?\s+#?\d+|(?:branch|commit)[ /:#-]+[\w./-]+)(?![\w])", re.I)
IP = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?(?![\w.])")
STAMP = re.compile(r"(?<![\w])(?:\d{4}-\d\d-\d\d[T ][0-2]?\d:\d\d(?::\d\d)?(?:Z|[+-]\d\d:?\d\d)?)|(?:[0-2]?\d:\d\d:\d\d)(?![\w])")
COMMAND = re.compile(r"^[ \t]*(?:[$❯➜][ \t]+|[\w.-]+@[\w.-]+:[^$ ]*\$[ \t]+)(.+?)\s*$")
CODEX_RESUME = re.compile(
    r"(?<![\w-])codex\s+resume\s+[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![\w-])",
    re.I,
)
EDITABLE_FILE_EXTENSIONS = frozenset({
    "asm", "astro", "bash", "bat", "c", "cc", "clj", "cljs", "conf", "cpp", "css",
    "dart", "env", "ex", "exs", "fish", "go", "gql", "graphql", "h", "hh", "hpp",
    "hs", "html", "ini", "java", "jl", "js", "json", "jsx", "kt", "kts", "less",
    "lua", "php", "pl", "ps1", "py", "rb", "rs", "scss", "sh", "sql", "svelte",
    "swift", "tex", "toml", "ts", "tsx", "txt", "vim", "vue", "xml", "yaml", "yml",
    "md", "markdown",
    "zig", "zsh",
})
DETECTABLE_FILE_EXTENSIONS = EDITABLE_FILE_EXTENSIONS | frozenset({
    "bmp", "csv", "gif", "jpeg", "jpg", "log", "md", "markdown", "mov", "mp3",
    "mp4", "pdf", "png", "svg", "tif", "tiff", "tsv", "txt", "webm", "webp", "xlsx",
    "xls", "zip",
})


def file_action(value: str) -> str:
    filename = value.rsplit("/", 1)[-1]
    if filename.lower() in {"dockerfile", "justfile", "makefile"}:
        return "edit"
    suffix = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    return "edit" if suffix in EDITABLE_FILE_EXTENSIONS else "open"


def is_file_candidate(value: str) -> bool:
    filename = value.rsplit("/", 1)[-1]
    if filename.lower() in {"dockerfile", "justfile", "makefile"}:
        return True
    suffix = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    return suffix in DETECTABLE_FILE_EXTENSIONS


def is_path_candidate(value: str) -> bool:
    if value.startswith("HOME/"):
        return False
    if value.startswith(("/", "~/", "./", "../", "$HOME/", "${HOME}/")):
        return True
    return is_file_candidate(value)


def clean(value: str) -> str:
    return value.rstrip(".,;:!?)]}>")


def cell_width(value: str) -> int:
    return sum(0 if unicodedata.combining(char) else 2 if unicodedata.east_asian_width(char) in "WFA" else 1 for char in value)


def display_column(line: str, index: int) -> int:
    return cell_width(line[:index])


def target_contains(target: Target, row: int, column: int) -> bool:
    end_row = target.end_row if target.end_row else target.row
    end_column = target.end_column if target.end_column else target.column + cell_width(target.text) - 1
    if row < target.row or row > end_row:
        return False
    if row == target.row and column < target.column:
        return False
    if row == end_row and column > end_column:
        return False
    return True


def _fenced_ranges(lines: list[str]) -> list[tuple[int, int]]:
    ranges = []
    index = 0
    while index < len(lines):
        if re.match(r"^\s*```", lines[index]):
            end = next((i for i in range(index + 1, len(lines)) if re.match(r"^\s*```\s*$", lines[i])), None)
            if end is not None:
                ranges.append((index, end))
                index = end
        index += 1
    return ranges


def overlaps(target: Target, row: int, column: int, length: int) -> bool:
    return target_contains(target, row, column) or target_contains(target, row, column + length - 1)


def detect(text: str) -> list[Target]:
    lines = text.splitlines()
    result: list[Target] = []
    seen: set[tuple[str, int, int, int, int]] = set()

    def add(kind: str, value: str, row: int, column: int, action: str = "copy",
            end_row: int | None = None, end_column: int | None = None) -> None:
        value = clean(value) if kind not in {"code", "json", "codex-response"} else value
        if kind == "ip":
            address = value.rsplit(":", 1)[0] if re.fullmatch(r"(?:\d{1,3}\.){3}\d{1,3}:\d{1,5}", value) else value
            if any(int(part) > 255 for part in address.split(".")):
                return
        location_key = (kind, row, column, end_row if end_row is not None else row,
                        end_column if end_column is not None else column + cell_width(value) - 1)
        if not value or location_key in seen:
            return
        seen.add(location_key)
        if end_row is None:
            end_row = row
        if end_column is None:
            end_column = column + cell_width(value) - 1 if end_row == row else 0
        result.append(Target(kind, value, value, row, column, action, end_row, end_column))

    fence_rows = {row for start, end in _fenced_ranges(lines) for row in range(start, end + 1)}
    for row, line in enumerate(lines):
        for match in URL.finditer(line):
            add("url", match.group(), row, display_column(line, match.start()), "open")
        for match in LOCATION.finditer(line):
            value = clean(match.group())
            if not value.startswith(("http", "//")):
                add("location", value, row, display_column(line, match.start()), "edit")
        for match in REPOSITORY.finditer(line):
            add("repository", match.group(), row, display_column(line, match.start()), "open")
        for match in REF.finditer(line):
            add("git-ref", match.group(), row, display_column(line, match.start()))
        for expression, kind, action in ((PATH, "path", None), (FILE, "path", None),
                                         (HASH, "git-hash", "copy"),
                                         (IP, "ip", "copy"), (STAMP, "timestamp", "copy")):
            for match in expression.finditer(line):
                start = display_column(line, match.start())
                if expression is FILE and IP.fullmatch(match.group()):
                    continue
                if expression is FILE and not is_file_candidate(match.group()):
                    continue
                if expression is PATH and not is_path_candidate(match.group()):
                    continue
                if not any(overlaps(t, row, start, cell_width(match.group())) for t in result):
                    value = match.group()
                    add(kind, value, row, display_column(line, match.start()),
                        file_action(value) if action is None else action)
        for match in CODEX_RESUME.finditer(line):
            add("codex-resume", match.group(), row, display_column(line, match.start()))
        command = COMMAND.match(line) if row not in fence_rows else None
        if command and command.group(1).strip():
            command_value = command.group(1).strip()
            add("command", command_value, row, display_column(line, command.start(1)))
        for match in re.finditer(r"\b(?:error|fatal|panic|exception|warning)\b[^\n]*", line, re.I):
            add("error", match.group(), row, display_column(line, match.start()))

    index = 0
    while index < len(lines):
        fence = re.match(r"^\s*```(json|\w+)?\s*$", lines[index], re.I)
        if fence:
            end = next((i for i in range(index + 1, len(lines)) if re.match(r"^\s*```\s*$", lines[i])), None)
            if end is not None and end > index + 1:
                kind = "json" if fence.group(1) and fence.group(1).lower() == "json" else "code"
                first_row = index + 1
                last_row = end - 1
                add(kind, "\n".join(lines[first_row:end]), first_row, 0,
                    end_row=last_row, end_column=cell_width(lines[last_row]) - 1)
                index = end
        index += 1

    for row, line in enumerate(lines):
        candidate = line.strip()
        if candidate.startswith(("{", "[")) and candidate.endswith(("}", "]")):
            try:
                json.loads(candidate)
            except (ValueError, TypeError):
                continue
            add("json", candidate, row, display_column(line, line.find(candidate)))

    markers = [i for i, line in enumerate(lines) if re.match(r"^\s*(?:assistant|codex)\s*:", line, re.I)]
    if markers:
        start = markers[-1]
        body = [re.sub(r"^\s*(?:assistant|codex)\s*:\s*", "", lines[start], flags=re.I)]
        for line in lines[start + 1:]:
            if re.match(r"^\s*(?:user|you)\s*[:>]", line, re.I) or re.match(r"^\s*[›❯]", line):
                break
            if re.match(r"^\s*(?:[$➜])\s+", line):
                break
            body.append(line)
        value = "\n".join(body).strip()
        if value:
            add("codex-response", value, start, 0)

    priority = {"location": 0, "url": 1, "repository": 2, "path": 3, "error": 4, "codex-resume": 5,
                "command": 6, "codex-response": 7, "git-ref": 8, "git-hash": 9,
                "json": 10, "code": 11, "ip": 12, "timestamp": 13}
    return sorted(result, key=lambda item: (priority.get(item.type, 99), -item.row, item.column))


def action_spans(text: str) -> list[dict[str, int | str]]:
    """Return display-cell ranges suitable for terminal renderers."""
    lines = text.splitlines()
    spans: list[dict[str, int | str]] = []
    for target in detect(text):
        last_row = target.end_row if target.end_row else target.row
        for row in range(target.row, last_row + 1):
            if row >= len(lines):
                break
            start = target.column if row == target.row else 0
            end = target.end_column if row == last_row and target.end_column else cell_width(lines[row]) - 1
            if end < start:
                continue
            spans.append({
                "row": row,
                "start_column": start,
                "end_column": end,
                "action": target.action,
                "type": target.type,
            })
    return spans


def parse_location(value: str) -> tuple[str, int | None, int | None]:
    match = re.match(r"^(.*?):(\d+)(?::(\d+))?$", value)
    return (match.group(1), int(match.group(2),), int(match.group(3)) if match and match.group(3) else None) if match else (value, None, None)


def editor() -> list[str]:
    return shlex.split(os.environ.get("VISUAL") or os.environ.get("EDITOR") or "") or ["nvim"]


def pane_cwd(pane_id: str | None) -> str:
    cwd = os.getcwd()
    tmux = shutil.which("tmux")
    if tmux and pane_id:
        try:
            cwd = subprocess.check_output(
                [tmux, "display-message", "-p", "-t", pane_id, "#{pane_current_path}"],
                text=True,
            ).strip() or cwd
        except (OSError, subprocess.CalledProcessError):
            pass
    return cwd


def repository_url(target: Target, pane_id: str | None) -> str:
    match = REPOSITORY.fullmatch(target.value)
    if not match:
        return target.value
    repo = match.group("repo")
    host = match.group("host")
    remote = None
    try:
        remote = subprocess.check_output(
            ["git", "-C", pane_cwd(pane_id), "remote", "get-url", "origin"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        pass
    if remote:
        remote = re.sub(r"\.git$", "", remote)
        if remote.startswith(("http://", "https://")):
            return remote
        remote_match = re.match(r"^[^@]+@([^:]+):(.+)$", remote)
        if remote_match:
            return f"https://{remote_match.group(1)}/{remote_match.group(2).removesuffix('.git')}"
    if host:
        return f"https://{host}/{repo.removesuffix('.git')}"
    return f"https://github.com/{repo.removesuffix('.git')}"


def open_command(target: Target, pane_id: str | None = None) -> list[str] | None:
    if target.type == "repository":
        value = repository_url(target, pane_id)
        return [("open" if sys.platform == "darwin" else "xdg-open"), value]
    if target.type == "url":
        value = target.value if "://" in target.value else f"https://{target.value}"
        return [("open" if sys.platform == "darwin" else "xdg-open"), value]
    if target.type in {"path", "location"}:
        path, _, _ = parse_location(target.value)
        return [("open" if sys.platform == "darwin" else "xdg-open"), os.path.expanduser(path)]
    return None


def edit_command(target: Target, pane_id: str | None) -> list[str] | None:
    if target.type not in {"path", "location"}:
        return None
    command = editor()
    path, line, column = parse_location(target.value)
    path = os.path.expanduser(path)
    if line and ("vim" in os.path.basename(command[0])):
        command.append(f"+call cursor({line},{column or 1})" if column else f"+{line}")
        command.append(path)
    else:
        command.append(path if not line else f"{path}:{line}:{column or 1}")
    tmux = shutil.which("tmux")
    if not tmux:
        return command
    cwd = os.getcwd()
    if pane_id:
        try:
            cwd = subprocess.check_output([tmux, "display-message", "-p", "-t", pane_id, "#{pane_current_path}"], text=True).strip() or cwd
        except (OSError, subprocess.CalledProcessError):
            pass
    return [tmux, "new-window", "-c", cwd, shlex.join(command)]


def copy_value(value: str) -> None:
    tmux = shutil.which("tmux")
    if tmux:
        try:
            subprocess.run([tmux, "load-buffer", "-"], input=value, text=True, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError):
            pass
    for command in (["pbcopy"], ["wl-copy"], ["xclip", "-selection", "clipboard"], ["xsel", "--clipboard", "--input"]):
        if shutil.which(command[0]):
            try:
                subprocess.run(command, input=value, text=True, check=True)
                return
            except (OSError, subprocess.CalledProcessError):
                pass
    payload = base64.b64encode(value.encode()).decode()
    sys.stdout.write(f"\033]52;c;{payload}\a")
    sys.stdout.flush()


def smart_action_target(text: str, row: int, column: int) -> Target | None:
    candidates = [target for target in detect(text) if target_contains(target, row, column)]
    if not candidates:
        return None
    priority = {"codex-resume": 0, "location": 1, "url": 2, "repository": 3, "path": 4,
                "error": 5, "command": 6, "codex-response": 7, "git-ref": 8,
                "git-hash": 9, "json": 10, "code": 11, "ip": 12, "timestamp": 13}
    return min(candidates, key=lambda item: (item.end_row - item.row,
                                             (item.end_column or item.column) - item.column,
                                             priority.get(item.type, 99)))


def smart_action(text: str, row: int, column: int, pane_id: str | None) -> int:
    target = smart_action_target(text, row, column)
    if target is None:
        return 0
    if pane_id and shutil.which("tmux"):
        subprocess.run(["tmux", "copy-mode", "-q", "-t", pane_id], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if target.action == "open":
        command = open_command(target, pane_id)
        if command:
            subprocess.run(command, check=False)
    elif target.action == "edit":
        command = edit_command(target, pane_id)
        if command:
            subprocess.run(command, check=False)
    else:
        copy_value(target.value)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--detect", action="store_true")
    parser.add_argument("--action-spans", action="store_true")
    parser.add_argument("--input-file")
    parser.add_argument("--smart-action")
    parser.add_argument("--smart-action-target")
    parser.add_argument("--pane-id")
    args = parser.parse_args()
    text = open(args.input_file, encoding="utf-8").read() if args.input_file else sys.stdin.read()
    if args.detect:
        print(json.dumps([asdict(target) for target in detect(text)], ensure_ascii=False))
    if args.action_spans:
        print(json.dumps(action_spans(text), ensure_ascii=False))
    if args.smart_action:
        row, column = (int(part) for part in args.smart_action.split(":", 1))
        return smart_action(text, row, column, args.pane_id)
    if args.smart_action_target:
        row, column = (int(part) for part in args.smart_action_target.split(":", 1))
        target = smart_action_target(text, row, column)
        if target:
            print(json.dumps(asdict(target), ensure_ascii=False))
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
