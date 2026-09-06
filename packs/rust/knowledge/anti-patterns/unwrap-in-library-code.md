---
type: anti-pattern
title: "Anti-Pattern: unwrap in Library Code"
description: "unwrap() turns a recoverable error into a process abort and takes the decision away from the caller; a library returns a Result."
tags: [rust, errors]
rules: [RUST001, RUST005]
status: stable
---
# Anti-Pattern: unwrap in Library Code

## The Problem

`Result` and `Option` exist so that a failure is a value the caller can match
on. `.unwrap()` throws that value away and aborts instead, on behalf of a
caller who may have been ready to retry, to fall back, or to answer the request
with a 400.

It is also the one call that carries no information. A panic from `.unwrap()`
says `called Option::unwrap() on a None value` and a line number. Nothing about
what was expected, or why the author believed it could not fail.

## Bad

```rust
/// Loads the order.
pub fn load(raw: &str) -> u32 {
    raw.parse::<u32>().unwrap()
}
```

The caller has two options, both bad: catch the unwind, or validate the input a
second time before calling.

## Good

```rust
/// Loads the order, or explains why the identifier was not a number.
pub fn load(raw: &str) -> Result<u32, std::num::ParseIntError> {
    raw.parse::<u32>()
}
```

The error is a value. The caller uses `?` to propagate it, `match` to handle
it, or `unwrap_or_default` to decide it does not matter here. All three are the
caller's decision, which is the point.

## Where `.expect()` sits

`RUST005` reports `.expect()` rather than refusing it, and the difference is
the message:

```rust
let schema = Schema::parse(EMBEDDED)
    .expect("the schema is embedded at build time and parsed in a test");
```

That message is the invariant, written where a reviewer reads it. It does not
prevent the panic; it makes the panic reviewable. An `.unwrap()` on the same
line carries nothing, which is why one blocks and the other warns.

## When a panic is right

- **Tests**, where a panic is how a failure is reported. Both rules are exempt
  in `tests/`, `benches/` and `*_test.rs`.
- **A broken invariant that no caller can act on**, in `main` or at start-up.
  Say so on the line:

```rust
    let config = Config::load().unwrap(); // craftsman-ignore: RUST001 - start-up, nothing to fall back to
```

## Related

- `RUST002` refuses `panic!`, `todo!`, `unimplemented!` and `unreachable!` for
  the same reason: they end the process instead of returning a value.
- `RUST003` asks an `unsafe` block for its invariant in a `// SAFETY:` comment.
  Same principle, applied to the one place the compiler stops helping.
- `knowledge/canonical/rust-handler.rs` shows the shape these rules push
  toward: an error enum, `?` to propagate, and a public surface that documents
  what it can return.
