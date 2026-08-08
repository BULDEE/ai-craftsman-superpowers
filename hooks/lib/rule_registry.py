#!/usr/bin/env python3
"""
Rule registry builder.

Reads rules/core.yml and every pack.yml handed to it, and emits one flat TSV
describing the rules the installation enforces. ci/doctrine-export.sh used to
own every id, its group and its wording, and hooks/lib/rules-engine.sh owned the
advisory defaults, so a pack shipping DART001 had nowhere to declare any of it.

Output, one row per rule:

    <id>\t<group>\t<default_severity>\t<owner>\t<text>

Text comes last: it is the only field that may contain spaces, so a consumer can
cut the first four columns without quoting rules.

A separate marker row fixes the order groups appear in:

    __group__\t<position>\t\t<owner>\t<group name>

Usage:
    rule_registry.py <rules/core.yml> [<pack.yml> ...]
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

VALID_SEVERITIES = ("block", "warn", "ignore")
GROUP_MARKER = "__group__"


def _parse(path: str) -> dict:
    try:
        import yaml
    except ImportError:
        return _parse_fallback(path)
    try:
        with open(path, "r") as handle:
            return yaml.safe_load(handle) or {}
    except Exception:
        return {}


def _fallback_flush(current: dict, into: list) -> None:
    if current:
        into.append(dict(current))


class _FallbackReader:
    """Minimal reader for the `rules: owned:` and `groups:` blocks."""

    def __init__(self) -> None:
        self.result: dict = {"rules": [], "groups": []}
        self._current: dict = {}
        self._section = ""

    def feed(self, raw: str) -> None:
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            return
        stripped = line.strip()
        if not line.startswith((" ", "\t")):
            self._close()
            # A pack.yml also has `languages:` entries keyed by `- id:`, and
            # reading those as rules produced phantom rules in an "Other" group.
            # Only the top-level `rules:` and `groups:` blocks are ours.
            if stripped.startswith("groups:"):
                self._section = "groups"
            elif stripped.startswith("rules:"):
                self._section = "rules"
            else:
                self._section = ""
            return
        self._feed_indented(stripped)

    def _feed_indented(self, stripped: str) -> None:
        from lang_registry import _unquote

        if self._section == "groups" and stripped.startswith("- "):
            self.result["groups"].append(_unquote(stripped[2:]))
            return
        if self._section != "rules":
            return
        if stripped.startswith("- id:"):
            self._close()
            self._current = {"id": _unquote(stripped[5:].strip())}
            return
        if self._current and ":" in stripped:
            key, _, value = stripped.partition(":")
            self._current[key.strip()] = _unquote(value.strip())

    def _close(self) -> None:
        _fallback_flush(self._current, self.result["rules"])
        self._current = {}

    def done(self) -> dict:
        self._close()
        return self.result


def _parse_fallback(path: str) -> dict:
    reader = _FallbackReader()
    try:
        lines = open(path, "r").read().splitlines()
    except OSError:
        return reader.done()
    for raw in lines:
        reader.feed(raw)
    return reader.done()


def _emit(row: list) -> None:
    if any("\t" in str(field) or "\n" in str(field) for field in row):
        return
    sys.stdout.write("\t".join(str(field) for field in row) + "\n")


class _Registry:
    """Carries ownership so the per-rule helpers stay within three parameters."""

    def __init__(self) -> None:
        self._owners: dict = {}
        self._groups: list = []
        # Rows are held until every manifest is read: core overriding a pack's
        # declaration cannot unprint a line already sent to stdout.
        self._rows: dict = {}
        self.conflicts = 0

    def add_manifest(self, path: str, owner: str) -> None:
        parsed = _parse(path)
        for name in parsed.get("groups") or []:
            if name not in self._groups:
                self._groups.append(str(name))
        for entry in self._rule_entries(parsed):
            self._add_rule(entry, owner)

    def _rule_entries(self, parsed: dict) -> list:
        rules = parsed.get("rules")
        if isinstance(rules, list):
            return [item for item in rules if isinstance(item, dict)]
        if isinstance(rules, dict):
            owned = rules.get("owned")
            if isinstance(owned, list):
                return [item for item in owned if isinstance(item, dict)]
        return []

    # Two packs claiming one id is a configuration error the user must resolve.
    # Letting load order decide would make the exported doctrine
    # non-deterministic: the same install would document two different wordings
    # depending on which pack was read first.
    #
    # Rules owned by core are not merely first, they win. A third-party pack
    # declaring SEC001 with default_severity: ignore would otherwise disarm a
    # security rule from its own manifest, with no reviewed config in the loop,
    # whenever it happened to be read first.
    def _claim(self, rule_id: str, owner: str) -> bool:
        previous = self._owners.get(rule_id)
        if not previous or previous == owner:
            self._owners[rule_id] = owner
            return True

        self.conflicts += 1
        if previous == "core" or owner != "core":
            sys.stderr.write(
                f"craftsman: rule '{rule_id}' is owned by '{previous}', "
                f"'{owner}' cannot redeclare it\n"
            )
            return False
        sys.stderr.write(
            f"craftsman: rule '{rule_id}' declared by '{previous}' is "
            "overridden by the engine's own definition\n"
        )
        self._owners[rule_id] = owner
        return True

    def _severity_of(self, entry: dict, rule_id: str) -> str:
        severity = str(entry.get("default_severity") or "block").strip()
        if severity in VALID_SEVERITIES:
            return severity
        sys.stderr.write(
            f"craftsman: rule '{rule_id}' declares default_severity "
            f"'{severity}', expected one of {', '.join(VALID_SEVERITIES)}\n"
        )
        return "block"

    def _add_rule(self, entry: dict, owner: str) -> None:
        rule_id = str(entry.get("id") or "").strip()
        if not rule_id or not self._claim(rule_id, owner):
            return
        group = str(entry.get("group") or "Other").strip()
        if group not in self._groups:
            self._groups.append(group)
        self._rows[rule_id] = [
            rule_id, group, self._severity_of(entry, rule_id), owner,
            str(entry.get("text") or rule_id),
        ]

    def flush(self) -> None:
        for rule_id in self._rows:
            _emit(self._rows[rule_id])
        for position, name in enumerate(self._groups):
            _emit([GROUP_MARKER, position, "", "core", name])


def _owner_of(path: str) -> str:
    """core.yml is the engine's own manifest; a pack.yml belongs to its dir."""
    directory = os.path.dirname(os.path.abspath(path))
    if os.path.basename(path) == "core.yml":
        return "core"
    return os.path.basename(directory)


def build(paths: list) -> int:
    registry = _Registry()
    for manifest in paths:
        if os.path.isfile(manifest):
            registry.add_manifest(manifest, _owner_of(manifest))
    registry.flush()
    return 1 if registry.conflicts else 0


def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: rule_registry.py <core.yml> [<pack.yml> ...]\n")
        return 2
    return build(sys.argv[1:])


if __name__ == "__main__":
    sys.exit(main())
