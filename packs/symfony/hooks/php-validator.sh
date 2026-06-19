#!/usr/bin/env bash
# =============================================================================
# PHP Regex Validator — Symfony Pack
# Provides pack_validate_php() for the pack-loader pipeline.
#
# Rules: PHP001-005, WARN-PHP001 (regex) + NEST001/LOC001/GOD001/PARAM001
#   (brace-aware, via structural_check_file) + CTRL001 (controller logic leak).
# Requires: add_violation(), add_warning(), line_has_ignore(), metrics_record_violation()
#   These are provided by the orchestrator (post-write-check.sh) before sourcing.
# craftsman-ignore: SH001
# =============================================================================

_check_php001() {
    local file="$1"
    if ! grep -q "declare(strict_types=1)" "$file" 2>/dev/null; then
        add_violation "PHP001" "Missing declare(strict_types=1)"
    fi
}

_check_php002() {
    local file="$1"
    grep -q "^class " "$file" 2>/dev/null || return 0
    grep -q "final class" "$file" 2>/dev/null && return 0
    grep -qE "(interface |trait |abstract class )" "$file" 2>/dev/null && return 0
    add_violation "PHP002" "Class should be final"
}

_check_php003() {
    local file="$1"
    local line
    while IFS= read -r line; do
        echo "$line" | grep -qE "public function set[A-Z]" 2>/dev/null || continue
        if ! line_has_ignore "$line" "no-setter"; then
            add_violation "PHP003" "Public setter found — use behavioral methods"
        else
            metrics_record_violation "PHP003" "$FILE_PATTERN" "critical" 0 1 2>/dev/null || true
        fi
    done < "$file"
}

_check_php004() {
    local file="$1"
    if grep -q "new DateTime()" "$file" 2>/dev/null || grep -q "new \\\\DateTime()" "$file" 2>/dev/null; then
        add_violation "PHP004" "new DateTime() found — inject Clock instead"
    fi
}

_check_php005() {
    local file="$1"
    if grep -A1 "catch" "$file" 2>/dev/null | grep -qE "^\s*\}\s*$" 2>/dev/null; then
        add_warning "PHP005" "Possible empty catch block"
    fi
}

_check_warn_php001() {
    local file="$1"
    if grep -qE "function\s+\w+\(([^,]+,){3,}" "$file" 2>/dev/null; then
        add_warning "WARN-PHP001" "Method with 4+ parameters — consider refactoring to object"
    fi
}

# NEST001/LOC001/GOD001/PARAM001 (brace-aware) + CTRL001 (controller logic leak)
_check_php_structure() {
    local file="$1"

    if declare -F structural_check_file >/dev/null 2>&1; then
        structural_check_file "$file" "php"
    fi

    echo "$file" | grep -qE "Controller\.php$|/Controller/" 2>/dev/null \
        || grep -qE "extends AbstractController" "$file" 2>/dev/null \
        || return 0
    # Alternation starts with a non-dash token so grep/ugrep never reads the
    # leading "->" as an option flag.
    if grep -qE "EntityManagerInterface|->persist\(|->flush\(|->getRepository\(" "$file" 2>/dev/null; then
        add_violation "CTRL001" "Controller performs persistence/EM work — move it into an Application UseCase"
    fi
}

pack_validate_php() {
    local file="$1"
    _check_php001 "$file"
    _check_php002 "$file"
    _check_php003 "$file"
    _check_php004 "$file"
    _check_php005 "$file"
    _check_warn_php001 "$file"
    _check_php_structure "$file"
}
