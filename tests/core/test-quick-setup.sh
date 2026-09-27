#!/usr/bin/env bash
# =============================================================================
# Tests for /craftsman:setup --quick mode
# Validates that quick-setup content is present in setup.md.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

SETUP_CMD="$ROOT_DIR/skills/setup/SKILL.md"

echo ""
echo "=== Quick Setup Tests ==="

# --- File exists ---

if [[ -f "$SETUP_CMD" ]]; then
    log_pass "setup.md exists"
else
    log_fail "setup.md missing"
    test_summary
fi

# --- Quick mode documented ---

if grep -q '\-\-quick' "$SETUP_CMD"; then
    log_pass "--quick flag documented"
else
    log_fail "--quick flag not documented in setup.md"
fi

# --- Auto-detect stack ---

if grep -q 'composer.json' "$SETUP_CMD" && grep -q 'package.json' "$SETUP_CMD"; then
    log_pass "auto-detect uses composer.json and package.json"
else
    log_fail "auto-detect missing stack detection files"
fi

# --- Git user name extraction ---

if grep -q 'git config user.name' "$SETUP_CMD"; then
    log_pass "extracts name from git config"
else
    log_fail "missing git config user.name extraction"
fi

# --- Smart defaults ---

# `--quick` used to announce "Strictness: strict (default)" while the resolver
# answers `moderate` on an existing repository without a mark. The default is
# config_default_strictness's, so the quick path writes none and reads it back.
if grep -q 'config_default_strictness' "$SETUP_CMD" \
    && ! grep -rq 'Strictness: strict (default)' "$SETUP_CMD" "$ROOT_DIR/examples/setup"; then
    log_pass "quick mode leaves strictness to the resolver and reports what it resolved"
else
    log_fail "quick strictness" "a hardcoded 'strict (default)' is announced, or config_default_strictness is not named"
fi

if grep -q 'acceleration' "$SETUP_CMD" && grep -q 'scope_creep' "$SETUP_CMD"; then
    log_pass "all biases enabled by default"
else
    log_fail "missing default biases"
fi

# --- Config guard ---

if grep -q '\-\-force' "$SETUP_CMD"; then
    log_pass "--force override documented"
else
    log_fail "missing --force flag for existing config"
fi

# --- Summary output ---

if grep -q 'Quick Setup Complete' "$SETUP_CMD"; then
    log_pass "quick setup summary output present"
else
    log_fail "missing quick setup summary"
fi

# --- Both modes documented ---

if grep -q 'Full interactive setup' "$SETUP_CMD" && grep -q 'Zero-question' "$SETUP_CMD"; then
    log_pass "both modes documented in modes table"
else
    log_fail "missing modes documentation table"
fi

# --- Situational onboarding (v4.0) ---

SIGNALS_COMMAND=$(grep -F 'conventions signals' "$SETUP_CMD")
SIGNALS_PROJECT=$(mktemp -d)
SIGNALS_OUTPUT=$(cd "$SIGNALS_PROJECT" && PATH="$ROOT_DIR/bin:$PATH" bash -c "$SIGNALS_COMMAND" 2>/dev/null)
rm -rf "$SIGNALS_PROJECT"
if [[ -n "$SIGNALS_COMMAND" ]] && printf '%s' "$SIGNALS_OUTPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["existing_project"] is False and d["has_tests"] is False else 1)' 2>/dev/null; then
    log_pass "the documented native setup command reads real project signals"
else
    log_fail "signals step" "missing command or invalid observation: $SIGNALS_OUTPUT"
fi

grep -q -- "--global" "$SETUP_CMD" \
    && log_pass "setup documents --global workshop profile" \
    || log_fail "--global" "missing"

grep -q "preferred_tools:" "$SETUP_CMD" \
    && log_pass "workshop profile records preferred_tools" \
    || log_fail "preferred_tools key" "missing"

SITU_COUNT=0
grep -qc "AskUserQuestion" "$SETUP_CMD" >/dev/null && \
SITU_COUNT=$(grep -c "Existing project or a new one\|Prototype or heading to production\|Solo or team\|Maximum help or maximum autonomy" "$SETUP_CMD")
[[ "$SITU_COUNT" -eq 4 ]] \
    && log_pass "exactly 4 situational questions documented" \
    || log_fail "situational questions" "found $SITU_COUNT"

grep -q "guided: true" "$SETUP_CMD" \
    && log_pass "guided mode key documented" \
    || log_fail "guided" "missing"

# --- Step D takes the mark the gate reads (CR-175, M7) ---
# The step promised that inherited debt stops blocking, and ran `ratchet.py
# init`, which records structure and no rule: the next scan of an untouched
# legacy file still refused it twice. The command is read from the skill and
# run on a throwaway repository; the verdict is the next scan's.
STEP_D_COMMAND=$(awk '/^### Step D/{inside=1;next} inside && /^### /{exit}
                      inside && /^```bash/{code=1;next} code && /^```/{exit} code' "$SETUP_CMD")
STEP_D_REPO=$(mktemp -d "${TMPDIR:-/tmp}/setup-step-d.XXXXXX")
(
    cd "$STEP_D_REPO" || exit 1
    git init -q . && git commit -q --allow-empty -m init
    mkdir src && printf '<?php\nclass Legacy {}\n' > src/Legacy.php
) >/dev/null 2>&1
STEP_D_SUMMARY=$(cd "$STEP_D_REPO" && export HOME="$STEP_D_REPO/home" && mkdir -p "$HOME/.claude" \
    && PATH="$ROOT_DIR/bin:$PATH" bash -c "$STEP_D_COMMAND" >/dev/null 2>&1 \
    && bash "$ROOT_DIR/ci/craftsman-ci.sh" --format json src 2>/dev/null \
    | python3 -c 'import json,sys; s=json.load(sys.stdin)["summary"]; print(s["violations"], s["warnings"])' 2>/dev/null)
rm -rf "$STEP_D_REPO"
if [[ -n "$STEP_D_COMMAND" && "$STEP_D_SUMMARY" == "0 2" ]]; then
    log_pass "Step D takes the canonical baseline: inherited debt reports as warnings and blocks nothing"
else
    log_fail "Step D baseline" "command '${STEP_D_COMMAND}' left 'violations warnings' = '${STEP_D_SUMMARY}', expected '0 2'"
fi

# --- Every config the skill writes is read back as chosen (CR-175, M6) ---
# Both templates wrote `version: "1.0"` and a `stack:` mapping of versions. The
# resolver reads `stack` as a scalar, got nothing, answered `fullstack`, and the
# healthcheck said ok because it only tested that the file existed. Each YAML
# block that writes a config (skill and example) is filled, written to a
# throwaway project, and asked of the real reader and the real validator.
config_blocks() {
    awk '/^```yaml/{inside=1; block=""; next}
         inside && /^```/{inside=0; if (block ~ /(^|\n)(stack|v|version):/) printf "%s%c", block, 30; next}
         inside{block = block $0 "\n"}' "$@"
}
BLOCKS_CHECKED=0
BLOCK_FAILURES=""
while IFS= read -r -d $'\x1e' block; do
    BLOCKS_CHECKED=$((BLOCKS_CHECKED + 1))
    CFG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/setup-config.XXXXXX")
    mkdir -p "$CFG_DIR/home/.claude"
    printf '%s' "$block" | sed -e 's/{stack}/symfony/g' -e 's/{strictness}/moderate/g' \
        -e 's/{guided}/true/g' -e 's/{[^}]*}/x/g' > "$CFG_DIR/.craft-config.yml"
    EXPECTED="fullstack|"
    grep -q '^stack:' "$CFG_DIR/.craft-config.yml" && EXPECTED="symfony|"
    READ_BACK=$(cd "$CFG_DIR" && HOME="$CFG_DIR/home" bash -c \
        'source "$1/hooks/lib/config.sh"; problems=$(config_validate .craft-config.yml 2>&1); printf "%s|%s" "$(config_stack)" "$problems"' _ "$ROOT_DIR")
    [[ "$READ_BACK" == "$EXPECTED" ]] || BLOCK_FAILURES+="[block ${BLOCKS_CHECKED}: stack|problems = ${READ_BACK}, expected ${EXPECTED}] "
    rm -rf "$CFG_DIR"
done < <(config_blocks "$SETUP_CMD" "$ROOT_DIR"/examples/setup/*.md)
if [[ "$BLOCKS_CHECKED" -gt 0 && -z "$BLOCK_FAILURES" ]]; then
    log_pass "every config the setup writes ($BLOCKS_CHECKED blocks) is v4 and config_stack reads the chosen stack"
else
    log_fail "setup config read back" "checked=${BLOCKS_CHECKED} ${BLOCK_FAILURES}"
fi

# The validator and the healthcheck row go RED on the file setup used to write.
V1_DIR=$(mktemp -d "${TMPDIR:-/tmp}/setup-v1.XXXXXX")
mkdir -p "$V1_DIR/home/.claude"
printf 'version: "1.0"\nstack:\n  php_version: "8.4"\n  symfony_version: "7.4"\n' > "$V1_DIR/.craft-config.yml"
V1_VERDICT=$(cd "$V1_DIR" && HOME="$V1_DIR/home" bash -c \
    'source "$1/hooks/lib/config.sh"; source "$1/hooks/lib/healthcheck.sh"; config_validate .craft-config.yml >/dev/null; rc=$?; hc_check_config; printf "%s|%s|%s" "$rc" "${_HC_STATUSES[0]}" "${_HC_MESSAGES[0]}"' _ "$ROOT_DIR" 2>/dev/null)
printf 'v: 4\nstack: react\n' > "$V1_DIR/.craft-config.yml"
V4_VERDICT=$(cd "$V1_DIR" && HOME="$V1_DIR/home" bash -c \
    'source "$1/hooks/lib/config.sh"; source "$1/hooks/lib/healthcheck.sh"; hc_check_config; printf "%s" "${_HC_STATUSES[0]}"' _ "$ROOT_DIR" 2>/dev/null)
printf 'v: 4\nstack: angular\n' > "$V1_DIR/.craft-config.yml"
V4_BAD_VERDICT=$(cd "$V1_DIR" && HOME="$V1_DIR/home" bash -c \
    'source "$1/hooks/lib/config.sh"; source "$1/hooks/lib/healthcheck.sh"; hc_check_config; printf "%s" "${_HC_STATUSES[0]}"' _ "$ROOT_DIR" 2>/dev/null)
rm -rf "$V1_DIR"
# A pre-v4 file is every user's config before they rerun setup: the row says
# which keys the resolver ignores and how to migrate, as a warning. An error
# is for a v4 file whose values are wrong, which no upgrade explains.
if [[ "$V1_VERDICT" == 1\|warn\|*stack* && "$V1_VERDICT" == *"v: 4"* && "$V4_VERDICT" == ok && "$V4_BAD_VERDICT" == error ]]; then
    log_pass "a pre-v4 config is refused by the validator and warned by the healthcheck, an invalid v4 one is an error, a valid v4 one is ok"
else
    log_fail "config validation" "pre-v4: '${V1_VERDICT}', v4: '${V4_VERDICT}', invalid v4: '${V4_BAD_VERDICT}'"
fi

grep -q "committed" "$SETUP_CMD" \
    && log_pass "baseline commit instruction present" \
    || log_fail "baseline commit instruction" "missing"

test_summary
