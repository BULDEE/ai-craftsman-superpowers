#!/usr/bin/env python3
"""One session's quality state as JSON, for the cockpit mod (ADR-0031).

Usage:
  session_status.py <state.json> <session-writes> <session-violations> <session-start-ts>

Prints {"since", "writes", "files", "blocked", "warned", "open", "tests",
"compactions"} from the files the hooks already keep for the session, and
writes nothing. A program reads this, never the prose a hook prints, so a
reworded message cannot silently blank the band or the turn receipt.
"""
from __future__ import annotations

import json
import sys
from typing import NamedTuple


def _lines(path: str) -> list[str]:
    try:
        with open(path, encoding='utf-8', errors='replace') as handle:
            return [line.rstrip('\n') for line in handle if line.strip()]
    except OSError:
        return []


def _state(path: str) -> dict:
    try:
        with open(path, encoding='utf-8') as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return {}
    return state if isinstance(state, dict) else {}


def _since(path: str) -> int | None:
    marker = _lines(path)
    return int(marker[0]) if marker and marker[0].isdigit() else None


def _open_blocks(state: dict) -> list[dict]:
    pending = state.get('blocked_violations')
    if not isinstance(pending, dict):
        return []
    return [{'file': path, 'rules': [str(rule) for rule in rules]}
            for path, rules in sorted(pending.items()) if isinstance(rules, list) and rules]


# The verdict the hooks hold on this session's tests, in the order they decide
# it: a red run outstanding outranks evidence, and evidence outranks a run that
# tested nothing.
def _verdict(state: dict, red: list[str]) -> str:
    if red:
        return 'red'
    if state.get('verified') is True:
        return 'verified'
    if state.get('last_test_empty') is True:
        return 'empty'
    tested = any(key in state for key in ('verified', 'last_test_failed', 'last_test_empty'))
    return 'unverified' if tested else 'not-run'


def _tests(state: dict) -> dict:
    runs = [run for run in state.get('failed_test_runs') or [] if isinstance(run, dict)]
    red = [str(run.get('command', '')) for run in runs]
    return {'verdict': _verdict(state, red), 'red_runs': red}


class SessionFiles(NamedTuple):
    state: str
    writes: str
    violations: str
    start: str


def status(files: SessionFiles) -> dict:
    state, writes, marks = _state(files.state), _lines(files.writes), _lines(files.violations)
    return {
        'since': _since(files.start),
        'writes': len(writes),
        'files': len(set(writes)),
        'blocked': marks.count('blocked'),
        'warned': marks.count('warned'),
        'open': _open_blocks(state),
        'tests': _tests(state),
        'compactions': int(state.get('compact_count') or 0),
    }


if __name__ == '__main__':
    if len(sys.argv) != 5:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        sys.exit(2)
    print(json.dumps(status(SessionFiles(*sys.argv[1:5]))))
