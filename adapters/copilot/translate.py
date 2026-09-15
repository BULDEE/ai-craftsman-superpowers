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


def _object(value):
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except ValueError:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return value if isinstance(value, dict) else {}


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


def translate(payload: dict) -> dict:
    tool = payload.get("tool_name") or payload.get("toolName") or ""
    args = _object(payload.get("tool_input") if "tool_input" in payload else payload.get("toolArgs"))
    core_tool = TOOL_NAMES.get(tool, tool)
    if tool == "str_replace_editor" and args.get("command") == "create":
        core_tool = "Write"
    out = {
        "hook_event_name": _event(payload),
        "session_id": payload.get("session_id") or payload.get("sessionId") or "",
        "cwd": payload.get("cwd") or "",
        "tool_name": core_tool,
        "tool_input": _arguments(tool, args) if core_tool in ("Write", "Edit", "Bash", "apply_patch") else args,
        "craftsman_host": "copilot",
        "craftsman_surface": "cloud" if os.environ.get("COPILOT_AGENT_PROMPT") else "cli",
        "copilot_tool_name": tool,
    }
    result = payload.get("tool_result") if "tool_result" in payload else payload.get("toolResult")
    if isinstance(result, dict):
        out["tool_result"] = result
    for key in ("prompt", "last_assistant_message", "agent_transcript_path", "reason"):
        if key in payload:
            out[key] = payload[key]
    return out


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    print(json.dumps(translate(payload)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
