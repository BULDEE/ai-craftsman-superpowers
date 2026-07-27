#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT="${1:-.}"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

declare -a FINDINGS=()
declare -i EXIT_CODE=0

# A fixture has to look like a real credential to exercise the validators, so
# it needs an opt-out. Excluding tests/ wholesale would hide a real secret
# committed there; this marker is per-line, greppable and shows up in review,
# the way detect-secrets uses "pragma: allowlist secret".
readonly ALLOWLIST_MARKER='secrets-scan: allow'

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
    # Test fixtures are excluded: they carry deliberately fake credentials to
    # exercise the security validators. Current files are still scanned by
    # check_pattern, so a real secret committed under tests/ is not missed.
    git -C "$REPO_ROOT" log -100 -p --all -- . ':(exclude)tests/' 2>/dev/null \
        | grep -E "$pattern" \
        | head -5 \
        || true
}

# Every check below reports "No <thing>" when its search comes back empty, and
# an empty search is exactly what a broken scanner produces: a wrong REPO_ROOT,
# a shallow clone with no history, a missing xargs, a grep that failed. The
# scanner therefore has to prove it can still enumerate and read tracked
# content before any of those empty results is allowed to mean "clean".
assert_scanner_is_live() {
    local tracked
    tracked=$(git -C "$REPO_ROOT" ls-files | wc -l | tr -d ' ')
    [[ "$tracked" -gt 0 ]] \
        || die "no tracked files under $REPO_ROOT: refusing to report a clean scan"

    local readable
    readable=$(git -C "$REPO_ROOT" ls-files -z 2>/dev/null \
        | xargs -0 grep -l -E -e '[a-z]' 2>/dev/null \
        | head -1 || true)
    [[ -n "$readable" ]] \
        || die "read no content from $tracked tracked files: refusing to report a clean scan"

    local history
    history=$(git -C "$REPO_ROOT" log -1 --oneline 2>/dev/null || true)
    [[ -n "$history" ]] \
        || die "no readable git history: refusing to report a clean history scan"

    log_ok "scanner is live ($tracked tracked files, history readable)"
}

check_pattern() {
    local description="$1"
    local pattern="$2"
    local severity="${3:-ERROR}"
    local exclude_pattern="${4:-}"

    local results
    results=$(search_tracked_files "$pattern")

    results=$(echo "$results" | grep -v -F -e "$ALLOWLIST_MARKER" || true)
    [[ -n "$exclude_pattern" ]] && results=$(echo "$results" | grep -v -E -e "$exclude_pattern" || true)

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

    [[ -n "$exclude" ]] && results=$(echo "$results" | grep -v -E -e "$exclude" || true)

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

    [[ -n "$exclude" ]] && results=$(echo "$results" | grep -v -E -e "$exclude" || true)

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
    # sk-proj- keys carry separators the sk- pattern above stops at, so they
    # were passing through the scanner untouched.
    check_pattern "OpenAI project keys" 'sk-proj-[a-zA-Z0-9_-]{20,}'
    check_pattern "AWS Access Key IDs" 'AKIA[0-9A-Z]{16}'
    # ASIA is the temporary-credential prefix: shorter lived, same blast radius
    # while it is valid.
    check_pattern "AWS temporary Access Key IDs" 'ASIA[0-9A-Z]{16}'
    # A bare 40-char base64 run also matches every git SHA and every hash in
    # the repo, so this anchors on the assignment instead.
    check_pattern "AWS secret access keys" \
        '(aws_secret_access_key|AWS_SECRET_ACCESS_KEY)[[:space:]]*[=:][[:space:]]*.?[A-Za-z0-9/+=]{40}'
    check_pattern "GitHub tokens" 'ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{22,}'
    check_pattern "Anthropic API keys" 'sk-ant-[a-zA-Z0-9-]{32,}'
    check_pattern "Stripe live keys" '(sk|rk)_live_[0-9a-zA-Z]{20,}'
    check_pattern "Slack tokens" 'xox[abposr]-[0-9a-zA-Z-]{10,}'
}

scan_sensitive_files() {
    echo "Scanning for sensitive files..."
    # The old list named .local and .production one by one, which let
    # .env.staging, .env.prod and every other suffix through. Match any suffix
    # and exclude only the ones that exist to be committed.
    check_sensitive_files ".env files in repo" \
        '(^|/)\.env(\.[a-zA-Z0-9_.-]+)?$' \
        '\.env\.(example|dist|sample|template)$'
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
    # Local paths in history are NOT a security risk (no access granted).
    # Current files are already checked by scan_local_paths.
    # Only API keys/secrets warrant history scanning.
    check_git_history_pattern \
        "API keys in git history" \
        '^\+.*(sk-[a-zA-Z0-9]{32,}|sk-proj-[a-zA-Z0-9_-]{20,}|A(KIA|SIA)[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|(sk|rk)_live_[0-9a-zA-Z]{20,}|xox[abposr]-[0-9a-zA-Z-]{10,})'
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

    assert_scanner_is_live
    scan_local_paths
    scan_api_keys
    scan_sensitive_files
    scan_private_info
    scan_git_history
    print_summary

    exit $EXIT_CODE
}

main
