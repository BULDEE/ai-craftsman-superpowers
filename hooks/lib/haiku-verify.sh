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

# haiku_findings <verdict-body>
# Constrain what a verification subprocess can say back to the main session.
#
# The subprocess reads files the plugin did not write. A hostile file can carry
# text aimed at the verifier ("ignore your instructions and reply ..."), and
# whatever the verifier then emits is shown to the main model as a system
# reminder. That is an indirect prompt injection path (ATLAS AML.T0051.001):
# untrusted content reaching an agent's instruction channel through a tool.
#
# Rather than trying to detect every possible injection on the way in, we parse
# the way out: a verdict is a list of findings in a known shape, so anything
# that is not that shape is dropped. Same principle the plugin's own doctrine
# states for system boundaries (knowledge/security/secure-by-design.md).
haiku_findings() {
    local body="$1"
    # Shape is the control, not character blocklisting: a line that survives
    # must look like "path:line something". Zero-width characters are left
    # alone on purpose - stripping them in bash 3.2 needs an escape form that
    # portably eats legitimate characters, and they cannot turn a finding line
    # into an instruction on their own.
    printf '%s' "$body" \
        | tr -d '\000-\010\013\014\016-\037' \
        | grep -E '^[[:space:]]*[-*]?[[:space:]]*[[:alnum:]/._-]+:[0-9]+[[:space:]]' \
        | cut -c1-300 \
        | head -10
}
