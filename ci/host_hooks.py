#!/usr/bin/env python3
"""Write a host's own hooks file from the plugin's manifest.

A host that discovers `hooks/hooks.json` and runs none of it (Grok 1.0.30,
measured twice) still runs a project or global hooks file. That file is this
manifest with three differences, and writing it by hand is how a wiring drifts
from the manifest it is supposed to mirror:

  - `${CLAUDE_PLUGIN_ROOT}` is expanded, because nothing expands it there;
  - the handlers carry the plugin's root and data directory in their own
    environment, since only a plugin hook is given them;
  - events the host does not fire (absent from its row's events_loaded in
    hooks/host-capabilities.json) are dropped. On Grok an `if:` handler is
    kept without the `if` (pre-push-verify.sh exits 0 unless it is git push).

Usage: host_hooks.py <host> <plugin root> <output file> [--data DIR]
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
import tempfile

def _capabilities(root: str) -> dict:
    with open(os.path.join(root, "hooks", "host-capabilities.json"), encoding="utf-8") as handle:
        return json.load(handle).get("hosts", {})


def _row(root: str, host: str) -> dict:
    row = _capabilities(root).get(host)
    if not isinstance(row, dict):
        raise SystemExit(f"host '{host}' is not in hooks/host-capabilities.json")
    return row


def _export_facts(row: dict, host: str) -> dict:
    facts = row.get("gate_export")
    if not row.get("gate_file") or not isinstance(facts, dict):
        note = row.get("gate_note") or "its plugin hooks run natively"
        raise SystemExit(f"host '{host}' declares no gate_file in hooks/host-capabilities.json. {note}")
    return facts


def _matcher_for(facts: dict, matcher: str) -> str:
    aliases = facts.get("matcher_aliases") or {}
    if not aliases or not matcher:
        return matcher
    seen = []
    for part in matcher.split("|"):
        if part and part not in seen:
            seen.append(part)
        for extra in aliases.get(part, ()):
            if extra not in seen:
                seen.append(extra)
    return "|".join(seen)


def _env_prefix(facts: dict, root: str, data: str) -> str:
    # The engine scripts read CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA on every
    # host; a host's own names are added only for that host.
    native = facts.get("native_env") or {}
    pairs = [("CLAUDE_PLUGIN_ROOT", root), ("CLAUDE_PLUGIN_DATA", data)]
    if native.get("root"):
        pairs.append((native["root"], root))
    if native.get("data"):
        pairs.append((native["data"], data))
    body = " ".join(f"{name}={shlex.quote(value)}" for name, value in pairs)
    return f"env {body} "


def _data_dir(facts: dict) -> str:
    if "--data" in sys.argv:
        return sys.argv[sys.argv.index("--data") + 1]
    return os.path.join(os.path.expanduser("~"), facts.get("data_dir") or os.path.join("plugins", "data", "craftsman"))


def _handler(entry: dict, root: str, data: str, facts: dict) -> dict | None:
    if "if" in entry and facts.get("conditional_handlers") != "keep_without_if":
        return None
    command = str(entry.get("command", "")).replace("${CLAUDE_PLUGIN_ROOT}", root)
    if not command:
        return None
    out = {"type": entry.get("type", "command"), "command": _env_prefix(facts, root, data) + command}
    timeout = entry.get("timeout") or facts.get("timeout")
    if timeout:
        out["timeout"] = timeout
    return out


def _marker(root: str) -> dict:
    version = "unknown"
    manifest = os.path.join(root, ".claude-plugin", "plugin.json")
    if os.path.isfile(manifest):
        try:
            with open(manifest, encoding="utf-8") as handle:
                version = str(json.load(handle).get("version") or "unknown")
        except (OSError, json.JSONDecodeError):
            version = "unknown"
    commit = "unknown"
    try:
        commit = subprocess.check_output(
            ["git", "-C", root, "rev-parse", "--short=12", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip() or "unknown"
    except (OSError, subprocess.CalledProcessError):
        commit = "unknown"
    return {"root": os.path.realpath(root), "commit": commit, "version": version}


def _groups(groups: list, root: str, data: str, facts: dict) -> list:
    kept = []
    for group in groups:
        handlers = [made for made in (_handler(entry, root, data, facts) for entry in group.get("hooks", [])) if made]
        if not handlers:
            continue
        rewritten = {"hooks": handlers}
        if group.get("matcher"):
            rewritten["matcher"] = _matcher_for(facts, group["matcher"])
        kept.append(rewritten)
    return kept


def gate_relpath(root: str, host: str) -> str:
    """Relative path of the exported gate, empty when the host declares none."""
    try:
        declared = _capabilities(root).get(host, {}).get("gate_file")
    except (OSError, json.JSONDecodeError, AttributeError):
        return ""
    return declared if isinstance(declared, str) else ""


def _write_gate(output: str, payload: dict) -> None:
    # A symlinked gate or gate directory is refused, never followed: a project
    # that ships .grok/hooks/craftsman.json as a link would otherwise turn the
    # export into a write anywhere its author chose.
    directory = os.path.dirname(os.path.abspath(output)) or "."
    for path in (output, directory):
        if os.path.islink(path):
            raise SystemExit(f"refusing to write the gate through a symlink: {path}")
    os.makedirs(directory, exist_ok=True)
    mode = os.stat(output).st_mode & 0o777 if os.path.exists(output) else None
    if mode is None:
        umask = os.umask(0)
        os.umask(umask)
        mode = 0o644 & ~umask
    descriptor, temporary = tempfile.mkstemp(dir=directory, prefix=".craftsman-gate-")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")
        os.chmod(temporary, mode)
        os.replace(temporary, output)
    except Exception:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise


def main() -> int:
    if len(sys.argv) >= 4 and sys.argv[1] == "--gate-rel":
        print(gate_relpath(sys.argv[2], sys.argv[3]))
        return 0
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    host, root, output = sys.argv[1:4]
    row = _row(root, host)
    facts = _export_facts(row, host)
    data = _data_dir(facts)
    with open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8") as handle:
        manifest = json.load(handle)
    loaded = set(row.get("events_loaded") or ())
    hooks = {}
    for event, groups in manifest.get("hooks", {}).items():
        if loaded and event not in loaded:
            continue
        kept = _groups(groups, root, data, facts)
        if kept:
            hooks[event] = kept
    _write_gate(output, {"craftsman": _marker(root), "hooks": hooks})
    handlers = sum(len(group["hooks"]) for groups in hooks.values() for group in groups)
    print(f"wrote {handlers} handler(s) on {len(hooks)} event(s) to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
