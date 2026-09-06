#!/usr/bin/env bash
# =============================================================================
# Go pack: one file that must be refused and one that must pass, per rule.
#
# A validator is only worth its false-negative rate, so every rule here is
# asserted in both directions. The clean fixture for a rule is not a blank file
# either: it is the shape a reviewer would wave through, which is what makes a
# green result mean the rule discriminates rather than that it never fires.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Go Pack Tests ==="

source "$ROOT_DIR/packs/go/hooks/go-validator.sh"
source "$ROOT_DIR/packs/go/hooks/layer-validator.sh"

VIOLATIONS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2"$'\n'; }
add_warning() { VIOLATIONS="${VIOLATIONS}$1:$2"$'\n'; }
line_has_ignore() { case "$1" in *"craftsman-ignore: $2"*) return 0 ;; *) return 1 ;; esac; }
metrics_record_violation() { true; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-go-pack.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# run_go <rule> <expectation: raises|clean> <description> <<'GO' ... GO
# The fixture is read from stdin so each case reads as the Go file it is.
run_go() {
    local rule="$1" expectation="$2" description="$3" name="${4:-sample.go}"
    local file="$WORK/$name"
    cat > "$file"
    VIOLATIONS=""
    pack_validate_go "$file"
    pack_validate_go_layers "$file"
    if echo "$VIOLATIONS" | grep -q "^${rule}:"; then
        if [[ "$expectation" == "raises" ]]; then
            log_pass "$rule: $description"
        else
            log_fail "$rule: $description" "raised on a clean fixture: $(echo "$VIOLATIONS" | grep "^${rule}:" | head -1)"
        fi
    else
        if [[ "$expectation" == "clean" ]]; then
            log_pass "$rule: $description"
        else
            log_fail "$rule: $description" "not detected (got: ${VIOLATIONS//$'\n'/ })"
        fi
    fi
    rm -f "$file"
}

# --- pack manifest -----------------------------------------------------------

if [[ -f "$ROOT_DIR/packs/go/pack.yml" ]]; then
    log_pass "pack.yml exists"
else
    log_fail "pack.yml exists" "not found"
fi

# The pack must not claim a metrics dialect: the shared extractor keys on
# `function` and on parenthesised control heads, so `c-like` on Go measures
# nothing while looking like coverage.
if grep -qE '^\s*metrics_dialect:' "$ROOT_DIR/packs/go/pack.yml"; then
    log_fail "pack.yml declares no metrics_dialect" "the shared extractor cannot read Go"
else
    log_pass "pack.yml declares no metrics_dialect"
fi

# --- GO001: panic outside main and outside Must* -----------------------------

run_go GO001 raises "panic in library code is refused" <<'GO'
package order

func Load(id string) *Order {
	if id == "" {
		panic("empty id")
	}
	return nil
}
GO

run_go GO001 clean "panic in package main is allowed" <<'GO'
package main

func main() {
	if err := run(); err != nil {
		panic(err)
	}
}
GO

run_go GO001 clean "panic in a Must constructor is allowed" <<'GO'
package order

// MustLoad panics when the order cannot be built, for use at start-up.
func MustLoad(id string) *Order {
	order, err := Load(id)
	if err != nil {
		panic(err)
	}
	return order
}
GO

run_go GO001 clean "panic in a test file is allowed" "sample_test.go" <<'GO'
package order

func TestSomething(t *testing.T) {
	panic("boom")
}
GO

run_go GO001 clean "the word panic inside a string is not a panic" <<'GO'
package order

// Describe returns a human message.
func Describe() string {
	return "do not panic(here)"
}
GO

# --- GO002: context.Context first ---------------------------------------------

run_go GO002 raises "context in second position is refused" <<'GO'
package order

// Save writes the order.
func Save(order *Order, ctx context.Context) error {
	return nil
}
GO

run_go GO002 clean "context in first position passes" <<'GO'
package order

// Save writes the order.
func Save(ctx context.Context, order *Order) error {
	return nil
}
GO

run_go GO002 clean "a method with a receiver still counts from its own first parameter" <<'GO'
package order

// Save writes the order.
func (r *Repository) Save(ctx context.Context, order *Order) error {
	return nil
}
GO

# --- GO003: doc comment on exported symbols ----------------------------------

run_go GO003 raises "exported function without a doc comment is reported" <<'GO'
package order

func Save(order *Order) error {
	return nil
}
GO

run_go GO003 clean "a documented exported function passes" <<'GO'
package order

// Save writes the order to storage.
func Save(order *Order) error {
	return nil
}
GO

run_go GO003 clean "an unexported function needs no doc comment" <<'GO'
package order

func save(order *Order) error {
	return nil
}
GO

run_go GO003 clean "a test file needs no doc comments" "sample_test.go" <<'GO'
package order

func TestSave(t *testing.T) {
}
GO

# --- GO004: error dropped into the blank identifier --------------------------

run_go GO004 raises "an error discarded into _ is reported" <<'GO'
package order

// Save writes the order.
func Save() {
	value, _ := strconv.Atoi("12")
	_ = value
}
GO

run_go GO004 clean "a handled error passes" <<'GO'
package order

// Save writes the order.
func Save() error {
	value, err := strconv.Atoi("12")
	if err != nil {
		return err
	}
	_ = value
	return nil
}
GO

run_go GO004 clean "a craftsman-ignore on the line silences it" <<'GO'
package order

// Save writes the order.
func Save() {
	value, _ := strconv.Atoi("12") // craftsman-ignore: GO004 - literal, cannot fail
	_ = value
}
GO

# --- GO005: init() -------------------------------------------------------------

run_go GO005 raises "init() is reported" <<'GO'
package order

func init() {
	registerDefaults()
}
GO

run_go GO005 clean "an explicit constructor passes" <<'GO'
package order

// NewRegistry builds the registry with its defaults.
func NewRegistry() *Registry {
	return &Registry{}
}
GO

# --- WARN-GO001: naked return with named results ------------------------------

run_go WARN-GO001 raises "a naked return with named results is reported" <<'GO'
package order

// Total returns the amount and an error.
func Total() (amount int, err error) {
	amount = 12
	return
}
GO

run_go WARN-GO001 clean "an explicit return passes" <<'GO'
package order

// Total returns the amount and an error.
func Total() (amount int, err error) {
	return 12, nil
}
GO

# --- Core structure rules, detected by this pack ------------------------------

run_go NEST001 raises "three nested control blocks are reported" <<'GO'
package order

// Walk traverses the tree.
func Walk(items []Item) {
	for _, item := range items {
		if item.Valid {
			if item.Ready {
				process(item)
			}
		}
	}
}
GO

run_go NEST001 clean "guard clauses pass" <<'GO'
package order

// Walk traverses the tree.
func Walk(items []Item) {
	for _, item := range items {
		if !item.Valid {
			continue
		}
		process(item)
	}
}
GO

run_go PARAM001 raises "four parameters are reported" <<'GO'
package order

// Build assembles an order.
func Build(customer string, items []Item, currency string, coupon string) *Order {
	return nil
}
GO

run_go PARAM001 clean "the return tuple is not counted as parameters" <<'GO'
package order

// Build assembles an order.
func Build(customer string, items []Item) (*Order, error, string, int) {
	return nil, nil, "", 0
}
GO

# --- LAYER001 ------------------------------------------------------------------

VIOLATIONS=""
mkdir -p "$WORK/internal/domain/order"
cat > "$WORK/internal/domain/order/order.go" <<'GO'
package order

import (
	"context"

	"github.com/acme/shop/internal/infrastructure/postgres"
)

// Order is the aggregate root.
type Order struct {
	store postgres.Store
}
GO
pack_validate_go_layers "$WORK/internal/domain/order/order.go"
if echo "$VIOLATIONS" | grep -q "^LAYER001:"; then
    log_pass "LAYER001: domain importing infrastructure is refused"
else
    log_fail "LAYER001: domain importing infrastructure is refused" "not detected"
fi

VIOLATIONS=""
cat > "$WORK/internal/domain/order/order.go" <<'GO'
package order

import (
	"context"
)

// Order is the aggregate root.
// It knows nothing about infrastructure/postgres, and saying so is not importing it.
type Order struct {
	id string
}
GO
pack_validate_go_layers "$WORK/internal/domain/order/order.go"
if echo "$VIOLATIONS" | grep -q "^LAYER001:"; then
    log_fail "LAYER001: a comment naming infrastructure is not an import" "raised on a comment"
else
    log_pass "LAYER001: a comment naming infrastructure is not an import"
fi

# --- The canonical example must survive its own pack -------------------------
#
# The Iron Law loads this file before scaffolding. A canonical example that its
# own validators reject teaches the opposite of what it is there for.
VIOLATIONS=""
pack_validate_go "$ROOT_DIR/packs/go/knowledge/canonical/go-handler.go"
pack_validate_go_layers "$ROOT_DIR/packs/go/knowledge/canonical/go-handler.go"
if [[ -z "$(echo "$VIOLATIONS" | grep -v '^$')" ]]; then
    log_pass "the canonical example raises nothing"
else
    log_fail "the canonical example raises nothing" "${VIOLATIONS//$'\n'/ }"
fi

test_summary
