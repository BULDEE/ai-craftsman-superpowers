#!/usr/bin/env bash
# =============================================================================
# secrets-scan.sh reads the repository it is given, not the one it runs from.
#
# `git -C <target> ls-files` names files relative to the target, and those
# names went to grep, which opened them relative to the caller's working
# directory. From anywhere but the target root the scanner read other files or
# none: a caller holding the same file names turned a key in the target into a
# SUCCESS, and a caller holding none refused a clean target (review of
# eb54d13, D1; CR-177). The verdict is a property of the target, so every case
# below scans one target from several directories and expects one answer.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCANNER="$ROOT_DIR/.github/scripts/secrets-scan.sh"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-secrets-scan.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Built at run time, so this file carries no key-shaped literal of its own.
FAKE_KEY="sk-$(printf 'A%.0s' {1..40})"
KEY_FINDING="OpenAI API keys (entry.txt)"

# Two tracked files: grep names the file it matched only when it is handed
# more than one, as it always is in a real repository.
make_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    printf 'harmless content\n' > "$dir/entry.txt"
    printf 'fixture\n' > "$dir/README.md"
    git -C "$dir" add entry.txt README.md
    git -C "$dir" commit -qm init
}

# scan_from <cwd> <target>: prints the exit code, keeps the output in scan.out.
scan_from() {
    local scan_exit=0
    (cd "$1" && bash "$SCANNER" "$2" > "$WORK/scan.out" 2>&1) || scan_exit=$?
    printf '%s' "$scan_exit"
}

make_repo "$WORK/target"
make_repo "$WORK/caller"
mkdir -p "$WORK/elsewhere"

echo ""
echo "=== A clean target is clean from every working directory ==="

for cwd in target caller elsewhere; do
    scan_exit=$(scan_from "$WORK/$cwd" "$WORK/target")
    if [[ "$scan_exit" == "0" ]] && grep -q "SUCCESS" "$WORK/scan.out"; then
        log_pass "clean target scanned from $cwd: exit 0"
    else
        log_fail "clean target scanned from $cwd" "exit $scan_exit: $(grep -m1 -E 'Error|FAILED' "$WORK/scan.out")"
    fi
done

echo ""
echo "=== A key in the target is found from every working directory ==="

printf 'key=%s\n' "$FAKE_KEY" > "$WORK/target/entry.txt"

scan_exit=$(scan_from "$WORK/target" "$WORK/target")
if [[ "$scan_exit" == "1" ]] && grep -qF "$KEY_FINDING" "$WORK/scan.out"; then
    log_pass "control: scanned from the target itself, the key is reported (exit 1)"
else
    log_fail "control: key scanned from the target" "exit $scan_exit"
fi

for cwd in caller elsewhere; do
    scan_exit=$(scan_from "$WORK/$cwd" "$WORK/target")
    if [[ "$scan_exit" == "1" ]] && grep -qF "$KEY_FINDING" "$WORK/scan.out"; then
        log_pass "scanned from $cwd, outside the target, the key is reported (exit 1)"
    else
        log_fail "key in a target scanned from $cwd" "exit $scan_exit, key finding absent: $(grep -m1 -E 'SUCCESS|Error' "$WORK/scan.out")"
    fi
done

scan_exit=$(scan_from "$WORK/caller" "../target")
if [[ "$scan_exit" == "1" ]] && grep -qF "$KEY_FINDING" "$WORK/scan.out"; then
    log_pass "a relative target is resolved against the caller, then read in place (exit 1)"
else
    log_fail "relative target ../target from caller" "exit $scan_exit"
fi

test_summary
