#!/usr/bin/env bash
# =============================================================================
# validate-pack.sh — Validates a pack directory against conventions.
#
# Usage:
#   validate-pack.sh <pack-dir> [--check-collisions <packs-root>]
#
# Exit codes:
#   0 = valid
#   2 = errors found
# =============================================================================
set -uo pipefail

PACK_DIR=""
CHECK_COLLISIONS=false
PACKS_ROOT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-collisions)
            CHECK_COLLISIONS=true
            PACKS_ROOT="${2:-}"
            shift 2
            ;;
        -*)
            echo "Unknown flag: $1" >&2
            exit 2
            ;;
        *)
            PACK_DIR="$1"
            shift
            ;;
    esac
done

if [[ -z "$PACK_DIR" ]]; then
    echo "Usage: validate-pack.sh <pack-dir> [--check-collisions <packs-root>]" >&2
    exit 2
fi

# =============================================================================
# YAML parsing helpers (POSIX/macOS-compatible — uses [[:space:]] not \s)
# =============================================================================

_yml_value() {
    local key="$1" file="$2"
    grep -E "^[[:space:]]*${key}:" "$file" 2>/dev/null | head -1 \
        | sed -E 's/^[^:]+:[[:space:]]*//' | tr -d '"' | tr -d "'" \
        | sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//'
}

_yml_nested_array() {
    local parent="$1" child="$2" file="$3"
    local in_parent=false
    while IFS= read -r line; do
        if echo "$line" | grep -qE "^${parent}:"; then
            in_parent=true; continue
        fi
        if [[ "$in_parent" == true ]]; then
            if echo "$line" | grep -qE '^[a-zA-Z]'; then
                in_parent=false; continue
            fi
            if echo "$line" | grep -qE "^[[:space:]]+${child}:"; then
                echo "$line" | sed -E 's/^[^[]*\[//' | sed -E 's/\].*//' \
                    | tr ',' '\n' | sed -E 's/^[[:space:]]*"?//;s/"?[[:space:]]*$//' | grep -v '^$'
                return
            fi
        fi
    done < "$file"
}

_yml_array() {
    local key="$1" file="$2"
    local line
    line=$(grep -E "^[[:space:]]*${key}:" "$file" 2>/dev/null | head -1)
    [[ -z "$line" ]] && return
    echo "$line" | sed -E 's/^[^[]*\[//' | sed -E 's/\].*//' \
        | tr ',' '\n' | sed -E 's/^[[:space:]]*"?//;s/"?[[:space:]]*$//' | grep -v '^$'
}

# =============================================================================
# Counters and output helpers
# =============================================================================

ERRORS=0
WARNINGS=0

log_ok()    { echo "  OK:    $1"; }
log_error() { echo "  ERROR: $1"; ERRORS=$((ERRORS + 1)); }
log_warn()  { echo "  WARN:  $1"; WARNINGS=$((WARNINGS + 1)); }

# =============================================================================
# Validation
# =============================================================================

echo ""
echo "=== Validating pack: ${PACK_DIR} ==="

PACK_YML="${PACK_DIR}/pack.yml"

# 1. pack.yml must exist
if [[ ! -f "$PACK_YML" ]]; then
    log_error "pack.yml not found in ${PACK_DIR}"
    echo "=== Validation: ${ERRORS} errors, ${WARNINGS} warnings ==="
    exit 2
fi
log_ok "pack.yml exists"

# 2. Required fields
for field in name version description; do
    value="$(_yml_value "$field" "$PACK_YML")"
    if [[ -z "$value" ]]; then
        log_error "Required field '${field}' is missing or empty"
    else
        log_ok "Field '${field}' present: ${value}"
    fi
done

# compatibility.stack (nested under compatibility:)
stack_values="$(_yml_nested_array "compatibility" "stack" "$PACK_YML")"
if [[ -z "$stack_values" ]]; then
    log_error "Required field 'compatibility.stack' is missing or empty"
else
    log_ok "Field 'compatibility.stack' present"
fi

# 3. Referenced validator files must exist
validators="$(_yml_array "validators" "$PACK_YML")"
if [[ -n "$validators" ]]; then
    while IFS= read -r validator; do
        [[ -z "$validator" ]] && continue
        validator_path="${PACK_DIR}/${validator}"
        if [[ ! -f "$validator_path" ]]; then
            log_error "Referenced validator not found: ${validator}"
        else
            log_ok "Validator exists: ${validator}"
            # Check for exit 1 (must use exit 0 or exit 2)
            if grep -qE '[^[:alnum:]]exit[[:space:]]+1([^[:digit:]]|$)' "$validator_path" 2>/dev/null; then
                log_error "Validator uses 'exit 1' (must use exit 0 or exit 2): ${validator}"
            fi
        fi
    done <<< "$validators"
fi

# 4. Referenced static analysis tool files must exist
sa_tools="$(_yml_array "tools" "$PACK_YML")"
if [[ -n "$sa_tools" ]]; then
    while IFS= read -r tool; do
        [[ -z "$tool" ]] && continue
        tool_path="${PACK_DIR}/${tool}"
        if [[ ! -f "$tool_path" ]]; then
            log_error "Referenced SA tool not found: ${tool}"
        else
            log_ok "SA tool exists: ${tool}"
        fi
    done <<< "$sa_tools"
fi

# 5. Referenced agent files must exist, and warn if missing allowedTools
agents="$(_yml_array "agents" "$PACK_YML")"
if [[ -n "$agents" ]]; then
    while IFS= read -r agent; do
        [[ -z "$agent" ]] && continue
        agent_path="${PACK_DIR}/${agent}"
        if [[ ! -f "$agent_path" ]]; then
            log_error "Referenced agent not found: ${agent}"
        else
            log_ok "Agent exists: ${agent}"
            if ! grep -qiE "allowedTools" "$agent_path" 2>/dev/null; then
                log_warn "Agent ${agent} missing allowedTools"
            fi
        fi
    done <<< "$agents"
fi

# 6. Rule ID collision detection with other packs
if [[ "$CHECK_COLLISIONS" == true ]]; then
    if [[ -z "$PACKS_ROOT" || ! -d "$PACKS_ROOT" ]]; then
        log_error "--check-collisions requires a valid packs root directory"
    else
        # Collect rule IDs from current pack
        current_rules="$(_yml_array "builtin" "$PACK_YML")"
        if [[ -n "$current_rules" ]]; then
            current_pack_name="$(_yml_value "name" "$PACK_YML")"
            while IFS= read -r rule_id; do
                [[ -z "$rule_id" ]] && continue
                # Search other packs for the same rule ID
                for other_pack_yml in "${PACKS_ROOT}"/*/pack.yml; do
                    [[ "$other_pack_yml" == "$PACK_YML" ]] && continue
                    [[ ! -f "$other_pack_yml" ]] && continue
                    other_name="$(_yml_value "name" "$other_pack_yml")"
                    [[ "$other_name" == "$current_pack_name" ]] && continue
                    other_rules="$(_yml_array "builtin" "$other_pack_yml")"
                    if echo "$other_rules" | grep -qxF "$rule_id"; then
                        log_error "Rule ID collision: '${rule_id}' also defined in pack '${other_name}'"
                    fi
                done
            done <<< "$current_rules"
        fi
        log_ok "Rule ID collision check completed"
    fi
fi

# =============================================================================
# Summary
# =============================================================================
echo "=== Validation: ${ERRORS} errors, ${WARNINGS} warnings ==="

if [[ "$ERRORS" -gt 0 ]]; then
    exit 2
fi
exit 0
