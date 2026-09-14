#!/usr/bin/env bash
# =============================================================================
# The engine holds no list of languages.
#
# A pack declares its languages in pack.yml; the registry compiles them; every
# hook, the pipeline and the Python helpers ask the registry. That is the rule
# CLAUDE.md states, and the review of 4.9.0 found eight places in the core that
# still knew "php" and "ts" by name: a FileChanged matcher that only ever
# watched three extensions, a stack detector that only ever found composer.json
# and package.json, a codemap with its own extension set, a namespace resolver
# and an AST checker owned by one pack each and living in hooks/lib, a rule list
# in the engine, and a metrics extractor that took the language name in place
# of its dialect.
#
# This test reads the core (hooks/, ci/, hooks.json) and fails on any language
# name or extension outside a comment. Dialect names (`php-like`, `c-like`) are
# not languages and are allowed; so is the test-path convention, which names
# directories, not languages.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== No language literal in the core ==="

HITS=$(python3 "$SCRIPT_DIR/../lib/language_literals.py" "$ROOT_DIR")

if [[ -z "$HITS" ]]; then
    log_pass "no language name or extension in hooks/, ci/ or hooks.json outside a comment"
else
    log_fail "no language name or extension in hooks/, ci/ or hooks.json outside a comment" \
        "$(echo "$HITS" | wc -l | tr -d ' ') hit(s):
$HITS"
fi

# The FileChanged matcher lists literal filenames or directories with a
# trailing slash (code.claude.com/docs/en/hooks, FileChanged: "Glob patterns
# such as *.php are not supported; list exact filenames. You can watch
# directories by adding a trailing /"). The glob the manifest carried never
# matched a file, so the hook never ran.
FC_MATCHER=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/hooks/hooks.json'))['hooks']['FileChanged'][0]['matcher'])")
if [[ "$FC_MATCHER" != *'*'* ]] && [[ -n "$FC_MATCHER" ]] && ! echo "$FC_MATCHER" | tr '|' '\n' | grep -qv '/$'; then
    log_pass "the FileChanged matcher watches directories, the form the event supports ($FC_MATCHER)"
else
    log_fail "the FileChanged matcher watches directories, the form the event supports" "matcher is '$FC_MATCHER'"
fi

test_summary
