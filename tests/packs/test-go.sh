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
WARNINGS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2"$'\n'; }
add_warning() { WARNINGS="${WARNINGS}$1:$2"$'\n'; }
all_findings() { printf '%s%s' "$VIOLATIONS" "$WARNINGS"; }
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
    WARNINGS=""
    pack_validate_go "$file"
    pack_validate_go_layers "$file"
    if all_findings | grep -q "^${rule}:"; then
        if [[ "$expectation" == "raises" ]]; then
            log_pass "$rule: $description"
        else
            log_fail "$rule: $description" "raised on a clean fixture: $(all_findings | grep "^${rule}:" | head -1)"
        fi
    else
        if [[ "$expectation" == "clean" ]]; then
            log_pass "$rule: $description"
        else
            log_fail "$rule: $description" "not detected (got: $(all_findings | tr '\n' ' '))"
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

# GOD001 measures the span of a declaration. A Go god object is a type with
# forty methods across a file and a five-line struct, so claiming the rule
# would guard a signal that never fires.
if grep -q 'GOD001' "$ROOT_DIR/packs/go/pack.yml"; then
    if grep -qE '^\s*builtin:.*GOD001|^\s*"GOD001"' "$ROOT_DIR/packs/go/pack.yml"; then
        log_fail "pack.yml does not claim GOD001" "claimed but never emitted on Go"
    else
        log_pass "pack.yml does not claim GOD001"
    fi
else
    log_pass "pack.yml does not claim GOD001"
fi

# A language pack filtered by the project's stack is silently off on every
# polyglot repository, and dispatch is by extension anyway.
if grep -qE '^\s*stack: \["\*"\]' "$ROOT_DIR/packs/go/pack.yml"; then
    log_pass "pack.yml loads on every stack"
else
    log_fail "pack.yml loads on every stack" "a Go file in a non-Go stack would be unvalidated"
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

# --- Cases the review found, kept as regressions -------------------------------

run_go NEST001 raises "the Go error idiom counts as nesting" <<'GO'
package order

// Run checks everything.
func Run() error {
	if err := checkOne(); err != nil {
		if err := checkTwo(); err != nil {
			if err := checkThree(); err != nil {
				return err
			}
		}
	}
	return nil
}
GO

run_go PARAM001 raises "a generic function is not invisible" <<'GO'
package order

// Build assembles anything.
func Build[T any](customer string, items []T, currency string, coupon string) T {
	var zero T
	return zero
}
GO

run_go GO002 raises "a generic function still checks its context position" <<'GO'
package order

// Save stores anything.
func Save[T any](item T, ctx context.Context) error {
	return nil
}
GO

run_go GO001 clean "a generic Must constructor keeps its exemption" <<'GO'
package order

// MustParse panics at start-up only.
func MustParse[T any](raw string) T {
	panic("bad")
}
GO

run_go GO001 clean "a closure does not end the enclosing Must exemption" <<'GO'
package order

// MustBuild panics at start-up only.
func MustBuild(ok bool) string {
	if !ok {
		panic("bad config")
	}
	go func() { close(done) }()
	if !ok {
		panic("still bad config")
	}
	return ""
}
GO

run_go GO004 clean "a type assertion discards a bool, not an error" <<'GO'
package order

// Describe names the value.
func Describe(v interface{}) string {
	s, _ := v.(string)
	return s
}
GO

run_go GO004 clean "a channel receive discards a bool, not an error" <<'GO'
package order

// Drain reads one value.
func Drain(ch chan int) int {
	v, _ := <-ch
	return v
}
GO

run_go GO004 clean "a map index discards a bool, not an error" <<'GO'
package order

// Lookup reads the map.
func Lookup(m map[string]int, k string) int {
	n, _ := m[k]
	return n
}
GO

run_go GO004 clean "range discards an element, not an error" <<'GO'
package order

// Count walks the slice.
func Count(xs []int) int {
	total := 0
	for i, _ := range xs {
		total += i
	}
	return total
}
GO

run_go GO006 raises "an error thrown away outright is reported" <<'GO'
package order

// Dump writes the payload.
func Dump(f *os.File, payload []byte) {
	f.Write(payload)
}
GO

run_go GO006 raises "a deferred Close discards its error" <<'GO'
package order

// Read opens and reads.
func Read(f *os.File) {
	defer f.Close()
}
GO

run_go GO006 clean "an assigned and handled result passes" <<'GO'
package order

// Dump writes the payload.
func Dump(f *os.File, payload []byte) error {
	if _, err := f.Write(payload); err != nil {
		return err
	}
	return nil
}
GO

run_go GO003 raises "a grouped exported constant needs a doc comment" <<'GO'
package order

const (
	StatusOpen = "open"
)
GO

run_go GO003 raises "a doc comment that does not name the symbol is not a doc comment" <<'GO'
package order

// This does something.
func Save(order *Order) error {
	return nil
}
GO

run_go GO003 clean "a documented grouped sentinel passes" <<'GO'
package order

var (
	// ErrNotFound is returned when the order is absent.
	ErrNotFound = errors.New("not found")
)
GO

run_go LOC001 raises "a function body past fifty lines is reported" <<'GO'
package order

// Long does far too much.
func Long() int {
	total := 0
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	total++
	return total
}
GO

run_go LOC001 clean "a short function passes" <<'GO'
package order

// Short does one thing.
func Short() int {
	return 1
}
GO

# A raw string literal is Go's here-doc: its content is not code, and the
# scanner must not read the braces or the comment markers inside it.
run_go NEST001 clean "a raw string containing code is not code" <<'GO'
package order

// Template returns the snippet.
func Template() string {
	return `if a { if b { if c { // not real
	} } }`
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

# --- The Level 2 claim compiles ------------------------------------------------
#
# `lang_registry.py` refuses a supersedes entry whose tool shares its name with
# the pack's own adapter, and it refuses it at compile time with a message on
# stderr rather than by failing. An entry that is silently dropped leaves the
# Level 1 rule emitting alongside the Level 2 verdict, which is the duplication
# the mechanism exists to remove: the first version of this pack named the
# adapter errcheck.sh and claimed `bin/errcheck`, and the claim never survived.
registry_out="$(cd "$ROOT_DIR" && python3 hooks/lib/lang_registry.py packs/go/pack.yml 2>&1)"
if echo "$registry_out" | grep -q "cannot supersede"; then
    log_fail "the errcheck claim compiles" "$(echo "$registry_out" | grep 'cannot supersede' | head -1)"
elif echo "$registry_out" | grep -q "supersedes.*errcheck=GO004,GO006"; then
    log_pass "the errcheck claim compiles"
else
    log_fail "the errcheck claim compiles" "no supersedes row: $(echo "$registry_out" | tr '\n' ' ')"
fi

# --- The gate that decides whether the validator runs at all ------------------
#
# Every assertion above sources the validator directly, so `_pack_stack_compatible`
# is never in the path: the pack could be gated off entirely and this file would
# stay green. That is exactly how the stack filter shipped unnoticed, with the
# same Go file producing five findings under `stack: go` and none under
# `stack: symfony`. This case drives the real CLI instead.

E2E="$WORK/e2e"
mkdir -p "$E2E/internal/domain/order"
cat > "$E2E/.craft-config.yml" <<'YML'
stack: symfony
strictness: strict
YML
cat > "$E2E/internal/domain/order/order.go" <<'GO'
package order

import (
	"github.com/acme/shop/internal/infrastructure"
)

func Load(id string) *Order {
	panic("empty id")
}
GO

if command -v git >/dev/null 2>&1; then
    ( cd "$E2E" && git init -q && git add -A ) >/dev/null 2>&1
fi
e2e_out="$(cd "$E2E" && CLAUDE_PLUGIN_ROOT="$ROOT_DIR" bash "$ROOT_DIR/ci/craftsman-ci.sh" internal 2>&1)"

if echo "$e2e_out" | grep -q "GO001"; then
    log_pass "the pack runs on a Go file in a project whose stack is not Go"
else
    log_fail "the pack runs on a Go file in a project whose stack is not Go" \
        "craftsman-ci found no GO001: $(echo "$e2e_out" | tr '\n' ' ')"
fi

if echo "$e2e_out" | grep -q "LAYER001"; then
    log_pass "LAYER001 catches an import ending on the infrastructure segment"
else
    log_fail "LAYER001 catches an import ending on the infrastructure segment" \
        "$(echo "$e2e_out" | tr '\n' ' ')"
fi

# --- The canonical example must survive its own pack -------------------------
#
# The Iron Law loads this file before scaffolding. A canonical example that its
# own validators reject teaches the opposite of what it is there for.
VIOLATIONS=""
WARNINGS=""
pack_validate_go "$ROOT_DIR/packs/go/knowledge/canonical/go-handler.go"
pack_validate_go_layers "$ROOT_DIR/packs/go/knowledge/canonical/go-handler.go"
if [[ -z "$(all_findings | grep -v '^$')" ]]; then
    log_pass "the canonical example raises nothing"
else
    log_fail "the canonical example raises nothing" "$(all_findings | tr '\n' ' ')"
fi

test_summary
