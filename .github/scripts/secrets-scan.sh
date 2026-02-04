#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT="${1:-.}"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

declare -a FINDINGS=()
declare -i EXIT_CODE=0

die() {
    echo "Error: $1" >&2
    exit 1
}

log_error() {
    FINDINGS+=("${RED}[ERROR]${NC} $1 ${2:+($2)}")
    EXIT_CODE=1
}

log_warn() {
    FINDINGS+=("${YELLOW}[WARN]${NC} $1 ${2:+($2)}")
}

log_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

search_tracked_files() {
    local pattern="$1"
    git -C "$REPO_ROOT" ls-files -z 2>/dev/null \
        | xargs -0 grep -n -E "$pattern" 2>/dev/null \
        || true
}

search_tracked_filenames() {
    local pattern="$1"
    git -C "$REPO_ROOT" ls-files 2>/dev/null \
        | grep -E "$pattern" \
        || true
}

search_git_history() {
    local pattern="$1"
    git -C "$REPO_ROOT" log -100 -p --all 2>/dev/null \
        | grep -E "$pattern" \
        | head -5 \
        || true
}

check_pattern() {
    local description="$1"
    local pattern="$2"
    local severity="${3:-ERROR}"
    local exclude_pattern="${4:-}"

    local results
    results=$(search_tracked_files "$pattern")

    [[ -n "$exclude_pattern" ]] && results=$(echo "$results" | grep -v -E "$exclude_pattern" || true)

    if [[ -n "$results" ]]; then
        while IFS= read -r line; do
            local file
            file=$(echo "$line" | cut -d: -f1)
            if [[ "$severity" == "ERROR" ]]; then
                log_error "$description" "$file"
            else
                log_warn "$description" "$file"
            fi
        done <<< "$results"
    else
        log_ok "No $description"
    fi
}

check_sensitive_files() {
    local description="$1"
    local pattern="$2"
    local exclude="${3:-}"

    local results
    results=$(search_tracked_filenames "$pattern")

    [[ -n "$exclude" ]] && results=$(echo "$results" | grep -v "$exclude" || true)

    if [[ -n "$results" ]]; then
        while IFS= read -r file; do
            log_error "$description" "$file"
        done <<< "$results"
    else
        log_ok "No $description"
    fi
}

check_git_history_pattern() {
    local description="$1"
    local pattern="$2"
    local exclude="${3:-}"

    local results
    results=$(search_git_history "$pattern")

    [[ -n "$exclude" ]] && results=$(echo "$results" | grep -v "$exclude" || true)

    if [[ -n "$results" ]]; then
        log_error "$description (run BFG to clean)"
    else
        log_ok "No $description"
    fi
}

scan_local_paths() {
    echo "Scanning for local filesystem paths..."
    check_pattern \
        "local filesystem paths" \
        '/Users/[a-zA-Z0-9_-]+/|/home/[a-zA-Z0-9_-]+/' \
        "ERROR" \
        "YOUR_USERNAME|YOUR-USERNAME"
}

scan_api_keys() {
    echo "Scanning for hardcoded API keys..."
    check_pattern "OpenAI API keys" 'sk-[a-zA-Z0-9]{32,}'
    check_pattern "AWS Access Key IDs" 'AKIA[0-9A-Z]{16}'
    check_pattern "GitHub tokens" 'ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{22,}'
    check_pattern "Anthropic API keys" 'sk-ant-[a-zA-Z0-9-]{32,}'
}

scan_sensitive_files() {
    echo "Scanning for sensitive files..."
    check_sensitive_files ".env files in repo" '^\.env$|/\.env$|\.env\.local$|\.env\.production$'
    check_sensitive_files "private key files in repo" '\.(pem|key|p12|pfx)$|id_rsa|id_ed25519'
    check_sensitive_files "credential files in repo" 'credentials\.json$|service-account\.json$' ".claude-plugin"
}

scan_private_info() {
    echo "Scanning for private information..."
    check_pattern \
        "private IP addresses" \
        '192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+' \
        "WARN" \
        '#|example|Example'
}

scan_git_history() {
    echo "Scanning git history for secrets..."
    check_git_history_pattern \
        "local paths in git history" \
        '^\+.*/Users/[a-zA-Z0-9_-]+/' \
        "YOUR_USERNAME"
    check_git_history_pattern \
        "API keys in git history" \
        '^\+.*(sk-[a-zA-Z0-9]{32,}|AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36})'
}

print_summary() {
    echo ""
    echo "=============================================="
    echo "  Scan Results"
    echo "=============================================="
    echo ""

    if [[ ${#FINDINGS[@]} -gt 0 ]]; then
        echo "Findings:"
        for finding in "${FINDINGS[@]}"; do
            echo -e "  $finding"
        done
        echo ""
    fi

    if [[ $EXIT_CODE -eq 1 ]]; then
        echo -e "${RED}FAILED${NC}: Secrets or sensitive data detected!"
        echo ""
        echo "Actions required:"
        echo "  1. Remove sensitive data from current files"
        echo "  2. If committed, clean history with BFG:"
        echo "     bfg --replace-text replacements.txt --no-blob-protection ."
        echo "     git reflog expire --expire=now --all && git gc --prune=now --aggressive"
        echo "  3. Force push to update remote"
    else
        echo -e "${GREEN}SUCCESS${NC}: No secrets or sensitive data found!"
    fi
}

main() {
    [[ -d "$REPO_ROOT/.git" ]] || die "Not a git repository: $REPO_ROOT"

    echo "=============================================="
    echo "  Secrets & Sensitive Data Scanner"
    echo "=============================================="
    echo ""

    scan_local_paths
    scan_api_keys
    scan_sensitive_files
    scan_private_info
    scan_git_history
    print_summary

    exit $EXIT_CODE
}

main
