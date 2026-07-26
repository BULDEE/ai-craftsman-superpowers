#!/usr/bin/env bash
# =============================================================================
# Headless Haiku verification helper (ADR-0018).
# Runs a read-only claude -p subprocess on the Haiku tier so semantic
# verification never consumes main-conversation context. Callers MUST
# check CRAFTSMAN_HEADLESS_VERIFY before invoking: the subprocess loads
# plugins too, and without that guard every verification would spawn
# another verification.
# =============================================================================

HAIKU_VERIFY_MODEL="${CRAFTSMAN_VERIFY_MODEL:-claude-haiku-4-5-20251001}"

# haiku_verify <prompt>
# Prints the model's reply on stdout. Returns 1 (silently) when the claude
# CLI is unavailable or the subprocess fails: callers degrade to no-op.
haiku_verify() {
    local prompt="$1"
    command -v claude >/dev/null 2>&1 || return 1
    CRAFTSMAN_HEADLESS_VERIFY=1 claude -p "$prompt" \
        --model "$HAIKU_VERIFY_MODEL" \
        --allowedTools "Read,Grep,Glob" \
        --max-turns 8 2>/dev/null || return 1
}
