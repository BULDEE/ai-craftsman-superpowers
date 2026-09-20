#!/usr/bin/env bash
# =============================================================================
# Host payload fixtures: what a real consumer sends to a hook.
#
# tests/fixtures/hosts/<host>/<version>/<event>.<tool>[.<case>].json, captured
# from the real CLI (PROVENANCE.md there). Paths inside are `__WORKSPACE__`;
# a suite binds that to its own temp workspace so the payload names files it
# can create. Any other rewrite is the suite's own business and goes through
# python, never sed on JSON.
#
#   host_fixture codex 0.154.0 pre-tool-use.apply_patch.multifile-move "$WORK"
#     prints the payload with __WORKSPACE__ bound to $WORK
#   host_fixture_with <same args> '<python expression over d>'
#     same, then applies a python statement to the dict `d` before printing
# =============================================================================

_HOST_FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures/hosts" && pwd)"

host_fixture_path() {
    printf '%s/%s/%s/%s.json' "$_HOST_FIXTURES_DIR" "$1" "$2" "$3"
}

host_fixture() {
    host_fixture_with "$1" "$2" "$3" "$4" "pass"
}

host_fixture_with() {
    local path
    path=$(host_fixture_path "$1" "$2" "$3")
    [[ -f "$path" ]] || { echo "no such host fixture: $path" >&2; return 1; }
    python3 - "$path" "$4" "$5" <<'PY'
import json, sys
path, workspace, statement = sys.argv[1:4]
raw = open(path, encoding="utf-8").read().replace("__WORKSPACE__", workspace)
d = json.loads(raw)
exec(statement)
print(json.dumps(d))
PY
}

host_fixture_versions() {
    ls "$_HOST_FIXTURES_DIR/$1" 2>/dev/null
}
