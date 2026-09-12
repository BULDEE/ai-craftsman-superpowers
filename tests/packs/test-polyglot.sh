#!/usr/bin/env bash
# =============================================================================
# A language pack runs on its files whatever stack the project declares.
#
# packs/go and packs/rust shipped with `stack: ["go", "fullstack"]`, copied
# from packs/python, packs/react and packs/symfony, and an adversarial review
# measured the cost: the same Go file produced five findings under `stack: go`
# and zero under `stack: symfony`, exit 0, nothing printed to say the pack was
# skipped. The Go pack was fixed; the three packs it copied were not (#35).
#
# Every pack suite sources its validator directly, so `_pack_stack_compatible`
# is never on the path they exercise. This one drives ci/craftsman-ci.sh, the
# real consumer, and asserts a known violation is REFUSED in a repository whose
# declared stack names another ecosystem. The last case proves the assertion
# can fail: a copy of the plugin with the old gate put back must go silent.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Polyglot repositories (#35) ==="

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-polyglot.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# make_project <name> <declared stack> <relative file> <<'SRC' ... SRC
make_project() {
    local name="$1" stack="$2" file="$3"
    local project="$WORK/$name"
    mkdir -p "$project/$(dirname "$file")"
    printf 'stack: %s\nstrictness: strict\n' "$stack" > "$project/.craft-config.yml"
    cat > "$project/$file"
    ( cd "$project" && git init -q && git add -A ) >/dev/null 2>&1
    printf '%s' "$project"
}

# scan <plugin root> <project>: craftsman-ci's output on src/, both streams.
scan() {
    ( cd "$2" && CLAUDE_PLUGIN_ROOT="$1" bash "$1/ci/craftsman-ci.sh" src 2>&1 )
}

# --- A .py file in a React project ------------------------------------------
PY_PROJECT="$(make_project "react-with-python" react "src/tool.py" <<'PY'
def load(path: str) -> str:
    try:
        return open(path).read()
    except:
        return ""
PY
)"
py_out="$(scan "$ROOT_DIR" "$PY_PROJECT")"
if echo "$py_out" | grep -q "PY004"; then
    log_pass "a .py file is refused in a project whose stack is react"
else
    log_fail "a .py file is refused in a project whose stack is react" \
        "no PY004: $(echo "$py_out" | tr '\n' ' ' | cut -c1-200)"
fi

# --- A .ts file in a Symfony project -----------------------------------------
TS_PROJECT="$(make_project "symfony-with-ts" symfony "src/widget.ts" <<'TS'
export function render(data: any): string {
    return String(data);
}
TS
)"
ts_out="$(scan "$ROOT_DIR" "$TS_PROJECT")"
if echo "$ts_out" | grep -q "TS001"; then
    log_pass "a .ts file is refused in a project whose stack is symfony"
else
    log_fail "a .ts file is refused in a project whose stack is symfony" \
        "no TS001: $(echo "$ts_out" | tr '\n' ' ' | cut -c1-200)"
fi

# --- A .php file in a Python project ------------------------------------------
PHP_PROJECT="$(make_project "python-with-php" python "src/Legacy.php" <<'PHP'
<?php
class Legacy {
    public function total($amount) { return $amount * 2; }
}
PHP
)"
php_out="$(scan "$ROOT_DIR" "$PHP_PROJECT")"
if echo "$php_out" | grep -q "PHP001"; then
    log_pass "a .php file is refused in a project whose stack is python"
else
    log_fail "a .php file is refused in a project whose stack is python" \
        "no PHP001: $(echo "$php_out" | tr '\n' ' ' | cut -c1-200)"
fi

# --- The assertion can fail -----------------------------------------------------
#
# A copy of the plugin with the Symfony pack gated back to its old stack list.
# If the .php case above stays green here, the test proves nothing about the
# gate, which is exactly how the hole shipped.
GATED="$WORK/gated-plugin"
mkdir -p "$GATED"
cp -R "$ROOT_DIR/hooks" "$ROOT_DIR/packs" "$ROOT_DIR/ci" "$GATED/"
[[ -f "$ROOT_DIR/.craft-config.yml" ]] && cp "$ROOT_DIR/.craft-config.yml" "$GATED/"
sed -i.bak 's/^  stack: \["\*"\]$/  stack: ["symfony", "fullstack"]/' "$GATED/packs/symfony/pack.yml"
if grep -q '^  stack: \["symfony", "fullstack"\]' "$GATED/packs/symfony/pack.yml"; then
    gated_out="$(scan "$GATED" "$PHP_PROJECT")"
    if echo "$gated_out" | grep -q "PHP001"; then
        log_fail "with the old gate put back, the .php file is waved through" \
            "PHP001 still reported, so the cases above do not exercise the gate"
    else
        log_pass "with the old gate put back, the .php file is waved through (the assertion can fail)"
    fi
else
    log_fail "with the old gate put back, the .php file is waved through" \
        "could not put the old gate back in the copy"
fi

test_summary
