#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 "$ROOT/tests/core/runtime_paths_test.py" || exit 1
python3 "$ROOT/tests/core/native_session_lifecycle_test.py"
