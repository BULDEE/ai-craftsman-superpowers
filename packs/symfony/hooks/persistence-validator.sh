#!/usr/bin/env bash
# =============================================================================
# PHP Persistence Validator - Symfony Pack
# Provides pack_validate_php_persistence() for storage-boundary enforcement.
#
# Rules:
#   LAYER004 - raw SQL/DQL inside Domain layer (persistence leaks into domain)
#   DB001    - SELECT * (fragile contract with the schema)
#   DB002    - migration without a down()/rollback path
#   DB003    - query call inside a loop (N+1 heuristic)
# Requires: add_violation(), add_warning(), line_has_ignore()
#   Provided by the orchestrator (post-write-check.sh or craftsman-ci.sh).
# =============================================================================

_persistence_php_is_domain() {
    local file="$1"
    [[ "$file" == *"/Domain/"* ]] && return 0
    grep -qE "namespace\s+App\\\\Domain" "$file" 2>/dev/null
}

_persistence_php_check_domain_sql() {
    local file="$1"
    _persistence_php_is_domain "$file" || return 0
    if grep -qEi "(SELECT\s+.+\s+FROM\s|INSERT\s+INTO\s|UPDATE\s+.+\s+SET\s|DELETE\s+FROM\s|createQuery\(|createNativeQuery\(|->executeQuery\()" "$file" 2>/dev/null; then
        add_violation "LAYER004" "Raw SQL/DQL inside Domain layer - persistence belongs behind a Repository interface in Infrastructure"
    fi
}

_persistence_php_check_select_star() {
    local file="$1"
    local line
    line=$(grep -nEi "SELECT\s+\*\s+FROM" "$file" 2>/dev/null | head -1)
    [[ -z "$line" ]] && return 0
    line_has_ignore "$(echo "$line" | cut -d: -f2-)" "DB001" && return 0
    add_warning "DB001" "SELECT * couples code to the full schema - name the columns you need"
}

_persistence_php_check_migration_down() {
    local file="$1"
    [[ "$file" == *[Mm]igration* ]] || return 0
    grep -qE "function\s+up\s*\(" "$file" 2>/dev/null || return 0
    if ! grep -qE "function\s+down\s*\(" "$file" 2>/dev/null; then
        add_warning "DB002" "Migration has up() but no down() - every schema change needs a tested rollback path"
    fi
}

_persistence_php_check_query_in_loop() {
    local file="$1"
    local hits
    hits=$(awk '
        /foreach|for[[:space:]]*\(|while[[:space:]]*\(/ { depth = 1; line = NR }
        depth && /->(find|findBy|findOneBy|query|executeQuery|fetch)[A-Za-z]*\(/ && NR > line { print line; depth = 0 }
        /^[[:space:]]*}/ { depth = 0 }
    ' "$file" 2>/dev/null | head -1)
    [[ -z "$hits" ]] && return 0
    add_warning "DB003" "Query call inside a loop (line ~${hits}) - likely N+1; batch the query or eager-load the association"
}

pack_validate_php_persistence() {
    local file="$1"
    _persistence_php_check_domain_sql "$file"
    _persistence_php_check_select_star "$file"
    _persistence_php_check_migration_down "$file"
    _persistence_php_check_query_in_loop "$file"
}
