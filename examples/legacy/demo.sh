#!/usr/bin/env bash
# =============================================================================
# One untested class, from arrival to safety. Replayable, no setup.
#
# Runs the four steps of a legacy rescue against the fixture in
# examples/legacy/fixture/ and prints the real output of each: the
# characterization net, the deliberate break that proves the net catches
# change, the seam, the refactor under the net, and the structural mark the
# ratchet records. Then it touches the class again and shows what the ratchet
# does about it.
#
# Requirements: python3, bash, git. The same three the plugin itself needs;
# nothing to install, no test framework, no network.
#
#   bash examples/legacy/demo.sh
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE="$SCRIPT_DIR/fixture"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-legacy-demo.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Python validates a cached .pyc against (mtime, size). Step 1b changes
# `BULK_THRESHOLD = 10` to `= 11`, which is the same number of bytes, and it
# does it in the same second as the copy that preceded it: both halves of the
# check match, the stale bytecode is reused, and the deliberate break runs the
# OLD code and passes. The demo then teaches the exact opposite of its own
# lesson. Found by running it, not by reading it.
export PYTHONDONTWRITEBYTECODE=1

RATCHET="$ROOT_DIR/hooks/lib/ratchet.py"

step() { printf '\n=== %s ===\n\n' "$1"; }
run() { printf '$ %s\n' "$*"; "$@" 2>&1; }

cd "$WORK"

# -----------------------------------------------------------------------------
step "The class that arrived"

cp "$FIXTURE/step1/pricing.py" .
printf 'It prices a basket, it is 48 lines, it has no tests, and three things\n'
printf 'make it hard to test: it reads the clock itself, it writes to stdout,\n'
printf 'and its rates are module-level constants a caller cannot substitute.\n\n'
run python3 "$RATCHET" measure pricing.py

# -----------------------------------------------------------------------------
step "Step 1: a net, before anything is touched"

cp "$FIXTURE/step1/test_pricing.py" .
printf 'Six assertions, every number read off the running code. Three of them\n'
printf 'record behaviour a reviewer would call wrong, on purpose: a net that\n'
printf 'pins only what you approve of has a hole where you are about to step.\n\n'
run python3 -m unittest test_pricing

# -----------------------------------------------------------------------------
step "Step 1b: a net nobody has seen fail protects nothing"

printf 'The bulk threshold is changed from 10 to 11, which is exactly the kind\n'
printf 'of off-by-one a refactor introduces. The net has to notice.\n\n'
sed -i.bak 's/^BULK_THRESHOLD = 10$/BULK_THRESHOLD = 11/' pricing.py && rm -f pricing.py.bak
run python3 -m unittest test_pricing
printf '\nReverted.\n'
cp "$FIXTURE/step1/pricing.py" pricing.py

# -----------------------------------------------------------------------------
step "Step 2: one seam, and nothing else"

printf 'The clock arrives through the constructor, defaulting to the real one so\n'
printf 'every existing caller keeps working. The twenty-one lines of pricing\n'
printf 'logic are untouched, deliberately: a step that adds a seam AND rearranges\n'
printf 'the code is a step whose failure you cannot attribute.\n\n'
run diff -u "$FIXTURE/step1/pricing.py" "$FIXTURE/step2/pricing.py"

cp "$FIXTURE/step2/pricing.py" pricing.py
cp "$FIXTURE/step2/test_pricing.py" test_pricing.py
printf '\nThe assertions are unchanged. mock.patch is gone, because the test no\n'
printf 'longer has to reach into the module to hold the clock still.\n\n'
run python3 -m unittest test_pricing

# -----------------------------------------------------------------------------
step "Step 3: one refactor, under the net"

printf 'The if/elif chain of discounts becomes a table the method walks. The net\n'
printf 'is copied from step 2 byte for byte and never edited, which is the whole\n'
printf 'exercise: a net you have to edit to make the refactor pass is a net that\n'
printf 'just told you the refactor changed behaviour.\n\n'
run diff -q "$FIXTURE/step2/test_pricing.py" "$FIXTURE/step3/test_pricing.py"

cp "$FIXTURE/step3/pricing.py" pricing.py
cp "$FIXTURE/step3/test_pricing.py" test_pricing.py
run python3 -m unittest test_pricing

# -----------------------------------------------------------------------------
step "Step 4: the mark the ratchet records"

printf 'The same measurement as at the top, on the refactored class.\n\n'
run python3 "$RATCHET" measure pricing.py
printf '\ncomplexity 4 to 1, and the worst function 21 lines to 15. The rescue is\n'
printf 'not a matter of opinion: it is two numbers that moved.\n\n'
# No --baseline flag: the demo already works inside its own throwaway
# directory, so ratchet.py's default lands there. That matters more than it
# looks: the walkthrough quotes these commands, and a quoted command carrying a
# flag the reader does not have produces silence instead of the payoff.
run python3 "$RATCHET" init pricing.py \
    --reason "legacy rescue: clock seam and discount table, under a characterization net"

# -----------------------------------------------------------------------------
step "What happens on the next touch"

printf 'Someone puts the discounts back inline, six months from now, in a hurry.\n'
printf 'The behaviour is identical and the tests stay green.\n\n'
cp "$FIXTURE/step2/pricing.py" pricing.py
run python3 -m unittest test_pricing
printf '\nGreen. The tests cannot see the difference, because there is no\n'
printf 'behavioural difference to see. The ratchet can:\n\n'
run python3 "$RATCHET" check pricing.py
printf '\nExit code above is 1: the file loosened a budget it had already earned.\n'
printf 'That is the mark doing its job. Raising it on purpose stays possible,\n'
printf 'with `ratchet.py init --reason`, where a reviewer sees it in the diff.\n'

printf '\n=== Done ===\n'
