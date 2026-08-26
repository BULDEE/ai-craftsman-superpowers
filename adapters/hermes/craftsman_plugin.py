"""Native Hermes plugin: the craftsman gate as a first-class citizen.

One gate, one implementation. Every verdict comes from `pre-verify.sh`, the
same script the shell-hook install runs, which itself calls
`ci/craftsman-ci.sh`: the parity suite (`tests/adapters/test-parity.sh`) holds
that path to the same severities as the Claude Code hooks and CI, and this
module inherits the guarantee instead of re-earning it.

What the plugin adds over the shell hook (ADR-0029 verbs):

- `gate`    pre_verify, delegated to pre-verify.sh. Fail-closed: an exception
            anywhere in this module returns a block, never a silent pass,
            because Hermes logs a raised hook exception and moves on.
- `inject`  pre_llm_call on the first turn: correction trends from metrics.db,
            so the agent starts each session knowing what this machine keeps
            fixing.
- `record`  violations at attempt 0, `fixed` corrections when a later attempt
            clears a rule, both tagged source=hermes. The `attempt` counter in
            the pre_verify payload is the causal thread: no log mining, no
            model judgment.

No jq, no sqlite3 CLI, no Claude Code binary, no Docker: python3, bash and git
are the whole dependency surface, and the Hermes image carries all three.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

_PLUGIN_ROOT = Path(__file__).resolve().parents[2]
_GATE = _PLUGIN_ROOT / "adapters" / "hermes" / "pre-verify.sh"
_METRICS_LIB = _PLUGIN_ROOT / "hooks" / "lib" / "metrics-db.sh"

_RULE_RE = re.compile(r"\b((?:WARN-)?[A-Z]{2,12}\d{3})\b")
_FILE_RULE_RE = re.compile(r"^(\S+):\d+\s+((?:WARN-)?[A-Z]{2,12}\d{3})\b", re.MULTILINE)

_GATE_SECONDS = 45
_INJECT_TRENDS = True

# Rules each session was blocked on at its last gate run. The gateway process
# is long-lived, so a module dict is the session store; a restart loses only
# in-flight correction attribution, never a verdict.
_session_rules: dict[str, set[str]] = {}

# Last workspace each session's gate ran in, plus the last one seen at all:
# the gateway process does not live in any workspace, so injection resolved
# from os.getcwd() queried the wrong project hash and returned nothing.
_session_cwd: dict[str, str] = {}
_last_cwd: str = ""


def _log(message: str) -> None:
    print(f"[craftsman] {message}", file=sys.stderr)


def _data_dir() -> Path:
    try:
        from plugins.plugin_storage import plugin_data_dir  # type: ignore

        return Path(plugin_data_dir("craftsman"))
    except Exception:
        return Path(os.environ.get("CLAUDE_PLUGIN_DATA") or Path.home() / ".claude" / "plugins" / "data" / "craftsman")


def _env() -> dict[str, str]:
    env = os.environ.copy()
    env["CLAUDE_PLUGIN_DATA"] = str(_data_dir())
    env["CRAFTSMAN_METRICS_SOURCE"] = "hermes"
    env.setdefault("CRAFTSMAN_GATE_SECONDS", str(_GATE_SECONDS))
    return env


def _run_gate(payload: dict[str, Any], cwd: str) -> dict[str, Any] | None:
    proc = subprocess.run(
        ["bash", str(_GATE)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=_GATE_SECONDS + 30,
        env=_env(),
        cwd=cwd,
    )
    out = (proc.stdout or "").strip()
    if not out:
        # pre-verify.sh always exits 0 and reports its own failures as a block
        # directive, so a nonzero exit with no output means the gate itself
        # never ran. That is a failure to surface, never a clean turn.
        if proc.returncode != 0:
            raise RuntimeError(f"gate exited {proc.returncode} with no verdict")
        return None
    return json.loads(out.splitlines()[0])


def _metrics_call(cwd: str, *call: str) -> str:
    proc = subprocess.run(
        ["bash", "-c", 'source "$1" && metrics_init >/dev/null 2>&1; shift; "$@"', "_", str(_METRICS_LIB), *call],
        capture_output=True,
        text=True,
        timeout=30,
        env=_env(),
        cwd=cwd,
    )
    return (proc.stdout or "").strip()


def _directive_text(directive: dict[str, Any] | None) -> str:
    if not directive:
        return ""
    return str(directive.get("reason") or directive.get("message") or "")


def _learn(session_id: str, attempt: int, directive: dict[str, Any] | None, cwd: str) -> None:
    if not session_id:
        return
    text = _directive_text(directive)
    blocking = bool(directive and ("decision" in directive))
    current = set(_RULE_RE.findall(text)) if blocking else set()
    patterns = dict((rule, path) for path, rule in _FILE_RULE_RE.findall(text))

    if attempt == 0:
        _session_rules[session_id] = current
        severity = "critical"
        for rule in sorted(current):
            _metrics_call(cwd, "metrics_record_violation", rule, patterns.get(rule, "<hermes-turn>"), severity, "1", "0")
        return

    previous = _session_rules.get(session_id, set())
    for rule in sorted(previous - current):
        _metrics_call(cwd, "metrics_record_correction", rule, patterns.get(rule, "<hermes-turn>"), "fixed", f"hermes attempt {attempt}")
    _session_rules[session_id] = current


def _track_workspace(session_id: str, cwd: str) -> None:
    global _last_cwd
    if session_id:
        _session_cwd[session_id] = cwd
    _last_cwd = cwd


def _resolve_trends(session_id: str) -> str:
    # The gateway process lives outside any workspace: prefer the last
    # workspace this session's gate ran in, then the last one seen at all,
    # and fall back to machine-wide trends when the project-scoped query has
    # nothing to say (a session's first turn precedes its first gate run).
    cwd = _session_cwd.get(session_id) or _last_cwd or os.getcwd()
    trends = _metrics_call(cwd, "metrics_correction_trends")
    if not trends:
        trends = _metrics_call(cwd, "metrics_correction_trends_global")
    return trends


def _payload(session_id: str, cwd: str, coding: bool, attempt: int, changed_paths: list[str]) -> dict[str, Any]:
    return {
        "hook_event_name": "pre_verify",
        "session_id": session_id,
        "cwd": cwd,
        "extra": {"coding": coding, "attempt": attempt, "changed_paths": changed_paths},
    }


def on_pre_verify(
    session_id: str = "",
    coding: bool = False,
    attempt: int = 0,
    changed_paths: list[str] | None = None,
    **kwargs: Any,
) -> dict[str, Any] | None:
    try:
        cwd = str(kwargs.get("cwd") or os.getcwd())
        _track_workspace(session_id, cwd)
        attempt = int(attempt or 0)
        directive = _run_gate(_payload(session_id, cwd, bool(coding), attempt, list(changed_paths or [])), cwd)
        try:
            # Only a coding turn teaches anything: the gate stays silent on the
            # others, and letting that silence reset the session's rule state
            # erased the violation between attempt 0 and the fix that followed.
            if coding:
                _learn(session_id, attempt, directive, cwd)
        except Exception as exc:  # learning must never change the verdict
            _log(f"learning skipped: {exc}")
        return directive
    except Exception as exc:
        return {
            "decision": "block",
            "reason": f"The craftsman gate could not run ({exc}). Do not conclude until it does.",
        }


def on_pre_llm_call(
    session_id: str = "",
    user_message: str = "",
    is_first_turn: bool = False,
    **kwargs: Any,
) -> dict[str, str] | None:
    if not is_first_turn or not _INJECT_TRENDS:
        return None
    try:
        trends = _resolve_trends(session_id)
        if not trends:
            return None
        return {
            "context": (
                "[craftsman] Correction history on this machine, most-fixed rules first:\n"
                + trends
                + "\nAvoid reintroducing these; the gate will refuse the turn."
            )
        }
    except Exception as exc:
        _log(f"trend injection skipped: {exc}")
        return None


def _command(raw_args: str) -> str:
    args = (raw_args or "").strip()
    if args == "status":
        db = _data_dir() / "metrics.db"
        counts = ""
        if db.is_file():
            counts = _metrics_call(os.getcwd(), "metrics_corrections_30d") or "no corrections in 30 days"
        return (
            f"craftsman {_read_version()}\n"
            f"gate: {_GATE}\n"
            f"metrics: {db} ({'present' if db.is_file() else 'not created yet'})\n"
            f"{counts}"
        )
    directive = on_pre_verify(session_id="", coding=True, attempt=0, changed_paths=[], cwd=os.getcwd())
    if directive is None:
        return "craftsman: clean worktree, nothing to fix."
    return _directive_text(directive) or json.dumps(directive)


def _read_version() -> str:
    try:
        manifest = json.loads((_PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text())
        return str(manifest.get("version", "unknown"))
    except Exception:
        return "unknown"


def _load_config(ctx: Any) -> None:
    global _GATE_SECONDS, _INJECT_TRENDS
    try:
        _GATE_SECONDS = int(ctx.get_config("gate_seconds", default=45))
    except Exception:
        _GATE_SECONDS = 45
    try:
        _INJECT_TRENDS = str(ctx.get_config("inject_trends", default="on")).lower() != "off"
    except Exception:
        _INJECT_TRENDS = True


def _register_command(ctx: Any) -> None:
    try:
        ctx.register_command(
            name="craftsman",
            handler=_command,
            description="Run the craftsman quality gate on the current worktree",
            args_hint="[status]",
        )
    except Exception as exc:
        _log(f"slash command unavailable on this host: {exc}")


def _register_skills(ctx: Any) -> None:
    skills_dir = _PLUGIN_ROOT / "adapters" / "hermes" / "skills"
    if not skills_dir.is_dir():
        return
    for child in sorted(skills_dir.iterdir()):
        skill_md = child / "SKILL.md"
        if not (child.is_dir() and skill_md.is_file()):
            continue
        try:
            ctx.register_skill(child.name, skill_md)
        except Exception as exc:
            _log(f"skill {child.name} not registered: {exc}")


def register(ctx: Any) -> None:
    _load_config(ctx)
    ctx.register_hook("pre_verify", on_pre_verify)
    ctx.register_hook("pre_llm_call", on_pre_llm_call)
    _register_command(ctx)
    _register_skills(ctx)
