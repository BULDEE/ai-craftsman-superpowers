---
type: anti-pattern
title: "Anti-Pattern: Panic in Library Code"
description: "panic() takes the decision away from the caller and unwinds the whole process; a library returns an error and lets the caller choose."
tags: [go, errors]
rules: [GO001]
status: stable
---
# Anti-Pattern: Panic in Library Code

## The Problem

`panic()` is not Go's error mechanism, it is Go's "this program cannot
continue" mechanism. A package that panics decides, on the caller's behalf,
that a bad input is fatal. The caller may have been ready to retry, to fall
back, or to answer the request with a 400.

It also crosses goroutine boundaries badly: a panic in a goroutine the caller
did not start takes down the whole process, and no `recover()` in the caller's
own stack can stop it.

## Bad

```go
package order

func Load(id string) *Order {
	if id == "" {
		panic("empty id")
	}
	return find(id)
}
```

The caller now has two options, both bad: wrap every call in `recover()`, or
validate the input twice.

## Good

```go
package order

var ErrEmptyID = errors.New("order: empty id")

// Load returns the order, or ErrEmptyID when no identifier was given.
func Load(id string) (*Order, error) {
	if id == "" {
		return nil, ErrEmptyID
	}
	return find(id)
}
```

The error is a value. The caller compares it with `errors.Is`, decides, and
keeps its process alive.

## When panic is right

Three cases, and the rule allows all three:

- **`package main`**, at start-up, when the program genuinely cannot run:
  a missing configuration file, a port already taken.
- **A `Must` prefixed constructor**, which exists precisely to say "this
  panics, call me only with a literal you control": `regexp.MustCompile`,
  `template.Must`. The name is the contract.
- **Tests**, where a panic is a failure report like any other.

## Why the rule blocks rather than warns

A layer violation and a panic in a library share a property: the fix is never
"leave it". Either the failure is expected, in which case it is an error value,
or it is impossible, in which case the constructor is named `Must` and says so.
There is no third reading to argue about, which is the bar this project sets
for a rule that refuses a write.

If a specific line genuinely is the fourth case, say so on the line:

```go
	panic(err) // craftsman-ignore: GO001 - unreachable, the schema is embedded
```

## Related

- `GO004`, an error dropped into `_`, is the quiet version of the same mistake.
- `knowledge/canonical/go-handler.go` shows the shape this rule pushes toward:
  wrap with `%w`, return, let the caller decide.
