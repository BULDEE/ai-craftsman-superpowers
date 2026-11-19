#!/usr/bin/env python3
"""Which of this plugin's hooks Codex runs, read from Codex's own trust record.

Codex runs a plugin hook only once its exact definition is trusted: "Non-managed
hooks must be reviewed and trusted before they run", and "Codex records trust
against the hook's current hash, so new or changed hooks are marked for review
and skipped until trusted" (developers.openai.com/codex/hooks, read 2026-11-19).
Installing or updating the plugin trusts nothing, and nothing outside the
/hooks view says which hooks stopped.

The record is the user config.toml, one `[hooks.state."<key>"]` table per
handler with `trusted_hash` and, when the user turned it off, `enabled = false`.
Only the user layer writes it (codex-rs/hooks/src/config_rules.rs). The key is
`<plugin>@<marketplace>:<hooks file>:<event>:<group>:<handler>`, two positions
in the manifest (codex-rs/hooks/src/lib.rs hook_key), so a handler inserted
ahead of others moves them onto keys trusted for another definition. The hash
is sha256 over the compact, key-sorted JSON of the normalized handler
(codex-rs/hooks/src/engine/discovery.rs hook_hash, codex-rs/config/src/
fingerprint.rs version_for_toml, both at rust-v0.163.0).

Usage: codex_hook_trust.py <plugin root> <config.toml> <events Codex loads, comma-separated>

Prints one `<verdict>\t<key>\t<script>` line per handler Codex lists, in
manifest order, the key without its plugin prefix. Verdicts, as Codex's own
hooks/list names them: trusted, modified, untrusted, plus disabled. Exit 3
when the plugin is not among the plugins config.toml records.
"""

import hashlib
import json
import os
import re
import sys
from typing import Dict, Iterator, List, Optional, Set, Tuple

# A handler with no timeout gets 600 s, SessionEnd and Interrupt 1 s within
# 1..3 (normalize_command_hook). The default context limit is not hashed.
_SHORT_EVENTS = {"SessionEnd", "Interrupt"}
_NO_MATCHER_EVENTS = {"UserPromptSubmit", "Stop", "Interrupt"}
_DEFAULT_CONTEXT_LIMIT = 2500

Handler = Tuple[str, int, int, Optional[str], dict]
States = Dict[str, Dict[str, str]]


def _snake(event: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", event).lower()


def _timeout(event: str, value: Optional[int]) -> int:
    if event in _SHORT_EVENTS:
        return min(max(1 if value is None else value, 1), 3)
    return max(600 if value is None else value, 1)


def handler_hash(event: str, matcher: Optional[str], handler: dict) -> str:
    """The trusted_hash Codex expects for one command handler."""
    normalized = {"type": "command", "command": handler["command"],
                  "timeout": _timeout(event, handler.get("timeout")),
                  "async": bool(handler.get("async", False))}
    if handler.get("statusMessage") is not None:
        normalized["statusMessage"] = handler["statusMessage"]
    limit = handler.get("additionalContextLimit")
    if limit is not None and limit != _DEFAULT_CONTEXT_LIMIT:
        normalized["additionalContextLimit"] = limit
    identity = {"event_name": _snake(event), "hooks": [normalized]}
    if event not in _NO_MATCHER_EVENTS and matcher is not None:
        identity["matcher"] = matcher
    text = json.dumps(identity, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def hook_states(config_text: str, prefix: str) -> States:
    """{key after prefix: {"trusted_hash": ..., "enabled": ...}} from the tables Codex writes."""
    states: States = {}
    current: Optional[Dict[str, str]] = None
    for line in config_text.splitlines():
        header = re.match(r'^\s*\[hooks\.state\."((?:[^"\\]|\\.)*)"\]\s*$', line)
        if header:
            key = header.group(1)
            current = states.setdefault(key[len(prefix):], {}) if key.startswith(prefix) else None
            continue
        if line.lstrip().startswith("["):
            current = None
            continue
        field = re.match(r'^\s*(trusted_hash|enabled)\s*=\s*"?([^"\s#]*)"?', line)
        if current is not None and field:
            current[field.group(1)] = field.group(2)
    return states


def plugin_id(root: str, name: str, config_text: str) -> Optional[str]:
    """<name>@<marketplace>: from the cache layout Codex installs into, else
    from the one [plugins."<name>@..."] table config.toml records."""
    parts = os.path.realpath(root).split(os.sep)
    if len(parts) >= 5 and parts[-5:-3] == ["plugins", "cache"] and parts[-2] == name:
        return "%s@%s" % (name, parts[-3])
    found = re.findall(r'^\s*\[plugins\."(%s@[^"]+)"\]' % re.escape(name), config_text, re.M)
    return found[0] if len(found) == 1 else None


def _script(command: str) -> str:
    match = re.search(r"([\w.-]+\.(?:sh|py))\b", command)
    return match.group(1) if match else command[:40]


def _is_command(handler: dict) -> bool:
    return handler.get("type") == "command" and bool(handler.get("command", "").strip())


def _event_handlers(event: str, groups: List[dict]) -> Iterator[Handler]:
    for group_index, group in enumerate(groups):
        yield from ((event, group_index, handler_index, group.get("matcher"), handler)
                    for handler_index, handler in enumerate(group.get("hooks", []))
                    if _is_command(handler))


def _verdict(state: Dict[str, str], current: str) -> str:
    if state.get("enabled") == "false":
        return "disabled"
    if "trusted_hash" not in state:
        return "untrusted"
    return "trusted" if state["trusted_hash"] == current else "modified"


def verdicts(manifest: dict, events_loaded: Set[str], states: States) -> Iterator[Tuple[str, str, str]]:
    """(verdict, key, script) for each handler Codex lists, in manifest order."""
    for event, groups in manifest.get("hooks", {}).items():
        if event not in events_loaded:
            continue
        for _, group_index, handler_index, matcher, handler in _event_handlers(event, groups):
            key = "%s:%d:%d" % (_snake(event), group_index, handler_index)
            current = handler_hash(event, matcher, handler)
            yield _verdict(states.get(key, {}), current), key, _script(handler["command"])


def main(argv: List[str]) -> int:
    root, config_path, events = argv[1], argv[2], set(argv[3].split(","))
    with open(os.path.join(root, ".codex-plugin", "plugin.json")) as handle:
        plugin = json.load(handle)
    hooks_file = plugin.get("hooks", "./hooks/hooks.json")
    with open(os.path.join(root, hooks_file)) as handle:
        manifest = json.load(handle)
    config_text = ""
    if os.path.exists(config_path):
        with open(config_path, encoding="utf-8") as handle:
            config_text = handle.read()
    pid = plugin_id(root, plugin["name"], config_text)
    if pid is None:
        return 3
    prefix = "%s:%s:" % (pid, re.sub(r"^\./", "", hooks_file))
    for verdict, key, script in verdicts(manifest, events, hook_states(config_text, prefix)):
        print("%s\t%s\t%s" % (verdict, key, script))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
