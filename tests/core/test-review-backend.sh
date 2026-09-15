#!/usr/bin/env bash
# =============================================================================
# The semantic review port: one prompt, one reply, several transports.
#
# The layer was `claude -p` only, so a machine without that CLI had no
# semantic review and said nothing about it (audit CR-117, C8). The backend is
# chosen once (CRAFTSMAN_REVIEW_BACKEND, the global file, else auto), the
# Codex transport is `codex exec` in a read-only ephemeral session, and every
# run row names the backend that answered. The CLIs here are fakes on PATH
# that record how they were called; the real consumer is exercised separately
# (review of lot 4, 2026-09-15).
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-review-backend.XXXXXX")
mkdir -p "$WORK/bin-claude" "$WORK/bin-codex" "$WORK/bin-both" "$WORK/global"
trap 'rm -rf "$WORK"' EXIT

# Fakes: each records its argv and the guard variable, and answers a verdict.
cat > "$WORK/bin-claude/claude" <<FAKE
#!/bin/sh
printf '%s\\n' "\$*" > "$WORK/claude.argv"; printf '%s' "\${CRAFTSMAN_HEADLESS_VERIFY:-unset}" > "$WORK/claude.guard"
echo "DDD_VIOLATIONS"; echo "src/Domain/Order.php:5 imports Infrastructure (layer violation)"
FAKE
cat > "$WORK/bin-codex/codex" <<FAKE
#!/bin/sh
printf '%s\\n' "\$*" > "$WORK/codex.argv"; printf '%s' "\${CRAFTSMAN_HEADLESS_VERIFY:-unset}" > "$WORK/codex.guard"
cat > "$WORK/codex.stdin"
out=""; while [ \$# -gt 0 ]; do case "\$1" in --output-last-message) out="\$2"; shift;; esac; shift; done
[ -n "\$out" ] && printf 'DDD_VIOLATIONS\\nsrc/Domain/Order.php:5 imports Infrastructure (layer violation)\\n' > "\$out"
exit 0
FAKE
chmod +x "$WORK/bin-claude/claude" "$WORK/bin-codex/codex"
cp "$WORK/bin-claude/claude" "$WORK/bin-codex/codex" "$WORK/bin-both/"
BASE_PATH="/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v python3)"):$(dirname "$(command -v jq)")"

_with() { # <bin dir or -> <env...> -- <bash snippet>
    local bins="$1"; shift
    local envs=()
    while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
    env -i HOME="$WORK" PATH="${bins:+$bins:}$BASE_PATH" CRAFTSMAN_GLOBAL_CONFIG_DIR="$WORK/global" ${envs[@]+"${envs[@]}"} \
        bash -c "source '$ROOT_DIR/hooks/lib/config.sh'; source '$ROOT_DIR/hooks/lib/haiku-verify.sh'; $1" 2>/dev/null
}

echo ""
echo "=== semantic review backend ==="

# selection
B=$(_with "$WORK/bin-both" -- 'semantic_backend')
[[ "$B" == "claude-cli" ]] && log_pass "auto: claude-cli when both CLIs are present" || log_fail "auto with both" "$B"
B=$(_with "$WORK/bin-codex" -- 'semantic_backend')
[[ "$B" == "codex-cli" ]] && log_pass "auto: codex-cli on a machine with codex and no claude" || log_fail "auto with codex" "$B"
B=$(_with "" -- 'semantic_backend; echo; haiku_verify_possible && echo possible || echo impossible')
[[ "$B" == $'none\nimpossible' ]] && log_pass "auto: none, and no verification is possible, with neither CLI" || log_fail "auto with none" "$B"
B=$(_with "$WORK/bin-both" CRAFTSMAN_REVIEW_BACKEND=codex-cli -- 'semantic_backend')
[[ "$B" == "codex-cli" ]] && log_pass "CRAFTSMAN_REVIEW_BACKEND overrides auto" || log_fail "env override" "$B"
printf 'review:\n  backend: codex-cli\n' > "$WORK/global/.craft-config.yml"
B=$(_with "$WORK/bin-both" -- 'semantic_backend')
[[ "$B" == "codex-cli" ]] && log_pass "review.backend in the global file overrides auto" || log_fail "global override" "$B"
printf 'review:\n  backend: none\n' > "$WORK/global/.craft-config.yml"
B=$(_with "$WORK/bin-both" -- 'haiku_verify_possible && echo possible || echo impossible')
[[ "$B" == "impossible" ]] && log_pass "review.backend none switches the layer off even with both CLIs present" || log_fail "none switch" "$B"
rm -f "$WORK/global/.craft-config.yml"
B=$(_with "$WORK/bin-codex" CRAFTSMAN_REVIEW_BACKEND=claude-cli -- 'haiku_verify_possible && echo possible || echo impossible')
[[ "$B" == "impossible" ]] && log_pass "a backend named but not installed is impossible, not silently swapped" || log_fail "named but absent" "$B"

# the Codex transport
rm -f "$WORK"/codex.*
OUT=$(_with "$WORK/bin-codex" -- 'haiku_verify "REVIEW THIS"; echo "[backend=$SEMANTIC_BACKEND_USED]"')
if [[ "$OUT" == *"DDD_VIOLATIONS"* && "$OUT" == *"[backend=codex-cli]"* ]] \
    && grep -q -- '--sandbox read-only' "$WORK/codex.argv" && grep -q -- '--ephemeral' "$WORK/codex.argv" \
    && grep -q -- '--output-last-message' "$WORK/codex.argv" && [[ "$(cat "$WORK/codex.stdin")" == "REVIEW THIS" ]]; then
    log_pass "codex-cli: codex exec read-only, ephemeral, prompt on stdin, the last message as the reply, backend recorded"
else
    log_fail "codex transport" "out=[$(printf '%s' "$OUT" | tr '\n' '|')] argv=[$(cat "$WORK/codex.argv" 2>/dev/null)]"
fi
if [[ "$(cat "$WORK/codex.guard")" == "1" ]]; then
    log_pass "the recursion guard reaches the Codex child through its environment"
else
    log_fail "guard inheritance" "CRAFTSMAN_HEADLESS_VERIFY=$(cat "$WORK/codex.guard")"
fi
if ! grep -q -- '-m ' "$WORK/codex.argv"; then
    log_pass "no Claude model id is handed to Codex (its default model applies unless CRAFTSMAN_VERIFY_MODEL_CODEX names one)"
else
    log_fail "model transposed" "$(cat "$WORK/codex.argv")"
fi
_with "$WORK/bin-codex" CRAFTSMAN_VERIFY_MODEL_CODEX=gpt-probe -- 'haiku_verify "x" >/dev/null'
grep -q -- '-m gpt-probe' "$WORK/codex.argv" && log_pass "CRAFTSMAN_VERIFY_MODEL_CODEX names the Codex model" || log_fail "codex model option" "$(cat "$WORK/codex.argv")"

# an empty reply is unavailable, never clean
cat > "$WORK/bin-codex/codex" <<'FAKE'
#!/bin/sh
exit 0
FAKE
RC=$(_with "$WORK/bin-codex" -- 'haiku_verify "x" >/dev/null; echo $?')
[[ "$RC" == "1" ]] && log_pass "a Codex run that returns nothing is unavailable (rc 1), not a clean verdict" || log_fail "empty reply" "rc=$RC"
cat > "$WORK/bin-codex/codex" <<'FAKE'
#!/bin/sh
exit 7
FAKE
RC=$(_with "$WORK/bin-codex" -- 'haiku_verify "x" >/dev/null; echo $?')
[[ "$RC" == "1" ]] && log_pass "a Codex run that fails is unavailable (rc 1)" || log_fail "failed reply" "rc=$RC"

# the claude transport is unchanged and still guarded
rm -f "$WORK"/claude.*
OUT=$(_with "$WORK/bin-claude" -- 'haiku_verify "x"; echo "[backend=$SEMANTIC_BACKEND_USED]"')
if [[ "$OUT" == *"[backend=claude-cli]"* ]] && grep -q -- '-p x --model' "$WORK/claude.argv" && [[ "$(cat "$WORK/claude.guard")" == "1" ]]; then
    log_pass "claude-cli: claude -p with the model, guarded, backend recorded"
else
    log_fail "claude transport" "$(cat "$WORK/claude.argv" 2>/dev/null) guard=$(cat "$WORK/claude.guard" 2>/dev/null)"
fi

# the run row carries the backend
DATA="$WORK/data"; mkdir -p "$DATA"
_with "$WORK/bin-codex" CLAUDE_PLUGIN_DATA="$DATA" -- "source '$ROOT_DIR/hooks/lib/metrics-db.sh'; metrics_init; SEMANTIC_BACKEND_USED=codex-cli metrics_record_haiku_run agent-ddd-verifier findings 1 120 ''; SEMANTIC_BACKEND_USED='' metrics_record_haiku_run agent-ddd-verifier unavailable 0 0 ''" >/dev/null
ROWS=$(sqlite3 "$DATA/metrics.db" "SELECT verdict || ':' || COALESCE(backend,'') FROM haiku_runs ORDER BY id" 2>/dev/null | tr '\n' ' ')
[[ "$ROWS" == "findings:codex-cli unavailable:none " ]] && log_pass "haiku_runs rows name the backend that answered, none for an unavailable run" || log_fail "backend column" "$ROWS"

test_summary
