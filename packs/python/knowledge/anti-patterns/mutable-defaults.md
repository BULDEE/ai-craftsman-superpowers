# Anti-Pattern: Mutable Default Arguments

## The Problem

Python evaluates default arguments once at function definition time, not at each call.
Mutable defaults (list, dict, set) are shared across all calls.

## Bad

```python
def add_item(item, items=[]):
    items.append(item)
    return items

# First call: ['a'] — looks fine
# Second call: ['a', 'b'] — shared state!
```

## Good

```python
def add_item(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items
```

## Rule

**PY005** — Mutable default argument detected. Use `None` + conditional assignment.
