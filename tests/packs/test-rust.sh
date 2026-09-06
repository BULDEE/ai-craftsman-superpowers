#!/usr/bin/env bash
# =============================================================================
# Rust pack: one file that must be refused and one that must pass, per rule.
#
# The clean fixture for a rule is not a blank file: it is the shape a reviewer
# would wave through, which is what makes a green result mean the rule
# discriminates rather than that it never fires.
#
# The Go pack review found six defects that a one-refused-one-accepted suite had
# missed, so the cases those produced are written here from the start: the
# language's own idioms, its generics, its literal forms, and the gate that
# decides whether the validator runs at all.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

echo "=== Rust Pack Tests ==="

source "$ROOT_DIR/packs/rust/hooks/rust-validator.sh"
source "$ROOT_DIR/packs/rust/hooks/layer-validator.sh"

VIOLATIONS=""
WARNINGS=""
add_violation() { VIOLATIONS="${VIOLATIONS}$1:$2"$'\n'; }
add_warning() { WARNINGS="${WARNINGS}$1:$2"$'\n'; }
all_findings() { printf '%s%s' "$VIOLATIONS" "$WARNINGS"; }
line_has_ignore() { case "$1" in *"craftsman-ignore: $2"*) return 0 ;; *) return 1 ;; esac; }
metrics_record_violation() { true; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-rust-pack.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# run_rs <rule> <expectation: raises|clean> <description> [filename] <<'RS' ... RS
run_rs() {
    local rule="$1" expectation="$2" description="$3" name="${4:-sample.rs}"
    local file="$WORK/$name"
    mkdir -p "$(dirname "$file")"
    cat > "$file"
    VIOLATIONS=""
    WARNINGS=""
    pack_validate_rust "$file"
    pack_validate_rust_layers "$file"
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

if [[ -f "$ROOT_DIR/packs/rust/pack.yml" ]]; then
    log_pass "pack.yml exists"
else
    log_fail "pack.yml exists" "not found"
fi

if grep -qE '^\s*metrics_dialect:' "$ROOT_DIR/packs/rust/pack.yml"; then
    log_fail "pack.yml declares no metrics_dialect" "the shared extractor cannot read Rust"
else
    log_pass "pack.yml declares no metrics_dialect"
fi

if grep -qE '^\s*stack: \["\*"\]' "$ROOT_DIR/packs/rust/pack.yml"; then
    log_pass "pack.yml loads on every stack"
else
    log_fail "pack.yml loads on every stack" "a Rust file in a non-Rust stack would be unvalidated"
fi

# lang_registry.py drops a supersedes entry whose tool shares its name with the
# pack's own adapter, with a message on stderr rather than a failure. A dropped
# claim leaves the Level 1 rule emitting alongside the Level 2 verdict, which is
# the duplication the mechanism exists to remove.
registry_out="$(cd "$ROOT_DIR" && python3 hooks/lib/lang_registry.py packs/rust/pack.yml 2>&1)"
if echo "$registry_out" | grep -q "cannot supersede"; then
    log_fail "the clippy claim compiles" "$(echo "$registry_out" | grep 'cannot supersede' | head -1)"
elif echo "$registry_out" | grep -q "supersedes.*clippy=RUST001,RUST005"; then
    log_pass "the clippy claim compiles"
else
    log_fail "the clippy claim compiles" "no supersedes row: $(echo "$registry_out" | tr '\n' ' ')"
fi

# --- RUST001 and RUST005: unwrap refuses, expect reports ---------------------

run_rs RUST001 raises "unwrap in library code is refused" <<'RS'
/// Loads the order.
pub fn load(raw: &str) -> u32 {
    raw.parse::<u32>().unwrap()
}
RS

run_rs RUST001 clean "the question mark operator passes" <<'RS'
/// Loads the order.
pub fn load(raw: &str) -> Result<u32, std::num::ParseIntError> {
    Ok(raw.parse::<u32>()?)
}
RS

run_rs RUST001 clean "unwrap in a test file is allowed" "tests/order.rs" <<'RS'
#[test]
fn parses() {
    assert_eq!("12".parse::<u32>().unwrap(), 12);
}
RS

run_rs RUST001 clean "a craftsman-ignore on the line silences it" <<'RS'
/// Loads the order.
pub fn load(raw: &str) -> u32 {
    raw.parse::<u32>().unwrap() // craftsman-ignore: RUST001 - literal, cannot fail
}
RS

run_rs RUST005 raises "expect in library code is reported" <<'RS'
/// Loads the order.
pub fn load(raw: &str) -> u32 {
    raw.parse::<u32>().expect("the caller validated this")
}
RS

run_rs RUST005 clean "no expect, nothing reported" <<'RS'
/// Loads the order.
pub fn load(raw: &str) -> Result<u32, std::num::ParseIntError> {
    raw.parse::<u32>()
}
RS

# --- RUST002: panicking macros ------------------------------------------------

run_rs RUST002 raises "panic! in library code is refused" <<'RS'
/// Loads the order.
pub fn load(id: &str) -> u32 {
    if id.is_empty() {
        panic!("empty id");
    }
    0
}
RS

run_rs RUST002 raises "todo! is refused too" <<'RS'
/// Loads the order.
pub fn load(id: &str) -> u32 {
    todo!("write this")
}
RS

run_rs RUST002 clean "a panicking macro under #[cfg(test)] is allowed" <<'RS'
/// Loads the order.
pub fn load(id: &str) -> u32 {
    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        panic!("boom");
    }
}
RS

# A string is not code. The scanner blanks literals before reading anything.
run_rs RUST002 clean "the word panic inside a string is not a macro" <<'RS'
/// Describes the failure.
pub fn describe() -> &'static str {
    "do not panic!(here)"
}
RS

run_rs RUST002 clean "a raw string containing code is not code" <<'RS'
/// Returns the snippet.
pub fn template() -> &'static str {
    r#"if a { panic!("x") }"#
}
RS

# A flag that flips to "we are in tests" on the first attribute and never flips
# back stops validating the file from there on. The convention puts
# `#[cfg(test)] mod tests` at the bottom, which is what makes the defect
# invisible: put anything after it and every rule below goes quiet.
run_rs RUST002 raises "production code after a test module is still checked" <<'RS'
/// Loads the order.
pub fn load(id: &str) -> u32 {
    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        panic!("boom");
    }
}

/// Reloads the order.
pub fn reload(id: &str) -> u32 {
    panic!("this is production code")
}
RS

run_rs RUST004 raises "a public item after a test module is still checked" <<'RS'
/// Loads the order.
pub fn load(id: &str) -> u32 {
    0
}

#[cfg(test)]
mod tests {
    #[test]
    fn it_works() {
        assert!(true);
    }
}

pub fn undocumented(id: &str) -> u32 {
    0
}
RS

# --- RUST003: unsafe without a stated invariant -------------------------------

run_rs RUST003 raises "an unsafe block with no SAFETY comment is refused" <<'RS'
/// Reads the raw pointer.
pub fn read(pointer: *const u8) -> u8 {
    unsafe { *pointer }
}
RS

run_rs RUST003 clean "an unsafe block with a SAFETY comment passes" <<'RS'
/// Reads the raw pointer.
pub fn read(pointer: *const u8) -> u8 {
    // SAFETY: the caller guarantees the pointer is non-null and aligned.
    unsafe { *pointer }
}
RS

# --- RUST004: doc comments on public items ------------------------------------

run_rs RUST004 raises "a public function without a doc comment is reported" <<'RS'
pub fn load(id: &str) -> u32 {
    0
}
RS

run_rs RUST004 clean "a documented public function passes" <<'RS'
/// Loads the order.
pub fn load(id: &str) -> u32 {
    0
}
RS

run_rs RUST004 clean "a private function needs no doc comment" <<'RS'
fn load(id: &str) -> u32 {
    0
}
RS

run_rs RUST004 raises "a public struct without a doc comment is reported" <<'RS'
pub struct Order {
    id: String,
}
RS

run_rs RUST004 clean "an attribute between the doc and the item still counts" <<'RS'
/// An order.
#[derive(Debug)]
pub struct Order {
    id: String,
}
RS

# --- WARN-RUST001: an unexplained #[allow] ------------------------------------

run_rs WARN-RUST001 raises "an allow with no justification is reported" <<'RS'
#[allow(dead_code)]
fn unused() {}
RS

run_rs WARN-RUST001 clean "an allow with a comment above it passes" <<'RS'
// The trait requires this method, the default implementation is never called.
#[allow(dead_code)]
fn unused() {}
RS

# --- Structure rules, detected by this pack -----------------------------------

run_rs NEST001 raises "three nested control blocks are reported" <<'RS'
/// Walks the tree.
pub fn walk(items: &[u32]) {
    for item in items {
        if *item > 0 {
            if *item < 10 {
                process(*item);
            }
        }
    }
}
RS

run_rs NEST001 clean "guard clauses pass" <<'RS'
/// Walks the tree.
pub fn walk(items: &[u32]) {
    for item in items {
        if *item == 0 {
            continue;
        }
        process(*item);
    }
}
RS

# `if let Some(x) = f() {` is Rust's most common conditional, and it reads
# nothing like the `if (cond)` the shared scanner looks for: no parentheses
# around the condition, a binding in the middle, a pattern on the left.
run_rs NEST001 raises "if let counts as nesting" <<'RS'
/// Walks the tree.
pub fn walk(a: Option<u32>, b: Option<u32>, c: Option<u32>) {
    if let Some(first) = a {
        if let Some(second) = b {
            if let Some(third) = c {
                process(first + second + third);
            }
        }
    }
}
RS

run_rs PARAM001 raises "four parameters are reported" <<'RS'
/// Builds an order.
pub fn build(customer: String, items: Vec<u32>, currency: String, coupon: String) -> u32 {
    0
}
RS

run_rs PARAM001 clean "self is not a parameter the caller passes" <<'RS'
/// An order.
pub struct Order;

impl Order {
    /// Rebuilds the order.
    pub fn rebuild(&self, customer: String, currency: String, coupon: String) -> u32 {
        0
    }
}
RS

run_rs PARAM001 clean "a where clause is not a parameter list" <<'RS'
/// Maps the items.
pub fn map_items<T>(items: Vec<T>, factor: u32) -> Vec<T>
where
    T: Clone + std::fmt::Debug,
{
    items
}
RS

run_rs PARAM001 raises "a generic function is not invisible" <<'RS'
/// Builds anything.
pub fn build<T: Clone>(customer: String, items: Vec<T>, currency: String, coupon: String) -> u32 {
    0
}
RS

# A lifetime is not an unterminated character literal. Reading `'a` as one
# blanks everything up to the next quote: the braces the scanner counts, the
# newlines it counts lines with, and the doc comment above the next item. The
# assertion is on the reported line NUMBER, because that is what desynchronises
# first and what a user sees: every finding after the first borrow points at
# the wrong line, and a rule that reads the line above starts answering from
# the wrong one. A pass or fail on the rule alone would not show it.
VIOLATIONS=""
WARNINGS=""
cat > "$WORK/lifetime.rs" <<'RS'
/// Holds a borrowed name.
pub struct Holder<'a> {
    name: &'a str,
}

/// Builds an order.
pub fn build(customer: String, items: Vec<u32>, currency: String, coupon: String) -> u32 {
    0
}
RS
pack_validate_rust "$WORK/lifetime.rs"
lifetime_findings="$(all_findings | grep -v '^$')"
if echo "$lifetime_findings" | grep -q "^PARAM001:line 7:"; then
    log_pass "a lifetime leaves the line numbers after it intact"
else
    log_fail "a lifetime leaves the line numbers after it intact" \
        "expected PARAM001 on line 7, got: $(echo "$lifetime_findings" | tr '\n' ' ')"
fi
if [[ "$(echo "$lifetime_findings" | wc -l | tr -d ' ')" == "1" ]]; then
    log_pass "a documented item after a lifetime stays documented"
else
    log_fail "a documented item after a lifetime stays documented" \
        "$(echo "$lifetime_findings" | tr '\n' ' ')"
fi
rm -f "$WORK/lifetime.rs"

run_rs GOD001 clean "a short impl block passes" <<'RS'
/// An order.
pub struct Order;

impl Order {
    /// Returns the identifier.
    pub fn id(&self) -> u32 {
        0
    }
}
RS

# A Rust type spreads its methods over several impl blocks: the inherent one,
# then one per trait. Measuring a single block is the defect packs/go
# documented when it refused GOD001 outright, so the spans are summed per type.
VIOLATIONS=""
WARNINGS=""
{
    echo "/// A god object."
    echo "pub struct God;"
    for block in 1 2 3; do
        echo "impl God {"
        for _ in $(seq 1 30); do
            echo "    /// Does a thing."
            echo "    pub fn thing_${block}_$RANDOM(&self) -> u32 {"
            echo "        0"
            echo "    }"
        done
        echo "}"
    done
} > "$WORK/god.rs"
pack_validate_rust "$WORK/god.rs"
if all_findings | grep -q "^GOD001:"; then
    log_pass "GOD001: the impl blocks of one type are summed, not judged apart"
else
    log_fail "GOD001: the impl blocks of one type are summed, not judged apart" \
        "three impl blocks of 120 lines each raised nothing"
fi
rm -f "$WORK/god.rs"

# --- LAYER001 ------------------------------------------------------------------

VIOLATIONS=""
mkdir -p "$WORK/src/domain/order"
cat > "$WORK/src/domain/order/mod.rs" <<'RS'
use crate::infrastructure::postgres::Store;

/// The aggregate root.
pub struct Order {
    store: Store,
}
RS
pack_validate_rust_layers "$WORK/src/domain/order/mod.rs"
if echo "$VIOLATIONS" | grep -q "^LAYER001:"; then
    log_pass "LAYER001: domain importing infrastructure is refused"
else
    log_fail "LAYER001: domain importing infrastructure is refused" "not detected"
fi

VIOLATIONS=""
cat > "$WORK/src/domain/order/mod.rs" <<'RS'
use std::fmt;

/// The aggregate root.
/// It knows nothing about infrastructure, and saying so is not importing it.
pub struct Order {
    id: String,
}
RS
pack_validate_rust_layers "$WORK/src/domain/order/mod.rs"
if echo "$VIOLATIONS" | grep -q "^LAYER001:"; then
    log_fail "LAYER001: a comment naming infrastructure is not an import" "raised on a comment"
else
    log_pass "LAYER001: a comment naming infrastructure is not an import"
fi

# --- Cases the adversarial review found, kept as regressions -------------------

# The pipeline scans relative paths. A fixture written at an absolute path
# passed while `craftsman-ci.sh tests/integration.rs` refused every unwrap in
# it: a fixture whose shape is not the consumer's proves nothing.
#
# The unwrap sits in a helper rather than in the #[test] itself, on purpose. An
# unwrap inside a #[test] block is exempt by the attribute alone, so a fixture
# shaped that way would pass whatever the path handling does, and prove
# nothing about the path handling.
VIOLATIONS=""
WARNINGS=""
mkdir -p "$WORK/relative/tests"
cat > "$WORK/relative/tests/integration.rs" <<'RS'
fn fixture() -> u32 {
    "12".parse::<u32>().unwrap()
}

#[test]
fn parses() {
    assert_eq!(fixture(), 12);
}
RS
( cd "$WORK/relative" && python3 "$ROOT_DIR/packs/rust/hooks/rust_structure.py" tests/integration.rs ) > "$WORK/relative.out" 2>&1
if [[ -s "$WORK/relative.out" ]]; then
    log_fail "a relative tests/ path is exempt too" "$(tr '\n' ' ' < "$WORK/relative.out")"
else
    log_pass "a relative tests/ path is exempt too"
fi

run_rs RUST001 clean "unwrap inside an inline #[cfg(test)] module is allowed" <<'RS'
/// Adds the numbers.
pub fn add(left: u32, right: u32) -> u32 {
    left + right
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_adds() {
        let parsed: u32 = "12".parse().unwrap();
        assert_eq!(add(parsed, 0), 12);
    }
}
RS

# The standard library writes SAFETY notes over two or three lines, and so does
# clippy's own documentation for undocumented_unsafe_blocks.
run_rs RUST003 clean "a multi-line SAFETY comment counts" <<'RS'
/// Reads the first byte.
pub fn first(buffer: &[u8]) -> u8 {
    // SAFETY: `buffer` is non-empty by the caller's contract, and the pointer
    // is valid for reads of one byte for the lifetime of the borrow.
    unsafe { *buffer.as_ptr() }
}
RS

# rustfmt spreads a derive over several lines, which pushes the doc comment
# further than one line above the item.
run_rs RUST004 clean "a doc comment above a multi-line derive still counts" <<'RS'
/// An order.
#[derive(
    Debug,
    Clone,
)]
pub struct Order {
    id: String,
}
RS

# LAYER001: rustfmt's default is the grouped form, and the 2018 edition allows
# a whole layer in one file beside its directory.
VIOLATIONS=""
mkdir -p "$WORK/layers/src/domain"
cat > "$WORK/layers/src/domain/order.rs" <<'RS'
use crate::{domain::customer::CustomerId, infrastructure::PostgresStore};

/// The aggregate root.
pub struct Order;
RS
pack_validate_rust_layers "$WORK/layers/src/domain/order.rs"
if echo "$VIOLATIONS" | grep -q "^LAYER001:"; then
    log_pass "LAYER001: a grouped import is still an import"
else
    log_fail "LAYER001: a grouped import is still an import" "not detected"
fi

VIOLATIONS=""
cat > "$WORK/layers/src/domain/multi.rs" <<'RS'
use crate::{
    domain::customer::CustomerId,
    infrastructure::PostgresStore,
};

/// The aggregate root.
pub struct Order;
RS
pack_validate_rust_layers "$WORK/layers/src/domain/multi.rs"
if echo "$VIOLATIONS" | grep -q "^LAYER001:"; then
    log_pass "LAYER001: a grouped import spread over lines is still an import"
else
    log_fail "LAYER001: a grouped import spread over lines is still an import" "not detected"
fi

VIOLATIONS=""
cat > "$WORK/layers/src/domain.rs" <<'RS'
use crate::infrastructure::PostgresStore;

/// The aggregate root.
pub struct Order;
RS
pack_validate_rust_layers "$WORK/layers/src/domain.rs"
if echo "$VIOLATIONS" | grep -q "^LAYER001:"; then
    log_pass "LAYER001: domain.rs is the domain layer too"
else
    log_fail "LAYER001: domain.rs is the domain layer too" "not detected"
fi

# --- Cases the code review found, kept as regressions --------------------------

# One escaped quote in a const used to blank the rest of the file: `find` on
# the closing quote stopped on the escaped one, the real one paired with the
# next quote, and the scanner reported the file clean.
run_rs PARAM001 raises "an escaped quote in a char literal does not silence the file" <<'RS'
/// Delimiters.
pub const DELIMS: [char; 2] = ['\'','"'];

/// Builds.
pub fn build(a: u32, b: u32, c: u32, d: u32) -> u32 {
    a + b + c + d
}
RS

# A backslash before a newline is a line continuation. Blanking both as spaces
# removes the newline and every line number after it is one too low, which also
# makes craftsman-ignore read the wrong line.
VIOLATIONS=""
WARNINGS=""
printf 'pub const BANNER: &str = "first \\\n second";\n\npub struct Undocumented;\n\n/// Four parameters.\npub fn build(a: u32, b: u32, c: u32, d: u32) -> u32 {\n    a\n}\n' > "$WORK/cont.rs"
pack_validate_rust "$WORK/cont.rs"
if all_findings | grep -q "^PARAM001:line 7:"; then
    log_pass "a string continuation leaves the line numbers intact"
else
    log_fail "a string continuation leaves the line numbers intact" \
        "expected PARAM001 on line 7, got: $(all_findings | tr '\n' ' ')"
fi
if all_findings | grep -q "^RUST004:line 7:"; then
    log_fail "a documented function after a continuation stays documented" \
        "$(all_findings | tr '\n' ' ')"
else
    log_pass "a documented function after a continuation stays documented"
fi
rm -f "$WORK/cont.rs"

# The `>` of an arrow is not the end of a parameter list, and neither is a
# shift. Counting them closed the group early and the function came back with
# no parameters at all.
run_rs PARAM001 raises "an arrow in a parameter type does not end the list" <<'RS'
/// Applies.
pub fn apply(f: impl Fn(u32) -> u32, b: u32, c: u32, d: u32) -> u32 {
    b
}
RS

run_rs PARAM001 raises "a shift in a parameter type does not end the list" <<'RS'
/// Fills.
pub fn fill(buffer: [u8; 1 << 4], b: u32, c: u32, d: u32) -> usize {
    0
}
RS

run_rs PARAM001 raises "a generic bound carrying an arrow is still a function" <<'RS'
/// Runs.
pub fn run<F: Fn(u32) -> u32>(f: F, a: u32, b: u32, c: u32) -> u32 {
    a
}
RS

# Rust nests block comments, unlike C. Stopping on the first `*/` hands the
# rest of a commented-out block back as live code, and rules then fire on lines
# rustc never compiles.
run_rs PARAM001 clean "a nested block comment stays commented out" <<'RS'
/* disabled
/* the old shape */
pub fn old_build(a: u32, b: u32, c: u32, d: u32) -> u32 { a }
*/

/// Runs.
pub fn run(a: u32) -> u32 {
    a
}
RS

# --- Cases the adversarial review found ----------------------------------------

# An attribute is not documentation. Accepting `#[` meant a single
# #[derive(Debug)] satisfied the rule, and derives are everywhere.
run_rs RUST004 raises "an attribute alone is not a doc comment" <<'RS'
#[derive(Debug)]
pub struct Undocumented {
    pub value: u32,
}
RS

run_rs RUST004 clean "a block doc comment counts" <<'RS'
/** Parses a decimal string.

Block doc comment, accepted by rustdoc. */
pub fn parse_decimal(raw: &str) -> Option<u32> {
    raw.parse().ok()
}
RS

# The trailing comment is where the reason for an #[allow] naturally goes, and
# a `///` above the item documents the item rather than the suppression.
run_rs WARN-RUST001 clean "a trailing comment justifies an allow" <<'RS'
#[allow(dead_code)] // kept for the C ABI, dropped when the FFI header goes
pub struct Legacy {
    field: u32,
}
RS

run_rs WARN-RUST001 raises "a doc comment does not justify an allow" <<'RS'
/// Legacy entry point.
#[allow(clippy::unwrap_used)]
pub fn legacy_entry(a: u8) -> u8 {
    a
}
RS

# Rust has its own suppression syntax. Ignoring it asks a developer to write
# the same exemption twice.
run_rs PARAM001 clean "an #[allow(clippy::too_many_arguments)] disarms PARAM001" <<'RS'
/// Legacy entry point.
// Kept for the C ABI.
#[allow(clippy::too_many_arguments)]
pub fn legacy_entry(a: u8, b: u8, c: u8, d: u8, e: u8) -> u8 {
    a + b + c + d + e
}
RS

# --- The gate that decides whether the validator runs at all ------------------
#
# Every assertion above sources the validator directly, so `_pack_stack_compatible`
# is never on the path: the pack could be gated off entirely and this file would
# stay green. That is how the Go pack shipped with a stack list, producing five
# findings under `stack: go` and none under `stack: symfony`. This case drives
# the real CLI instead.

E2E="$WORK/e2e"
mkdir -p "$E2E/src/domain/order"
cat > "$E2E/.craft-config.yml" <<'YML'
stack: symfony
strictness: strict
YML
cat > "$E2E/src/domain/order/mod.rs" <<'RS'
use crate::infrastructure::postgres::Store;

pub fn load(raw: &str) -> u32 {
    raw.parse::<u32>().unwrap()
}
RS

if command -v git >/dev/null 2>&1; then
    ( cd "$E2E" && git init -q && git add -A ) >/dev/null 2>&1
fi
e2e_out="$(cd "$E2E" && CLAUDE_PLUGIN_ROOT="$ROOT_DIR" bash "$ROOT_DIR/ci/craftsman-ci.sh" src 2>&1)"

if echo "$e2e_out" | grep -q "RUST001"; then
    log_pass "the pack runs on a Rust file in a project whose stack is not Rust"
else
    log_fail "the pack runs on a Rust file in a project whose stack is not Rust" \
        "craftsman-ci found no RUST001: $(echo "$e2e_out" | tr '\n' ' ')"
fi

if echo "$e2e_out" | grep -q "LAYER001"; then
    log_pass "LAYER001 reaches the pipeline as well as the hook"
else
    log_fail "LAYER001 reaches the pipeline as well as the hook" \
        "$(echo "$e2e_out" | tr '\n' ' ')"
fi

# --- The canonical example must survive its own pack -------------------------
#
# The Iron Law loads this file before scaffolding. A canonical example that its
# own validators reject teaches the opposite of what it is there for.
VIOLATIONS=""
WARNINGS=""
pack_validate_rust "$ROOT_DIR/packs/rust/knowledge/canonical/rust-handler.rs"
pack_validate_rust_layers "$ROOT_DIR/packs/rust/knowledge/canonical/rust-handler.rs"
if [[ -z "$(all_findings | grep -v '^$')" ]]; then
    log_pass "the canonical example raises nothing"
else
    log_fail "the canonical example raises nothing" "$(all_findings | tr '\n' ' ')"
fi

test_summary
