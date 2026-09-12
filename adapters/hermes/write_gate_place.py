#!/usr/bin/env python3
"""Lay the content a Hermes write WOULD produce under a mirror of its workspace.

The half of pre-tool-call.sh that understands the tool call. Reads the hook
payload on stdin, prints one line for the shell half:

  MIRROR <relative path>   the would-be file is in the mirror, judge it
  GATE <relative path>     the write edits the gate's own configuration
  UNJUDGED <why>           a write this hook cannot judge and must not wave
  (nothing)                not a write this hook judges

Usage: write_gate_place.py <mirror dir>  < payload.json
"""

from __future__ import annotations

import json
import os
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


def _is_v4a(args: dict) -> bool:
    """`mode: patch` with a `patch` body: the V4A form the handler accepts from any model.

    Not parsed here. A V4A body can name several files and carries its own
    hunk grammar; reading it would duplicate Hermes's parser and diverge from
    it. An unread mutation is not a pass: the shell half refuses it and says
    which form to use instead.
    """
    return args.get("mode") == "patch" or isinstance(args.get("patch"), str)


def _place(mirror: str, workspace: str, relative: str, content: str) -> None:
    """The would-be file, and every rule file the engine would read for it.

    `rules_severity_for_file` walks up from the file's own directory, so a
    directory `.craft-rules.yml` that relaxes a rule (differentiator 2) must
    be in the mirror too, or the write gate blocks what CI and the hooks let
    through: the exact disagreement the parity suite exists to refuse.
    """
    destination = os.path.join(mirror, relative)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    with open(destination, "w", encoding="utf-8") as handle:
        handle.write(content)
    for directory in _ancestors(os.path.dirname(relative)):
        _copy_rules(workspace, mirror, directory)


def _ancestors(directory: str) -> list:
    """The directory and every one above it up to the workspace root ("")."""
    chain = [directory]
    while directory:
        directory = os.path.dirname(directory)
        chain.append(directory)
    return chain


def _copy_rules(workspace: str, mirror: str, directory: str) -> None:
    for name in (".craft-config.yml", ".craft-rules.yml"):
        source = os.path.join(workspace, directory, name)
        if os.path.isfile(source):
            shutil.copy(source, os.path.join(mirror, directory, name))


def _resolve(path: str, hint: str) -> tuple:
    """(target, workspace, relative). A relative path with no cwd to resolve it against is refused.

    Never the process cwd: in gateway mode that is the Hermes process's
    directory, not the task's, and a mirror built there judges the wrong tree
    with the wrong project's rules.
    """
    if not os.path.isabs(path):
        if not hint:
            return None, None, None
        path = os.path.join(hint, path)
    target = os.path.realpath(path)
    workspace = _workspace_of(target, os.path.realpath(hint) if hint else "")
    return target, workspace, os.path.relpath(target, workspace)


def main() -> int:
    mirror = sys.argv[1]
    payload = _payload()
    tool = payload.get("tool_name") or ""
    if tool not in WRITE_TOOLS:
        return 0
    args = _arguments(payload)
    if _is_v4a(args):
        print("UNJUDGED a V4A patch (mode: patch) is not read by the write gate; use write_file or a replace-mode patch (old_string/new_string)")
        return 0
    if not args.get("path"):
        return 0
    target, workspace, relative = _resolve(str(args["path"]), str(payload.get("cwd") or ""))
    if target is None:
        print("UNJUDGED a relative path with no workspace to resolve it against; write an absolute path")
        return 0
    if _touches_gate(relative):
        print("GATE " + relative)
        return 0
    content = _would_be_content(tool, args, target)
    if content is None:
        return 0
    _place(mirror, workspace, relative, content)
    print("MIRROR " + relative)
    return 0


if __name__ == "__main__":
    sys.exit(main())
