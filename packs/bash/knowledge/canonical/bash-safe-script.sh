#!/usr/bin/env bash
# =============================================================================
# Canonical Bash Script — demonstrates safety options, naming, and structure.
# =============================================================================
set -euo pipefail

# Constants at the top — no magic numbers
readonly MAX_RETRY_COUNT=3
readonly TIMEOUT_SECONDS=30
readonly LOG_FILE="/var/log/app/process.log"

# Descriptive function names, local variables, early returns
validate_input_file() {
    local input_file_path="$1"

    [[ -z "$input_file_path" ]] && {
        echo "ERROR: input file path is required" >&2
        return 1
    }

    [[ ! -f "$input_file_path" ]] && {
        echo "ERROR: file not found: ${input_file_path}" >&2
        return 1
    }

    [[ ! -r "$input_file_path" ]] && {
        echo "ERROR: file not readable: ${input_file_path}" >&2
        return 1
    }
}

# Atomic file write — temp file + rename (no partial writes)
write_output_atomically() {
    local output_path="$1"
    local content="$2"
    local parent_directory
    parent_directory=$(dirname "$output_path")

    local temporary_file
    temporary_file=$(mktemp "${parent_directory}/output.XXXXXX")

    # Cleanup on failure
    trap 'rm -f "$temporary_file"' ERR

    echo "$content" > "$temporary_file"
    mv "$temporary_file" "$output_path"
}

# Retry with exponential backoff — descriptive variable names
retry_with_backoff() {
    local command_to_run="$1"
    local current_attempt=0
    local wait_seconds=1

    while [[ $current_attempt -lt $MAX_RETRY_COUNT ]]; do
        if eval "$command_to_run"; then
            return 0
        fi

        ((current_attempt++))
        echo "Attempt ${current_attempt}/${MAX_RETRY_COUNT} failed, waiting ${wait_seconds}s..." >&2
        sleep "$wait_seconds"
        ((wait_seconds *= 2))
    done

    echo "ERROR: all ${MAX_RETRY_COUNT} attempts failed" >&2
    return 1
}

# Main — short, delegates to functions
main() {
    local input_file="${1:-}"

    validate_input_file "$input_file"

    local processed_content
    processed_content=$(process_file "$input_file")

    write_output_atomically "${input_file}.out" "$processed_content"

    echo "Done: ${input_file}" >> "$LOG_FILE"
}

main "$@"
