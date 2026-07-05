#!/usr/bin/env bash
# =============================================================================
# Canonical example: SOLID principles adapted to Bash.
#
# Bash has no classes, so SOLID applies through FUNCTIONS, SOURCED FILES, and
# ABSTRACTED COMMANDS. Some principles map cleanly, others only in spirit; this
# file is honest about which is which. See knowledge/principles.md for the theory.
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# S - Single Responsibility
# One function does one thing. A function that validates AND fetches AND formats
# is three functions wearing a trench coat. Split them.
# -----------------------------------------------------------------------------
validate_email() {
    local email="$1"
    [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]
}

format_currency() {
    local cents="$1"
    printf '%d.%02d EUR' $((cents / 100)) $((cents % 100))
}

# -----------------------------------------------------------------------------
# O - Open/Closed
# Add a new handler without editing the dispatcher: dispatch by convention to a
# function named handle_<type>, so a new type is a new function, not an edited case.
# -----------------------------------------------------------------------------
handle_json() { printf 'rendering json\n'; }
handle_text() { printf 'rendering text\n'; }

render_report() {
    local format="$1"
    local handler="handle_${format}"
    if declare -F "$handler" >/dev/null; then
        "$handler"        # extend by adding handle_<format>, dispatcher unchanged
    else
        echo "unknown format: ${format}" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# L - Liskov Substitution (in spirit)
# Any function used as a "logger" must honor the same contract: take a message,
# return 0. A drop-in replacement that exits non-zero on success breaks callers.
# -----------------------------------------------------------------------------
log_to_stdout() { printf '%s\n' "$1"; return 0; }
log_to_file()   { printf '%s\n' "$1" >>"${LOG_FILE:-/dev/null}"; return 0; }

# -----------------------------------------------------------------------------
# I - Interface Segregation (in spirit)
# Pass a function only the arguments it needs, not a giant associative array of
# everything. Narrow, positional inputs keep callers decoupled from unused data.
# -----------------------------------------------------------------------------
send_notification() {
    local recipient="$1" subject="$2"   # exactly what it needs, nothing more
    printf 'notifying %s: %s\n' "$recipient" "$subject"
}

# -----------------------------------------------------------------------------
# D - Dependency Inversion
# Depend on an abstraction (a logger function name) injected by the caller,
# instead of hard-coding one logging command inside the business function.
# -----------------------------------------------------------------------------
process_order() {
    local order_id="$1"
    local logger="${2:-log_to_stdout}"   # injected abstraction, default provided
    "$logger" "processing order ${order_id}"
}

# Example wiring (the composition root decides the concrete dependency):
#   process_order "ORD-1" log_to_file
