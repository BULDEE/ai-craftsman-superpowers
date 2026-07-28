#!/usr/bin/env bash
# =============================================================================
# Run Claude Code headless with the craftsman plugin loaded.
#
# Hermes ships a skill that delegates coding to the Claude Code CLI
# (skills/autonomous-ai-agents/claude-code/SKILL.md) but the binary is absent
# from the image. Installing it is the cheapest way to get the full plugin into
# an autonomous loop: the hooks that already exist run unchanged, so there is
# no second implementation of the gate to keep in sync.
#
# Two documented behaviours decide everything here (docs/en/headless,
# docs/en/authentication):
#
#   --bare skips auto-discovery of hooks, skills, plugins, MCP servers and
#   CLAUDE.md, AND does not read CLAUDE_CODE_OAUTH_TOKEN.
#
# So bare mode loads none of this plugin, and the docs say it "will become the
# default for -p in a future release". This wrapper exists to make the non-bare
# invocation explicit and to keep it that way.
#
# Credential precedence is the other trap. ANTHROPIC_API_KEY outranks
# CLAUDE_CODE_OAUTH_TOKEN, and the Hermes image already carries one, so the
# credential the caller supplied would silently not be the one in use. The key
# is dropped from this process when an OAuth token is present.
#
# Usage:
#   CLAUDE_CODE_OAUTH_TOKEN=... claude-craftsman.sh "fix the failing test"
# =============================================================================
set -uo pipefail

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

command -v claude >/dev/null 2>&1 || {
    echo "claude-craftsman: the Claude Code CLI is not installed" >&2
    exit 127
}

# The OAuth token wins only if no API key is in the environment to outrank it.
# Dropping the key here rather than in the image keeps it available to
# everything else in the container that legitimately uses it.
if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        echo "claude-craftsman: ANTHROPIC_API_KEY outranks CLAUDE_CODE_OAUTH_TOKEN, dropping it for this call" >&2
        unset ANTHROPIC_API_KEY
    fi
    unset ANTHROPIC_AUTH_TOKEN 2>/dev/null || true
elif [[ -z "${ANTHROPIC_API_KEY:-}" && -z "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
    echo "claude-craftsman: no credential found, set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY" >&2
    exit 78
fi

# Refuse --bare rather than silently producing an ungated run. A caller that
# passes it is asking for the opposite of what this wrapper is for, and the
# failure would otherwise be invisible: no hooks, no plugin, and a credential
# resolved from somewhere other than the one supplied.
for arg in "$@"; do
    [[ "$arg" == "--bare" ]] || continue
    echo "claude-craftsman: --bare disables the plugin and ignores CLAUDE_CODE_OAUTH_TOKEN, refusing" >&2
    exit 64
done

exec claude -p \
    --plugin-dir "$PLUGIN_ROOT" \
    --permission-mode "${CRAFTSMAN_PERMISSION_MODE:-acceptEdits}" \
    "$@"
