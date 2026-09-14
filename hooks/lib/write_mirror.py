#!/usr/bin/env python3
"""Lay the content a write WOULD produce under a mirror of its workspace.

The one mechanism behind "judge the would-be file": the Claude Code pre-write
gate and the Hermes write gate both place the content here and run the pack
validators on the mirror, so there is one set of detectors and not a fork of
them (the fork read "App" where the pack reads composer.json's psr-4 root,
and an Acme\\ project passed pre-write while post-write refused it).

Reads the hook payload on stdin, prints one line for the shell half:

  MIRROR <relative path>   the would-be file is in the mirror, judge it
  GATE <relative path>     the write edits the gate's own configuration
  UNJUDGED <why>           a write this hook cannot judge and must not wave
  (nothing)                not a write this hook judges

Two payload shapes. Hermes: `tool_name` write_file|patch with `args` (plugin
hook) or `tool_input` (shell hook), `path`, `content` or
`old_string`/`new_string`/`replace_all`, and `cwd`. Claude Code: `tool_name`
Write|Edit with `tool_input`, `file_path`, `content` or
`old_string`/`new_string`/`replace_all`.

Beside the file, the mirror carries what the engine reads for it: every
`.craft-config.yml`/`.craft-rules.yml` on the ancestor chain, the workspace's
`composer.json`/`package.json` (namespace root, language markers) and its
`.craftsman-baseline.json` (a mark the hook and CI honour must hold at write
time too, or the gate refuses what they let through).

Usage: write_mirror.py <mirror dir>  < payload.json
"""

from __future__ import annotations

import json
import os
import shutil
import sys

WRITE_TOOLS = ("write_file", "patch", "Write", "Edit")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import lang_registry_read
except ImportError:  # pragma: no cover - the helper ships next to this file
    lang_registry_read = None


def _pack_markers() -> tuple:
    """The entry markers every loaded pack declares, from the registry.

    A literal list here named five languages' markers and would have missed
    the sixth pack's; the registry is where a pack says what marks its root.
    """
    if lang_registry_read is None:
        return ()
    try:
        return tuple(sorted(lang_registry_read.entry_markers()))
    except Exception:  # noqa: BLE001 - a broken registry must not break the mirror
        return ()


ENGINE_MARKERS = (".git", ".craft-config.yml")
WORKSPACE_MARKERS = ENGINE_MARKERS + _pack_markers()
# The gate's own configuration, refused rather than judged. The names are the
# engine's; a host adds its own paths through CRAFTSMAN_GATE_OWN_PATHS (space
# separated, a trailing slash marks a directory), so this core helper names no
# adapter and the adapter's conclusion gate refuses the same set (its suite
# fails when the two drift). The Claude Code side has its own gate for these
# files (config-protection.sh).
GATE_OWN_NAMES = (".craft-rules.yml", ".craft-config.yml", ".craftsman-baseline.json")


def _host_gate_own() -> tuple:
    entries = os.environ.get("CRAFTSMAN_GATE_OWN_PATHS", "").split()
    paths = tuple(e for e in entries if not e.endswith("/"))
    prefixes = tuple(e for e in entries if e.endswith("/"))
    return paths, prefixes


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
    # No marker anywhere above: mirror the whole absolute path, so a rule keyed
    # on a path segment (/Domain/, /Application/) still sees it. Mirroring the
    # file's own directory alone dropped every segment above the file.
    return os.path.abspath(os.sep)


def _touches_gate(relative: str) -> bool:
    if os.path.basename(relative) in GATE_OWN_NAMES:
        return True
    paths, prefixes = _host_gate_own()
    if relative in paths:
        return True
    return any(relative.startswith(prefix) for prefix in prefixes)


def _would_be_content(tool: str, args: dict, target: str) -> str | None:
    if tool in ("write_file", "Write"):
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
    _copy_roots(workspace, mirror)


def _ancestors(directory: str) -> list:
    """The directory and every one above it up to the workspace root ("")."""
    chain = [directory]
    while directory:
        directory = os.path.dirname(directory)
        chain.append(directory)
    return chain


# What a validator or a mark reads at the root for any file under it: the
# packs' entry markers (a namespace root, a language marker) and the mark.
ROOT_FILES = _pack_markers() + (".craftsman-baseline.json",)


def _copy_roots(workspace: str, mirror: str) -> None:
    """The workspace files a validator or a mark reads for any file under it."""
    for name in ROOT_FILES:
        source = os.path.join(workspace, name)
        if os.path.isfile(source):
            shutil.copy(source, os.path.join(mirror, name))


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


def _placement(payload: dict, mirror: str) -> str:
    """The line the shell half reads, or "" for a call this gate does not judge."""
    tool = payload.get("tool_name") or ""
    args = _arguments(payload)
    if not tool:
        # A Claude Code payload with no tool name (the suites build them that
        # way): the fields say which write it is.
        tool = "Edit" if "old_string" in args else "Write"
    if tool not in WRITE_TOOLS:
        return ""
    if _is_v4a(args):
        return "UNJUDGED a V4A patch (mode: patch) is not read by the write gate; use write_file or a replace-mode patch (old_string/new_string)"
    path = args.get("path") or args.get("file_path")
    if not path:
        return ""
    target, workspace, relative = _resolve(str(path), str(payload.get("cwd") or ""))
    if target is None:
        return "UNJUDGED a relative path with no workspace to resolve it against; write an absolute path"
    if _touches_gate(relative):
        return "GATE " + relative
    content = _would_be_content(tool, args, target)
    if content is None:
        return ""
    _place(mirror, workspace, relative, content)
    return "MIRROR " + relative


def main() -> int:
    line = _placement(_payload(), sys.argv[1])
    if line:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
