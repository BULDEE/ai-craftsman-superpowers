#!/usr/bin/env python3
"""Translate a GitHub Copilot hook payload into the shape the core hooks read.

Usage: translate.py < copilot-payload.json    prints the core payload

Copilot sends either the camelCase envelope (`sessionId`, `toolName`,
`toolArgs`, `toolResult`) or the PascalCase Claude-compatible one
(`session_id`, `tool_name`, `tool_input`, `tool_result`), both documented at
docs.github.com/en/copilot/reference/hooks-reference (read 2026-09-15). The
tool names are Copilot's: `create`, `edit`, `str_replace_editor`,
`apply_patch`, `bash`, `powershell`, `view`... The core hooks read Write, Edit,
Bash and apply_patch with `file_path`, `content`, `old_string`/`new_string`
and `command`, so this is where the names change and nothing else does.

PROVENANCE: documented, not captured. No Copilot consumer was available on
the machine that wrote this (tests/fixtures/hosts/copilot/documented/); the
argument names of the file tools are the documented tool's, and the first
real capture replaces them. `toolArgs` may arrive as a JSON string ("parsed
from JSON string when possible" in the reference): parsed here too.

The output carries `craftsman_host: copilot` and the surface when known
(`craftsman_surface: cli|cloud`, from COPILOT_AGENT_PROMPT which the cloud
agent sets), so hooks/lib/host.sh names the host without guessing.
"""

from __future__ import annotations

import json
import os
import sys

TOOL_NAMES = {
    "create": "Write",
    "edit": "Edit",
    "str_replace_editor": "Edit",
    "apply_patch": "apply_patch",
    "bash": "Bash",
    "powershell": "Bash",
}

# Copilot tool argument names, as documented for each tool, to the core's.
ARGUMENT_NAMES = {
    "path": "file_path",
    "file_path": "file_path",
    "file_text": "content",
    "content": "content",
    "old_str": "old_string",
    "old_string": "old_string",
    "new_str": "new_string",
    "new_string": "new_string",
    "command": "command",
    "patch": "command",
}


class Unreadable(Exception):
    """A payload this translator cannot read for a write: refused, never passed."""


def _object(value, required: bool):
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except ValueError:
            if required:
                raise Unreadable("toolArgs is a string that is not JSON")
            return {}
        if not isinstance(parsed, dict):
            if required:
                raise Unreadable("toolArgs is JSON but not an object")
            return {}
        return parsed
    if isinstance(value, dict):
        return value
    if required:
        raise Unreadable("tool arguments are missing")
    return {}


def _event(payload: dict) -> str:
    event = payload.get("hook_event_name") or payload.get("hookEventName") or ""
    camel = {"preToolUse": "PreToolUse", "postToolUse": "PostToolUse", "sessionStart": "SessionStart",
             "sessionEnd": "SessionEnd", "userPromptSubmitted": "UserPromptSubmit", "agentStop": "Stop",
             "postToolUseFailure": "PostToolUseFailure", "subagentStop": "SubagentStop"}
    return camel.get(event, event)


def _arguments(tool: str, args: dict) -> dict:
    """The core's argument names. A str_replace_editor `command: create` is a
    Write, `str_replace` an Edit; the sub-command is not a shell command."""
    if tool == "str_replace_editor":
        args = {key: value for key, value in args.items() if key != "command"}
    translated = {}
    for key, value in args.items():
        translated[ARGUMENT_NAMES.get(key, key)] = value
    return translated


def _is_patch(args: dict) -> bool:
    command = args.get("command") if isinstance(args.get("command"), str) else ""
    return isinstance(args.get("patch"), str) or command.lstrip().startswith("*** Begin Patch")


def _core_tool(tool: str, args: dict) -> str:
    """The core's tool name. In the PascalCase form the host has already
    mapped its tools to Claude names, and `apply_patch` arrives as "Edit"
    (review of 84b2350, F1): a patch body is a patch whatever the name says."""
    if tool in ("Write", "Edit", "Bash") and _is_patch(args):
        return "apply_patch"
    if tool == "str_replace_editor" and args.get("command") == "create":
        return "Write"
    return TOOL_NAMES.get(tool, tool)


def _check_write(core_tool: str, args: dict, event: str) -> None:
    """A write the core cannot judge is refused here, not waved through. The
    would-be content matters before the write; after it, the file on disk is
    what post-write-check.sh reads, so the path is enough."""
    if core_tool in ("Write", "Edit") and not args.get("file_path"):
        raise Unreadable(f"a {core_tool} with no file path")
    if event == "PreToolUse" and core_tool == "Write" and not isinstance(args.get("content"), str):
        raise Unreadable("a Write with no content")
    if core_tool == "apply_patch" and not isinstance(args.get("command"), str):
        raise Unreadable("an apply_patch with no patch body")


def _envelope(payload: dict, event: str, tool: str) -> dict:
    return {
        "hook_event_name": event,
        "session_id": payload.get("session_id") or payload.get("sessionId") or "",
        "cwd": payload.get("cwd") or "",
        "craftsman_host": "copilot",
        "craftsman_surface": "cloud" if os.environ.get("COPILOT_AGENT_PROMPT") else "cli",
        "copilot_tool_name": tool,
    }


def _carried(payload: dict) -> dict:
    """Fields the core hooks read unchanged when present."""
    out = {}
    result = payload.get("tool_result") if "tool_result" in payload else payload.get("toolResult")
    if isinstance(result, dict):
        out["tool_result"] = result
    for key in ("prompt", "last_assistant_message", "agent_transcript_path", "reason"):
        if key in payload:
            out[key] = payload[key]
    return out


def translate(payload: dict) -> dict:
    tool = payload.get("tool_name") or payload.get("toolName") or ""
    raw = payload.get("tool_input") if "tool_input" in payload else payload.get("toolArgs")
    is_write = tool in TOOL_NAMES and TOOL_NAMES[tool] != "Bash" or tool in ("Write", "Edit")
    args = _object(raw, required=is_write)
    core_tool = _core_tool(tool, args)
    arguments = _arguments(tool, args) if core_tool in ("Write", "Edit", "Bash", "apply_patch") else args
    event = _event(payload)
    if core_tool in ("Write", "Edit", "apply_patch"):
        _check_write(core_tool, arguments, event)
    out = _envelope(payload, event, tool)
    out.update(tool_name=core_tool, tool_input=arguments)
    out.update(_carried(payload))
    return out


def main() -> int:
    """0 and the core payload; 3 and a reason on stderr for a write this
    translator cannot read (the gate denies on it; review of 84b2350, F2). An
    envelope that is not JSON at all is refused the same way: what it carries
    is unknown, and unknown may be a write."""
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        sys.stderr.write("craftsman: the Copilot payload is not JSON\n")
        return 3
    if not isinstance(payload, dict):
        sys.stderr.write("craftsman: the Copilot payload is not an object\n")
        return 3
    try:
        print(json.dumps(translate(payload)))
    except Unreadable as why:
        sys.stderr.write(f"craftsman: cannot judge this Copilot write: {why}\n")
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
