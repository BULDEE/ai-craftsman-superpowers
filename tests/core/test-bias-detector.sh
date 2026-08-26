#!/usr/bin/env bash
# =============================================================================
# Bias Detector Tests (data-driven, ADR-0030)
# Behavior cases live in tests/fixtures/bias/<lang>.cases; adding a language
# to the detector means adding a conf file and a cases file, no code here.
# Fixture grammar:
#   expect|<CATEGORY>|curated|<prompt>   JSON systemMessage carries the label
#   expect|<CATEGORY>|signal|<prompt>    plain-stdout note carries the slug
#   silent|<prompt>                      hook prints nothing
# Prompts must not contain | " or \ (field separator and JSON framing).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures/bias"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

run_bias() {
    local prompt="$1"
    local output
    output=$(echo "{\"prompt\":\"$prompt\"}" | bash "$ROOT_DIR/hooks/bias-detector.sh" 2>/dev/null)
    local exit_code=$?
    echo "$exit_code|$output"
}

label_for() {
    case "$1" in
        ACCELERATION)    printf 'Acceleration' ;;
        SCOPE_CREEP)     printf 'Scope Creep' ;;
        OVER_OPT)        printf 'Over-Optimization' ;;
        DOMAIN_MODELING) printf 'Domain Modeling' ;;
        *)               printf 'UNKNOWN' ;;
    esac
}

slug_for() {
    case "$1" in
        ACCELERATION)    printf 'acceleration' ;;
        SCOPE_CREEP)     printf 'scope_creep' ;;
        OVER_OPT)        printf 'over_optimization' ;;
        DOMAIN_MODELING) printf 'domain_modeling' ;;
        *)               printf 'unknown' ;;
    esac
}

assert_curated_case() {
    local category="$1" prompt="$2" lang="$3"
    local result exit_code output label
    result=$(run_bias "$prompt")
    exit_code="${result%%|*}"
    output="${result#*|}"
    label=$(label_for "$category")
    if [[ "$exit_code" == "0" ]] \
        && echo "$output" | jq -e .systemMessage >/dev/null 2>&1 \
        && echo "$output" | grep -qi "$label"; then
        log_pass "$lang curated $category: '$prompt'"
    else
        log_fail "$lang curated $category: '$prompt'" "exit=$exit_code output=$output"
    fi
}

assert_signal_case() {
    local category="$1" prompt="$2" lang="$3"
    local result exit_code output slug
    result=$(run_bias "$prompt")
    exit_code="${result%%|*}"
    output="${result#*|}"
    slug=$(slug_for "$category")
    if [[ "$exit_code" == "0" ]] \
        && echo "$output" | grep -q "Bias signal (${slug}" \
        && ! echo "$output" | jq -e . >/dev/null 2>&1; then
        log_pass "$lang signal $category: '$prompt'"
    else
        log_fail "$lang signal $category: '$prompt'" "exit=$exit_code output=$output"
    fi
}

assert_silent_case() {
    local prompt="$1" lang="$2"
    local result exit_code output
    result=$(run_bias "$prompt")
    exit_code="${result%%|*}"
    output="${result#*|}"
    if [[ "$exit_code" == "0" && -z "$output" ]]; then
        log_pass "$lang silent: '$prompt'"
    else
        log_fail "$lang silent: '$prompt'" "exit=$exit_code output=$output"
    fi
}

run_case_file() {
    local cases_file="$1"
    local lang kind f2 f3 f4
    lang=$(basename "$cases_file" .cases)
    while IFS='|' read -r kind f2 f3 f4; do
        [[ -z "$kind" ]] && continue
        case "$kind" in
            \#*) continue ;;
            expect)
                case "$f3" in
                    curated) assert_curated_case "$f2" "$f4" "$lang" ;;
                    signal)  assert_signal_case "$f2" "$f4" "$lang" ;;
                    *) log_fail "$lang fixture line" "unknown tier '$f3'" ;;
                esac
                ;;
            silent) assert_silent_case "$f2" "$lang" ;;
            *) log_fail "$lang fixture line" "unknown kind '$kind'" ;;
        esac
    done < "$cases_file"
}

echo ""
echo "=== Bias Detector Tests (data-driven) ==="

found_any=false
for cases_file in "$FIXTURES_DIR"/*.cases; do
    [[ -f "$cases_file" ]] || continue
    found_any=true
    echo ""
    echo "--- $(basename "$cases_file") ---"
    run_case_file "$cases_file"
done

if [[ "$found_any" == "false" ]]; then
    log_fail "fixture discovery" "no .cases file under $FIXTURES_DIR; a silent suite proves nothing"
fi

# =============================================================================
# Signal tier behavior (controlled pattern dir via CRAFTSMAN_BIAS_PATTERNS_DIR)
# =============================================================================
echo ""
echo "--- Signal tier ---"

SIGNAL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bias-signal-fixtures.XXXXXX")
trap 'rm -rf "$SIGNAL_DIR"; cleanup_test_env' EXIT

cat > "$SIGNAL_DIR/en.conf" <<'EOF'
BIAS_REGISTERED_LANGS+=("en")
BIAS_EN_MODE="curated"
BIAS_EN_ACCELERATION="just do it"
EOF

cat > "$SIGNAL_DIR/xx.conf" <<'EOF'
BIAS_REGISTERED_LANGS+=("xx")
BIAS_XX_MODE="signal"
BIAS_XX_ACCELERATION="xx-hurry|Xx-hurry"
BIAS_XX_DOMAIN_MODELING="xx-entity"
EOF

run_bias_dir() {
    local prompt="$1"
    local output
    output=$(echo "{\"prompt\":\"$prompt\"}" \
        | CRAFTSMAN_BIAS_PATTERNS_DIR="$SIGNAL_DIR" bash "$ROOT_DIR/hooks/bias-detector.sh" 2>/dev/null)
    echo "$?|$output"
}

result=$(run_bias_dir "please xx-hurry with this task")
exit_code="${result%%|*}"; output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q 'Bias signal (acceleration): lexeme "xx-hurry"' \
    && ! echo "$output" | jq -e . >/dev/null 2>&1; then
    log_pass "signal hit emits plain-stdout note with slug and lexeme"
else
    log_fail "signal hit should emit adjudication note" "exit=$exit_code output=$output"
fi

result=$(run_bias_dir "just do it and also xx-hurry")
exit_code="${result%%|*}"; output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | jq -e .systemMessage >/dev/null 2>&1 \
    && ! echo "$output" | grep -q "Bias signal ("; then
    log_pass "curated warning wins: JSON only, no signal note (exclusive formats)"
else
    log_fail "curated must suppress every signal note" "exit=$exit_code output=$output"
fi

result=$(run_bias_dir "a perfectly clean prompt")
exit_code="${result%%|*}"; output="${result#*|}"
if [[ "$exit_code" == "0" && -z "$output" ]]; then
    log_pass "clean prompt emits nothing from either tier"
else
    log_fail "clean prompt should be silent" "exit=$exit_code output=$output"
fi

result=$(run_bias_dir "we should xx-entity here")
exit_code="${result%%|*}"; output="${result#*|}"
if [[ "$exit_code" == "0" ]] && echo "$output" | grep -q "Bias signal (domain_modeling)"; then
    log_pass "signal domain_modeling emits note when design_used flag is absent"
else
    log_fail "signal domain_modeling should note without design session" "exit=$exit_code output=$output"
fi

# =============================================================================
# Exit code must ALWAYS be 0 (non-blocking hook), whatever the prompt
# =============================================================================
echo ""
echo "--- Exit Code Safety ---"

for prompt in "fais ça vite" "et aussi" "abstraire" "crée une entité User" "normal prompt"; do
    result=$(run_bias "$prompt")
    exit_code="${result%%|*}"
    if [[ "$exit_code" == "0" ]]; then
        log_pass "Exit 0 for: '$prompt'"
    else
        log_fail "Must always exit 0" "got exit $exit_code for '$prompt'"
    fi
done

test_summary
