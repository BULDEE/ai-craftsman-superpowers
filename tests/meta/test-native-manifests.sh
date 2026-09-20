#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/lib/test-helpers.sh"
python3 "$ROOT/scripts/native-manifests.py" --check
assert_exit_code 'native manifests match their publisher metadata' 0 "$?"
FIXTURE=$(mktemp -d)
mkdir -p "$FIXTURE/.claude-plugin"
cp "$ROOT/.claude-plugin/"*.json "$FIXTURE/.claude-plugin/"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" >/dev/null
printf '{"name":"wrong"}\n' > "$FIXTURE/plugin.json"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" --check >/dev/null
assert_exit_code 'guard rejects a stale native manifest' 1 "$?"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" >/dev/null
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" --check >/dev/null
assert_exit_code 'regeneration restores the native manifest' 0 "$?"
rm -rf "$FIXTURE"
test_summary
