#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Bash Pack Tests ==="

# Source validator
source "$ROOT_DIR/packs/bash/hooks/bash-validator.sh"

# Provide mock helpers
VIOLATIONS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2\n"; }
add_warning() { VIOLATIONS="${VIOLATIONS}WARN:$1:$2\n"; }
line_has_ignore() { return 1; }
metrics_record_violation() { true; }
FILE_PATTERN="test"

# Test: pack.yml exists
if [[ -f "$ROOT_DIR/packs/bash/pack.yml" ]]; then
    log_pass "pack.yml exists"
else
    log_fail "pack.yml exists" "file not found"
fi

# Test: SH001 detects missing set -u
tmpfile=$(mktemp /tmp/test_sh_XXXXXX.sh)
cat > "$tmpfile" << 'SHELL'
#!/usr/bin/env bash
echo "hello"
SHELL
VIOLATIONS=""
pack_validate_bash "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "SH001"; then
    log_pass "SH001: detects missing set -u"
else
    log_fail "SH001: detects missing set -u" "not detected"
fi

# Test: SH001 passes with set -uo pipefail
cat > "$tmpfile" << 'SHELL'
#!/usr/bin/env bash
set -uo pipefail
echo "hello"
SHELL
VIOLATIONS=""
pack_validate_bash "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "SH001"; then
    log_fail "SH001: passes with set -uo" "false positive"
else
    log_pass "SH001: passes with set -uo"
fi

# Test: SH002 detects long functions
cat > "$tmpfile" << 'SHELL'
#!/usr/bin/env bash
set -uo pipefail
very_long_function() {
    local line1="a"
    local line2="b"
    local line3="c"
    local line4="d"
    local line5="e"
    local line6="f"
    local line7="g"
    local line8="h"
    local line9="i"
    local line10="j"
    local line11="k"
    local line12="l"
    local line13="m"
    local line14="n"
    local line15="o"
    local line16="p"
    local line17="q"
    local line18="r"
    local line19="s"
    local line20="t"
    local line21="u"
    local line22="v"
    local line23="w"
    local line24="x"
    local line25="y"
    local line26="z"
    local line27="aa"
    local line28="bb"
    local line29="cc"
    local line30="dd"
    local line31="ee"
    echo "$line1"
}
SHELL
VIOLATIONS=""
pack_validate_bash "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "SH002"; then
    log_pass "SH002: detects long functions"
else
    log_fail "SH002: detects long functions" "not detected"
fi

# Test: SH004 detects eval usage
cat > "$tmpfile" << 'SHELL'
#!/usr/bin/env bash
set -uo pipefail
eval "echo hello"
SHELL
VIOLATIONS=""
pack_validate_bash "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "SH004"; then
    log_pass "SH004: detects eval usage"
else
    log_fail "SH004: detects eval usage" "not detected"
fi

# Test: SH005 detects unquoted variables
cat > "$tmpfile" << 'SHELL'
#!/usr/bin/env bash
set -uo pipefail
rm $filepath
SHELL
VIOLATIONS=""
pack_validate_bash "$tmpfile"
if echo -e "$VIOLATIONS" | grep -q "SH005"; then
    log_pass "SH005: detects unquoted variables"
else
    log_fail "SH005: detects unquoted variables" "not detected"
fi

# Test: Clean bash file passes
cat > "$tmpfile" << 'SHELL'
#!/usr/bin/env bash
set -uo pipefail

readonly MAX_COUNT=10

process_items() {
    local item_count="$1"
    echo "Processing ${item_count} items"
}

process_items "$MAX_COUNT"
SHELL
VIOLATIONS=""
pack_validate_bash "$tmpfile"
# Allow SH001 and warnings but no violations
if echo -e "$VIOLATIONS" | grep -qv "WARN:" | grep -q "."; then
    log_fail "Clean bash file: no blocking violations" "got: $(echo -e "$VIOLATIONS")"
else
    log_pass "Clean bash file: no blocking violations"
fi

rm -f "$tmpfile"
echo "=== Bash Pack Tests Complete ==="
