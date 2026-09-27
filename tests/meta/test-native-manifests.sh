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
assert_contains 'native install writes the grok hook export' "$(cat "$CALL_LOG")" 'ci export --target grok-hooks'
PATH="$FIXTURE/tools:$PATH" bash "$FIXTURE/bin/craftsman-grok-install" --compat-hooks >/dev/null
assert_contains 'explicit compatibility retains the hook export' "$(cat "$CALL_LOG")" 'ci export --target grok-hooks'
PATH="$FIXTURE/tools:$PATH" bash "$FIXTURE/bin/craftsman-grok-install" --invalid >/dev/null 2>&1
assert_exit_code 'unknown install modes are rejected' 2 "$?"
# Already installed is read from `grok plugin list --json`, not from the
# wording of an install error: the install is skipped, the gate still written.
FIXTURE_REAL=$(cd "$FIXTURE" && pwd -P)
cat > "$FIXTURE/tools/grok" << EOF
#!/bin/sh
printf "grok %s\\n" "\$*" >> "\$CALL_LOG"
case "\$*" in
    "plugin list --json") printf '[{"status":"installed","name":"craftsman","source":"%s"}]' "$FIXTURE_REAL" ;;
    "plugin install"*) exit 1 ;;
esac
EOF
chmod +x "$FIXTURE/tools/grok" "$FIXTURE/ci/craftsman-ci.sh"
: > "$CALL_LOG"
HOME="$FIXTURE/home" PATH="$FIXTURE/tools:$PATH" bash "$FIXTURE/bin/craftsman-grok-install" >/dev/null 2>&1; RC=$?
assert_contains 'already installed still exports the gate' "$(cat "$CALL_LOG")" 'ci export --target grok-hooks'
assert_exit_code 'already installed from this checkout is not an error' 0 "$RC"
if grep -q 'grok plugin install' "$CALL_LOG"; then
    log_fail 'already installed skips the install' "$(cat "$CALL_LOG")"
else
    log_pass 'already installed skips the install'
fi
# Not installed and the install fails: nothing is exported.
cat > "$FIXTURE/tools/grok" << 'EOF'
#!/bin/sh
printf "grok %s\n" "$*" >> "$CALL_LOG"
case "$*" in
    "plugin list --json") printf '[]' ;;
    "plugin install"*) echo "install failed" >&2; exit 3 ;;
esac
EOF
: > "$CALL_LOG"
HOME="$FIXTURE/home" PATH="$FIXTURE/tools:$PATH" bash "$FIXTURE/bin/craftsman-grok-install" >/dev/null 2>&1; RC=$?
if [[ "$RC" -ne 0 ]] && ! grep -q 'ci export' "$CALL_LOG"; then
    log_pass 'a failed install exports no gate and fails'
else
    log_fail 'a failed install exports no gate and fails' "rc=$RC calls=$(tr '\n' '|' < "$CALL_LOG")"
fi
rm -rf "$FIXTURE"
test_summary
