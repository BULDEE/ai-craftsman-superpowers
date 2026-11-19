#!/usr/bin/env python3
"""Plugin hooks a change would stop under Codex without saying so (CR-320).

Codex keys each plugin hook's trust by its position in hooks.json, the group
and the handler index under the event, and records there the hash of the
definition the user approved (hooks/lib/codex_hook_trust.py cites the source).
A handler inserted ahead of others moves them onto keys trusted for another
definition, and Codex skips them until the user reviews /hooks again. Measured
on 2026-11-19 (CR-317): on a machine whose approvals dated from September, 9 of
the 19 hooks Codex lists were skipped, among them the git guard and the
end-of-turn gate, and nothing in the release said so.

This compares every position the last published release had with the same
position now. A position whose definition changed is a hook every Codex user
has to approve again, so the change is refused unless CHANGELOG.md names its
key above the published version's heading. A handler appended at the end of
its group, or a group appended at the end of its event, takes a new key and
moves nothing.

Usage: codex-trust-drift.py <repository root> [<published ref>]

The published ref defaults to the newest v<x.y.z> tag reachable from HEAD.
Prints `<key>\t<published script>\t<current script>` per unannounced change.
Exit 0: none. 1: some. 3: no published ref (a clone without its tags).
"""

import json
import os
import re
import subprocess
import sys
from typing import Dict, Iterator, List, Optional, Set, Tuple

_TRUST_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "hooks", "lib")

Positions = Dict[str, Tuple[str, str]]
Change = Tuple[str, str, str]


def _keyed_handlers(manifest: dict, events_loaded: Set[str]) -> Iterator[Tuple[str, str, str]]:
    """The key and hash rule the healthcheck reads trust with, so both agree."""
    if _TRUST_LIB not in sys.path:
        sys.path.insert(0, _TRUST_LIB)
    from codex_hook_trust import keyed_handlers
    return keyed_handlers(manifest, events_loaded)


def _git(root: str, *args: str) -> Optional[str]:
    run = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, check=False)
    return run.stdout if run.returncode == 0 else None


def published_ref(root: str) -> Optional[str]:
    """The newest v<x.y.z> tag HEAD descends from."""
    described = _git(root, "describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", "HEAD")
    return described.strip() if described else None


def _read(path: str) -> str:
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def _hooks_file(root: str) -> str:
    plugin = json.loads(_read(os.path.join(root, ".codex-plugin", "plugin.json")) or "{}")
    return re.sub(r"^\./", "", plugin.get("hooks", "./hooks/hooks.json"))


def positions(manifest_text: str, events_loaded: Set[str]) -> Positions:
    """{key: (hash Codex trusts, script)} for one hooks.json."""
    manifest = json.loads(manifest_text or "{}")
    return {key: (digest, script) for key, digest, script in _keyed_handlers(manifest, events_loaded)}


def moved(published: Positions, current: Positions) -> List[Change]:
    """Positions trusted at publication whose definition is no longer the one trusted."""
    return [(key, published[key][1], current[key][1])
            for key in published
            if key in current and current[key][0] != published[key][0]]


def notes_since(changelog: str, ref: str) -> str:
    """CHANGELOG text written after the published version's heading."""
    version = re.match(r"^v(\d+\.\d+\.\d+)$", ref)
    if not version:
        return changelog
    heading = re.search(r"^## \[%s\]" % re.escape(version.group(1)), changelog, re.M)
    return changelog[:heading.start()] if heading else changelog


def unannounced(changes: List[Change], notes: str) -> List[Change]:
    return [change for change in changes
            if not re.search(r"(?<![\w:])%s(?![\w:])" % re.escape(change[0]), notes)]


def main(argv: List[str]) -> int:
    root = argv[1]
    ref = argv[2] if len(argv) > 2 else published_ref(root)
    if not ref:
        print("no published v<x.y.z> tag reachable from HEAD: fetch the tags", file=sys.stderr)
        return 3
    capabilities = json.loads(_read(os.path.join(root, "hooks", "host-capabilities.json")) or "{}")
    events = set(capabilities.get("hosts", {}).get("codex", {}).get("events_loaded", []))
    hooks_file = _hooks_file(root)
    published = positions(_git(root, "show", "%s:%s" % (ref, hooks_file)) or "", events)
    current = positions(_read(os.path.join(root, hooks_file)), events)
    notes = notes_since(_read(os.path.join(root, "CHANGELOG.md")), ref)
    found = unannounced(moved(published, current), notes)
    for key, was, now in found:
        print("%s\t%s\t%s" % (key, was, now))
    if found:
        print("Codex skips these hooks until each user approves them again in /hooks. "
              "Append a new handler at the end of its group, or name each key in "
              "CHANGELOG.md so Codex users know what to approve.", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
