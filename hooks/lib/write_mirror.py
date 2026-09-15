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

Three payload shapes. Hermes: `tool_name` write_file|patch with `args` (plugin
hook) or `tool_input` (shell hook), `path`, `content` or
`old_string`/`new_string`/`replace_all`, and `cwd`. Claude Code: `tool_name`
Write|Edit with `tool_input`, `file_path`, `content` or
`old_string`/`new_string`/`replace_all`. Codex: `tool_name` apply_patch with
the whole patch in `tool_input.command` (tests/fixtures/hosts/codex), one
patch naming any number of files: the lines above are printed once per file,
and a patch is judged as a whole by the shell half (one refused file refuses
the patch, since the host applies it atomically).

  --list   print one `<op>\t<path>[\t<new path>]` per change (absolute paths,
           op in add|update|delete|move) and nothing else. What the
           config gate and the post-write hook read to know which files a
           call touches without building a mirror.

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

WRITE_TOOLS = ("write_file", "patch", "Write", "Edit", "apply_patch")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import lang_registry_read
except ImportError:  # pragma: no cover - the helper ships next to this file
    lang_registry_read = None
import v4a_patch


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


# ---------------------------------------------------------------------------
# One call, many files: the change list every shape is read into
# ---------------------------------------------------------------------------

class Change:
    """One file the call would touch: op add|update|delete|move, its paths, its would-be content.

    `content` is None when the call cannot say what the file will hold (a
    delete, or an update whose hunks did not locate their context and whose
    added lines are judged instead). `judged` is the text the validators see.
    """

    __slots__ = ("op", "path", "new_path", "content")

    def __init__(self, op: str, path: str, new_path: str | None = None, content: str | None = None):
        self.op, self.path, self.new_path, self.content = op, path, new_path, content

    @property
    def destination(self) -> str:
        return self.new_path or self.path


def _absolute(path: str | None, cwd: str) -> str | None:
    if path is None:
        return None
    return path if os.path.isabs(path) or not cwd else os.path.join(cwd, path)


def _current_text(target: str) -> str:
    try:
        with open(target, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return ""


def _patch_change(entry: tuple, cwd: str) -> Change:
    """One (op, path, new_path, body) entry as the Change it amounts to.

    Raises ValueError for a hunk that cannot be placed: the caller refuses.
    """
    op, path, new_path, body = entry
    target, new_target = _absolute(path, cwd), _absolute(new_path, cwd)
    if op == "add":
        # Patch lines are lines: the file ends with a newline, and a validator
        # reading it with `while read` sees the last one too (review, F1).
        return Change("add", target, None, "\n".join(body) + "\n" if body else "")
    if op == "delete":
        return Change("delete", target)
    applied = v4a_patch.apply_hunks(_current_text(target), body)
    if applied is None:
        raise ValueError(f"a hunk of Update File {path} does not match the file as it is; re-read it and rewrite the patch")
    return Change(op, target, new_target, applied)


def _patch_changes(command: str, cwd: str) -> list:
    """Every file a Codex apply_patch would touch, with its would-be content."""
    return [_patch_change(entry, cwd) for entry in v4a_patch.parse(command)]


def changes_of(payload: dict) -> list:
    """The change list of any payload shape this helper reads; [] when it reads none."""
    tool = payload.get("tool_name") or ""
    args = _arguments(payload)
    if not tool:
        tool = "Edit" if "old_string" in args else "Write"
    if tool not in WRITE_TOOLS or _is_v4a(args):
        return []
    cwd = str(payload.get("cwd") or "")
    if tool == "apply_patch":
        command = args.get("command")
        if not isinstance(command, str):
            return []
        return _patch_changes(command, cwd)
    path = args.get("path") or args.get("file_path")
    if not path:
        return []
    target = str(path) if os.path.isabs(str(path)) or not cwd else os.path.join(cwd, str(path))
    return [Change("update" if tool in ("Edit", "patch") else "add", target, None, _would_be_content(tool, args, target))]


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


UNJUDGED_RELATIVE = "UNJUDGED a relative path with no workspace to resolve it against; write an absolute path"


def _tool_of(payload: dict, args: dict) -> str:
    tool = payload.get("tool_name") or ""
    if tool:
        return tool
    # A Claude Code payload with no tool name (the suites build them that
    # way): the fields say which write it is.
    return "Edit" if "old_string" in args else "Write"


def _changes_or_line(payload: dict, tool: str, args: dict, hint: str) -> tuple:
    """(changes, "") or ([], <line to print>) for a call the mirror cannot judge."""
    if _is_v4a(args):
        return [], "UNJUDGED a V4A patch (mode: patch) is not read by the write gate; use write_file or a replace-mode patch (old_string/new_string)"
    if tool == "apply_patch":
        try:
            return changes_of(payload), ""
        except ValueError as error:
            return [], f"UNJUDGED the apply_patch body could not be read ({error}); rewrite the patch"
    path = args.get("path") or args.get("file_path")
    if not path:
        return [], ""
    if not os.path.isabs(str(path)) and not hint:
        return [], UNJUDGED_RELATIVE
    return changes_of(payload), ""


def _mirror_roots(mirror: str, resolved: list) -> dict:
    """One mirror root per workspace. Two packages of a monorepo each holding
    src/example.ts landed on the same mirror path and the second overwrote the
    first (review, F5); a single workspace keeps the plain form the Hermes gate
    reads."""
    workspaces = sorted({workspace for _, _, workspace, _ in resolved})
    if len(workspaces) == 1:
        return {workspaces[0]: mirror}
    return {workspace: os.path.join(mirror, f"ws{number}") for number, workspace in enumerate(workspaces)}


def _placement(payload: dict, mirror: str) -> str:
    """The lines the shell half reads, or "" for a call this gate does not judge."""
    args = _arguments(payload)
    tool = _tool_of(payload, args)
    if tool not in WRITE_TOOLS:
        return ""
    hint = str(payload.get("cwd") or "")
    changes, line = _changes_or_line(payload, tool, args, hint)
    if line or not changes:
        return line
    resolved = []
    for change in changes:
        if not os.path.isabs(change.destination) and not hint:
            return UNJUDGED_RELATIVE
        resolved.append((change,) + _resolve(change.destination, hint))
    roots = _mirror_roots(mirror, resolved)
    lines = []
    for change, target, workspace, relative in resolved:
        if _touches_gate(relative):
            lines.append("GATE " + relative)
        elif change.content is not None:
            _place(roots[workspace], workspace, relative, change.content)
            lines.append("MIRROR " + os.path.relpath(os.path.join(roots[workspace], relative), mirror))
    return "\n".join(lines)


def _listing(payload: dict) -> str:
    try:
        changes = changes_of(payload)
    except ValueError as error:
        return "UNREADABLE\t" + str(error)
    rows = []
    for change in changes:
        row = change.op + "\t" + os.path.abspath(change.path)
        if change.new_path:
            row += "\t" + os.path.abspath(change.new_path)
        rows.append(row)
    return "\n".join(rows)


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--list":
        line = _listing(_payload())
    else:
        line = _placement(_payload(), sys.argv[1])
    if line:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
