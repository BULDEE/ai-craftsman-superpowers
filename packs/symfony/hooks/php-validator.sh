#!/usr/bin/env bash
# =============================================================================
# PHP Regex Validator — Symfony Pack
# Provides pack_validate_php() for the pack-loader pipeline.
#
# Rules: PHP001-005, WARN-PHP001
# Requires: add_violation(), add_warning(), line_has_ignore(), metrics_record_violation()
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
# =============================================================================

pack_validate_php() {
    local file="$1"

    # PHP001: declare(strict_types=1) required
    if ! grep -q "declare(strict_types=1)" "$file" 2>/dev/null; then
        add_violation "PHP001" "Missing declare(strict_types=1)"
    fi

    # PHP002: Classes must be final (except interface/trait/abstract)
    if grep -q "^class " "$file" 2>/dev/null; then
        if ! grep -q "final class" "$file" 2>/dev/null; then
            if ! grep -qE "(interface |trait |abstract class )" "$file" 2>/dev/null; then
                add_violation "PHP002" "Class should be final"
            fi
        fi
    fi

    # PHP003: No public setters (check each line for craftsman-ignore)
    while IFS= read -r line; do
        if echo "$line" | grep -qE "public function set[A-Z]" 2>/dev/null; then
            if ! line_has_ignore "$line" "no-setter"; then
                add_violation "PHP003" "Public setter found — use behavioral methods"
            else
                metrics_record_violation "PHP003" "$FILE_PATTERN" "critical" 0 1 2>/dev/null || true
            fi
        fi
    done < "$file"

    # PHP004: No new DateTime()
    if grep -q "new DateTime()" "$file" 2>/dev/null || grep -q "new \\\\DateTime()" "$file" 2>/dev/null; then
        add_violation "PHP004" "new DateTime() found — inject Clock instead"
    fi

    # PHP005: No empty catch blocks
    if grep -A1 "catch" "$file" 2>/dev/null | grep -qE "^\s*\}\s*$" 2>/dev/null; then
        add_warning "PHP005" "Possible empty catch block"
    fi

    # WARN-PHP001: Max 3 parameters
    if grep -qE "function\s+\w+\(([^,]+,){3,}" "$file" 2>/dev/null; then
        add_warning "WARN-PHP001" "Method with 4+ parameters — consider refactoring to object"
    fi
}
