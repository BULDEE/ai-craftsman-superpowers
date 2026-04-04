#!/usr/bin/env bash
# =============================================================================
# Circuit Breaker + Channel Cache Tests
# Tests circuit-breaker.sh and channel-cache.sh with TDD.
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../lib/test-helpers.sh"

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        log_pass "$label"
    else
        log_fail "$label" "expected '$expected', got '$actual'"
    fi
}

assert_empty() {
    local label="$1" actual="$2"
    if [[ -z "$actual" ]]; then
        log_pass "$label"
    else
        log_fail "$label" "expected empty, got '$actual'"
    fi
}

assert_not_empty() {
    local label="$1" actual="$2"
    if [[ -n "$actual" ]]; then
        log_pass "$label"
    else
        log_fail "$label" "expected non-empty, got empty"
    fi
}

# Isolated temp dir for test data
export CLAUDE_PLUGIN_DATA="/tmp/craftsman-cb-tests-$$"
mkdir -p "$CLAUDE_PLUGIN_DATA"

source "$ROOT_DIR/hooks/lib/circuit-breaker.sh"
source "$ROOT_DIR/hooks/lib/channel-cache.sh"

# =============================================================================
# CIRCUIT BREAKER TESTS
# =============================================================================

# =============================================================================
# 1. Initial state is closed
# =============================================================================
echo ""
echo "=== 1. Circuit Breaker Initial State ==="

cb_init "sentry" 3 300

result=$(cb_state "sentry")
assert_eq "Initial state is closed" "closed" "$result"

result=$(cb_failures "sentry")
assert_eq "Initial failures is 0" "0" "$result"

# =============================================================================
# 2. Failure tracking stays closed below threshold
# =============================================================================
echo ""
echo "=== 2. Failure Tracking Below Threshold ==="

cb_record_failure "sentry"
result=$(cb_state "sentry")
assert_eq "Still closed after 1 failure" "closed" "$result"

result=$(cb_failures "sentry")
assert_eq "Failure count is 1" "1" "$result"

cb_record_failure "sentry"
result=$(cb_state "sentry")
assert_eq "Still closed after 2 failures" "closed" "$result"

result=$(cb_failures "sentry")
assert_eq "Failure count is 2" "2" "$result"

# =============================================================================
# 3. Opens after reaching threshold
# =============================================================================
echo ""
echo "=== 3. Opens After Threshold ==="

cb_record_failure "sentry"
result=$(cb_state "sentry")
assert_eq "Opens after 3 failures (threshold)" "open" "$result"

result=$(cb_failures "sentry")
assert_eq "Failure count is 3" "3" "$result"

# =============================================================================
# 4. Success resets failure counter
# =============================================================================
echo ""
echo "=== 4. Success Resets Failures ==="

cb_reset "sentry"
cb_record_failure "sentry"
cb_record_failure "sentry"

result=$(cb_failures "sentry")
assert_eq "2 failures after reset + 2 failures" "2" "$result"

cb_record_success "sentry"
result=$(cb_state "sentry")
assert_eq "Closed after success" "closed" "$result"

result=$(cb_failures "sentry")
assert_eq "Failures reset to 0 after success" "0" "$result"

# =============================================================================
# 5. Half-open transition after cooldown
# =============================================================================
echo ""
echo "=== 5. Half-Open After Cooldown ==="

cb_init "fast-channel" 2 1
cb_record_failure "fast-channel"
cb_record_failure "fast-channel"

result=$(cb_state "fast-channel")
assert_eq "Circuit opens at threshold" "open" "$result"

sleep 2

result=$(cb_state "fast-channel")
assert_eq "Circuit half-open after cooldown expires" "half-open" "$result"

# =============================================================================
# 6. Half-open + success -> closed
# =============================================================================
echo ""
echo "=== 6. Half-Open + Success -> Closed ==="

cb_record_success "fast-channel"
result=$(cb_state "fast-channel")
assert_eq "Half-open + success -> closed" "closed" "$result"

result=$(cb_failures "fast-channel")
assert_eq "Failures reset after half-open success" "0" "$result"

# =============================================================================
# 7. Half-open + failure -> back to open
# =============================================================================
echo ""
echo "=== 7. Half-Open + Failure -> Open ==="

cb_init "retry-channel" 1 1
cb_record_failure "retry-channel"

result=$(cb_state "retry-channel")
assert_eq "Opens after 1 failure (threshold=1)" "open" "$result"

sleep 2

result=$(cb_state "retry-channel")
assert_eq "Half-open after cooldown" "half-open" "$result"

cb_record_failure "retry-channel"
result=$(cb_state "retry-channel")
assert_eq "Half-open + failure -> back to open" "open" "$result"

# =============================================================================
# 8. Force reset
# =============================================================================
echo ""
echo "=== 8. Force Reset ==="

cb_init "reset-channel" 2 300
cb_record_failure "reset-channel"
cb_record_failure "reset-channel"

result=$(cb_state "reset-channel")
assert_eq "Circuit is open before reset" "open" "$result"

cb_reset "reset-channel"
result=$(cb_state "reset-channel")
assert_eq "Force reset -> closed" "closed" "$result"

result=$(cb_failures "reset-channel")
assert_eq "Force reset -> 0 failures" "0" "$result"

# =============================================================================
# 9. Status summary is human-readable
# =============================================================================
echo ""
echo "=== 9. Status Summary ==="

cb_init "summary-channel" 3 300
summary=$(cb_status_summary "summary-channel")
assert_not_empty "Status summary is not empty" "$summary"

if echo "$summary" | grep -q "closed"; then
    log_pass "Status summary mentions state"
else
    log_fail "Status summary should mention state" "got '$summary'"
fi

# =============================================================================
# CHANNEL CACHE TESTS
# =============================================================================

# =============================================================================
# 10. Cache set + get
# =============================================================================
echo ""
echo "=== 10. Cache Set + Get ==="

cache_set "sentry" "issues:open" "42 issues found" 60

result=$(cache_get "sentry" "issues:open")
assert_eq "Cache hit returns stored value" "42 issues found" "$result"

# =============================================================================
# 11. Cache miss returns empty
# =============================================================================
echo ""
echo "=== 11. Cache Miss ==="

result=$(cache_get "sentry" "nonexistent:key")
assert_empty "Cache miss returns empty" "$result"

# =============================================================================
# 12. TTL expiry
# =============================================================================
echo ""
echo "=== 12. TTL Expiry ==="

cache_set "sentry" "temp:data" "short-lived" 1

result=$(cache_get "sentry" "temp:data")
assert_eq "Cache hit before TTL" "short-lived" "$result"

sleep 2

result=$(cache_get "sentry" "temp:data")
assert_empty "Cache miss after TTL expired" "$result"

# Stale read still works
result=$(cache_get_stale "sentry" "temp:data")
assert_eq "Stale read returns expired data" "short-lived" "$result"

# =============================================================================
# 13. LRU eviction
# =============================================================================
echo ""
echo "=== 13. LRU Eviction ==="

cache_set "evict-ch" "key1" "val1" 3600
sleep 1
cache_set "evict-ch" "key2" "val2" 3600
sleep 1
cache_set "evict-ch" "key3" "val3" 3600
sleep 1
cache_set "evict-ch" "key4" "val4" 3600
sleep 1
cache_set "evict-ch" "key5" "val5" 3600

cache_evict "evict-ch" 3

result=$(cache_get "evict-ch" "key1")
assert_empty "LRU: oldest key1 evicted" "$result"

result=$(cache_get "evict-ch" "key2")
assert_empty "LRU: second oldest key2 evicted" "$result"

result=$(cache_get "evict-ch" "key3")
assert_eq "LRU: key3 still present" "val3" "$result"

result=$(cache_get "evict-ch" "key4")
assert_eq "LRU: key4 still present" "val4" "$result"

result=$(cache_get "evict-ch" "key5")
assert_eq "LRU: key5 still present" "val5" "$result"

# =============================================================================
# Cleanup
# =============================================================================
rm -rf "$CLAUDE_PLUGIN_DATA"

test_summary
