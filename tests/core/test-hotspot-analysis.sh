#!/usr/bin/env bash
# =============================================================================
# Tests for hooks/lib/hotspot_analysis.py
# Verifies churn x complexity ranking, JSON output, and quadrant classification
# on a deterministic throwaway git repo.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TOOL="$ROOT_DIR/hooks/lib/hotspot_analysis.py"
PYTHON="$(command -v python3 || echo python3)"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo ""
echo "=== Hotspot Analysis Tests ==="

if [[ ! -f "$TOOL" ]]; then
    log_fail "hotspot_analysis.py missing"
    test_summary
    exit 0
fi

# --- Build a deterministic repo: one hot+complex file, one cold+simple file ---
FIXTURE="$(mktemp -d /tmp/craftsman_hotspot_XXXXXX)"
trap 'rm -rf "$FIXTURE"' EXIT
(
    cd "$FIXTURE"
    git init -q
    git config user.email t@t.t; git config user.name t

    # hot.php: changed many times, deeply nested (high complexity + high churn)
    for n in 1 2 3 4 5; do
        {
            echo "<?php"
            echo "class Hot {"
            echo "  function f(\$x) {"
            echo "    if (\$x) { if (\$x) { if (\$x) { return $n; } } }"
            printf '    // padding line\n%.0s' $(seq 1 60)
            echo "  }"
            echo "}"
        } > hot.php
        git add hot.php && git commit -qm "change $n"
    done

    # cold.php: committed once, trivial (low churn, low complexity)
    printf '<?php\nfinal class Cold { public function id(): int { return 1; } }\n' > cold.php
    git add cold.php && git commit -qm "add cold"
)

# --- 1. JSON output is valid and ranks hot.php in the top-right ---
JSON=$("$PYTHON" "$TOOL" --json "$FIXTURE" 2>/dev/null)
if echo "$JSON" | "$PYTHON" -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    log_pass "produces valid JSON"
else
    log_fail "JSON output invalid" "$(echo "$JSON" | head -1)"
fi

TOP_FILE=$(echo "$JSON" | "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["file"] if d else "")' 2>/dev/null)
if [[ "$TOP_FILE" == "hot.php" ]]; then
    log_pass "ranks the hot+complex file first"
else
    log_fail "hot.php should rank first" "got '$TOP_FILE'"
fi

TOP_QUADRANT=$(echo "$JSON" | "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["quadrant"] if d else "")' 2>/dev/null)
if [[ "$TOP_QUADRANT" == "top-right" ]]; then
    log_pass "hottest file is in the top-right quadrant"
else
    log_fail "hot file should be top-right" "got '$TOP_QUADRANT'"
fi

# --- 2. churn reflects the number of commits touching the file ---
HOT_CHURN=$(echo "$JSON" | "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(next((r["churn"] for r in d if r["file"]=="hot.php"), 0))' 2>/dev/null)
if [[ "${HOT_CHURN:-0}" -ge 5 ]]; then
    log_pass "churn counts commits (hot.php churn=${HOT_CHURN})"
else
    log_fail "hot.php churn should be >= 5" "got '${HOT_CHURN}'"
fi

# --- 3. table output is human-readable and points at the top-right ---
TABLE=$("$PYTHON" "$TOOL" "$FIXTURE" 2>/dev/null)
if echo "$TABLE" | grep -q 'top-right'; then
    log_pass "table output labels the top-right quadrant"
else
    log_fail "table should mention top-right"
fi

# --- 4. empty / non-repo path degrades gracefully ---
EMPTY=$(mktemp -d)
OUT=$("$PYTHON" "$TOOL" "$EMPTY" 2>/dev/null); rc=$?
rm -rf "$EMPTY"
if [[ "$rc" -eq 0 ]]; then
    log_pass "non-repo path exits 0 (graceful)"
else
    log_fail "non-repo path should exit 0" "got $rc"
fi

# --- 5. no em-dash (copywriting rule) ---
if [[ "$(grep -c $'\xe2\x80\x94' "$TOOL")" == "0" ]]; then
    log_pass "no em-dash in hotspot_analysis.py"
else
    log_fail "em-dash found in hotspot_analysis.py"
fi

test_summary
