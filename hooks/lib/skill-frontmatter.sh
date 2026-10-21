#!/usr/bin/env bash
# =============================================================================
# Which skills are locked to the user, read from their frontmatter in one pass.
#
# A skill with `disable-model-invocation: true` starts only when the user types
# `/craftsman:<name>` first in a prompt; the Skill tool refuses it. The
# healthcheck counts those skills and the routing table sorts on them. Both
# read the frontmatter with an awk and a grep per skill: some sixty processes
# per SessionStart for one question about two dozen files.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/hooks/lib/skill-frontmatter.sh"
#   skill_locked_files <file>...   prints each file that is locked, once
#
# Every argument must be an existing file: BSD awk stops at the first file it
# cannot open, which would hide the lock of every file after it.
# =============================================================================

skill_locked_files() {
    [[ $# -gt 0 ]] || return 0
    awk 'FNR == 1 { inside = ($0 == "---"); next }
         inside && $0 == "---" { inside = 0 }
         inside { print FILENAME "\t" $0 }' "$@" 2>/dev/null \
        | grep -E $'^[^\t]*\tdisable-model-invocation:[[:space:]]*true' \
        | cut -f1 | uniq
}
