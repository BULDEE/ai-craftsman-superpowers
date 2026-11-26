#!/usr/bin/env bash
# The factory pack: its spine end to end, with a stand-in `gh` and no model.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The suite runs inside a Claude Code session whose id and plugin data would
# name the factory's files after the session that launched the tests.
unset CLAUDE_CODE_SESSION_ID CRAFTSMAN_SESSION_ID CRAFTSMAN_PLUGIN_DATA CLAUDE_PLUGIN_DATA
PYTHONPATH="$ROOT/packs/factory/scripts" python3 "$ROOT/tests/packs/factory_test.py" || exit 1
