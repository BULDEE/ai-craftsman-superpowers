#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/lib/test-helpers.sh"
python3 "$ROOT/scripts/native-manifests.py" --check
assert_exit_code 'native manifests match their publisher metadata' 0 "$?"
FIXTURE=$(mktemp -d)
mkdir -p "$FIXTURE/.claude-plugin" "$FIXTURE/packs/example/agents"
printf '# Native agent\n' > "$FIXTURE/packs/example/agents/probe.md"
cp "$ROOT/.claude-plugin/"*.json "$FIXTURE/.claude-plugin/"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" >/dev/null
printf '{"name":"wrong"}\n' > "$FIXTURE/.codex-plugin/plugin.json"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" --check >/dev/null
assert_exit_code 'guard rejects a stale native manifest' 1 "$?"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" >/dev/null
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" --check >/dev/null
assert_exit_code 'regeneration restores the native manifest' 0 "$?"
printf '{"name":"portable"}\n' > "$FIXTURE/plugin.json"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" --check >/dev/null
assert_exit_code 'guard rejects a portable entry point masking native hooks' 1 "$?"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" >/dev/null
assert_exit_code 'generator preserves an unexpected portable manifest for explicit resolution' 1 "$?"
rm "$FIXTURE/plugin.json"
printf '# Stale agent\n' > "$FIXTURE/agents/probe.md"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" --check >/dev/null
assert_exit_code 'guard rejects a stale bundled agent' 1 "$?"
rm "$FIXTURE/agents/probe.md"
ln -s ../packs/example/agents/probe.md "$FIXTURE/agents/probe.md"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" --check >/dev/null
assert_exit_code 'guard rejects a bundled agent symlink' 1 "$?"
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" >/dev/null
python3 "$ROOT/scripts/native-manifests.py" --root "$FIXTURE" --check >/dev/null
assert_exit_code 'regeneration restores an ordinary bundled agent' 0 "$?"
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
