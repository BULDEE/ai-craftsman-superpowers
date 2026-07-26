#!/usr/bin/env bash
# =============================================================================
# TypeScript Persistence Validator - React Pack
# Provides pack_validate_typescript_persistence() for storage-boundary
# enforcement in TS codebases (API/backend-for-frontend layers included).
#
# Rules:
#   LAYER004 - database client imported inside domain/ (storage leaks into domain)
#   DB001    - SELECT * in query strings
#   DB003    - awaited query inside a loop (N+1 heuristic)
# Requires: add_violation(), add_warning()
# =============================================================================

_persistence_ts_check_domain_client() {
    local file="$1"
    [[ "$file" == *"/domain/"* ]] || return 0
    if grep -qE "from\s+['\"](pg|mysql2?|mongoose|mongodb|@prisma/client|drizzle-orm|typeorm|knex|redis|ioredis)['\"]" "$file" 2>/dev/null; then
        add_violation "LAYER004" "Database client imported inside domain/ - persistence belongs behind a repository interface in infrastructure"
    fi
}

_persistence_ts_check_select_star() {
    local file="$1"
    if grep -qEi "SELECT\s+\*\s+FROM" "$file" 2>/dev/null; then
        add_warning "DB001" "SELECT * couples code to the full schema - name the columns you need"
    fi
}

_persistence_ts_check_query_in_loop() {
    local file="$1"
    local hits
    hits=$(awk '
        /for[[:space:]]*\(|for[[:space:]]+await|while[[:space:]]*\(|\.forEach\(|\.map\(/ { depth = 1; line = NR }
        depth && /await[[:space:]]+.*\.(query|findUnique|findMany|findOne|find|aggregate|execute)\(/ && NR > line { print line; depth = 0 }
        /^[[:space:]]*}[[:space:]]*\)?;?[[:space:]]*$/ { depth = 0 }
    ' "$file" 2>/dev/null | head -1)
    [[ -z "$hits" ]] && return 0
    add_warning "DB003" "Awaited query inside a loop (line ~${hits}) - likely N+1; use findMany/IN clause or batch the calls"
}

pack_validate_typescript_persistence() {
    local file="$1"
    _persistence_ts_check_domain_client "$file"
    _persistence_ts_check_select_star "$file"
    _persistence_ts_check_query_in_loop "$file"
}
