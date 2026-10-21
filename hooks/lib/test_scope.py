#!/usr/bin/env python3
"""Keep a red test run outstanding until a run at least as wide passes (CR-289).

    test_scope.py fail <state file> <command as run> <runner invocation>
    test_scope.py pass <state file> <runner invocation>

The runner invocation is the command with its launcher removed (`php`,
`npx`, `poetry run`), which post-bash-test-verify.sh strips with the same
pattern that recognised the runner.

`fail` records the run. `pass` clears every red run it covers, grants the
evidence when none is left, and otherwise prints the commands of the red
runs still outstanding, one per line.

A passing run covers a red one when it adds no argument to it. Any added
argument may have narrowed the run, a filter, a path or a test name, and
which flags narrow is each runner's business, so this module names none of
them. The cost of that doubt is one re-run of the red command; the cost of
the other direction is a red suite reported as flaky and pushed, which is
what a session did: the suite failed, the one failing test passed alone, and
that filtered run erased the failure.
"""
from __future__ import annotations

import os
import shlex
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from session_state import mark_verified, read_state, write_state_atomically  # noqa: E402

OUTSTANDING = 'failed_test_runs'


def scope(invocation: str) -> list[str]:
    """The run's arguments, the runner named without its path: `vendor/bin/phpunit`
    and `bin/phpunit` start the same suite."""
    try:
        tokens = shlex.split(invocation)
    except ValueError:
        tokens = invocation.split()
    if tokens:
        tokens[0] = os.path.basename(tokens[0])
    return tokens


def covers(passing: list[str], failed: list[str]) -> bool:
    return not Counter(passing) - Counter(failed)


def record_failure(state: dict, command: str, invocation: str) -> None:
    runs = [run for run in state.get(OUTSTANDING) or [] if run.get('scope') != scope(invocation)]
    runs.append({'command': command, 'scope': scope(invocation)})
    state[OUTSTANDING] = runs
    state['last_test_failed'] = True
    state['verified'] = False


def record_pass(state: dict, invocation: str) -> list[str]:
    passing = scope(invocation)
    runs = [run for run in state.get(OUTSTANDING) or [] if not covers(passing, run.get('scope') or [])]
    state[OUTSTANDING] = runs
    if not runs:
        mark_verified(state)
    return [run.get('command', '') for run in runs]


def main(arguments: list[str]) -> int:
    action, state_path = arguments[0], arguments[1]
    state = read_state(state_path)
    if action == 'fail':
        record_failure(state, arguments[2], arguments[3])
        write_state_atomically(state_path, state)
        return 0
    outstanding = record_pass(state, arguments[2])
    write_state_atomically(state_path, state)
    for command in outstanding:
        print(command)
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
