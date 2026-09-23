#!/usr/bin/env python3
"""Write a host's own hooks file from the plugin's manifest.

A host that discovers `hooks/hooks.json` and runs none of it (Grok 1.0.30,
measured twice) still runs a project or global hooks file. That file is this
manifest with three differences, and writing it by hand is how a wiring drifts
from the manifest it is supposed to mirror:

  - `${CLAUDE_PLUGIN_ROOT}` is expanded, because nothing expands it there;
  - the handlers carry the plugin's root and data directory in their own
    environment, since only a plugin hook is given them;
  - events the host does not fire are dropped. On Grok an `if:` handler is
    kept without the `if` (pre-push-verify.sh exits 0 unless it is git push).

Usage: host_hooks.py <host> <plugin root> <output file> [--data DIR]
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys

# What each host does not fire, measured (hooks/host-capabilities.json).
UNFIRED = {
    "grok": ("TaskCompleted", "FileChanged"),
    "codex": ("TaskCompleted", "PostToolUseFailure", "FileChanged"),
}

# Grok 1.0.34 aliases Write/Edit to search_replace and keeps the Claude
# name, but the create tool is `write` (lowercase) and is not that alias
# (hooks guide: Write -> search_replace). A matcher that only says Write|Edit
# therefore misses every creation. Extra names are OR'd; Claude ignores them.
GROK_MATCHER_EXTRA = {
    "Write": ("write", "search_replace"),
    "Edit": ("write", "search_replace"),
    "Bash": ("run_terminal_command",),
}


def _matcher_for(host: str, matcher: str) -> str:
    if host != "grok" or not matcher:
        return matcher
    seen = []
    for part in matcher.split("|"):
        if part and part not in seen:
            seen.append(part)
        for extra in GROK_MATCHER_EXTRA.get(part, ()):
            if extra not in seen:
                seen.append(extra)
    return "|".join(seen)


# Names the host itself exports to a native plugin hook. The engine scripts
# still read CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA, so those two are set
# for every host. A host's own names are added only for that host: a Codex
# gate must not carry GROK_PLUGIN_*, and a Grok gate must not carry PLUGIN_DATA.
_NATIVE_ENV = {
    "grok": ("GROK_PLUGIN_ROOT", "GROK_PLUGIN_DATA"),
    "codex": ("PLUGIN_ROOT", "PLUGIN_DATA"),
}


def _env_prefix(host: str, root: str, data: str) -> str:
    names = ["CLAUDE_PLUGIN_ROOT", "CLAUDE_PLUGIN_DATA", *_NATIVE_ENV.get(host, ())]
    values = {
        "CLAUDE_PLUGIN_ROOT": root,
        "CLAUDE_PLUGIN_DATA": data,
        "GROK_PLUGIN_ROOT": root,
        "GROK_PLUGIN_DATA": data,
        "PLUGIN_ROOT": root,
        "PLUGIN_DATA": data,
    }
    body = " ".join(f"{name}={shlex.quote(values[name])}" for name in names)
    return f"env {body} "


def _data_dir(host: str) -> str:
    if "--data" in sys.argv:
        return sys.argv[sys.argv.index("--data") + 1]
    # A Claude session's CLAUDE_PLUGIN_DATA must not be baked into another
    # host's gate. That variable is inherited by every child of this process.
    if host == "claude-code":
        inherited = os.environ.get("CLAUDE_PLUGIN_DATA", "")
        if inherited:
            return inherited
        return os.path.join(os.path.expanduser("~"), ".claude", "plugins", "data", "craftsman")
    return os.path.join(os.path.expanduser("~"), f".{host}", "plugins", "data", "craftsman")


def _handler(entry: dict, root: str, data: str, host: str) -> dict | None:
    if "if" in entry and host != "grok":
        return None
    command = str(entry.get("command", "")).replace("${CLAUDE_PLUGIN_ROOT}", root)
    if not command:
        return None
    out = {"type": entry.get("type", "command"), "command": _env_prefix(host, root, data) + command}
    if entry.get("timeout"):
        out["timeout"] = entry["timeout"]
    return out


def _marker(root: str) -> dict:
    version = "unknown"
    manifest = os.path.join(root, ".claude-plugin", "plugin.json")
    if os.path.isfile(manifest):
        try:
            version = str(json.load(open(manifest, encoding="utf-8")).get("version") or "unknown")
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


def _groups(groups: list, root: str, data: str, host: str) -> list:
    kept = []
    for group in groups:
        handlers = [made for made in (_handler(entry, root, data, host) for entry in group.get("hooks", [])) if made]
        if not handlers:
            continue
        rewritten = {"hooks": handlers}
        if group.get("matcher"):
            rewritten["matcher"] = _matcher_for(host, group["matcher"])
        kept.append(rewritten)
    return kept


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    host, root, output = sys.argv[1:4]
    data = _data_dir(host)
    manifest = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))
    unfired = UNFIRED.get(host, ())
    hooks = {}
    for event, groups in manifest.get("hooks", {}).items():
        if event in unfired:
            continue
        kept = _groups(groups, root, data, host)
        if kept:
            hooks[event] = kept
    os.makedirs(os.path.dirname(os.path.abspath(output)) or ".", exist_ok=True)
    with open(output, "w", encoding="utf-8") as handle:
        json.dump({"craftsman": _marker(root), "hooks": hooks}, handle, indent=2)
        handle.write("\n")
    handlers = sum(len(group["hooks"]) for groups in hooks.values() for group in groups)
    print(f"wrote {handlers} handler(s) on {len(hooks)} event(s) to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
