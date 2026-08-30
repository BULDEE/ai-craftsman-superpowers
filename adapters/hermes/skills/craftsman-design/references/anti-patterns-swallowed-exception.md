---
type: anti-pattern
title: "Anti-Pattern: Swallowed Exception"
description: "An except block that catches an exception and does nothing with it - the failure disappears instead of being handled or propagated."
tags: [exceptions, error-handling]
rules: [PY006]
status: stable
---
# Anti-Pattern: Swallowed Exception

## What It Is

An `except` block whose body is empty (only `pass`, optionally after a docstring). The exception is caught and discarded: no log, no re-raise, no recovery.

## Why It's Bad

- The failure is invisible: nothing in logs, metrics, or the caller signals that something went wrong.
- Debugging becomes guesswork, because the stack trace that would have pointed at the cause is gone.
- It hides bugs that would otherwise surface immediately, letting them corrupt state further downstream.

## Bad

```python
try:
    save_to_database(record)
except Exception:
    pass
```

## Good

```python
try:
    save_to_database(record)
except Exception as db_error:
    logger.error("Failed to save record %s: %s", record.id, db_error)
    raise
```

If a failure genuinely has no consequence, say so explicitly with a comment explaining why, rather than an empty body that looks like an oversight.

## Rule

**PY006** - `except Exception` with an empty body. Either handle it or let it propagate.
