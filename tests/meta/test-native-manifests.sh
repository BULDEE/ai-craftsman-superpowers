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
mkdir -p "$FIXTURE/bin" "$FIXTURE/ci" "$FIXTURE/tools"
cp "$ROOT/bin/craftsman-grok-install" "$FIXTURE/bin/"
printf '#!/bin/sh\nprintf "grok %%s\\n" "$*" >> "$CALL_LOG"\n' > "$FIXTURE/tools/grok"
printf '#!/bin/sh\nprintf "ci %%s\\n" "$*" >> "$CALL_LOG"\n' > "$FIXTURE/ci/craftsman-ci.sh"
chmod +x "$FIXTURE/tools/grok"
export CALL_LOG="$FIXTURE/calls"
PATH="$FIXTURE/tools:$PATH" bash "$FIXTURE/bin/craftsman-grok-install" >/dev/null
assert_not_contains 'native install exports no hook configuration' "$(cat "$CALL_LOG")" 'ci export'
PATH="$FIXTURE/tools:$PATH" bash "$FIXTURE/bin/craftsman-grok-install" --compat-hooks >/dev/null
assert_contains 'explicit compatibility retains the hook export' "$(cat "$CALL_LOG")" 'ci export --target grok-hooks'
PATH="$FIXTURE/tools:$PATH" bash "$FIXTURE/bin/craftsman-grok-install" --invalid >/dev/null 2>&1
assert_exit_code 'unknown install modes are rejected' 2 "$?"
rm -rf "$FIXTURE"
test_summary
