#!/usr/bin/env bash
# =============================================================================
# Copilot adapter (CR-133): the documented envelopes reach the same core gates.
#
# Every fixture under tests/fixtures/hosts/copilot/documented is transcribed
# from the GitHub hooks reference, not captured: this suite proves the adapter
# honours the documented contract (both envelopes, toolArgs as a JSON string,
# Copilot tool names and argument names, deny on exit 2, ask never emitted,
# non-write tools untouched, fail-closed on a broken payload). It does not
# qualify a Copilot surface; that needs the consumer (PROVENANCE.md there).
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"
source "$SCRIPT_DIR/../lib/host-fixtures.sh"

export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="${TMPDIR:-/tmp}/craftsman-copilot-$$"
export CLAUDE_PLUGIN_OPTION_stack="fullstack"
export CLAUDE_PLUGIN_OPTION_strictness="strict"
unset CRAFTSMAN_DISABLED_HOOKS CRAFTSMAN_HOOK_PROFILE CLAUDECODE COPILOT_AGENT_PROMPT
mkdir -p "$CLAUDE_PLUGIN_DATA"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-copilot.XXXXXX"); WORK=$(cd "$WORK" && pwd -P)
PREV_PWD="$PWD"
trap 'cd "$PREV_PWD"; rm -rf "$WORK" "$CLAUDE_PLUGIN_DATA"' EXIT
mkdir -p "$WORK/src/Domain"; cd "$WORK" && git init -q .
printf '{"autoload":{"psr-4":{"App\\\\":"src/"}}}\n' > composer.json
printf '<?php\ndeclare(strict_types=1);\nnamespace App\\Domain;\nfinal class Existing\n{\n}\n' > src/Domain/Existing.php
git add -A >/dev/null && git commit -qm base >/dev/null

PRE="$ROOT_DIR/adapters/copilot/pre-tool-use.sh"
POST="$ROOT_DIR/adapters/copilot/post-tool-use.sh"
TR="$ROOT_DIR/adapters/copilot/translate.py"
_fx() { host_fixture_with copilot documented "$1" "$WORK" "${2:-pass}"; }
_run() { local out rc=0; out=$(printf '%s' "$2" | bash "$1" 2>&1) || rc=$?; printf '%s|%s' "$rc" "$out"; }

echo ""
echo "=== Copilot adapter (documented contract) ==="

# translation
T=$(_fx pre-tool-use.create.pascal | python3 "$TR")
if [[ "$(printf '%s' "$T" | jq -r .tool_name)" == "Write" && "$(printf '%s' "$T" | jq -r .tool_input.file_path)" == "$WORK/src/Domain/Order.php" \
    && "$(printf '%s' "$T" | jq -r .tool_input.content)" == *"class Order"* && "$(printf '%s' "$T" | jq -r .craftsman_host)" == "copilot" ]]; then
    log_pass "PascalCase create becomes Write with file_path and content, host named copilot"
else
    log_fail "translate create pascal" "$(printf '%s' "$T" | cut -c1-200)"
fi
T=$(_fx pre-tool-use.create.camel | python3 "$TR")
if [[ "$(printf '%s' "$T" | jq -r .tool_name)" == "Write" && "$(printf '%s' "$T" | jq -r .session_id)" == "copilot-doc-2" && "$(printf '%s' "$T" | jq -r .tool_input.content)" == *"class Order"* ]]; then
    log_pass "camelCase create with toolArgs as a JSON string is parsed and translated the same way"
else
    log_fail "translate create camel" "$(printf '%s' "$T" | cut -c1-200)"
fi
T=$(_fx pre-tool-use.str_replace_editor.pascal | python3 "$TR")
if [[ "$(printf '%s' "$T" | jq -r .tool_name)" == "Edit" && "$(printf '%s' "$T" | jq -r .tool_input.old_string)" == "final class Existing" && "$(printf '%s' "$T" | jq -r '.tool_input.command // "absent"')" == "absent" ]]; then
    log_pass "str_replace_editor str_replace becomes Edit with old_string/new_string, its sub-command dropped"
else
    log_fail "translate str_replace_editor" "$(printf '%s' "$T" | cut -c1-200)"
fi
T=$(_fx pre-tool-use.bash.pascal | python3 "$TR")
[[ "$(printf '%s' "$T" | jq -r .tool_name)" == "Bash" ]] && log_pass "bash becomes Bash" || log_fail "translate bash" "$T"
H=$(bash -c "source '$ROOT_DIR/hooks/lib/host.sh'; host_detect '$(_fx pre-tool-use.create.pascal | tr -d '\n')'")
H2=$(bash -c "source '$ROOT_DIR/hooks/lib/host.sh'; host_detect '$(printf '%s' "$T" | tr -d '\n')'")
[[ "$H" == "copilot" && "$H2" == "copilot" ]] && log_pass "host_detect names copilot on the raw envelope (timestamp) and on the translated one (craftsman_host)" || log_fail "host_detect copilot" "raw=$H translated=$H2"

# gates
R=$(_run "$PRE" "$(_fx pre-tool-use.create.pascal)")
if [[ "${R%%|*}" == "2" && "${R#*|}" == *'"permissionDecision": "deny"'* && "${R#*|}" == *LAYER001* && "${R#*|}" == *PHP002* ]]; then
    log_pass "preToolUse: an invalid Domain class through create is denied (exit 2, permissionDecision deny, LAYER001 and PHP002 named)"
else
    log_fail "preToolUse deny" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi
R=$(_run "$PRE" "$(_fx pre-tool-use.create.camel)")
[[ "${R%%|*}" == "2" && "${R#*|}" == *LAYER001* ]] && log_pass "preToolUse: the camelCase envelope is denied identically" || log_fail "preToolUse camel" "rc=${R%%|*}"
R=$(_run "$PRE" "$(_fx pre-tool-use.create.pascal "d['tool_input']['file_text'] = '<?php\\ndeclare(strict_types=1);\\nnamespace App\\\\\\\\Domain;\\nfinal class Order\\n{\\n}\\n'")")
[[ "${R%%|*}" == "0" && -z "${R#*|}" ]] && log_pass "preToolUse: a valid create passes with no output (the host's own permission flow applies)" || log_fail "preToolUse valid" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | cut -c1-120)"
R=$(_run "$PRE" "$(_fx pre-tool-use.str_replace_editor.pascal)")
[[ "${R%%|*}" == "2" && "${R#*|}" == *PHP002* ]] && log_pass "preToolUse: removing final through str_replace_editor is denied (PHP002 on the would-be file)" || log_fail "preToolUse edit" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
R=$(_run "$PRE" "$(_fx pre-tool-use.create.pascal "d['tool_input']['path'] = '$WORK/src/Domain/.craft-rules.yml'; d['tool_input']['file_text'] = 'rules:\\n  LAYER001: ignore\\n'")")
[[ "${R%%|*}" == "2" && "${R#*|}" == *'"deny"'* && "${R#*|}" != *'"ask"'* ]] && log_pass "preToolUse: the gate's own configuration is denied, never asked (ask is deny in the cloud anyway)" || log_fail "preToolUse gate config" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-160)"
R=$(_run "$PRE" "$(_fx pre-tool-use.bash.pascal)")
[[ "${R%%|*}" == "0" && -z "${R#*|}" ]] && log_pass "preToolUse: a tool that is not a write is left alone (a surface that ignores matchers sends every tool)" || log_fail "preToolUse non-write" "rc=${R%%|*}"
R=$(_run "$PRE" "not json at all")
[[ "${R%%|*}" == "0" ]] && log_pass "preToolUse: a payload with no tool is not this gate's (exit 0)" || log_fail "preToolUse garbage" "rc=${R%%|*} $(printf '%s' "${R#*|}" | cut -c1-100)"
R=$(printf '%s' "$(_fx pre-tool-use.create.pascal)" | PATH="/nonexistent" bash "$PRE" 2>&1); RC=$?
[[ "$RC" -ne 0 ]] && log_pass "preToolUse: a gate that cannot run fails closed (non-zero exit denies on this host)" || log_fail "preToolUse fail-closed" "rc=$RC"

# post
printf '<?php\ndeclare(strict_types=1);\nnamespace App\\Domain;\nuse App\\Infrastructure\\Persistence\\DoctrineOrderRepository;\nclass Order\n{\n}\n' > src/Domain/Order.php
R=$(_run "$POST" "$(_fx post-tool-use.create.pascal)")
if [[ "${R%%|*}" == "2" && "${R#*|}" == *'"additionalContext"'* && "${R#*|}" == *LAYER001* ]]; then
    log_pass "postToolUse: the landed invalid file is reported as additionalContext with exit 2 (logged, the write stands)"
else
    log_fail "postToolUse" "rc=${R%%|*} out=$(printf '%s' "${R#*|}" | tr '\n' ' ' | cut -c1-200)"
fi
rm -f src/Domain/Order.php

# test results in the documented shape
D=$(_fx post-tool-use.bash.camel | python3 "$TR" | python3 "$ROOT_DIR/hooks/lib/tool_result.py" | jq -r .state)
[[ "$D" == "failed" ]] && log_pass "a Copilot toolResult failure decodes as failed (documented shape, no exit code)" || log_fail "tool_result copilot" "$D"

# the hooks file is the documented form
if jq -e '.version == 1 and (.hooks.PreToolUse[0].matcher == "Edit|Write") and (.hooks.PreToolUse[0].timeoutSec >= 60) and (.hooks.PreToolUse[0].bash | test("pre-tool-use.sh"))' "$ROOT_DIR/adapters/copilot/hooks.json" >/dev/null; then
    log_pass "adapters/copilot/hooks.json: version 1, PascalCase events, Edit|Write matcher, timeoutSec above the gates' latency (a timeout is fail-open)"
else
    log_fail "copilot hooks.json" "$(jq -c . "$ROOT_DIR/adapters/copilot/hooks.json" | cut -c1-200)"
fi
[[ -f "$ROOT_DIR/tests/fixtures/hosts/copilot/documented/PROVENANCE.md" ]] && grep -q "NOT CAPTURED" "$ROOT_DIR/tests/fixtures/hosts/copilot/documented/PROVENANCE.md" \
    && log_pass "the fixtures say they are documented, not captured" || log_fail "provenance" "missing"

test_summary
