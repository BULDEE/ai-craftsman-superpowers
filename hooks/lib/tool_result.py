#!/usr/bin/env python3
"""What a command's tool event says about how the command ended.

One decoder for the shapes the hosts actually send (tests/fixtures/hosts).
Nothing here reads a field a capture did not show:

  Claude Code, PostToolUse Bash        `tool_response` is an object with stdout,
                                       stderr, interrupted, isImage; NO exit
                                       code. A non-zero exit is not a
                                       PostToolUse at all, it is a
                                       PostToolUseFailure, so a PostToolUse is
                                       a completed command unless it carries
                                       `backgroundTaskId` (started, result
                                       pending) or `interrupted`.
  Claude Code, PostToolUseFailure Bash `error` starts with "Exit code N"; the
                                       output follows. `is_interrupt` marks a
                                       user interruption.
  Claude Code, PostToolUse TaskOutput  `tool_response.task` carries task_id,
                                       status, exitCode, output; the command
                                       is not in it, the caller maps task_id
                                       back to the Bash that started it.
  Codex, PostToolUse Bash              `tool_response` is the output string.
                                       `exit 3` gave the output, `false` gave
                                       "": the exit code is not observable.

States: succeeded, failed, interrupted, running, unknown. `unknown` grants no
evidence and invents no regression; the old reader defaulted a missing
`tool_result.exit_code` to 1 and turned a passing suite into "REGRESSED".

Usage: tool_result.py < payload.json   prints one JSON object:
  {"state", "exit_code" (int or null), "command" (or null), "task_id" (or
   null), "tool", "event", "why"}
"""

from __future__ import annotations

import json
import re
import sys

EXIT_CODE_RE = re.compile(r"^\s*Exit code:?\s+(-?\d+)", re.IGNORECASE | re.MULTILINE)


def _int(value) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _result(payload: dict) -> dict:
    args = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    command = args.get("command") if isinstance(args.get("command"), str) else None
    return {"state": "unknown", "exit_code": None, "command": command, "task_id": None,
            "tool": payload.get("tool_name") or "", "event": payload.get("hook_event_name") or "",
            "why": "no rule matched this event shape"}


def _verdict(result: dict, state: str, code=None, why: str = "", task_id=None) -> dict:
    result.update(state=state, exit_code=code, why=why, task_id=task_id)
    return result


def _from_exit_code(result: dict, code: int, why: str, task_id=None) -> dict:
    return _verdict(result, "succeeded" if code == 0 else "failed", code, why, task_id)


def _decode_failure(result: dict, payload: dict) -> dict:
    error = payload.get("error") if isinstance(payload.get("error"), str) else ""
    if payload.get("is_interrupt") is True:
        return _verdict(result, "interrupted", None, "PostToolUseFailure with is_interrupt")
    match = EXIT_CODE_RE.search(error)
    if match:
        return _from_exit_code(result, int(match.group(1)), "PostToolUseFailure error names the exit code")
    return _verdict(result, "failed", None, "PostToolUseFailure without an exit code in error")


def _decode_task_output(result: dict, response: dict, args: dict) -> dict:
    task = response.get("task") if isinstance(response.get("task"), dict) else {}
    task_id = task.get("task_id") or args.get("task_id")
    status = task.get("status")
    code = _int(task.get("exitCode"))
    if status == "completed" and code is not None:
        return _from_exit_code(result, code, "TaskOutput task completed with exitCode", task_id)
    if status in ("running", "pending"):
        return _verdict(result, "running", None, "TaskOutput task still running", task_id)
    if status in ("killed", "cancelled", "canceled"):
        return _verdict(result, "interrupted", code, f"TaskOutput task {status}", task_id)
    return _verdict(result, "unknown", code, f"TaskOutput status {status!r} without a usable exitCode", task_id)


def _decode_object(result: dict, response: dict) -> dict:
    task_id = response.get("backgroundTaskId")
    if task_id:
        return _verdict(result, "running", None, "Bash started in the background; result arrives on TaskOutput", task_id)
    if response.get("interrupted") is True:
        return _verdict(result, "interrupted", None, "tool_response.interrupted")
    code = _int(response.get("exit_code", response.get("exitCode")))
    if code is not None:
        return _from_exit_code(result, code, "tool_response carries an exit code")
    if "stdout" in response or "stderr" in response:
        return _verdict(result, "succeeded", 0, "Claude Code PostToolUse for a Bash command: a non-zero exit is a PostToolUseFailure, not this event")
    return _verdict(result, "unknown", None, "object tool_response without exit code or stdout")


def _decode_string(result: dict, response: str) -> dict:
    match = EXIT_CODE_RE.search(response)
    if match:
        return _from_exit_code(result, int(match.group(1)), "string tool_response names the exit code")
    return _verdict(result, "unknown", None, "string tool_response without an exit code (Codex shell output); the exit code is not observable on this host")


def decode(payload: dict) -> dict:
    result = _result(payload)
    event, tool, response = result["event"], result["tool"], payload.get("tool_response")
    args = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    if event == "PostToolUseFailure":
        return _decode_failure(result, payload)
    if event and event != "PostToolUse":
        return _verdict(result, "unknown", None, f"{event} carries no command result")
    if tool == "TaskOutput" and isinstance(response, dict):
        return _decode_task_output(result, response, args)
    if isinstance(response, dict):
        return _decode_object(result, response)
    if isinstance(response, str):
        return _decode_string(result, response)
    return result


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    print(json.dumps(decode(payload)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
