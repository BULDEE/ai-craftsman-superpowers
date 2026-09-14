#!/usr/bin/env bash
# =============================================================================
# Dogfood Self-Validation Tests
# Runs the plugin's own pack validators against its own source code.
# If we enforce rules on users, we must pass them ourselves.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

# --- Mock helpers expected by validators ---
VIOLATIONS=""
VIOLATION_COUNT=0
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2\n"; ((VIOLATION_COUNT++)) || true; }
add_warning() { true; }
line_has_ignore() { return 1; }
metrics_record_violation() { true; }
FILE_PATTERN="dogfood"

# Source validators
source "$ROOT_DIR/packs/bash/hooks/bash-validator.sh"
source "$ROOT_DIR/packs/python/hooks/python-validator.sh"

# --- Helper to reset state between files ---
reset_violations() {
    VIOLATIONS=""
    VIOLATION_COUNT=0
}

# =============================================================================
# Every shell and python file the plugin ships, under the gate it ships
#
# The scope used to be hooks/*.sh, hooks/lib/*.sh and hooks/lib/*.py: the
# pipeline (ci/), the pack validators, the Hermes adapter and the scripts were
# never self-validated, and the suite carried a hand-kept advisory list plus
# an SH001 exemption of its own (architecture review, MUST-FIX). The gate is
# the engine's: severity per file through rules_severity_for_file, a
# file-level marker honoured unless the rule is never_ignorable, a baseline
# mark honoured, the developer's global config ignored. Only `block` fails.
# =============================================================================
export CRAFTSMAN_GLOBAL_CONFIG_DIR=""
source "$ROOT_DIR/hooks/lib/rules-engine.sh"
rules_init "$ROOT_DIR" ""

_dogfood_files() {
    {
        find "$ROOT_DIR/hooks" "$ROOT_DIR/ci" "$ROOT_DIR/adapters" "$ROOT_DIR/scripts" "$ROOT_DIR/.github/scripts" \
             "$ROOT_DIR"/packs/*/hooks "$ROOT_DIR"/packs/*/scripts "$ROOT_DIR"/packs/*/static-analysis \
             "$ROOT_DIR"/packs/*/knowledge/canonical \
            -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null
        find "$ROOT_DIR" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null
    } | grep -v '__pycache__' | sort
}

_dogfood_blocking() {
    local file="$1" line rule severity count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        rule="${line%%:*}"
        severity=$(rules_severity_for_file "$file" "$rule")
        [[ "$severity" == "block" ]] || continue
        if grep -qE "craftsman-ignore:[^#]*\b${rule}\b" "$file" 2>/dev/null \
            && ! { type rule_never_ignorable >/dev/null 2>&1 && rule_never_ignorable "$rule"; }; then
            continue
        fi
        rules_baseline_holds "$file" "$rule" "$severity" && continue
        ((count++)) || true
        DOGFOOD_DETAIL="${DOGFOOD_DETAIL}${line}; "
    done < <(echo -e "$VIOLATIONS")
    printf '%s' "$count"
}

bash_total=0; bash_pass=0; python_total=0; python_pass=0
while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    relative="${file#"$ROOT_DIR"/}"
    reset_violations
    DOGFOOD_DETAIL=""
    case "$file" in
        *.sh) FILE_PATH="$file"; pack_validate_bash "$file"; bash_total=$((bash_total + 1)) ;;
        *.py) FILE_PATH="$file"; pack_validate_python "$file"; python_total=$((python_total + 1)) ;;
    esac
    blocking=$(_dogfood_blocking "$file")
    if [[ "$blocking" -eq 0 ]]; then
        log_pass "self-validate: $relative"
        case "$file" in *.sh) bash_pass=$((bash_pass + 1)) ;; *.py) python_pass=$((python_pass + 1)) ;; esac
    else
        log_fail "self-validate: $relative" "${blocking} blocking finding(s): ${DOGFOOD_DETAIL}"
    fi
done < <(_dogfood_files)

# The scope is a claim about the tree: a directory that ships shell or python
# and is not walked here is a directory the plugin's rules do not reach.
UNWALKED=$(find "$ROOT_DIR" -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null \
    | grep -v -E "/(tests|examples|graphify-out|node_modules|\.git|__pycache__)/" \
    | grep -v -E "^$ROOT_DIR/(hooks|ci|adapters|scripts|\.github/scripts|packs/[^/]+/(hooks|scripts|static-analysis|knowledge/canonical))/" \
    | grep -v -E "^$ROOT_DIR/[^/]+\.(sh|py)$" || true)
if [[ -z "$UNWALKED" ]]; then
    log_pass "every shipped shell and python file is in the dogfood scope"
else
    log_fail "shipped files outside the dogfood scope" "$(echo "$UNWALKED" | sed "s|$ROOT_DIR/||" | tr '\n' ' ')"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
total=$((bash_total + python_total))
pass=$((bash_pass + python_pass))
echo "--- Dogfood Summary: ${pass}/${total} files pass self-validation ---"

test_summary
