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
# Bash Self-Validation — Hook scripts (executable, must pass all rules)
# =============================================================================
echo ""
echo "=== Dogfood: Bash hook scripts (hooks/*.sh) ==="

bash_total=0
bash_pass=0

for file in "$ROOT_DIR"/hooks/*.sh; do
    [[ ! -f "$file" ]] && continue
    basename="$(basename "$file")"
    reset_violations
    pack_validate_bash "$file"
    bash_total=$((bash_total + 1))
    if [[ "$VIOLATION_COUNT" -eq 0 ]]; then
        log_pass "bash self-validate: $basename"
        bash_pass=$((bash_pass + 1))
    else
        log_fail "bash self-validate: $basename" "${VIOLATION_COUNT} violation(s)"
    fi
done

# =============================================================================
# Bash Self-Validation — Sourced libs (hooks/lib/*.sh)
# Skip SH001 (no set -euo needed for sourced libs), check SH002-SH005
# =============================================================================
echo ""
echo "=== Dogfood: Bash sourced libs (hooks/lib/*.sh) ==="

for file in "$ROOT_DIR"/hooks/lib/*.sh; do
    [[ ! -f "$file" ]] && continue
    basename="$(basename "$file")"
    reset_violations
    pack_validate_bash "$file"

    # Filter out SH001 violations (sourced libs are exempt by design)
    local_violations=""
    local_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" != SH001:* ]]; then
            local_violations="${local_violations}${line}\n"
            ((local_count++)) || true
        fi
    done < <(echo -e "$VIOLATIONS")

    bash_total=$((bash_total + 1))
    if [[ "$local_count" -eq 0 ]]; then
        log_pass "bash self-validate (lib): $basename"
        bash_pass=$((bash_pass + 1))
    else
        log_fail "bash self-validate (lib): $basename" "${local_count} violation(s) (excl. SH001)"
    fi
done

# =============================================================================
# Python Self-Validation — hooks/lib/*.py
# =============================================================================
echo ""
echo "=== Dogfood: Python files (hooks/lib/*.py) ==="

python_total=0
python_pass=0

# Advisory (warn-first) rules do not gate self-validation, mirroring the SH001
# exemption for sourced libs: they ship as warnings by design (see
# rules-engine.sh _rules_is_advisory). A file-level craftsman-ignore is honored
# too, matching the production gate.
ADVISORY_RULES="NEST001 LOC001 GOD001 PARAM001 CTRL001"

for file in "$ROOT_DIR"/hooks/lib/*.py; do
    [[ ! -f "$file" ]] && continue
    basename="$(basename "$file")"
    reset_violations
    pack_validate_python "$file"

    blocking_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        rule="${line%%:*}"
        case " $ADVISORY_RULES " in *" $rule "*) continue ;; esac
        grep -qE "craftsman-ignore:[^#]*\b${rule}\b" "$file" 2>/dev/null && continue
        ((blocking_count++)) || true
    done < <(echo -e "$VIOLATIONS")

    python_total=$((python_total + 1))
    if [[ "$blocking_count" -eq 0 ]]; then
        log_pass "python self-validate: $basename"
        python_pass=$((python_pass + 1))
    else
        log_fail "python self-validate: $basename" "${blocking_count} violation(s) (excl. advisory + craftsman-ignore)"
    fi
done

# =============================================================================
# Summary
# =============================================================================
echo ""
total=$((bash_total + python_total))
pass=$((bash_pass + python_pass))
echo "--- Dogfood Summary: ${pass}/${total} files pass self-validation ---"

test_summary
