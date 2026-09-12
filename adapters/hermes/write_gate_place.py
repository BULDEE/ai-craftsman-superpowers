#!/usr/bin/env python3
"""Lay the content a Hermes write WOULD produce under a mirror of its workspace.

The half of pre-tool-call.sh that understands the tool call. Reads the hook
payload on stdin, prints one line for the shell half:

  MIRROR <relative path>   the would-be file is in the mirror, judge it
  GATE <relative path>     the write edits the gate's own configuration
  (nothing)                not a write this hook judges

Usage: write_gate_place.py <mirror dir>  < payload.json
"""

from __future__ import annotations

import json
import os
import re
import shutil
import sys

WRITE_TOOLS = ("write_file", "patch")
WORKSPACE_MARKERS = (".git", ".craft-config.yml", "composer.json", "package.json",
                     "pyproject.toml", "go.mod", "Cargo.toml")
# The same set pre-verify.sh refuses at the conclusion (GATE_TOUCHED), and
# tests/adapters/test-hermes-plugin.sh fails when the two drift.
GATE_OWN_NAMES = (".craft-rules.yml", ".craft-config.yml")
GATE_OWN_PATHS = ("ci/craftsman-ci.sh",)
GATE_OWN_PREFIXES = ("adapters/hermes/",)

V4A_FILE_RE = re.compile(r"^\*\*\* (?:Update|Add) File: (.+)$")


def _payload() -> dict:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def _arguments(payload: dict) -> dict:
    """`tool_input` on the shell wire, `args` from a plugin hook."""
    for key in ("tool_input", "args"):
        value = payload.get(key)
        if isinstance(value, dict):
            return value
    return {}


def _workspace_of(target: str, hint: str) -> str:
    """The nearest marker directory above the target, else the hint, else its own directory."""
    cursor = os.path.dirname(target)
    while True:
        if any(os.path.exists(os.path.join(cursor, marker)) for marker in WORKSPACE_MARKERS):
            return cursor
        parent = os.path.dirname(cursor)
        if parent == cursor:
            break
        cursor = parent
    if hint and os.path.isdir(hint) and (target == hint or target.startswith(hint + os.sep)):
        return hint
    return os.path.dirname(target)


def _touches_gate(relative: str) -> bool:
    if os.path.basename(relative) in GATE_OWN_NAMES:
        return True
    if relative in GATE_OWN_PATHS:
        return True
    return any(relative.startswith(prefix) for prefix in GATE_OWN_PREFIXES)


def _would_be_content(tool: str, args: dict, target: str) -> str | None:
    if tool == "write_file":
        content = args.get("content")
        return content if isinstance(content, str) else None
    if isinstance(args.get("patch"), str) and args.get("mode") == "patch":
        return None  # V4A, handled per file by _v4a_contents
    old, new = args.get("old_string"), args.get("new_string")
    if not isinstance(old, str) or not isinstance(new, str):
        return None
    try:
        with open(target, encoding="utf-8", errors="replace") as handle:
            current = handle.read()
    except OSError:
        current = ""
    if old and old in current:
        return current.replace(old, new) if args.get("replace_all") else current.replace(old, new, 1)
    # Hermes applies old_string through a chain of fuzzy strategies (whitespace,
    # indentation), so "not in the file" here does not mean "will not apply".
    # An unjudged mutation is not a pass: judge what the patch adds, which is
    # where a new import or a new literal can only be.
    return new


def _v4a_contents(patch: str) -> dict:
    """path -> the lines a V4A patch adds there, per `*** Update File` / `*** Add File` section."""
    added: dict = {}
    current = None
    for line in patch.splitlines():
        match = V4A_FILE_RE.match(line)
        if match:
            current = match.group(1).strip()
            added.setdefault(current, [])
            continue
        if current is not None and line.startswith("+") and not line.startswith("+++"):
            added[current].append(line[1:])
    return {path: "\n".join(lines) + "\n" for path, lines in added.items() if lines}


def _place(mirror: str, workspace: str, relative: str, content: str) -> None:
    destination = os.path.join(mirror, relative)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    with open(destination, "w", encoding="utf-8") as handle:
        handle.write(content)
    for name in (".craft-config.yml", ".craft-rules.yml"):
        source = os.path.join(workspace, name)
        if os.path.isfile(source) and not os.path.exists(os.path.join(mirror, name)):
            shutil.copy(source, os.path.join(mirror, name))


def _resolve(path: str, hint: str) -> tuple:
    target = os.path.realpath(path if os.path.isabs(path) else os.path.join(hint or os.getcwd(), path))
    workspace = _workspace_of(target, os.path.realpath(hint) if hint else "")
    return target, workspace, os.path.relpath(target, workspace)


def _writes(tool: str, args: dict, hint: str) -> dict:
    """path -> would-be content, one entry per file the call writes."""
    if isinstance(args.get("patch"), str) and args.get("mode") == "patch":
        return _v4a_contents(args["patch"])
    if not args.get("path"):
        return {}
    content = _would_be_content(tool, args, _resolve(str(args["path"]), hint)[0])
    return {str(args["path"]): content} if content is not None else {}


def main() -> int:
    mirror = sys.argv[1]
    payload = _payload()
    tool = payload.get("tool_name") or ""
    if tool not in WRITE_TOOLS:
        return 0
    hint = str(payload.get("cwd") or "")
    placed = []
    for path, content in _writes(tool, _arguments(payload), hint).items():
        _, workspace, relative = _resolve(path, hint)
        if _touches_gate(relative):
            print("GATE " + relative)
            return 0
        _place(mirror, workspace, relative, content)
        placed.append(relative)
    if placed:
        # One path per run keeps the shell half simple; a V4A patch touching
        # several files is judged on the first, and the conclusion gate sees
        # the rest.
        print("MIRROR " + placed[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
